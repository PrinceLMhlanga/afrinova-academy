import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../widgets/math_renderer.dart';

class StudentExamTakerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String subjectName;
  final int totalQuestions;
  final int timeMinutes;

  const StudentExamTakerScreen({
    super.key,
    required this.questions,
    required this.subjectName,
    required this.totalQuestions,
    required this.timeMinutes,
  });

  @override
  State<StudentExamTakerScreen> createState() => _StudentExamTakerScreenState();
}

class _StudentExamTakerScreenState extends State<StudentExamTakerScreen> {
  final AuthService _authService = AuthService();
  final Map<int, String> _answers = {};
  final Map<int, bool> _flagged = {};
  
  int _currentIndex = 0;
  int _remainingSeconds = 0;
  Timer? _timer;
  bool _isTimeUp = false;
  bool _isSubmitting = false;
  bool _showResults = false;

  // Results
  int _score = 0;
  int _totalMarks = 0;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.timeMinutes * 60;
    _startTimer();
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

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _getTimeWarning() {
    if (_remainingSeconds < 60) return 'Hurry up! Less than a minute left!';
    if (_remainingSeconds < 300) return '${_remainingSeconds ~/ 60} minutes remaining';
    return '${_remainingSeconds ~/ 60} min left';
  }

  void _selectAnswer(String option) {
    setState(() => _answers[_currentIndex] = option);
  }

  void _toggleFlag() {
    setState(() {
      if (_flagged[_currentIndex] == true) {
        _flagged.remove(_currentIndex);
      } else {
        _flagged[_currentIndex] = true;
      }
    });
  }

  void _goToQuestion(int index) {
    if (index >= 0 && index < widget.questions.length) {
      setState(() => _currentIndex = index);
    }
  }

