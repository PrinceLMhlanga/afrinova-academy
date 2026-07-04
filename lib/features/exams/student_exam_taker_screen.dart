import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../ai/math_message_renderer.dart';
import '../teacher/math_keyboard.dart';
import '../teacher/drawing_canvas.dart';
import '../teacher/circuit_canvas_screen.dart';
import '../teacher/graph_plotter.dart';
import '../../core/auth_service.dart';

class StudentExamTakerScreen extends StatefulWidget {
  final Map<String, dynamic> paper;

  const StudentExamTakerScreen({super.key, required this.paper});

  @override
  State<StudentExamTakerScreen> createState() => _StudentExamTakerScreenState();
}

class _StudentExamTakerScreenState extends State<StudentExamTakerScreen> {
  final AuthService _authService = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final _globalMathController = TextEditingController();
  final _answerController = TextEditingController();
  final _finalAnswerController = TextEditingController();
  final Map<String, Uint8List> _imageCache = {};
  String _cachedPreviewText = '';

  List<Map<String, dynamic>> _questions = [];
  Map<String, _StudentAnswer> _answers = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showPreview = true;

  int _activeQuestionIndex = 0;

  bool _showMathKeyboard = false;
  bool _showGraphPlotter = false;
  String? _pendingGraphData;
  String? _pendingCircuitData;
  String? _pendingDrawingData;

