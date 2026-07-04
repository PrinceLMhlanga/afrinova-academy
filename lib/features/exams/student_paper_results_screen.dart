import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ai/math_message_renderer.dart';
import '../../core/auth_service.dart';

class StudentPaperResultsScreen extends StatefulWidget {
  final Map<String, dynamic> paper;
  final Map<String, dynamic> submission;

  const StudentPaperResultsScreen({
    super.key,
    required this.paper,
    required this.submission,
  });

  @override
  State<StudentPaperResultsScreen> createState() => _StudentPaperResultsScreenState();
}

class _StudentPaperResultsScreenState extends State<StudentPaperResultsScreen> {
  List<Map<String, dynamic>> _questions = [];
  Map<String, Map<String, dynamic>> _answers = {};
  final Map<String, Uint8List> _imageCache = {};
  final AuthService _authService = AuthService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final questions = await Supabase.instance.client
          .from('exam_questions')
          .select()
          .eq('paper_id', widget.paper['id'])
          .order('display_order');

      final answers = await Supabase.instance.client
          .from('exam_answers')
          .select()
          .eq('paper_id', widget.paper['id'])
          .eq('student_id', userId);

      if (mounted) {
        setState(() {
          _questions = List<Map<String, dynamic>>.from(questions);
          for (final a in answers) {
            _answers[a['question_id'] as String] = a;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading results: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ===== EXTRACTION METHODS =====
  
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
      title: m.group(1) ?? 'Graph', 
      xLabel: m.group(2) ?? 'x', 
      yLabel: m.group(3) ?? 'y',
      color: Color(int.parse(m.group(4)!, radix: 16)), 
      data: m.group(5) ?? '',
    )).toList();
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
  
  Widget _buildFormattedContent(String text, {List<dynamic>? additionalImages}) {
    if (text.isEmpty && (additionalImages == null || additionalImages.isEmpty)) {
      return const Text('No answer submitted.', 
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
    }

    final svgs = _extractSvgs(text);
    final drawings = _extractDrawings(text);
    final images = _extractImages(text);
    final graphs = _extractGraphs(text);
    final tables = _extractTables(text);  // ✅ Extract tables

    // Combine images from text and additional images
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
        .replaceAll(RegExp(r'%%TABLE:[A-Za-z0-9+/=]+%%'), '')  // ✅ Clean table markers
        .replaceAll(RegExp(r'GRAPH:[^\n]+'), '')
        .trim();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      // Text content
      if (cleanText.isNotEmpty) 
        MathMessageRenderer(text: cleanText, textColor: Colors.black87),
      
      // ✅ Tables
      ...tables.map((table) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.table_chart, size: 14, color: Colors.teal),
                  SizedBox(width: 4),
                  Text('Table', style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 11, 
                    color: Colors.grey,
                  )),
                ],
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
      )),
      
