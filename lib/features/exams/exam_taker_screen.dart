import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/exam_service.dart';
import '../../core/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExamTakerScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const ExamTakerScreen({super.key, required this.exam});

  @override
  State<ExamTakerScreen> createState() => _ExamTakerScreenState();
}

class _ExamTakerScreenState extends State<ExamTakerScreen> {
  final ExamService _examService = ExamService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _questions = [];
  Map<int, String> _answers = {}; // questionIndex -> answer
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Timer
  int? _durationSeconds;
  int _remainingSeconds = 0;
  Timer? _timer;
  bool _isTimeUp = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final questions =
          await _examService.getQuestions(widget.exam['id']);
      final durationMin = widget.exam['duration_minutes'];

      if (mounted) {
        for (var i = 0; i < questions.length; i++) {
    debugPrint('Q${i + 1}: display_order=${questions[i]['display_order']}, text=${questions[i]['question_text']}');
  }
        setState(() {
          _questions = questions;
          _isLoading = false;

          if (durationMin != null && durationMin > 0) {
            _durationSeconds = durationMin * 60;
            _remainingSeconds = _durationSeconds!;
            _startTimer();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading questions: $e')),
        );
      }
    }
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

  Future<void> _submitExam({bool autoSubmit = false}) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Calculate score
      int totalMarks = 0;
      int scoredMarks = 0;

      for (int i = 0; i < _questions.length; i++) {
        final question = _questions[i];
        final marks = question['marks'] as int? ?? 1;
        totalMarks += marks;

        final studentAnswer = _answers[i] ?? '';
        final correctAnswer = question['correct_answer'] as String? ?? '';

        if (studentAnswer.trim().toLowerCase() ==
            correctAnswer.trim().toLowerCase()) {
          scoredMarks += marks;
        }
      }

      final percentage = totalMarks > 0
          ? ((scoredMarks / totalMarks) * 100).toStringAsFixed(1)
          : '0.0';
      final passed = double.parse(percentage) >=
          (widget.exam['passing_percentage'] as int? ?? 50);

      // Save attempt to database
      final attemptResponse = await Supabase.instance.client
          .from('exam_attempts')
          .insert({
        'exam_id': widget.exam['id'],
        'student_id': userId,
        'score': scoredMarks,
        'total_marks': totalMarks,
        'percentage': double.parse(percentage),
        'passed': passed,
        'completed_at': DateTime.now().toIso8601String(),
        'time_taken_seconds':
            _durationSeconds != null ? _durationSeconds! - _remainingSeconds : 0,
      }).select('id').single();

      // Save individual answers
      final attemptId = attemptResponse['id'];
      for (int i = 0; i < _questions.length; i++) {
        final question = _questions[i];
        final studentAnswer = _answers[i] ?? '';
        final correctAnswer = question['correct_answer'] as String? ?? '';
        final marks = question['marks'] as int? ?? 1;

        await Supabase.instance.client.from('student_answers').insert({
          'attempt_id': attemptId,
          'question_id': question['id'],
          'student_answer': studentAnswer,
          'is_correct': studentAnswer.trim().toLowerCase() ==
              correctAnswer.trim().toLowerCase(),
          'marks_obtained':
              studentAnswer.trim().toLowerCase() ==
                      correctAnswer.trim().toLowerCase()
                  ? marks
                  : 0,
        });
      }

      _timer?.cancel();

      if (mounted) {
        // Show results
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ExamResultsScreen(
              examTitle: widget.exam['title'] ?? 'Exam',
              score: scoredMarks,
              totalMarks: totalMarks,
              percentage: double.parse(percentage),
              passed: passed,
              questions: _questions,
              answers: _answers,
              autoSubmit: autoSubmit,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting exam: $e')),
        );
      }
    }
  }

  void _goToQuestion(int index) {
    if (index >= 0 && index < _questions.length) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(widget.exam['title'] ?? 'Exam'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF1A237E)),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.exam['title'] ?? 'Exam'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No questions in this exam yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final question = _questions[_currentIndex];
    final questionType = question['question_type'] as String? ?? 'multiple_choice';
    final options = (question['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return WillPopScope(
      onWillPop: () async {
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave Exam?'),
            content: const Text(
                'Your progress will be lost. Are you sure you want to leave?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    const Text('Leave', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        return result ?? false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(widget.exam['title'] ?? 'Exam'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          actions: [
            // Timer
            if (_durationSeconds != null)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _remainingSeconds < 60
                        ? Colors.red.withOpacity(0.3)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _remainingSeconds < 60
                            ? Icons.timer_off
                            : Icons.timer,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(_remainingSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // Progress bar
            LinearProgressIndicator(
              value: (_currentIndex + 1) / _questions.length,
              backgroundColor: Colors.grey.shade200,
              color: const Color(0xFFFF9800),
              minHeight: 4,
            ),
            // Question content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question number and marks
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A237E).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Question ${_currentIndex + 1} of ${_questions.length}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${question['marks'] ?? 1} pts',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF9800),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Question text
                    Text(
                      question['question_text'] ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A237E),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Options
                    if (questionType == 'multiple_choice')
                      ...options.asMap().entries.map((entry) {
                        final index = entry.key;
                        final option = entry.value;
                        final isSelected = _answers[_currentIndex] == option;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _answers[_currentIndex] = option;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF1A237E).withOpacity(0.05)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF1A237E)
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? const Color(0xFF1A237E)
                                        : Colors.grey.shade100,
                                  ),
                                  child: Center(
                                    child: Text(
                                      String.fromCharCode(65 + index),
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    option,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: isSelected
                                          ? const Color(0xFF1A237E)
                                          : Colors.grey.shade700,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle,
                                      color: Color(0xFF1A237E), size: 22),
                              ],
                            ),
                          ),
                        );
                      }),

                    // True/False
                    if (questionType == 'true_false')
                      Row(
                        children: [
                          Expanded(
                            child: _TrueFalseButton(
                              label: 'True',
                              isSelected: _answers[_currentIndex] == 'True',
                              color: const Color(0xFF4CAF50),
                              onTap: () {
                                setState(() {
                                  _answers[_currentIndex] = 'True';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TrueFalseButton(
                              label: 'False',
                              isSelected: _answers[_currentIndex] == 'False',
                              color: Colors.red,
                              onTap: () {
                                setState(() {
                                  _answers[_currentIndex] = 'False';
                                });
                              },
                            ),
                          ),
                        ],
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Previous button
                    if (_currentIndex > 0)
                      OutlinedButton.icon(
                        onPressed: () => _goToQuestion(_currentIndex - 1),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A237E),
                          side: const BorderSide(color: Color(0xFF1A237E)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    else
                      const SizedBox(width: 100),

                    const Spacer(),

                    // Question dots
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        _questions.length > 8 ? 8 : _questions.length,
                        (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _currentIndex
                                ? const Color(0xFFFF9800)
                                : _answers[i] != null
                                    ? const Color(0xFF4CAF50)
                                    : Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Next / Submit button
                    if (_currentIndex < _questions.length - 1)
                      ElevatedButton.icon(
                        onPressed: () => _goToQuestion(_currentIndex + 1),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('Next'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () => _showSubmitConfirmation(),
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 18),
                        label: Text(_isSubmitting
                            ? 'Submitting...'
                            : 'Submit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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

  void _showSubmitConfirmation() {
    final unanswered =
        _questions.length - _answers.values.where((a) => a.isNotEmpty).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Submit Exam?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'You have answered ${_answers.length} of ${_questions.length} questions.'),
            if (unanswered > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$unanswered question(s) unanswered.',
                style: const TextStyle(color: Colors.orange),
              ),
            ],
            const SizedBox(height: 8),
            const Text('You cannot change answers after submission.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Review'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitExam();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

class _TrueFalseButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _TrueFalseButton({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              label == 'True' ? Icons.check : Icons.close,
              size: 36,
              color: isSelected ? color : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== RESULTS SCREEN ====================
class ExamResultsScreen extends StatelessWidget {
  final String examTitle;
  final int score;
  final int totalMarks;
  final double percentage;
  final bool passed;
  final List<Map<String, dynamic>> questions;
  final Map<int, String> answers;
  final bool autoSubmit;

  const ExamResultsScreen({
    super.key,
    required this.examTitle,
    required this.score,
    required this.totalMarks,
    required this.percentage,
    required this.passed,
    required this.questions,
    required this.answers,
    this.autoSubmit = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Results'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Score card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: passed
                      ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                      : [Colors.red.shade400, Colors.red.shade300],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    passed ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                    size: 64,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    passed ? 'Congratulations! 🎉' : 'Keep Trying! 💪',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    autoSubmit ? 'Time\'s up! Exam auto-submitted.' : '',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$score / $totalMarks',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Review section
            const Text(
              'Review Answers',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 12),

            ...questions.asMap().entries.map((entry) {
              final index = entry.key;
              final question = entry.value;
              final studentAnswer = answers[index] ?? '';
              final correctAnswer =
                  question['correct_answer'] as String? ?? '';
              final isCorrect = studentAnswer.trim().toLowerCase() ==
                  correctAnswer.trim().toLowerCase();

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCorrect
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: isCorrect
                                ? const Color(0xFF4CAF50)
                                : Colors.red,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Q${index + 1}: ${question['question_text'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${question['marks'] ?? 1} pts',
                            style: TextStyle(
                              fontSize: 12,
                              color: isCorrect
                                  ? const Color(0xFF4CAF50)
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your answer: $studentAnswer',
                        style: TextStyle(
                          fontSize: 13,
                          color: isCorrect
                              ? const Color(0xFF4CAF50)
                              : Colors.red,
                        ),
                      ),
                      if (!isCorrect)
                        Text(
                          'Correct: $correctAnswer',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      if (question['explanation'] != null &&
                          question['explanation'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.lightbulb_outline,
                                    size: 16, color: Colors.blue),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    question['explanation'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                    ),
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
            }),

            const SizedBox(height: 20),

            // Done button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.popUntil(
                      context, (route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Back to Dashboard',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}