  int _remainingSeconds = 0;
  Timer? _timer;
  bool _isTimeUp = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    _answerController.addListener(_onAnswerChanged);
    _finalAnswerController.addListener(_onAnswerChanged);
  }

  void _onAnswerChanged() {
    if (mounted) {
      _updatePreview();
      setState(() {});
    }
  }

  Future<void> _loadQuestions() async {
    try {
      final response = await Supabase.instance.client
          .from('exam_questions')
          .select()
          .eq('paper_id', widget.paper['id'])
          .order('display_order', ascending: true);

      if (mounted) {
        setState(() {
          _questions = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });

        for (final q in _questions) {
          _answers[q['id'] as String] = _StudentAnswer();
        }

        final durationMin = widget.paper['duration_minutes'] as int?;
        if (durationMin != null && durationMin > 0) {
          _remainingSeconds = durationMin * 60;
          _startTimer();
        }

        _loadActiveQuestion();
        _updatePreview();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadActiveQuestion() {
    if (_activeQuestionIndex >= _questions.length) return;
    final qId = _questions[_activeQuestionIndex]['id'] as String;
    final answer = _answers[qId]!;
    _answerController.text = answer.textAnswer;
    _finalAnswerController.text = answer.finalAnswer;
    _pendingCircuitData = answer.circuitData;
    _pendingDrawingData = answer.drawingData;
    _pendingGraphData = answer.graphData;
    _updatePreview();
  }

  void _saveActiveQuestion() {
    if (_activeQuestionIndex >= _questions.length) return;
    final qId = _questions[_activeQuestionIndex]['id'] as String;
    _answers[qId]!.textAnswer = _answerController.text;
    _answers[qId]!.finalAnswer = _finalAnswerController.text;
    _answers[qId]!.circuitData = _pendingCircuitData;
    _answers[qId]!.drawingData = _pendingDrawingData;
    _answers[qId]!.graphData = _pendingGraphData;
  }

  void _goToQuestion(int index) {
    if (index < 0 || index >= _questions.length) return;
    _saveActiveQuestion();
    _imageCache.clear();
    setState(() {
      _activeQuestionIndex = index;
      _pendingCircuitData = null;
      _pendingDrawingData = null;
      _pendingGraphData = null;
    });
    _loadActiveQuestion();
    _updatePreview();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _timer?.cancel();
        setState(() => _isTimeUp = true);
        _submitExam(autoSubmit: true);
      }
    });
  }

  void _updatePreview() {
    _cachedPreviewText = _composeAnswerText();
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) return '${hours}h ${mins.toString().padLeft(2, '0')}m';
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _removeGraphData() {
    setState(() {
      _pendingGraphData = null;
      _saveActiveQuestion();
      _updatePreview();
    });
  }

  void _removeDrawingData() {
    setState(() {
      _pendingDrawingData = null;
      _saveActiveQuestion();
      _updatePreview();
    });
  }

  void _removeCircuitData() {
    setState(() {
      _pendingCircuitData = null;
      _saveActiveQuestion();
      _updatePreview();
    });
  }

  void _removeUploadedImage(int index) {
    final qId = _questions.isNotEmpty && _activeQuestionIndex < _questions.length 
        ? _questions[_activeQuestionIndex]['id'] as String? : null;
    if (qId != null && _answers[qId]!.workingsImages.length > index) {
      setState(() {
        _answers[qId]!.workingsImages.removeAt(index);
        _saveActiveQuestion();
        _updatePreview();
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (image != null) {
        List<int> imageBytes = kIsWeb ? await image.readAsBytes() : await File(image.path).readAsBytes();
        final qId = _questions[_activeQuestionIndex]['id'] as String;
        setState(() {
          _answers[qId]!.workingsImages.add(base64Encode(imageBytes));
          _updatePreview();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (image != null) {
        List<int> imageBytes = kIsWeb ? await image.readAsBytes() : await File(image.path).readAsBytes();
        final qId = _questions[_activeQuestionIndex]['id'] as String;
        setState(() {
          _answers[qId]!.workingsImages.add(base64Encode(imageBytes));
          _updatePreview();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _openDrawingCanvas() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DrawingCanvas(onSave: (base64Image) {
        Navigator.pop(context);
        setState(() {
          _pendingDrawingData = '%%DRAWING:$base64Image%%';
          _saveActiveQuestion();
          _updatePreview();
        });
      }),
    ));
  }

  Future<void> _openCircuitCanvas() async {
    final svgMarkup = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => CircuitCanvasScreen(onInsert: (svg) => Navigator.pop(context, svg)),
    ));
    if (svgMarkup != null && svgMarkup.isNotEmpty) {
      final base64Svg = base64Encode(utf8.encode(svgMarkup));
      setState(() {
        _pendingCircuitData = '%%CIRCUIT:$base64Svg%%';
        _saveActiveQuestion();
        _updatePreview();
      });
    }
  }

  String _composeAnswerText() {
    final buffer = StringBuffer();
    final text = _answerController.text.trim();
    if (text.isNotEmpty) buffer.write(text);
    
    if (_pendingCircuitData != null && _pendingCircuitData!.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(_pendingCircuitData);
    }
    if (_pendingDrawingData != null && _pendingDrawingData!.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(_pendingDrawingData);
    }
    if (_pendingGraphData != null && _pendingGraphData!.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(_pendingGraphData);
    }
    
    // Add uploaded images
    final qId = _questions.isNotEmpty && _activeQuestionIndex < _questions.length 
        ? _questions[_activeQuestionIndex]['id'] as String? : null;
    if (qId != null && _answers[qId]!.workingsImages.isNotEmpty) {
      for (final img in _answers[qId]!.workingsImages) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write('%%IMAGE:$img%%');
      }
    }
    return buffer.toString();
  }

  // ===== EXTRACTION METHODS =====
  
  List<String> _extractImages(String text) {
    final regex = RegExp(r'%%IMAGE:([A-Za-z0-9+/=]+)%%');
    return regex.allMatches(text).map((m) => m.group(1)!).toList();
  }

  List<String> _extractSvgs(String text) {
    final regex = RegExp(r'%%CIRCUIT:([A-Za-z0-9+/=\s]+)%%', dotAll: true);
    return regex.allMatches(text).map((m) {
      try {
        final b64 = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
        return b64.isNotEmpty ? utf8.decode(base64Decode(b64)) : '';
      } catch (_) { return ''; }
    }).where((s) => s.isNotEmpty).toList();
  }

  List<String> _extractDrawings(String text) {
    final regex = RegExp(r'%%DRAWING:([A-Za-z0-9+/=]+)%%');
    return regex.allMatches(text).map((m) => m.group(1)!).toList();
  }

  List<_GraphSpec> _extractGraphs(String text) {
    final regex = RegExp(r'GRAPH:([^:]+):([^:]+):([^:]+):([a-fA-F0-9]+):(.+)');
    return regex.allMatches(text).map((match) {
      return _GraphSpec(
        title: match.group(1) ?? 'Graph',
        xLabel: match.group(2) ?? 'x',
        yLabel: match.group(3) ?? 'y',
        color: Color(int.parse(match.group(4)!, radix: 16)),
        data: match.group(5) ?? '',
      );
    }).toList();
  }

  // ✅ ADD TABLE EXTRACTION
  List<List<List<String>>> _extractTables(String text) {
    final List<List<List<String>>> tables = [];
    final tableRegex = RegExp(r'%%TABLE:([A-Za-z0-9+/=]+)%%');
    for (final match in tableRegex.allMatches(text)) {
      try {
        final base64Data = match.group(1)!;
        final jsonString = utf8.decode(base64Decode(base64Data));
        final List<dynamic> decoded = jsonDecode(jsonString);
        final List<List<String>> table = decoded.map((row) {
          return (row as List<dynamic>).map((cell) => cell.toString()).toList();
        }).toList();
        tables.add(table);
      } catch (e) {
        debugPrint('Error decoding table: $e');
      }
    }
    return tables;
  }

  // ===== CONTENT RENDERING =====
  
  Widget _buildFormattedContent(String text, {
    VoidCallback? onDeleteGraph,
    VoidCallback? onDeleteDrawing,
    VoidCallback? onDeleteCircuit,
    void Function(int index)? onDeleteImage,
  }) {
    final svgs = _extractSvgs(text);
    final drawings = _extractDrawings(text);
    final images = _extractImages(text);
    final graphs = _extractGraphs(text);
    final tables = _extractTables(text);  // ✅ Add tables
    
    String cleanText = text
        .replaceAll(RegExp(r'%%CIRCUIT:[A-Za-z0-9+/=\s]+%%', dotAll: true), '')
        .replaceAll(RegExp(r'%%DRAWING:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%IMAGE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%TABLE:[A-Za-z0-9+/=]+%%'), '')  // ✅ Clean table markers
        .replaceAll(RegExp(r'GRAPH:[^\n]+'), '')
        .trim();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (cleanText.isNotEmpty) 
        MathMessageRenderer(text: cleanText, textColor: Colors.black87),
      
      // ✅ Tables
      ...tables.map((table) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Table', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  border: TableBorder.all(color: Colors.grey.shade300),
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: table.map((row) {
                    return TableRow(
                      children: row.map((cell) {
                        return Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(cell.isEmpty ? ' ' : cell, style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      )),
      
      // Images with delete button
      ...images.asMap().entries.map((entry) {
        final img = entry.value;
        if (!_imageCache.containsKey(img)) {
          _imageCache[img] = base64Decode(img);
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text('Image ${entry.key + 1}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                  if (onDeleteImage != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onDeleteImage(entry.key),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8), 
                child: Image.memory(_imageCache[img]!, fit: BoxFit.contain, gaplessPlayback: true),
              ),
            ],
          ),
        );
      }),
      
      // Circuits with delete button
      ...svgs.map((s) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.electrical_services, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                const Text('Circuit',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange)),
                if (onDeleteCircuit != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onDeleteCircuit,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            SvgPicture.string(s, height: 120),
          ],
        ),
      )),
      
      // Drawings with delete button
      ...drawings.map((d) {
        if (!_imageCache.containsKey(d)) {
          _imageCache[d] = base64Decode(d);
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.draw, size: 14, color: Colors.purple),
                  const SizedBox(width: 4),
                  const Text('Drawing',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.purple)),
                  if (onDeleteDrawing != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onDeleteDrawing,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8), 
                child: Image.memory(_imageCache[d]!, fit: BoxFit.contain, gaplessPlayback: true),
              ),
            ],
          ),
        );
      }),
      
      // Graphs with delete button
      ...graphs.map((g) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_chart, size: 14, color: Colors.blue),
                const SizedBox(width: 4),
                Text(g.title,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue)),
                if (onDeleteGraph != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onDeleteGraph,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            _buildGraphPreview(g),
          ],
        ),
      )),
    ]);
  }

  Widget _buildGraphPreview(_GraphSpec spec) {
    final spots = spec.data
        .split(';')
        .where((part) => part.contains(','))
        .map((part) {
          final values = part.split(',');
          return FlSpot(
            double.tryParse(values.first.trim()) ?? 0,
            double.tryParse(values.last.trim()) ?? 0,
          );
        })
        .toList();

    if (spots.length < 2) {
      return const SizedBox.shrink();
    }

    final minX = spots.map((s) => s.x).reduce((a, b) => a < b ? a : b);
    final maxX = spots.map((s) => s.x).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    final xPad = (maxX - minX).abs() < 1 ? 1.0 : (maxX - minX) * 0.15;
    final yPad = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.15;

    final leftBound = minX - xPad;
    final rightBound = maxX + xPad;
    final bottomBound = minY - yPad;
    final topBound = maxY + yPad;

    final showZeroX = leftBound <= 0 && rightBound >= 0;
    final showZeroY = bottomBound <= 0 && topBound >= 0;

    final xInterval = _niceInterval(leftBound, rightBound);
    final yInterval = _niceInterval(bottomBound, topBound);

    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LineChart(
        LineChartData(
          minX: leftBound,
          maxX: rightBound,
          minY: bottomBound,
          maxY: topBound,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            drawHorizontalLine: true,
            getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: showZeroY ? [HorizontalLine(y: 0, color: const Color(0xFF1A237E), strokeWidth: 2)] : [],
            verticalLines: showZeroX ? [VerticalLine(x: 0, color: const Color(0xFF1A237E), strokeWidth: 2)] : [],
          ),
          borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade400)),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(spec.yLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              sideTitles: SideTitles(
                showTitles: true, interval: yInterval,
                getTitlesWidget: (value, meta) {
                  if (value == 0 && !showZeroY) return const SizedBox.shrink();
                  return Text(value == 0 ? '0' : value.toStringAsFixed(value.abs() >= 10 ? 0 : 1),
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(spec.xLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              sideTitles: SideTitles(
                showTitles: true, interval: xInterval,
                getTitlesWidget: (value, meta) {
                  if (value == 0 && !showZeroX) return const SizedBox.shrink();
                  return Text(value == 0 ? '0' : value.toStringAsFixed(value.abs() >= 10 ? 0 : 1),
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) => LineTooltipItem(
                '(${spot.x.toStringAsFixed(2)}, ${spot.y.toStringAsFixed(2)})',
                const TextStyle(color: Colors.white, fontSize: 12),
              )).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(spots: spots, color: spec.color, barWidth: 2.5, dotData: const FlDotData(show: true)),
          ],
        ),
      ),
    );
  }

  double _niceInterval(double min, double max) {
    final range = (max - min).abs();
    if (range == 0) return 1;
    final raw = range / 5;
    final exponent = raw == 0 ? 0 : (log(raw) / log(10)).floor();
    final magnitude = pow(10, exponent).toDouble();
    final normalized = raw / magnitude;
    double interval;
    if (normalized <= 1) { interval = 1; }
    else if (normalized <= 2) { interval = 2; }
    else if (normalized <= 5) { interval = 5; }
    else { interval = 10; }
    return interval * magnitude;
  }

  Future<void> _submitExam({bool autoSubmit = false}) async {
    if (_isSubmitting) return;
    _saveActiveQuestion();

    if (!autoSubmit) {
      final unanswered = _answers.entries.where((e) =>
        e.value.textAnswer.isEmpty &&
        e.value.finalAnswer.isEmpty &&
        e.value.workingsImages.isEmpty &&
        e.value.drawingData == null
      ).length;

      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Submit Exam?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You have answered ${_questions.length - unanswered} of ${_questions.length} questions.'),
          if (unanswered > 0) ...[
            const SizedBox(height: 8),
            Text('$unanswered question(s) unanswered.', style: const TextStyle(color: Colors.orange)),
          ],
          const SizedBox(height: 8),
          const Text('You cannot change your answers after submission.', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Review')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
            child: const Text('Submit')),
        ],
      ));
      if (confirmed != true) return;
    }

    setState(() => _isSubmitting = true);
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      for (final entry in _answers.entries) {
        final answer = entry.value;
        final composedText = StringBuffer();
        
        if (answer.textAnswer.isNotEmpty) composedText.write(answer.textAnswer);
        if (answer.circuitData != null && answer.circuitData!.isNotEmpty) {
          if (composedText.isNotEmpty) composedText.write('\n\n');
          composedText.write(answer.circuitData);
        }
        if (answer.drawingData != null && answer.drawingData!.isNotEmpty) {
          if (composedText.isNotEmpty) composedText.write('\n\n');
          composedText.write(answer.drawingData);
        }
        if (answer.graphData != null && answer.graphData!.isNotEmpty) {
          if (composedText.isNotEmpty) composedText.write('\n\n');
          composedText.write(answer.graphData);
        }

        await Supabase.instance.client.from('exam_answers').upsert({
          'paper_id': widget.paper['id'],
          'question_id': entry.key,
          'student_id': userId,
          'text_answer': composedText.toString(),
          'final_answer': answer.finalAnswer,
          'workings_images': answer.workingsImages,
          'drawing_data': answer.drawingData,
          'circuit_data': answer.circuitData,
          'graph_data': answer.graphData,
          'status': 'submitted',
        }, onConflict: 'paper_id, question_id, student_id');
      }

      if (mounted) {
        _timer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exam submitted! ✅'), backgroundColor: Color(0xFF4CAF50)));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  void dispose() {
    _saveActiveQuestion();
    _timer?.cancel();
    _globalMathController.dispose();
    _answerController.removeListener(_onAnswerChanged);
    _finalAnswerController.removeListener(_onAnswerChanged);
    _answerController.dispose();
    _finalAnswerController.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
    if (_isTimeUp) {
      return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.timer_off, size: 64, color: Colors.red), const SizedBox(height: 16),
        const Text('Time\'s Up!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), const Text('Your exam is being submitted...'), const SizedBox(height: 16),
        const CircularProgressIndicator(),
      ])));
    }

    final currentQ = _questions.isNotEmpty ? _questions[_activeQuestionIndex] : null;
    final currentQId = currentQ?['id'] as String?;
    final previewText = _cachedPreviewText;
    final isLargeScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.paper['title'] ?? 'Exam'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Preview toggle button (only on small screens)
          if (!isLargeScreen)
            IconButton(
              icon: Icon(
                _showPreview ? Icons.visibility_off : Icons.visibility,
                color: Colors.white,
              ),
              onPressed: () => setState(() => _showPreview = !_showPreview),
              tooltip: _showPreview ? 'Hide Preview' : 'Show Preview',
            ),
          Center(child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _remainingSeconds < 300 ? Colors.red.withOpacity(0.3) : Colors.white24,
              borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_remainingSeconds < 300 ? Icons.timer_off : Icons.timer, color: Colors.white, size: 18),
              const SizedBox(width: 4),
              Text(_formatTime(_remainingSeconds), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ]))),
          TextButton.icon(
            onPressed: _isSubmitting ? null : () => _submitExam(),
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00897B)))
          : isLargeScreen
              ? _buildLargeScreenLayout(currentQ, previewText)
              : _buildMobileLayout(currentQ, previewText),
    );
  }

