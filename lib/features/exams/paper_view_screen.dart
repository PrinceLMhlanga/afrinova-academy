import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ai/math_message_renderer.dart';
import 'student_exam_taker_screen.dart';

class PaperViewScreen extends StatefulWidget {
  final Map<String, dynamic> paper;

  const PaperViewScreen({super.key, required this.paper});

  @override
  State<PaperViewScreen> createState() => _PaperViewScreenState();
}

class _PaperViewScreenState extends State<PaperViewScreen> {
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;
  String? _submissionStatus;
  bool _isCheckingSubmission = true;

  @override
  void initState() {
    super.initState();
    _checkSubmission();
    _loadQuestions();
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
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

 Future<void> _checkSubmission() async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    debugPrint('🔍 Checking submission for paper: ${widget.paper['id']}, student: $userId');

    // ✅ Get ALL answers for this paper (not just single)
    final response = await Supabase.instance.client
        .from('exam_answers')
        .select('status')
        .eq('paper_id', widget.paper['id'])
        .eq('student_id', userId);

    debugPrint('📋 Found ${response.length} answer(s) for this paper');

    // ✅ Determine status: highest priority wins
    String? finalStatus;
    final statuses = response.map((r) => r['status'] as String?).toList();
    
    if (statuses.contains('marked')) {
      finalStatus = 'marked';
    } else if (statuses.contains('submitted')) {
      finalStatus = 'submitted';
    } else if (statuses.contains('draft')) {
      finalStatus = 'draft';
    }

    debugPrint('📋 Final submission status: ${finalStatus ?? 'null (no submission)'}');

    if (mounted) {
      setState(() {
        _submissionStatus = finalStatus;
        _isCheckingSubmission = false;
      });
    }
  } catch (e) {
    debugPrint('❌ Submission check error: $e');
    if (mounted) setState(() => _isCheckingSubmission = false);
  }
}

  List<String> _extractSvgs(String text) {
  final List<String> svgs = [];

  // Try new format: %%CIRCUIT:base64%%
  final newRegex = RegExp(r'%%CIRCUIT:([A-Za-z0-9+/=\s]+)%%', dotAll: true);
  for (final match in newRegex.allMatches(text)) {
    try {
      final base64Svg = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
      if (base64Svg.isNotEmpty) {
        final svgString = utf8.decode(base64Decode(base64Svg));
        if (svgString.isNotEmpty) svgs.add(svgString);
      }
    } catch (_) {}
  }

  // Try old format: ![Circuit](data:image/svg+xml;base64,...)
  final oldRegex = RegExp(r'!\[[^\]]*\]\((data:image/svg\+xml;base64,([A-Za-z0-9+/=]+))\)', dotAll: true);
  for (final match in oldRegex.allMatches(text)) {
    try {
      final dataUri = match.group(1)!;
      final svgPayload = dataUri.split(',').last;
      final svgString = utf8.decode(base64Decode(svgPayload));
      if (svgString.isNotEmpty) svgs.add(svgString);
    } catch (_) {}
  }

  return svgs;
}

// Add these extraction methods
static List<String> _extractImages(String text) {
  final List<String> images = [];
  final imageRegex = RegExp(r'%%IMAGE:([A-Za-z0-9+/=]+)%%');
  for (final match in imageRegex.allMatches(text)) {
    images.add(match.group(1)!);
  }
  return images;
}

static List<String> _extractDrawings(String text) {
  final List<String> drawings = [];
  final drawingRegex = RegExp(r'%%DRAWING:([A-Za-z0-9+/=]+)%%');
  for (final match in drawingRegex.allMatches(text)) {
    drawings.add(match.group(1)!);
  }
  return drawings;
}

static List<List<List<String>>> _extractTables(String text) {
  final List<List<List<String>>> tables = [];
  
  // Try to find TABLE markers
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

  List<_GraphSpec> _extractGraphs(String text) {
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

  Widget _buildFormattedQuestionContent(String text) {
  final List<String> svgs = _extractSvgs(text);
  final List<_GraphSpec> graphs = _extractGraphs(text);
  final drawings = _extractDrawings(text);
  final images = _extractImages(text);
  final tables = _extractTables(text);

  // Clean text - remove all markers
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

  // Text content
  if (cleanText.isNotEmpty) {
    contentWidgets.add(
      MathMessageRenderer(text: cleanText, textColor: Colors.black87)
    );
  }

  // Circuit diagrams
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

  // Drawings
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

  // Images
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
                'Image',
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

  // Graphs
  for (final spec in graphs) {
    contentWidgets.add(
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _buildGraphPreview(spec),
      ),
    );
  }

  // Tables
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
                'Table',
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
                          child: Text(
                            cell.isEmpty ? ' ' : cell,
                            style: const TextStyle(fontSize: 13),
                          ),
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
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.shade400),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(right: 6),
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
            bottomTitles: AxisTitles(
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(top: 6),
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
            LineChartBarData(
              spots: spots,
              color: spec.color,
              barWidth: 2.5,
              dotData: const FlDotData(show: true),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.paper['title'] ?? 'Exam Paper'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Paper header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF00897B).withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.paper['title'] ?? '',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('${widget.paper['curriculum'] ?? ''} • ${widget.paper['paper_type'] ?? ''}'),
                        Text('Total: ${widget.paper['total_marks'] ?? 0} marks • ${widget.paper['duration_minutes'] ?? 0} minutes'),
                        if (widget.paper['instructions'] != null && widget.paper['instructions'].toString().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(widget.paper['instructions'],
                              style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Start Exam Button
// Show appropriate button based on submission status
if (_isCheckingSubmission)
  const Center(child: Padding(
    padding: EdgeInsets.all(20),
    child: CircularProgressIndicator(),
  ))
else if (_submissionStatus == 'submitted')
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.hourglass_bottom, color: Colors.orange, size: 24),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paper Submitted', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
            Text('Awaiting teacher marking...', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ],
    ),
  )
else if (_submissionStatus == 'marked')
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF4CAF50).withOpacity(0.05),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 24),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paper Marked', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4CAF50))),
            Text('View your results in Exam Papers > Marked', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ],
    ),
  )
else if (_submissionStatus == 'draft')
  SizedBox(
    width: double.infinity,
    height: 56,
    child: ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentExamTakerScreen(paper: widget.paper),
          ),
        );
      },
      icon: const Icon(Icons.edit_note, size: 24),
      label: Text(
        'Continue Exam (${widget.paper['duration_minutes'] ?? 0} minutes)',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  )
else
  SizedBox(
    width: double.infinity,
    height: 56,
    child: ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentExamTakerScreen(paper: widget.paper),
          ),
        );
      },
      icon: const Icon(Icons.edit_note, size: 24),
      label: Text(
        'Start Exam (${widget.paper['duration_minutes'] ?? 0} minutes)',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  ),
const SizedBox(height: 24),

                  // Questions
                  ..._questions.asMap().entries.map((entry) {
                    final q = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
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
                                child: Text('Q${entry.key + 1}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00897B))),
                              ),
                              const Spacer(),
                              Text('${q['marks'] ?? 0} marks',
                                  style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildFormattedQuestionContent(q['question_text'] ?? ''),
                          // Answer space
                      

                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
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