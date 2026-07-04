import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ai/math_message_renderer.dart';
import '../../core/auth_service.dart';


class MarkingScreen extends StatefulWidget {
  final Map<String, dynamic> paper;
  final String studentId;
  final String studentName;

  const MarkingScreen({
    super.key,
    required this.paper,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<MarkingScreen> createState() => _MarkingScreenState();
}

class _MarkingScreenState extends State<MarkingScreen> {
  final AuthService _authService = AuthService();
  final Map<String, Uint8List> _imageCache = {};
  
  List<Map<String, dynamic>> _questions = [];
  Map<String, Map<String, dynamic>> _answers = {};
  Map<String, TextEditingController> _marksControllers = {};
  Map<String, TextEditingController> _commentControllers = {};
  Map<String, int?> _awardedMarks = {};
  
  bool _isLoading = true;
  bool _isSaving = false;
  int _currentQuestionIndex = 0;
  String? _paperTitle;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final questions = await Supabase.instance.client
          .from('exam_questions')
          .select()
          .eq('paper_id', widget.paper['id'])
          .order('display_order');

      final answers = await Supabase.instance.client
          .from('exam_answers')
          .select()
          .eq('paper_id', widget.paper['id'])
          .eq('student_id', widget.studentId);

      if (mounted) {
        setState(() {
          _questions = List<Map<String, dynamic>>.from(questions);
          _paperTitle = widget.paper['title'] ?? 'Exam Paper';
          _isLoading = false;
        });

        for (final a in answers) {
          final qId = a['question_id'] as String;
          _answers[qId] = a;
          _awardedMarks[qId] = a['marks_awarded'] as int?;
          _marksControllers[qId] = TextEditingController(
            text: a['marks_awarded']?.toString() ?? '',
          );
          _commentControllers[qId] = TextEditingController(
            text: a['teacher_comment'] ?? '',
          );
        }

        for (final q in _questions) {
          final qId = q['id'] as String;
          _marksControllers[qId] ??= TextEditingController();
          _commentControllers[qId] ??= TextEditingController();
          _awardedMarks[qId] ??= null;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAndNext() async {
    if (_currentQuestionIndex >= _questions.length) return;
    
    final q = _questions[_currentQuestionIndex];
    final qId = q['id'] as String;
    
    setState(() => _isSaving = true);

    try {
      final teacherId = _authService.currentUserId;
      
      await Supabase.instance.client.from('exam_answers').upsert({
        'paper_id': widget.paper['id'],
        'question_id': qId,
        'student_id': widget.studentId,
        'marks_awarded': int.tryParse(_marksControllers[qId]!.text),
        'teacher_comment': _commentControllers[qId]!.text,
        'marked_by': teacherId,
        'marked_at': DateTime.now().toIso8601String(),
        'status': 'marked',
      }, onConflict: 'paper_id, question_id, student_id');

      setState(() {
        _awardedMarks[qId] = int.tryParse(_marksControllers[qId]!.text);
      });

      if (_currentQuestionIndex < _questions.length - 1) {
        setState(() => _currentQuestionIndex++);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All questions marked! ✅'), backgroundColor: Color(0xFF4CAF50)),
          );
        }
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

  void _goToQuestion(int index) {
    if (index < 0 || index >= _questions.length) return;
    setState(() => _currentQuestionIndex = index);
  }

  // ===== RENDER HELPERS =====
  List<String> _extractSvgs(String text) {
    final regex = RegExp(r'%%CIRCUIT:([A-Za-z0-9+/=\s]+)%%', dotAll: true);
    return regex.allMatches(text).map((m) {
      try {
        final b64 = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
        return b64.isNotEmpty ? utf8.decode(base64Decode(b64)) : '';
      } catch (_) { return ''; }
    }).where((s) => s.isNotEmpty).toList();
  }

  List<String> _extractImages(String text) {
    final regex = RegExp(r'%%IMAGE:([A-Za-z0-9+/=]+)%%');
    return regex.allMatches(text).map((m) => m.group(1)!).toList();
  }

  List<String> _extractDrawings(String text) {
    final regex = RegExp(r'%%DRAWING:([A-Za-z0-9+/=]+)%%');
    return regex.allMatches(text).map((m) => m.group(1)!).toList();
  }

  List<_GraphSpec> _extractGraphs(String text) {
    final regex = RegExp(r'GRAPH:([^:]+):([^:]+):([^:]+):([a-fA-F0-9]+):(.+)');
    return regex.allMatches(text).map((m) => _GraphSpec(
      title: m.group(1) ?? 'Graph', xLabel: m.group(2) ?? 'x', yLabel: m.group(3) ?? 'y',
      color: Color(int.parse(m.group(4)!, radix: 16)), data: m.group(5) ?? '',
    )).toList();
  }

  // ✅ Used for both question AND answer rendering
  Widget _buildFormattedContent(String text, {List<dynamic>? additionalImages}) {
  if (text.isEmpty && (additionalImages == null || additionalImages.isEmpty)) {
    return const Text('No answer submitted.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
  }

  final svgs = _extractSvgs(text);
  final drawings = _extractDrawings(text);
  final images = _extractImages(text);
  final graphs = _extractGraphs(text);

  // Also add images from the workings_images column
  final allImages = <String>[...images];
  if (additionalImages != null) {
    for (final img in additionalImages) {
      if (img is String && img.isNotEmpty && !allImages.contains(img)) {
        allImages.add(img);
      }
    }
  }
  
  String cleanText = text
      .replaceAll(RegExp(r'%%CIRCUIT:[A-Za-z0-9+/=\s]+%%', dotAll: true), '')
      .replaceAll(RegExp(r'%%DRAWING:[A-Za-z0-9+/=]+%%'), '')
      .replaceAll(RegExp(r'%%IMAGE:[A-Za-z0-9+/=]+%%'), '')
      .replaceAll(RegExp(r'GRAPH:[^\n]+'), '')
      .trim();

  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    if (cleanText.isNotEmpty) MathMessageRenderer(text: cleanText, textColor: Colors.black87),
    ...allImages.map((img) {
      if (!_imageCache.containsKey(img)) {
        try {
          _imageCache[img] = base64Decode(img);
        } catch (_) {
          return const SizedBox.shrink();
        }
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(_imageCache[img]!, fit: BoxFit.contain),
        ),
      );
    }),
    ...svgs.map((s) => Padding(padding: const EdgeInsets.only(top: 8), child: SvgPicture.string(s, height: 150))),
    ...drawings.map((d) {
      if (!_imageCache.containsKey(d)) {
        try {
          _imageCache[d] = base64Decode(d);
        } catch (_) {
          return const SizedBox.shrink();
        }
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_imageCache[d]!, fit: BoxFit.contain)),
      );
    }),
    ...graphs.map((g) => Padding(padding: const EdgeInsets.only(top: 12), child: _buildGraphPreview(g))),
  ]);
}

  // ✅ Updated graph with bold axes through origin
  Widget _buildGraphPreview(_GraphSpec spec) {
    final spots = spec.data.split(';').where((p) => p.contains(',')).map((p) {
      final v = p.split(',');
      return FlSpot(double.tryParse(v.first.trim()) ?? 0, double.tryParse(v.last.trim()) ?? 0);
    }).toList();
    if (spots.length < 2) return const SizedBox.shrink();

    final minX = spots.map((s) => s.x).reduce(min), maxX = spots.map((s) => s.x).reduce(max);
    final minY = spots.map((s) => s.y).reduce(min), maxY = spots.map((s) => s.y).reduce(max);
    final xPad = (maxX - minX).abs() < 1 ? 1.0 : (maxX - minX) * 0.18;
    final yPad = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.18;

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
      padding: const EdgeInsets.only(right: 40, top: 20, bottom: 20, left: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LineChart(LineChartData(
        minX: leftBound, maxX: rightBound, minY: bottomBound, maxY: topBound,
        gridData: FlGridData(
          show: true, drawVerticalLine: true, drawHorizontalLine: true,
          getDrawingVerticalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 0.5),
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 0.5),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: showZeroY
              ? [HorizontalLine(y: 0, color: Colors.black54, strokeWidth: 1.2, dashArray: [4, 4])]
              : [],
          verticalLines: showZeroX
              ? [VerticalLine(x: 0, color: Colors.black54, strokeWidth: 1.2, dashArray: [4, 4])]
              : [],
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black, width: 2),
            bottom: BorderSide(color: Colors.black, width: 2),
            right: BorderSide(color: Colors.transparent),
            top: BorderSide(color: Colors.transparent),
          ),
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
              showTitles: true, reservedSize: 28, interval: xInterval,
              getTitlesWidget: (value, meta) {
                if (value == value.roundToDouble()) {
                  return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey));
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(spec.yLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 36, interval: yInterval,
              getTitlesWidget: (value, meta) {
                if (value == value.roundToDouble()) {
                  return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey));
                }
                return const SizedBox.shrink();
              },
            ),
          ),
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
            spots: spots, color: spec.color, barWidth: 3, isStrokeCapRound: true,
            belowBarData: BarAreaData(show: true, color: spec.color.withOpacity(0.08)),
            dotData: FlDotData(show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 5, color: Colors.white, strokeWidth: 2, strokeColor: spec.color,
              ),
            ),
          ),
        ],
      )),
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
    if (normalized <= 1) interval = 1;
    else if (normalized <= 2) interval = 2;
    else if (normalized <= 5) interval = 5;
    else interval = 10;
    return interval * magnitude;
  }

  @override
  void dispose() {
    for (final c in _marksControllers.values) { c.dispose(); }
    for (final c in _commentControllers.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Marking'), backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final currentQ = _questions[_currentQuestionIndex];
    final qId = currentQ['id'] as String;
    final answer = _answers[qId];
    final answerText = answer?['text_answer'] as String? ?? '';
    final finalAnswer = answer?['final_answer'] as String? ?? '';
    final totalMarks = currentQ['marks'] as int? ?? 0;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('$_paperTitle — ${widget.studentName}'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Center(
            child: Text('${_currentQuestionIndex + 1} of ${_questions.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(children: [
        // Question navigator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_questions.length, (i) {
                final qId_i = _questions[i]['id'] as String;
                final isMarked = _awardedMarks[qId_i] != null;
                return GestureDetector(
                  onTap: () => _goToQuestion(i),
                  child: Container(
                    width: 40, height: 40, margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: i == _currentQuestionIndex ? const Color(0xFF1A237E) 
                          : isMarked ? const Color(0xFF4CAF50).withOpacity(0.2) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: i == _currentQuestionIndex ? const Color(0xFF1A237E) : Colors.grey.shade300, width: i == _currentQuestionIndex ? 2 : 1),
                    ),
                    child: Center(child: Text('${i + 1}',
                      style: TextStyle(fontWeight: FontWeight.bold,
                        color: i == _currentQuestionIndex ? Colors.white : isMarked ? const Color(0xFF4CAF50) : Colors.grey))),
                  ),
                );
              }),
            ),
          ),
        ),

        Expanded(child: Row(children: [
          // Left: Question + Student's answer
          Expanded(flex: 3, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Question header
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF1A237E).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('Question ${_currentQuestionIndex + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E)))),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFF9800).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('$totalMarks marks', style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 12),

              // ✅ Question text — now uses _buildFormattedContent for graphs/circuits
              Container(width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                child: _buildFormattedContent(currentQ['question_text'] ?? '')),
              const SizedBox(height: 16),

              // Final answer
              if (finalAnswer.isNotEmpty) ...[
                Container(width: double.infinity, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.05), borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Final Answer:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50), fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(finalAnswer, style: const TextStyle(fontSize: 15)),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // Student's workings
                            // Student's workings
              const Text('Student Answer:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A237E))),
              const SizedBox(height: 8),

              // ✅ Parse workings_images from the answer
              Builder(builder: (_) {
                List<dynamic> workingsImages = [];
                final rawWorkings = answer?['workings_images'];
                if (rawWorkings is List) {
                  workingsImages = rawWorkings;
                } else if (rawWorkings is String && rawWorkings.startsWith('[')) {
                  try {
                    workingsImages = jsonDecode(rawWorkings) as List<dynamic>;
                  } catch (_) {}
                }

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _buildFormattedContent(
                    answerText,
                    additionalImages: workingsImages,
                  ),
                );
              }),
            ]),
          )),

          // Right: Marking panel
          Expanded(flex: 1, child: Container(
            color: Colors.white,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(padding: const EdgeInsets.all(14), color: const Color(0xFF1A237E).withOpacity(0.03), child: Row(children: [
                const Text('Marking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E))),
                const Spacer(),
                if (_awardedMarks[qId] != null)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text('Marked ✅', style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w600))),
              ])),
              const Divider(height: 1),
              Padding(padding: const EdgeInsets.all(14), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Marks Awarded', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _marksControllers[qId],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '/ $totalMarks',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                      suffixText: '/ $totalMarks',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Comment', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _commentControllers[qId],
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Feedback for student...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveAndNext,
                    icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                        : const Icon(Icons.check),
                    label: Text(_currentQuestionIndex < _questions.length - 1 ? 'Save & Next →' : 'Save & Finish ✅'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (_currentQuestionIndex > 0)
                      Expanded(child: OutlinedButton(
                        onPressed: () => _goToQuestion(_currentQuestionIndex - 1),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A237E)),
                        child: const Text('← Previous'),
                      )),
                    if (_currentQuestionIndex < _questions.length - 1)
                      Expanded(child: OutlinedButton(
                        onPressed: () => _goToQuestion(_currentQuestionIndex + 1),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A237E)),
                        child: const Text('Next →'),
                      )),
                  ]),
                ],
              )),
            ]),
          )),
        ])),
      ]),
    );
  }
}

class _GraphSpec {
  final String title, xLabel, yLabel, data;
  final Color color;
  const _GraphSpec({required this.title, required this.xLabel, required this.yLabel, required this.color, required this.data});
}