// Large screen: side-by-side layout
Widget _buildLargeScreenLayout(Map<String, dynamic>? currentQ, String previewText) {
  return Column(children: [
    // Question navigator
    _buildQuestionNavigator(),
    
    // Main content - side by side
    Expanded(
      child: Row(children: [
        // Left: Question + Answer
        Expanded(flex: 3, child: _buildAnswerArea(currentQ)),
        
        // Right: Preview
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.white,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                const Text('Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A237E))),
                const Spacer(),
                Switch(value: _showPreview, onChanged: (v) => setState(() => _showPreview = v), activeColor: const Color(0xFF00897B)),
              ])),
              const Divider(height: 1),
              Expanded(child: _showPreview && previewText.isNotEmpty
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(12), 
                      child: _buildFormattedContent(
                        previewText,
                        onDeleteGraph: _removeGraphData,
                        onDeleteDrawing: _removeDrawingData,
                        onDeleteCircuit: _removeCircuitData,
                        onDeleteImage: _removeUploadedImage,
                      ),
                    )
                  : const Center(child: Text('Start typing to see preview...', 
                      style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))),
            ]),
          ),
        ),
      ]),
    ),
    
    // Bottom toolbars
    if (_showMathKeyboard)
      MathKeyboard(
        controller: _answerController,
        onClose: () => setState(() => _showMathKeyboard = false),
      ),
    if (_showGraphPlotter)
      Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: GraphPlotter(
          onInsertGraph: (graphData) {
            setState(() {
              _pendingGraphData = graphData;
              _showGraphPlotter = false;
              _updatePreview();
            });
          },
        ),
      ),
  ]);
}

