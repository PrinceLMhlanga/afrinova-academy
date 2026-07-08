import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/exam_paper_service.dart';
import '../../core/auth_service.dart';
import '../../core/teacher_service.dart';
import '../ai/math_message_renderer.dart';
import 'math_keyboard.dart';
import 'circuit_canvas_screen.dart';
import 'graph_plotter.dart';
import 'drawing_canvas.dart';
import 'table_editor_screen.dart';
import 'table_markup.dart';

class ExamPaperEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? existingPaper;

  const ExamPaperEditorScreen({super.key, this.existingPaper});

  @override
  State<ExamPaperEditorScreen> createState() => _ExamPaperEditorScreenState();
}

class _ExamPaperEditorScreenState extends State<ExamPaperEditorScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final ExamPaperService _paperService = ExamPaperService();
  final AuthService _authService = AuthService();
  final TeacherService _teacherService = TeacherService();

  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _durationController = TextEditingController(text: '120');
  final _questionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  List<Map<String, dynamic>> _subjects = [];
  String? _selectedSubjectId;
  String? _selectedSubjectName;
  String _curriculum = 'ZIMSEC';
  String _paperType = 'Paper 1';
  bool _isSaving = false;
  bool _showPreview = true;
  String? _pendingGraphData;
  String? _pendingCircuitData;
  String? _pendingDrawingData;
  String? _pendingImageData;
  String? _pendingTableData;

  // ✅ ADD: Level support
List<Map<String, dynamic>> _levels = [];
String? _selectedLevelId;
String? _selectedLevelName;

  // Toolbar states
  bool _showMathKeyboard = false;
  bool _showCircuitToolbar = false;
  bool _showGraphPlotter = false;

  // Preview panel state
  bool _isPreviewOpen = true; // Default to open on larger screens
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Questions list
  final List<_PaperQuestion> _questions = [];
  int _currentMarks = 5;
  int? _editingQuestionIndex;

  @override
void initState() {
  super.initState();
  
  _loadLevels();
  _loadExistingPaper();
  
  _slideController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  _slideAnimation = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _slideController,
    curve: Curves.easeOut,
  ));
  
  // Use post-frame callback to check screen size
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      final isLargeScreen = MediaQuery.of(context).size.width > 900;
      setState(() {
        _isPreviewOpen = isLargeScreen;
      });
      if (_isPreviewOpen) {
        _slideController.forward();
      }
    }
  });
}

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // This will also be called when screen rotates or window resizes
  // But we handle it in build with LayoutBuilder anyway
}

  @override
  void dispose() {
    _slideController.dispose();
    _titleController.dispose();
    _instructionsController.dispose();
    _durationController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  void _togglePreview() {
    setState(() {
      _isPreviewOpen = !_isPreviewOpen;
      if (_isPreviewOpen) {
        _slideController.forward();
      } else {
        _slideController.reverse();
      }
    });
  }

  Future<void> _loadLevels() async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final response = await Supabase.instance.client
        .from('teacher_levels')
        .select('level_id, levels!inner(name)')
        .eq('teacher_id', userId);

    if (mounted) setState(() => _levels = List<Map<String, dynamic>>.from(response));
  } catch (_) {}
}