      // Images
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text('Image', style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 11, 
                    color: Colors.grey,
                  )),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8), 
                child: Image.memory(_imageCache[img]!, fit: BoxFit.contain),
              ),
            ],
          ),
        );
      }),
      
      // Circuit diagrams
      ...svgs.map((s) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.electrical_services, size: 14, color: Colors.orange),
                SizedBox(width: 4),
                Text('Circuit Diagram', style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 11, 
                  color: Colors.grey,
                )),
              ],
            ),
            const SizedBox(height: 4),
            SvgPicture.string(s, height: 120),
          ],
        ),
      )),
      
      // Drawings
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.draw, size: 14, color: Colors.purple),
                  SizedBox(width: 4),
                  Text('Drawing', style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 11, 
                    color: Colors.grey,
                  )),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8), 
                child: Image.memory(_imageCache[d]!, fit: BoxFit.contain),
              ),
            ],
          ),
        );
      }),
      
      // Graphs
      ...graphs.map((g) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_chart, size: 14, color: Colors.blue),
                const SizedBox(width: 4),
                Text(g.title, style: const TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 11, 
                  color: Colors.grey,
                )),
              ],
            ),
            const SizedBox(height: 4),
            _buildGraphPreview(g),
          ],
        ),
      )),
    ]);
  }

  // ===== QUESTION CONTENT RENDERING (for the question itself) =====
  
  Widget _buildQuestionContent(String text) {
    final svgs = _extractSvgs(text);
    final drawings = _extractDrawings(text);
    final images = _extractImages(text);
    final graphs = _extractGraphs(text);
    final tables = _extractTables(text);

    String cleanText = text
        .replaceAll(RegExp(r'%%CIRCUIT:[A-Za-z0-9+/=\s]+%%', dotAll: true), '')
        .replaceAll(RegExp(r'%%DRAWING:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%IMAGE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'%%TABLE:[A-Za-z0-9+/=]+%%'), '')
        .replaceAll(RegExp(r'GRAPH:[^\n]+'), '')
        .trim();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (cleanText.isNotEmpty) 
        MathMessageRenderer(text: cleanText, textColor: Colors.black87),
      
      ...tables.map((table) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            border: TableBorder.all(color: Colors.grey.shade300),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: table.map((row) => TableRow(
              children: row.map((cell) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text(cell.isEmpty ? ' ' : cell, style: const TextStyle(fontSize: 13)),
              )).toList(),
            )).toList(),
          ),
        ),
      )),
      
      ...images.map((img) {
        if (!_imageCache.containsKey(img)) {
          try { _imageCache[img] = base64Decode(img); } catch (_) {}
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _imageCache.containsKey(img) 
              ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_imageCache[img]!, fit: BoxFit.contain))
              : const SizedBox.shrink(),
        );
      }),
      
      ...svgs.map((s) => Padding(padding: const EdgeInsets.only(top: 8), child: SvgPicture.string(s, height: 120))),
      
      ...drawings.map((d) {
        if (!_imageCache.containsKey(d)) {
          try { _imageCache[d] = base64Decode(d); } catch (_) {}
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _imageCache.containsKey(d)
              ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_imageCache[d]!, fit: BoxFit.contain))
              : const SizedBox.shrink(),
        );
      }),
      
      ...graphs.map((g) => Padding(padding: const EdgeInsets.only(top: 8), child: _buildGraphPreview(g))),
    ]);
  }

  Widget _buildGraphPreview(_GraphSpec spec) {
    final spots = spec.data.split(';').where((p) => p.contains(',')).map((p) {
      final v = p.split(',');
      return FlSpot(double.tryParse(v.first.trim()) ?? 0, double.tryParse(v.last.trim()) ?? 0);
    }).toList();
    if (spots.length < 2) return const SizedBox.shrink();

    final minX = spots.map((s) => s.x).reduce(min), maxX = spots.map((s) => s.x).reduce(max);
    final minY = spots.map((s) => s.y).reduce(min), maxY = spots.map((s) => s.y).reduce(max);
    final xPad = (maxX - minX).abs() < 1 ? 1.0 : (maxX - minX) * 0.15;
    final yPad = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.15;

    return Container(
      height: 200, 
      padding: const EdgeInsets.only(right: 40, top: 20, bottom: 20, left: 8),
      decoration: BoxDecoration(
        color: Colors.white, 
        border: Border.all(color: Colors.grey.shade300), 
        borderRadius: BorderRadius.circular(8),
      ),
      child: LineChart(LineChartData(
        minX: minX - xPad, maxX: maxX + xPad, minY: minY - yPad, maxY: maxY + yPad,
        gridData: FlGridData(show: true, drawVerticalLine: true, drawHorizontalLine: true,
          getDrawingVerticalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 0.5),
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 0.5)),
        borderData: FlBorderData(show: true, border: const Border(
          left: BorderSide(color: Colors.black, width: 2), 
          bottom: BorderSide(color: Colors.black, width: 2),
          right: BorderSide(color: Colors.transparent), 
          top: BorderSide(color: Colors.transparent))),
        lineBarsData: [LineChartBarData(
          spots: spots, color: spec.color, barWidth: 3, isStrokeCapRound: true,
          belowBarData: BarAreaData(show: true, color: spec.color.withOpacity(0.08)),
          dotData: FlDotData(show: true, getDotPainter: (_, __, ___, ____) =>
            FlDotCirclePainter(radius: 5, color: Colors.white, strokeWidth: 2, strokeColor: spec.color)))],
      )),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) { return dateStr; }
  }

  @override
  Widget build(BuildContext context) {
    int totalAwarded = 0;
    for (final a in _answers.values) {
      totalAwarded += (a['marks_awarded'] as int?) ?? 0;
    }
    final totalMarks = widget.paper['total_marks'] as int? ?? 0;
    final markedAt = _answers.values.firstWhere(
      (a) => a['marked_at'] != null,
      orElse: () => {},
    )['marked_at'] as String?;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.paper['title'] ?? 'Marked Paper'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Score header card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [const Color(0xFF4CAF50), const Color(0xFF4CAF50).withOpacity(0.8)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.assignment_turned_in, color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Marked Paper', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            Text('$totalAwarded / $totalMarks marks',
                                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                            if (totalMarks > 0)
                              Text('${((totalAwarded / totalMarks) * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
                          ],
                        )),
                      ],
                    ),
                  ),
                  if (markedAt != null) ...[
                    const SizedBox(height: 8),
                    Text('Marked on ${_formatDate(markedAt)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                  const SizedBox(height: 20),

                  // Paper info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.2)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.paper['title'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${widget.paper['curriculum'] ?? ''} • ${widget.paper['paper_type'] ?? ''}',
                          style: const TextStyle(color: Colors.grey)),
                      if (widget.paper['instructions']?.toString().isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Text(widget.paper['instructions'], 
                          style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Questions & Answers
                  ..._questions.asMap().entries.map((entry) {
                    final q = entry.value;
                    final qId = q['id'] as String;
                    final answer = _answers[qId];
                    final answerText = answer?['text_answer'] as String? ?? '';
                    final answerMarks = answer?['marks_awarded'] as int?;
                    final totalQMarks = q['marks'] as int? ?? 0;
                    final teacherComment = answer?['teacher_comment'] as String?;
                    final finalAnswer = answer?['final_answer'] as String?;

                    // Parse workings_images
                    List<dynamic> workingsImages = [];
                    final rawWorkings = answer?['workings_images'];
                    if (rawWorkings is List) {
                      workingsImages = rawWorkings;
                    } else if (rawWorkings is String && rawWorkings.startsWith('[')) {
                      try { workingsImages = jsonDecode(rawWorkings); } catch (_) {}
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Question header
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A237E).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Question ${entry.key + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: answerMarks != null
                                    ? const Color(0xFF4CAF50).withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${answerMarks ?? '?'} / $totalQMarks marks',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: answerMarks != null ? const Color(0xFF4CAF50) : Colors.grey,
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),

                          // Question text
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: _buildQuestionContent(q['question_text'] ?? ''),  // ✅ Use proper question renderer
                          ),
                          const SizedBox(height: 16),

                          // Student's answer
                          const Text('Your Answer:', 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A237E))),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: _buildFormattedContent(answerText, additionalImages: workingsImages),
                          ),

                          // ✅ Final answer if submitted
                          if (finalAnswer != null && finalAnswer.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(children: [
                                    Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                                    SizedBox(width: 6),
                                    Text('Final Answer:', 
                                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(finalAnswer, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ],

                          // Teacher's comment/correction
                          if (teacherComment != null && teacherComment.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(children: [
                                    Icon(Icons.comment, size: 16, color: Colors.red),
                                    SizedBox(width: 6),
                                    Text('Teacher\'s Comment:', 
                                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(teacherComment, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

class _GraphSpec {
  final String title, xLabel, yLabel, data;
  final Color color;
  const _GraphSpec({required this.title, required this.xLabel, required this.yLabel, required this.color, required this.data});
}