// Mobile layout: full screen with slide-over preview
Widget _buildMobileLayout(Map<String, dynamic>? currentQ, String previewText) {
  return Stack(
    children: [
      // Main answer area (always visible)
      Column(children: [
        // Question navigator
        _buildQuestionNavigator(),
        
        // Answer area
        Expanded(child: _buildAnswerArea(currentQ)),
        
        // Bottom toolbars
        if (_showMathKeyboard)
          MathKeyboard(
            controller: _answerController,
            onClose: () => setState(() => _showMathKeyboard = false),
          ),
        if (_showGraphPlotter)
          Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: GraphPlotter(
              onInsertGraph: (graphData) {
                setState(() {
                  _pendingGraphData = graphData;
                  _showGraphPlotter = false;
                  _updatePreview();
                });
              },
            ),
          ),
      ]),
      
      // Slide-over preview panel (only when toggled)
      if (_showPreview)
        // Overlay tap to close
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _showPreview = false),
            child: Container(color: Colors.black54),
          ),
        ),
      if (_showPreview)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.9,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomLeft: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(-4, 0),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Answer Preview',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00897B),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => setState(() => _showPreview = false),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Preview content
                  Expanded(
                    child: previewText.isNotEmpty
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: _buildFormattedContent(
                              previewText,
                              onDeleteGraph: _removeGraphData,
                              onDeleteDrawing: _removeDrawingData,
                              onDeleteCircuit: _removeCircuitData,
                              onDeleteImage: _removeUploadedImage,
                            ),
                          )
                        : const Center(
                            child: Text(
                              'Start typing to see preview...',
                              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

// Question navigator (used by both layouts)
Widget _buildQuestionNavigator() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_questions.length, (i) {
          final isActive = i == _activeQuestionIndex;
          final qId = _questions[i]['id'] as String;
          final answer = _answers[qId];
          final hasAnswer = (answer?.textAnswer.isNotEmpty == true) ||
              (answer?.finalAnswer.isNotEmpty == true) ||
              (answer?.workingsImages.isNotEmpty == true) ||
              (answer?.circuitData != null) ||
              (answer?.drawingData != null);
          return GestureDetector(
            onTap: () => _goToQuestion(i),
            child: Container(
              width: 40, height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF00897B) : hasAnswer ? const Color(0xFF4CAF50).withOpacity(0.2) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isActive ? const Color(0xFF00897B) : Colors.grey.shade300, width: isActive ? 2 : 1),
              ),
              child: Center(child: Text('${i + 1}',
                style: TextStyle(fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : hasAnswer ? const Color(0xFF4CAF50) : Colors.grey))),
            ),
          );
        }),
      ),
    ),
  );
}