Future<void> _loadSubjectsForLevel(String levelId) async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final response = await Supabase.instance.client
        .from('teacher_subjects')
        .select('subject_id, subjects!inner(name, color_hex, icon_name)')
        .eq('teacher_id', userId)
        .eq('level_id', levelId);

    if (mounted) {
      setState(() {
        _subjects = List<Map<String, dynamic>>.from(response);
        _selectedSubjectId = null;
      });
    }
  } catch (_) {}
}

  Future<void> _loadExistingPaper() async {
    final paper = widget.existingPaper;
    if (paper == null) return;

    _titleController.text = paper['title'] ?? '';
    _instructionsController.text = paper['instructions'] ?? '';
    _durationController.text = paper['duration_minutes']?.toString() ?? '120';
    _curriculum = paper['curriculum'] ?? 'ZIMSEC';
    _paperType = paper['paper_type'] ?? 'Paper 1';

    final subjectId = paper['subject_id'] as String?;
    if (subjectId != null && _subjects.isNotEmpty) {
      final subject = _subjects.firstWhere(
        (s) => s['id'] == subjectId,
        orElse: () => {},
      );
      if (subject.isNotEmpty) {
        _selectedSubjectId = subjectId;
        _selectedSubjectName = subject['name'] as String?;
      }
    }

    try {
      final questions = await _paperService.getPaperQuestions(paper['id'] as String);
      if (mounted) {
        setState(() {
          _questions.clear();
          for (final q in questions) {
  _questions.add(_PaperQuestion(
    text: q['question_text'] ?? '',
    marks: q['marks'] as int? ?? 0,
    number: q['question_number'] as int? ?? _questions.length + 1,
  ));
}

        });
      }
    } catch (_) {}
  }

  

  void _resetQuestionComposer() {
    _questionController.clear();
    _pendingGraphData = null;
    _pendingCircuitData = null;
    _pendingDrawingData = null;
    _pendingImageData = null;
    _pendingTableData = null;
    _currentMarks = 5;
    _editingQuestionIndex = null;
  }

  void _startEditingQuestion(int index) {
    final question = _questions[index];
    setState(() {
      _editingQuestionIndex = index;
      _questionController.text = _stripQuestionMarkers(question.text);
      _pendingGraphData = _extractGraphMarker(question.text);
      _pendingCircuitData = _extractCircuitMarker(question.text);
      _pendingDrawingData = _extractDrawingMarker(question.text);
      _pendingImageData = _extractImageMarker(question.text);
      _pendingTableData = TableMarkup.extractTableMarker(question.text);
      _currentMarks = question.marks;
      _showPreview = true;
    });
  }

  Future<void> _insertImage({required ImageSource source}) async {
    try {
      final image = await _imagePicker.pickImage(source: source, imageQuality: 85);
      if (image == null) return;

      final imageBytes = await image.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      if (!mounted) return;

      setState(() {
        _pendingImageData = '%%IMAGE:$base64Image%%';
        _showPreview = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickImageSource() async {
    if (!mounted) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      await _insertImage(source: source);
    }
  }

  void _insertTable(List<List<String>> cells) {
    if (cells.isEmpty) return;
    setState(() {
      _pendingTableData = TableMarkup.encodeTableMarker(cells);
      _showPreview = true;
    });
  }

  Future<void> _openTableEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TableEditorScreen(onInsertTable: _insertTable),
      ),
    );
  }

  void _saveQuestion() {
    final text = _composeDraftText().trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter question text or insert a graph/circuit'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      if (_editingQuestionIndex != null) {
        final question = _questions[_editingQuestionIndex!];
        _questions[_editingQuestionIndex!] = _PaperQuestion(
          text: text,
          marks: _currentMarks,
          number: question.number,
        );
      } else {
        _questions.add(_PaperQuestion(
          text: text,
          marks: _currentMarks,
          number: _questions.length + 1,
        ));
      }
      _resetQuestionComposer();
    });
  }

  static String _stripQuestionMarkers(String text) {
    return text
        .replaceAll(RegExp(r'%%CIRCUIT:[A-Za-z0-9+/=\s]+%%', dotAll: true), '')
        .replaceAll(RegExp(r'%%DRAWING:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%IMAGE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%TABLE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'GRAPH:[^\n]+'), '')
        .trim();
  }

  static String? _extractCircuitMarker(String text) {
    final match = RegExp(r'%%CIRCUIT:[A-Za-z0-9+/=\s]+%%', dotAll: true).firstMatch(text);
    return match?.group(0);
  }

  static String? _extractDrawingMarker(String text) {
    final match = RegExp(r'%%DRAWING:[A-Za-z0-9+/=]+%%').firstMatch(text);
    return match?.group(0);
  }

  static String? _extractGraphMarker(String text) {
    final match = RegExp(r'GRAPH:[^\n]+').firstMatch(text);
    return match?.group(0);
  }

  static String? _extractImageMarker(String text) {
    final match = RegExp(r'%%IMAGE:[A-Za-z0-9+/=]+%%').firstMatch(text);
    return match?.group(0);
  }

  static List<List<List<String>>> _extractTables(String text) {
    return TableMarkup.extractTables(text);
  }

  static List<String> _extractDrawings(String text) {
    final List<String> drawings = [];
    final drawingRegex = RegExp(r'%%DRAWING:([A-Za-z0-9+/=]+)%%');
    for (final match in drawingRegex.allMatches(text)) {
      drawings.add(match.group(1)!);
    }
    return drawings;
  }

  static List<String> _extractImages(String text) {
    final List<String> images = [];
    final imageRegex = RegExp(r'%%IMAGE:([A-Za-z0-9+/=]+)%%');
    for (final match in imageRegex.allMatches(text)) {
      images.add(match.group(1)!);
    }
    return images;
  }

  String _composeDraftText() {
    final buffer = StringBuffer();
    final questionText = _questionController.text.trim();

    if (questionText.isNotEmpty) {
      buffer.write(questionText);
    }

    if (_pendingGraphData != null && _pendingGraphData!.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(_pendingGraphData);
    }

    if (_pendingCircuitData != null && _pendingCircuitData!.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(_pendingCircuitData);
    }

    if (_pendingDrawingData != null && _pendingDrawingData!.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(_pendingDrawingData!);
    }

    if (_pendingImageData != null && _pendingImageData!.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(_pendingImageData!);
    }

    if (_pendingTableData != null && _pendingTableData!.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(_pendingTableData!);
    }

    return buffer.toString();
  }

  static List<String> _extractSvgs(String text) {
    final List<String> svgs = [];
    final newRegex = RegExp(r'%%CIRCUIT:([A-Za-z0-9+/=\s]+)%%', dotAll: true);
    for (final match in newRegex.allMatches(text)) {
      try {
        final base64Svg = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
        if (base64Svg.isNotEmpty) {
          final svgString = utf8.decode(base64Decode(base64Svg));
          if (svgString.isNotEmpty) {
            svgs.add(svgString);
          }
        }
      } catch (e) {
        print('Error decoding circuit SVG: $e');
      }
    }
    return svgs;
  }

  static List<_GraphSpec> _extractGraphs(String text) {
    final regex = RegExp(
      r'GRAPH:([^:]+):([^:]+):([^:]+):([a-fA-F0-9]+):(.+)'
    );
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

  static Widget _buildFormattedQuestionContentStatic(String text) {
    
    final List<String> svgs = _extractSvgs(text);
    final List<_GraphSpec> graphs = _extractGraphs(text);
    final drawings = _extractDrawings(text);
    final images = _extractImages(text);
    final tables = _extractTables(text);

    String cleanText = text
        .replaceAll(RegExp(r'%%CIRCUIT_LABEL:[^%]+%%'), '')
        .replaceAll(RegExp(r'%%CIRCUIT:[A-Za-z0-9+/=\s]+%%', dotAll: true), '')
        .replaceAll(RegExp(r'%%DRAWING:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%IMAGE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%TABLE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\(data:image/svg\+xml;base64,[A-Za-z0-9+/=]+\)'), '')
        .replaceAll(RegExp(r'GRAPH:[^\n]+'), '')
        .trim();

    List<Widget> contentWidgets = [];

    if (cleanText.isNotEmpty) {
      contentWidgets.add(
        MathMessageRenderer(text: cleanText, textColor: Colors.black87)
      );
    }

    for (final svg in svgs) {
      String fixedSvg = svg;
      if (!fixedSvg.contains('xmlns="http://www.w3.org/2000/svg"')) {
        fixedSvg = fixedSvg.replaceFirst(
          '<svg',
          '<svg xmlns="http://www.w3.org/2000/svg"'
        );
      }
      contentWidgets.add(
        Padding(
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
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Circuit Diagram',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 200,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SvgPicture.string(
                      fixedSvg,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (final drawing in drawings) {
      contentWidgets.add(
        Padding(
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
              children: [
                const Text(
                  'Drawing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    base64Decode(drawing),
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (final spec in graphs) {
      contentWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _buildGraphPreview(spec),
        ),
      );
    }

    for (final image in images) {
      contentWidgets.add(
        Padding(
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
              children: [
                const Text(
                  'Inserted Image',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    base64Decode(image),
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (final table in tables) {
      contentWidgets.add(
        Padding(
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
                const Text(
                  'Inserted Table',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
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
                            child: Text(cell.isEmpty ? ' ' : cell),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (contentWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: contentWidgets,
    );
  }

  static Widget _buildGraphPreview(_GraphSpec spec) {
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
      height: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) => LineTooltipItem(
                '(${spot.x.toStringAsFixed(2)}, ${spot.y.toStringAsFixed(2)})',
                const TextStyle(color: Colors.white, fontSize: 12),
              )).toList(),
            ),
          ),
          minX: leftBound,
          maxX: rightBound,
          minY: bottomBound,
          maxY: topBound,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            drawHorizontalLine: true,
            getDrawingVerticalLine: (value) => FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
            ),
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: showZeroY
                ? [
                    HorizontalLine(
                      y: 0,
                      color: const Color(0xFF1A237E),
                      strokeWidth: 2,
                    ),
                  ]
                : [],
            verticalLines: showZeroX
                ? [
                    VerticalLine(
                      x: 0,
                      color: const Color(0xFF1A237E),
                      strokeWidth: 2,
                    ),
                  ]
                : [],
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(spec.xLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  if (value == 0 && !showZeroX) return const SizedBox.shrink();
                  return Text(
                    value == 0 ? '0' : value.toStringAsFixed(value.abs() >= 10 ? 0 : 1),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(spec.yLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                interval: yInterval,
                getTitlesWidget: (value, meta) {
                  if (value == 0 && !showZeroY) return const SizedBox.shrink();
                  return Text(
                    value == 0 ? '0' : value.toStringAsFixed(value.abs() >= 10 ? 0 : 1),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.shade400),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: spec.color,
              barWidth: 2.5,
              belowBarData: BarAreaData(show: false),
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }

  static double _niceInterval(double min, double max) {
    final range = (max - min).abs();
    if (range == 0) return 1;
    final raw = range / 5;
    final exponent = raw == 0 ? 0 : (log(raw) / log(10)).floor();
    final magnitude = pow(10, exponent).toDouble();
    final normalized = raw / magnitude;
    double interval;
    if (normalized <= 1) {
      interval = 1;
    } else if (normalized <= 2) {
      interval = 2;
    } else if (normalized <= 5) {
      interval = 5;
    } else {
      interval = 10;
    }
    return interval * magnitude;
  }

  Future<void> _savePaper() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) return;
    if (_selectedSubjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a subject'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one question'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = _authService.currentUserId!;
      final totalMarks = _questions.fold<int>(0, (sum, q) => sum + q.marks);

      if (widget.existingPaper != null) {
        final paperId = widget.existingPaper!['id'] as String;
        
        await Supabase.instance.client.from('exam_papers').update({
          'title': _titleController.text.trim(),
          'instructions': _instructionsController.text.trim(),
          'subject_id': _selectedSubjectId,
          'level_id': _selectedLevelId,
          'total_marks': totalMarks,
          'duration_minutes': int.tryParse(_durationController.text) ?? 120,
          'curriculum': _curriculum,
          'paper_type': _paperType,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', paperId);

        await Supabase.instance.client.from('exam_questions').delete().eq('paper_id', paperId);

        for (int i = 0; i < _questions.length; i++) {
          final q = _questions[i];
          await Supabase.instance.client.from('exam_questions').insert({
            'paper_id': paperId,
            'question_number': i + 1,
            'question_text': q.text,
            'marks': q.marks,
            'display_order': i + 1,
          });
        }
      } else {
        await _paperService.createPaper(
          creatorId: userId,
          subjectId: _selectedSubjectId!,
          levelId: _selectedLevelId,
          title: _titleController.text.trim(),
          instructions: _instructionsController.text.trim(),
          totalMarks: totalMarks,
          durationMinutes: int.tryParse(_durationController.text) ?? 120,
          curriculum: _curriculum,
          paperType: _paperType,
          questions: _questions.map((q) => ({
            'text': q.text,
            'marks': q.marks,
            'parts': [],
            'format': 'structured',
            'answer': null,
          })).toList(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingPaper != null ? 'Paper updated! ✅' : 'Exam paper saved! 📝'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildLivePaperPreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleController.text.trim().isEmpty ? 'Paper Title' : _titleController.text.trim(),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                 Text(
  '${_selectedSubjectName ?? 'Subject'} • ${_curriculum} • ${_paperType}',
  style: const TextStyle(fontSize: 13, color: Colors.grey),
),
                  Text(
                    'Total: ${_questions.fold<int>(0, (sum, q) => sum + q.marks)} marks • ${_durationController.text} minutes',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  if (_instructionsController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _instructionsController.text.trim(),
                      style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ..._questions.asMap().entries.map((entry) {
                    final q = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00897B).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Q${q.number}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00897B)),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${q.marks} marks',
                                style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildFormattedQuestionContentStatic(q.text),
                          const SizedBox(height: 12),
                          Container(
                            height: 90,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 900;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingPaper != null ? 'Edit Exam Paper' : 'Create Exam Paper'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        actions: [
          // Preview toggle button
          IconButton(
            icon: Badge(
              isLabelVisible: _questions.isNotEmpty,
              backgroundColor: Colors.white,
              textColor: const Color(0xFF00897B),
              label: Text('${_questions.length}'),
              child: Icon(
                _isPreviewOpen ? Icons.visibility_off : Icons.visibility,
                color: Colors.white,
              ),
            ),
            onPressed: _togglePreview,
            tooltip: _isPreviewOpen ? 'Hide Preview' : 'Show Preview',
          ),
          TextButton(
            onPressed: _isSaving ? null : _savePaper,
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // On large screens, show side by side
          if (isLargeScreen) {
            return Row(
              children: [
                Expanded(
                  flex: 1,
                  child: _buildEditor(),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(left: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: _buildLivePaperPreview(),
                  ),
                ),
              ],
            );
          }
          
          // On mobile, use slide-out panel
          return Stack(
            children: [
              _buildEditor(),
              // Overlay tap to close
              if (_isPreviewOpen)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _togglePreview,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              if (_isPreviewOpen)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: MediaQuery.of(context).size.width * 0.92,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
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
                                  Text(
                                    'Paper Preview',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF00897B),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.grey),
                                    onPressed: _togglePreview,
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: _buildLivePaperPreview(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Paper Settings
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Paper Title',
                    hintText: 'e.g., Mathematics Paper 2 - June 2025',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v!.isEmpty ? 'Enter title' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _instructionsController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Instructions',
                    hintText: 'Answer ALL questions...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // ✅ Level Dropdown (full width, outside Row)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: DropdownButtonFormField<String>(
                    value: _selectedLevelId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Class Level',
                      prefixIcon: const Icon(Icons.school_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    items: _levels.map((row) {
                      final level = row['levels'] as Map<String, dynamic>;
                      return DropdownMenuItem<String>(
                        value: row['level_id'] as String,
                        child: Text(level['name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedLevelId = v;
                        _selectedSubjectId = null;
                        _subjects = [];
                      });
                      if (v != null) _loadSubjectsForLevel(v);
                    },
                    validator: (v) => v == null ? 'Select a class' : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Subject + Curriculum Row
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedSubjectId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Subject',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                          ),
                          items: _subjects.map<DropdownMenuItem<String>>((row) {
                            final subject = row['subjects'] as Map<String, dynamic>;
                            return DropdownMenuItem<String>(
                              value: row['subject_id'] as String?,
                              child: Text(subject['name'] ?? ''),
                            );
                          }).toList(),
                          onChanged: (v) {
  setState(() {
    _selectedSubjectId = v;
    // ✅ Set the subject name
    if (v != null) {
      final subject = _subjects.firstWhere(
        (s) => s['subject_id'] == v || s['id'] == v,
        orElse: () => {},
      );
      final subjectData = subject['subjects'] as Map<String, dynamic>?;
      _selectedSubjectName = subjectData?['name'] ?? subject['name'];
    }
  });
},
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _curriculum,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Curriculum',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'ZIMSEC', child: Text('ZIMSEC')),
                            DropdownMenuItem(value: 'Cambridge', child: Text('Cambridge')),
                          ],
                          onChanged: (v) => setState(() => _curriculum = v!),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // FIXED: Wrap in a Container with constraints
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _paperType,
                          decoration: InputDecoration(
                            labelText: 'Paper',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Paper 1', child: Text('Paper 1')),
                            DropdownMenuItem(value: 'Paper 2', child: Text('Paper 2')),
                          ],
                          onChanged: (v) => setState(() => _paperType = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _durationController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Duration (min)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Question input - KEPT ORIGINAL
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00897B).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Q${_questions.length + 1}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00897B)),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        initialValue: _currentMarks.toString(),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Marks',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                        onChanged: (v) => _currentMarks = int.tryParse(v) ?? 5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _questionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: r'Type your question... Use math keyboard for symbols',
                    border: OutlineInputBorder(),
                    helperText: 'Math symbols will be auto-formatted with \$...\$',
                  ),
                ),
                const SizedBox(height: 8),
                // Question Preview - KEPT ORIGINAL
                Row(
                  children: [
                    const Text('Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Spacer(),
                    Switch(
                      value: _showPreview,
                      onChanged: (v) => setState(() => _showPreview = v),
                      activeColor: const Color(0xFF00897B),
                    ),
                  ],
                ),
                if (_showPreview)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: KeyedSubtree(
  key: ValueKey('preview_${_pendingCircuitData}_${_pendingDrawingData}_${_pendingGraphData}_${_pendingImageData}_${_pendingTableData}'),
  child: _LiveQuestionPreview(
    questionController: _questionController,
    questionNumber: _editingQuestionIndex != null ? _questions[_editingQuestionIndex!].number : _questions.length + 1,
    marks: _currentMarks,
    getPendingCircuitData: () => _pendingCircuitData,
    getPendingDrawingData: () => _pendingDrawingData,
    getPendingGraphData: () => _pendingGraphData,
    getPendingImageData: () => _pendingImageData,
    getPendingTableData: () => _pendingTableData,
    onRemoveCircuit: () {
      setState(() {
        _pendingCircuitData = null;
      });
    },
    onRemoveDrawing: () {
      setState(() {
        _pendingDrawingData = null;
      });
    },
    onRemoveGraph: () {
      setState(() {
        _pendingGraphData = null;
      });
    },
    onRemoveImage: () {
      setState(() {
        _pendingImageData = null;
      });
    },
    onRemoveTable: () {
      setState(() {
        _pendingTableData = null;
      });
    },
  ),
),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveQuestion,
                        icon: Icon(_editingQuestionIndex != null ? Icons.save_alt : Icons.add, size: 18),
                        label: Text(_editingQuestionIndex != null ? 'Update Question' : 'Add Question'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (_editingQuestionIndex != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _resetQuestionComposer,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                ..._questions.asMap().entries.map((entry) {
                  final q = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF00897B).withOpacity(0.1),
                        child: Text('${q.number}', style: const TextStyle(color: Color(0xFF00897B))),
                      ),
                      title: Text(
                        _stripQuestionMarkers(q.text).isNotEmpty
                            ? _stripQuestionMarkers(q.text)
                            : 'Question with diagram',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text('${q.marks} marks'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Color(0xFF00897B), size: 20),
                            onPressed: () => _startEditingQuestion(entry.key),
                            tooltip: 'Edit question',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () {
                              setState(() {
                                if (_editingQuestionIndex == entry.key) {
                                  _resetQuestionComposer();
                                }
                                _questions.removeAt(entry.key);
                              });
                            },
                            tooltip: 'Delete question',
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        if (_showMathKeyboard)
          SizedBox(
            height: 220,
            child: MathKeyboard(
              controller: _questionController,
              onClose: () => setState(() => _showMathKeyboard = false),
            ),
          ),
        if (_showGraphPlotter)
  SizedBox(
    height: 300,
    child: GraphPlotter(
      onInsertGraph: (graphData) {
        setState(() {
          _pendingGraphData = graphData;
          _showGraphPlotter = false;
          _showPreview = true;
        });
      },
    ),
  ),
        // Bottom toolbar - KEPT ORIGINAL
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey.shade100,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.start,
            children: [
              _MiniToolButton(
                icon: Icons.functions,
                label: 'Math',
                isActive: _showMathKeyboard,
                onTap: () => setState(() {
                  _showMathKeyboard = !_showMathKeyboard;
                  _showCircuitToolbar = false;
                  _showGraphPlotter = false;
                }),
              ),
              _MiniToolButton(
                icon: Icons.electrical_services,
                label: 'Circuits',
                isActive: _showCircuitToolbar,
                onTap: () async {
                  setState(() {
                    _showMathKeyboard = false;
                    _showGraphPlotter = false;
                  });
                  
                  final svgMarkup = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CircuitCanvasScreen(
                        onInsert: (svgMarkup) {
                          Navigator.pop(context, svgMarkup);
                        },
                      ),
                    ),
                  );
                  
                  if (svgMarkup != null && svgMarkup.isNotEmpty) {
                    final svgBytes = utf8.encode(svgMarkup);
                    final base64Svg = base64Encode(svgBytes);
                    setState(() {
                      _pendingCircuitData = '%%CIRCUIT:$base64Svg%%';
                      _showPreview = true;
                    });
                  }
                },
              ),
              _MiniToolButton(
                icon: Icons.insert_chart,
                label: 'Graph',
                isActive: _showGraphPlotter,
                onTap: () => setState(() {
                  _showGraphPlotter = !_showGraphPlotter;
                  _showMathKeyboard = false;
                  _showCircuitToolbar = false;
                }),
              ),
              _MiniToolButton(
                icon: Icons.draw,
                label: 'Draw',
                isActive: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DrawingCanvas(
                        onSave: (base64Image) {
                          Navigator.pop(context);
                          setState(() {
                            _pendingDrawingData = '%%DRAWING:$base64Image%%';
                            _showPreview = true;
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
              _MiniToolButton(
                icon: Icons.image_outlined,
                label: 'Image',
                isActive: false,
                onTap: _pickImageSource,
              ),
              _MiniToolButton(
                icon: Icons.table_chart_outlined,
                label: 'Table',
                isActive: false,
                onTap: _openTableEditor,
              ),
              if (_questions.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_questions.length} Qs • ${_questions.fold<int>(0, (sum, q) => sum + q.marks)} marks',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF00897B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaperQuestion {
  int number;
  String text;
  int marks;

  _PaperQuestion({required this.number, required this.text, required this.marks});
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

class _MiniToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _MiniToolButton({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00897B) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? const Color(0xFF00897B) : Colors.grey.shade300),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: isActive ? Colors.white : const Color(0xFF00897B)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: isActive ? Colors.white : const Color(0xFF00897B))),
          ],
        ),
      ),
    );
  }
}

class _LiveQuestionPreview extends StatefulWidget {
  final TextEditingController questionController;
  final int questionNumber;
  final int marks;
  final String? Function() getPendingCircuitData;
  final String? Function() getPendingDrawingData;
  final String? Function() getPendingGraphData;
  final String? Function() getPendingImageData;
  final String? Function() getPendingTableData;
  final VoidCallback? onRemoveCircuit;     // ✅ Add this
  final VoidCallback? onRemoveDrawing;     // ✅ Add this
  final VoidCallback? onRemoveGraph;       // ✅ Add this
  final VoidCallback? onRemoveImage;       // ✅ Add this
  final VoidCallback? onRemoveTable;       // ✅ Add this

  _LiveQuestionPreview({
    required this.questionController,
    required this.questionNumber,
    required this.marks,
    required this.getPendingCircuitData,
    required this.getPendingDrawingData,
    required this.getPendingGraphData,
    required this.getPendingImageData,
    required this.getPendingTableData,
    this.onRemoveCircuit,    // ✅ Add this
    this.onRemoveDrawing,    // ✅ Add this
    this.onRemoveGraph,      // ✅ Add this
    this.onRemoveImage,      // ✅ Add this
    this.onRemoveTable,      // ✅ Add this
  });

  @override
  State<_LiveQuestionPreview> createState() => _LiveQuestionPreviewState();
}

class _LiveQuestionPreviewState extends State<_LiveQuestionPreview> {
  final Map<String, Widget> _cachedWidgets = {};  
  @override
  void initState() {
    super.initState();
    widget.questionController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.questionController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _composeText() {
    final buffer = StringBuffer();
    final text = widget.questionController.text.trim();
    
    if (text.isNotEmpty) buffer.write(text);
    
    final circuitData = widget.getPendingCircuitData();
    final drawingData = widget.getPendingDrawingData();
    final graphData = widget.getPendingGraphData();
    final imageData = widget.getPendingImageData();
    final tableData = widget.getPendingTableData();
    
    if (circuitData != null && circuitData.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(circuitData);
    }
    if (drawingData != null && drawingData.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(drawingData);
    }
    if (graphData != null && graphData.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(graphData);
    }
    if (imageData != null && imageData.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(imageData);
    }
    if (tableData != null && tableData.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(tableData);
    }
    
    return buffer.toString();
  }



  @override
  Widget build(BuildContext context) {
    final text = _composeText();
    
    if (text.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          'Start typing to see formatted preview...',
          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF00897B).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility, size: 14, color: Color(0xFF00897B)),
              const SizedBox(width: 4),
              Text('Live Preview', style: TextStyle(fontSize: 11, color: const Color(0xFF00897B).withOpacity(0.8), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF00897B).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text('Q${widget.questionNumber}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00897B), fontSize: 12)),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFF9800).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text('${widget.marks} marks', style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w600, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: _buildPreviewContent(text),
        ),
        
        // ✅ Show inserted elements with remove buttons
        _buildInsertedElementsList(),
      ],
    );
  }

  // ✅ New method to show inserted elements with remove buttons
  Widget _buildInsertedElementsList() {
    final circuitData = widget.getPendingCircuitData();
    final drawingData = widget.getPendingDrawingData();
    final graphData = widget.getPendingGraphData();
    final imageData = widget.getPendingImageData();
    final tableData = widget.getPendingTableData();
    
    final List<Widget> elements = [];
    
    // Circuit indicator with remove button
    if (circuitData != null && circuitData.isNotEmpty) {
      elements.add(
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.electrical_services, size: 16, color: Colors.blue),
              const SizedBox(width: 6),
              const Text('Circuit Diagram', style: TextStyle(fontSize: 12, color: Colors.blue)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRemoveCircuit,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Drawing indicator with remove button
    if (drawingData != null && drawingData.isNotEmpty) {
      elements.add(
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.purple.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.draw, size: 16, color: Colors.purple),
              const SizedBox(width: 6),
              const Text('Drawing', style: TextStyle(fontSize: 12, color: Colors.purple)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRemoveDrawing,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Image indicator with remove button
    if (imageData != null && imageData.isNotEmpty) {
      elements.add(
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_outlined, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              const Text('Image', style: TextStyle(fontSize: 12, color: Colors.orange)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRemoveImage,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Table indicator with remove button
    if (tableData != null && tableData.isNotEmpty) {
      elements.add(
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.teal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.table_chart_outlined, size: 16, color: Colors.teal),
              const SizedBox(width: 6),
              const Text('Table', style: TextStyle(fontSize: 12, color: Colors.teal)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRemoveTable,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Graph indicator with remove button
    if (graphData != null && graphData.isNotEmpty) {
      elements.add(
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_chart, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              const Text('Graph', style: TextStyle(fontSize: 12, color: Colors.green)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRemoveGraph,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    if (elements.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: elements,
      ),
    );
  }

  // ✅ Updated to show remove buttons on the actual preview elements too
  Widget _buildPreviewContent(String text) {
    final List<String> svgs = _ExamPaperEditorScreenState._extractSvgs(text);
    final List<_GraphSpec> graphs = _ExamPaperEditorScreenState._extractGraphs(text);
    final drawings = _ExamPaperEditorScreenState._extractDrawings(text);
    final images = _ExamPaperEditorScreenState._extractImages(text);
    final tables = _ExamPaperEditorScreenState._extractTables(text);

    String cleanText = text
        .replaceAll(RegExp(r'%%CIRCUIT_LABEL:[^%]+%%'), '')
        .replaceAll(RegExp(r'%%CIRCUIT:[A-Za-z0-9+/=\s]+%%', dotAll: true), '')
        .replaceAll(RegExp(r'%%DRAWING:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%IMAGE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%TABLE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\(data:image/svg\+xml;base64,[A-Za-z0-9+/=]+\)'), '')
        .replaceAll(RegExp(r'GRAPH:[^\n]+'), '')
        .trim();

    List<Widget> contentWidgets = [];

    if (cleanText.isNotEmpty) {
      contentWidgets.add(
        MathMessageRenderer(text: cleanText, textColor: Colors.black87)
      );
    }

    for (final svg in svgs) {
      String fixedSvg = svg;
      if (!fixedSvg.contains('xmlns="http://www.w3.org/2000/svg"')) {
        fixedSvg = fixedSvg.replaceFirst(
          '<svg',
          '<svg xmlns="http://www.w3.org/2000/svg"'
        );
      }
      contentWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Stack(  // ✅ Wrap in Stack for remove button
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Circuit Diagram',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SvgPicture.string(
                          fixedSvg,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ✅ Remove button overlay
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: widget.onRemoveCircuit,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    for (final drawing in drawings) {
      final cacheKey = 'drawing_${drawing.hashCode}';
      if (!_cachedWidgets.containsKey(cacheKey)) {
        _cachedWidgets[cacheKey] = Padding(
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
              children: [
                const Text('Drawing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(base64Decode(drawing), fit: BoxFit.contain),
                ),
              ],
            ),
          ),
        );
      }
      contentWidgets.add(_cachedWidgets[cacheKey]!);
    }

    for (final spec in graphs) {
      contentWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Stack(  // ✅ Wrap in Stack for remove button
            children: [
              _ExamPaperEditorScreenState._buildGraphPreview(spec),
              // ✅ Remove button overlay
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: widget.onRemoveGraph,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

     // ✅ Cache key for images/drawings
    for (final image in images) {
      final cacheKey = 'image_${image.hashCode}';
      if (!_cachedWidgets.containsKey(cacheKey)) {
        _cachedWidgets[cacheKey] = Padding(
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
              children: [
                const Text('Inserted Image', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(base64Decode(image), fit: BoxFit.contain),
                ),
              ],
            ),
          ),
        );
      }
      contentWidgets.add(_cachedWidgets[cacheKey]!);
    }


    for (final table in tables) {
      contentWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Stack(
            children: [
              Container(
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
                    const Text(
                      'Inserted Table',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
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
                                child: Text(cell.isEmpty ? ' ' : cell),
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: widget.onRemoveTable,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (contentWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: contentWidgets,
    );
  }
}