  Future<void> _submitExam({bool autoSubmit = false}) async {
    if (_isSubmitting) return;

    if (!autoSubmit) {
      final unanswered = widget.questions.length - _answers.length;
      final flagged = _flagged.length;
      
      final message = StringBuffer();
      message.write('You have answered ${_answers.length} of ${widget.questions.length} questions.\n');
      if (unanswered > 0) message.write('$unanswered unanswered.\n');
      if (flagged > 0) message.write('$flagged flagged for review.\n');
      message.write('\nYou cannot change answers after submission.');

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Submit Exam?'),
          content: Text(message.toString()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Review')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isSubmitting = true);
    _timer?.cancel();

    // Grade the exam
    int correct = 0;
    final results = <Map<String, dynamic>>[];

    for (int i = 0; i < widget.questions.length; i++) {
      final question = widget.questions[i];
      final correctAnswer = (question['correct_answer'] as String?)?.toUpperCase() ?? '';
      final studentAnswer = _answers[i] ?? '';
      final isCorrect = studentAnswer.toUpperCase() == correctAnswer;

      if (isCorrect) correct++;

      results.add({
        'index': i + 1,
        'question': question['question_text'] ?? '',
        'option_a': question['option_a'] ?? '',
        'option_b': question['option_b'] ?? '',
        'option_c': question['option_c'] ?? '',
        'option_d': question['option_d'] ?? '',
        'correct_answer': correctAnswer,
        'student_answer': studentAnswer,
        'is_correct': isCorrect,
        'diagram_url': question['diagram_url'],
      });
    }

    // Save attempt
    try {
      final userId = _authService.currentUserId;
      if (userId != null) {
        final totalQuestions = widget.questions.length;
        final percentage = totalQuestions > 0 ? (correct / totalQuestions * 100) : 0;

        await Supabase.instance.client.from('exam_attempts').insert({
          'student_id': userId,
          'subject_id': widget.questions.first['subject_id'],
          'score': correct,
          'total_marks': totalQuestions,
          'percentage': percentage,
          'passed': percentage >= 50,
          'completed_at': DateTime.now().toIso8601String(),
          'time_taken_seconds': (widget.timeMinutes * 60) - _remainingSeconds,
        });
      }
    } catch (e) {
      debugPrint('Error saving attempt: $e');
    }

    setState(() {
      _showResults = true;
      _score = correct;
      _totalMarks = widget.questions.length;
      _results = results;
      _isSubmitting = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showResults) return _buildResults();

    final question = widget.questions[_currentIndex];
    final options = [
      question['option_a'] as String? ?? '',
      question['option_b'] as String? ?? '',
      question['option_c'] as String? ?? '',
      question['option_d'] as String? ?? '',
    ];
    final hasDiagram = question['diagram_url'] != null && (question['diagram_url'] as String).isNotEmpty;

    return WillPopScope(
      onWillPop: () async {
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave Exam?'),
            content: const Text('Your progress will be lost. Are you sure?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave', style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        return result ?? false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(widget.subjectName, style: const TextStyle(fontSize: 16)),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // Timer
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _remainingSeconds < 60 ? Colors.red.withOpacity(0.3) : _remainingSeconds < 300 ? Colors.orange.withOpacity(0.3) : Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _remainingSeconds < 60 ? Icons.timer_off : Icons.timer,
                      color: Colors.white, size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(_formatTime(_remainingSeconds),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Progress bar + timer warning
            LinearProgressIndicator(
              value: (_currentIndex + 1) / widget.questions.length,
              backgroundColor: Colors.grey.shade200,
              color: _remainingSeconds < 60 ? Colors.red : const Color(0xFFFF9800),
              minHeight: 3,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: _remainingSeconds < 60 ? Colors.red.shade50 : _remainingSeconds < 300 ? Colors.orange.shade50 : Colors.white,
              child: Row(
                children: [
                  Text(
                    'Q${_currentIndex + 1} of ${widget.questions.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const Spacer(),
                  Icon(Icons.timer, size: 14, color: _remainingSeconds < 60 ? Colors.red : Colors.grey),
                  const SizedBox(width: 4),
                  Text(_getTimeWarning(), style: TextStyle(fontSize: 11, color: _remainingSeconds < 60 ? Colors.red : Colors.grey)),
                ],
              ),
            ),

            // Question content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question text
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MathRenderer(
                            question['question_text'] ?? '',
                            fontSize: 16,
                            textColor: const Color(0xFF1A237E),
                          ),
                          // Diagram
                          if (hasDiagram)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  question['diagram_url'] as String,
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      height: 200,
                                      color: Colors.grey.shade100,
                                      child: const Center(child: CircularProgressIndicator()),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    height: 100,
                                    color: Colors.grey.shade100,
                                    child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Options
                    ...List.generate(4, (i) {
                      final letter = String.fromCharCode(65 + i);
                      final optionText = options[i];
                      if (optionText.isEmpty) return const SizedBox.shrink();
                      
                      final isSelected = _answers[_currentIndex] == letter;

                      return GestureDetector(
                        onTap: () => _selectAnswer(letter),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF1A237E).withOpacity(0.05) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade100,
                                ),
                                child: Center(
                                  child: Text(letter, style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  )),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: MathRenderer(
                                  optionText,
                                  fontSize: 14,
                                  textColor: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade700,
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle, color: Color(0xFF1A237E), size: 22),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),

                    // Flag for review
                    GestureDetector(
                      onTap: _toggleFlag,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _flagged[_currentIndex] == true ? Colors.orange.withOpacity(0.1) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _flagged[_currentIndex] == true ? Colors.orange : Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _flagged[_currentIndex] == true ? Icons.flag : Icons.flag_outlined,
                              size: 18,
                              color: _flagged[_currentIndex] == true ? Colors.orange : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _flagged[_currentIndex] == true ? 'Flagged for review' : 'Flag for review',
                              style: TextStyle(
                                fontSize: 13,
                                color: _flagged[_currentIndex] == true ? Colors.orange : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom navigation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    if (_currentIndex > 0)
                      OutlinedButton.icon(
                        onPressed: () => _goToQuestion(_currentIndex - 1),
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A237E)),
                      )
                    else
                      const SizedBox(width: 100),

                    const Spacer(),

                    // Question dots
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        widget.questions.length > 8 ? 8 : widget.questions.length,
                        (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _currentIndex
                                ? const Color(0xFFFF9800)
                                : _flagged[i] == true
                                    ? Colors.orange.shade300
                                    : _answers[i] != null
                                        ? const Color(0xFF4CAF50)
                                        : Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),

                    if (_currentIndex < widget.questions.length - 1)
                      ElevatedButton.icon(
                        onPressed: () => _goToQuestion(_currentIndex + 1),
                        icon: const Icon(Icons.arrow_forward, size: 16),
                        label: const Text('Next'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : () => _submitExam(),
                        icon: _isSubmitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 16),
                        label: Text(_isSubmitting ? 'Submitting...' : 'Submit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
  final percentage = _totalMarks > 0 ? (_score / _totalMarks * 100).toStringAsFixed(1) : '0.0';
  final passed = double.parse(percentage) >= 50;

  // ✅ Helper to get option text from letter
  String _getOptionText(String letter, Map<String, dynamic> question) {
    switch (letter.toUpperCase()) {
      case 'A': return question['option_a'] ?? '';
      case 'B': return question['option_b'] ?? '';
      case 'C': return question['option_c'] ?? '';
      case 'D': return question['option_d'] ?? '';
      default: return letter;
    }
  }

  return Scaffold(
    backgroundColor: Colors.grey.shade50,
    appBar: AppBar(
      title: const Text('Results'),
      backgroundColor: const Color(0xFF1A237E),
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Score card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: passed
                  ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                  : [Colors.red.shade400, Colors.red.shade300],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(passed ? Icons.emoji_events : Icons.sentiment_dissatisfied, size: 56, color: Colors.white),
              const SizedBox(height: 12),
              Text(passed ? 'Congratulations! 🎉' : 'Keep Practicing! 💪',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              Text('$_score / $_totalMarks', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('$percentage%', style: const TextStyle(fontSize: 18, color: Colors.white70)),
              const SizedBox(height: 4),
              Text(passed ? 'You passed!' : 'Need 50% to pass', style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Review answers
        const Text('Review Answers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        const SizedBox(height: 12),

        ..._results.asMap().entries.map((entry) {
          final index = entry.key;
          final r = entry.value;
          final isCorrect = r['is_correct'] as bool;
          final question = widget.questions[index];
          
          // ✅ Get actual option text for student's answer
          final studentLetter = r['student_answer'] as String? ?? '';
          final studentText = studentLetter.isNotEmpty 
              ? _getOptionText(studentLetter, question) 
              : 'Not answered';
          
          // ✅ Get actual option text for correct answer
          final correctLetter = r['correct_answer'] as String? ?? '';
          final correctText = correctLetter.isNotEmpty 
              ? _getOptionText(correctLetter, question) 
              : '';

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(isCorrect ? Icons.check_circle : Icons.cancel, 
                          color: isCorrect ? const Color(0xFF4CAF50) : Colors.red, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MathRenderer(
                          'Q${r['index']}: ${r['question']}',
                          fontSize: 14,
                          textColor: const Color(0xFF1A237E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // ✅ Use MathRenderer for student answer with LaTeX
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your answer: ',
                        style: TextStyle(
                          fontSize: 13, 
                          color: isCorrect ? const Color(0xFF4CAF50) : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (studentLetter.isEmpty)
                        Text(
                          'Not answered',
                          style: TextStyle(
                            fontSize: 13, 
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else
                        Expanded(
                          child: MathRenderer(
                            '$studentLetter. $studentText',
                            fontSize: 13,
                            textColor: isCorrect ? const Color(0xFF4CAF50) : Colors.red,
                          ),
                        ),
                    ],
                  ),
                  
                  if (!isCorrect && correctText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Correct: ',
                            style: TextStyle(
                              fontSize: 13, 
                              color: Color(0xFF4CAF50),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Expanded(
                            child: MathRenderer(
                              '$correctLetter. $correctText',
                              fontSize: 13,
                              textColor: const Color(0xFF4CAF50),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Back to Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ),
  );
}
}