// Answer area (used by both layouts)
Widget _buildAnswerArea(Map<String, dynamic>? currentQ) {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentQ != null) ...[
          // Question header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00897B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Question ${_activeQuestionIndex + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00897B))),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${currentQ['marks'] ?? 0} marks',
                  style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 16),

          // Question content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _buildFormattedContent(currentQ['question_text'] ?? ''),
          ),
          const SizedBox(height: 20),

          // Answer field
          const Text('Your Answer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 8),
          TextField(
            controller: _answerController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Type your answer, workings, and explanation...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          // Final answer
          TextField(
            controller: _finalAnswerController,
            decoration: InputDecoration(
              hintText: 'Final Answer (box your answer)',
              prefixIcon: const Icon(Icons.check_circle_outline, color: Color(0xFF00897B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Tools
          Wrap(spacing: 8, runSpacing: 8, children: [
            _ToolButton(icon: Icons.image_outlined, label: 'Upload', onTap: _pickImage),
            _ToolButton(icon: Icons.camera_alt_outlined, label: 'Photo', onTap: _takePhoto),
            _ToolButton(icon: Icons.draw_outlined, label: 'Draw', onTap: _openDrawingCanvas),
            _ToolButton(icon: Icons.electrical_services_outlined, label: 'Circuit', onTap: _openCircuitCanvas),
            _ToolButton(icon: Icons.insert_chart_outlined, label: 'Graph', onTap: () {
              setState(() => _showGraphPlotter = !_showGraphPlotter);
            }),
            _ToolButton(icon: Icons.functions, label: 'Math', isActive: _showMathKeyboard,
                onTap: () => setState(() => _showMathKeyboard = !_showMathKeyboard)),
          ]),

          // Navigation buttons
          const SizedBox(height: 24),
          Row(children: [
            if (_activeQuestionIndex > 0)
              OutlinedButton.icon(
                onPressed: () => _goToQuestion(_activeQuestionIndex - 1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Previous'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF00897B)),
              ),
            const Spacer(),
            if (_activeQuestionIndex < _questions.length - 1)
              ElevatedButton.icon(
                onPressed: () => _goToQuestion(_activeQuestionIndex + 1),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white,
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}


class _StudentAnswer {
  String textAnswer = '';
  String finalAnswer = '';
  List<String> workingsImages = [];
  String? drawingData;
  String? circuitData;
  String? graphData;
}

class _GraphSpec {
  final String title;
  final String xLabel;
  final String yLabel;
  final Color color;
  final String data;

  const _GraphSpec({
    required this.title,
    required this.xLabel,
    required this.yLabel,
    required this.color,
    required this.data,
  });
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({required this.icon, required this.label, this.isActive = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00897B).withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? const Color(0xFF00897B) : Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: isActive ? const Color(0xFF00897B) : Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: isActive ? const Color(0xFF00897B) : Colors.grey.shade700)),
        ]),
      ),
    );
  }
}