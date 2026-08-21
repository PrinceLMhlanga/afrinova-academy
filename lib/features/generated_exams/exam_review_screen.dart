import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../../core/auth_service.dart';
import '../../widgets/math_renderer.dart';

class ExamReviewScreen extends StatefulWidget {
  final String sessionId;
  final String subjectName;

  const ExamReviewScreen({
    super.key,
    required this.sessionId,
    required this.subjectName,
  });

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;
  int _correct = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get all questions from this session
      final history = await Supabase.instance.client
          .from('practice_exam_history')
          .select('''
            *,
            question:question_id(
              question_text,
              option_a,
              option_b,
              option_c,
              option_d,
              correct_answer,
              explanation,
              diagram_url
            )
          ''')
          .eq('exam_session_id', widget.sessionId)
          .eq('student_id', userId)
          .order('attempted_at', ascending: true);

      int correct = 0;
      final questions = <Map<String, dynamic>>[];

      for (final record in history) {
        if (record['is_correct'] == true) correct++;
        
        // Get AI explanation if exists
        final aiFeedback = await Supabase.instance.client
            .from('exam_ai_feedback')
            .select('ai_explanation')
            .eq('question_id', record['question_id'])
            .maybeSingle();

        questions.add({
          ...record,
          'ai_explanation': aiFeedback?['ai_explanation'],
        });
      }

      if (mounted) {
        setState(() {
          _questions = questions;
          _correct = correct;
          _total = history.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading session: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final percentage = _total > 0 ? (_correct / _total * 100).toStringAsFixed(1) : '0.0';
    final passed = double.parse(percentage) >= 50;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.subjectName),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Score summary
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: passed
                          ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                          : [Colors.red.shade400, Colors.red.shade300],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(passed ? Icons.emoji_events : Icons.sentiment_dissatisfied, color: Colors.white, size: 40),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$_correct / $_total correct', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('$percentage% • ${_questions.length} questions', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Questions
                ..._questions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final q = entry.value;
                  final question = q['question'] as Map<String, dynamic>?;
                  final isCorrect = q['is_correct'] == true;
                  final aiExplanation = q['ai_explanation'] as String?;

                  // ✅ Check for diagram
                  final hasDiagram = question?['diagram_url'] != null && 
                      (question?['diagram_url'] as String? ?? '').isNotEmpty;
                  final diagramUrl = question?['diagram_url'] as String?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: isCorrect ? const Color(0xFF4CAF50) : Colors.red, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: MathRenderer(
                                  'Q${index + 1}: ${question?['question_text'] ?? 'N/A'}',
                                  fontSize: 14,
                                  textColor: const Color(0xFF1A237E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          // ✅ Diagram display
                          if (hasDiagram && diagramUrl != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  diagramUrl,
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      height: 200,
                                      color: Colors.grey.shade100,
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    height: 100,
                                    color: Colors.grey.shade100,
                                    child: const Center(
                                      child: Icon(Icons.broken_image, color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          
                          // Options
                          if (question != null) ...[
                            _buildOption('A', question['option_a'] as String?, q['selected_answer'] == 'A', question['correct_answer'] == 'A', isCorrect),
                            _buildOption('B', question['option_b'] as String?, q['selected_answer'] == 'B', question['correct_answer'] == 'B', isCorrect),
                            _buildOption('C', question['option_c'] as String?, q['selected_answer'] == 'C', question['correct_answer'] == 'C', isCorrect),
                            _buildOption('D', question['option_d'] as String?, q['selected_answer'] == 'D', question['correct_answer'] == 'D', isCorrect),
                          ],
                          
                          // AI Explanation for wrong answers
                          if (!isCorrect && aiExplanation != null && aiExplanation.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.purple.shade50, Colors.blue.shade50],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.auto_awesome, color: Colors.purple, size: 14),
                                      SizedBox(width: 6),
                                      Text('AI Feedback', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.purple)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  GptMarkdown(
                                    aiExplanation,
                                    useDollarSignsForLatex: true,
                                    style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildOption(String letter, String? text, bool isSelected, bool isCorrect, bool questionCorrect) {
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    
    Color bgColor = Colors.grey.shade50;
    Color borderColor = Colors.grey.shade200;
    
    if (isSelected && isCorrect) {
      bgColor = const Color(0xFF4CAF50).withOpacity(0.1);
      borderColor = const Color(0xFF4CAF50);
    } else if (isSelected && !isCorrect) {
      bgColor = Colors.red.withOpacity(0.1);
      borderColor = Colors.red;
    } else if (isCorrect && !questionCorrect) {
      bgColor = const Color(0xFF4CAF50).withOpacity(0.05);
      borderColor = const Color(0xFF4CAF50).withOpacity(0.5);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? (isCorrect ? const Color(0xFF4CAF50) : Colors.red) : Colors.grey.shade300,
            ),
            child: Center(child: Text(letter, style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MathRenderer(
              text,
              fontSize: 13,
              textColor: Colors.black87,
            ),
          ),
          if (isCorrect) const Icon(Icons.check, color: Color(0xFF4CAF50), size: 16),
        ],
      ),
    );
  }
}