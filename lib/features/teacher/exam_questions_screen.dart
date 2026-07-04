import 'package:flutter/material.dart';
import '../../core/exam_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExamQuestionsScreen extends StatefulWidget {
  final String examId;
  final String examTitle;

  const ExamQuestionsScreen({
    super.key,
    required this.examId,
    required this.examTitle,
  });

  @override
  State<ExamQuestionsScreen> createState() => _ExamQuestionsScreenState();
}

class _ExamQuestionsScreenState extends State<ExamQuestionsScreen> {
  final ExamService _examService = ExamService();
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await _examService.getQuestions(widget.examId);
      if (mounted) {
        setState(() {
          _questions = questions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteQuestion(String questionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Question?'),
        content: const Text(
            'This question will be permanently removed from the exam.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _examService.deleteQuestion(questionId);
        _loadQuestions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Question deleted'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _addQuestion() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuestionEditorSheet(
        examId: widget.examId,
        onSaved: () => _loadQuestions(),
      ),
    );
  }

  void _editQuestion(Map<String, dynamic> question) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuestionEditorSheet(
        examId: widget.examId,
        existingQuestion: question,
        onSaved: () => _loadQuestions(),
      ),
    );
  }

  Future<void> _updateTotalMarks() async {
    final totalMarks = _questions.fold<int>(
        0, (sum, q) => sum + ((q['marks'] as int?) ?? 1));
    await _examService.updateTotalMarks(widget.examId, totalMarks);
  }

  @override
  Widget build(BuildContext context) {
    final totalMarks = _questions.fold<int>(
        0, (sum, q) => sum + ((q['marks'] as int?) ?? 1));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examTitle),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          Center(
            child: Text(
              '${_questions.length} Q • $totalMarks pts',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Question',
            onPressed: _addQuestion,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _questions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.help_outline,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text(
                        'No questions yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap + to add your first question',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _addQuestion,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Question'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _questions.length,
                  itemBuilder: (context, index) {
                    final q = _questions[index];
                    final type = q['question_type'] as String? ?? '';
                    final options =
                        (q['options'] as List<dynamic>?)?.cast<String>() ??
                            [];
                    final correctAnswer =
                        q['correct_answer'] as String? ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A237E)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Q${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A237E),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    type == 'multiple_choice'
                                        ? 'MCQ'
                                        : type == 'true_false'
                                            ? 'T/F'
                                            : type,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${q['marks'] ?? 1} pts',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF9800),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // Edit button
                                GestureDetector(
                                  onTap: () => _editQuestion(q),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // Delete button
                                GestureDetector(
                                  onTap: () => _deleteQuestion(
                                      q['id'] as String),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Question text
                            Text(
                              q['question_text'] ?? '',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Options with correct answer highlighted
                            if (options.isNotEmpty)
                              ...options.map((opt) => Padding(
                                    padding:
                                        const EdgeInsets.only(left: 4, top: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          opt == correctAnswer
                                              ? Icons.check_circle
                                              : Icons.circle_outlined,
                                          size: 18,
                                          color: opt == correctAnswer
                                              ? const Color(0xFF4CAF50)
                                              : Colors.grey.shade400,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            opt,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color:
                                                  opt == correctAnswer
                                                      ? const Color(
                                                          0xFF4CAF50)
                                                      : Colors.grey.shade700,
                                              fontWeight:
                                                  opt == correctAnswer
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),

                            // True/False display
                            if (type == 'true_false')
                              Padding(
                                padding: const EdgeInsets.only(left: 4, top: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle,
                                        size: 18, color: Color(0xFF4CAF50)),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Correct: $correctAnswer',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF4CAF50),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Explanation
                            if (q['explanation'] != null &&
                                q['explanation'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.lightbulb_outline,
                                          size: 16, color: Colors.blue),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          q['explanation'],
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
                  },
                ),
    );
  }
}

// ==================== QUESTION EDITOR BOTTOM SHEET ====================
class _QuestionEditorSheet extends StatefulWidget {
  final String examId;
  final Map<String, dynamic>? existingQuestion;
  final VoidCallback onSaved;

  const _QuestionEditorSheet({
    required this.examId,
    this.existingQuestion,
    required this.onSaved,
  });

  @override
  State<_QuestionEditorSheet> createState() => _QuestionEditorSheetState();
}

class _QuestionEditorSheetState extends State<_QuestionEditorSheet> {
  final _qFormKey = GlobalKey<FormState>();
  final ExamService _examService = ExamService();
  final _questionController = TextEditingController();
  final _marksController = TextEditingController(text: '1');
  final _explanationController = TextEditingController();
  String _questionType = 'multiple_choice';
  List<TextEditingController> _optionControllers = [];
  String _correctAnswer = '';
  bool _isSaving = false;

  bool get _isEditing => widget.existingQuestion != null;

  @override
  void initState() {
    super.initState();
    _optionControllers = [
      TextEditingController(),
      TextEditingController(),
      TextEditingController(),
      TextEditingController(),
    ];

    if (_isEditing) {
      final q = widget.existingQuestion!;
      _questionController.text = q['question_text'] ?? '';
      _questionType = q['question_type'] ?? 'multiple_choice';
      _marksController.text = (q['marks'] ?? 1).toString();
      _explanationController.text = q['explanation'] ?? '';
      _correctAnswer = q['correct_answer'] ?? '';
      final options =
          (q['options'] as List<dynamic>?)?.cast<String>() ?? [];
      for (int i = 0; i < options.length && i < 4; i++) {
        _optionControllers[i].text = options[i];
      }
    }
  }

  Future<void> _save() async {
    if (!_qFormKey.currentState!.validate()) return;

    // Validate correct answer is selected
    if (_questionType == 'multiple_choice') {
      if (_correctAnswer.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select the correct answer'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else if (_questionType == 'true_false') {
      if (_correctAnswer.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select True or False'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final options = _optionControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      final marks = int.tryParse(_marksController.text) ?? 1;

      if (_isEditing) {
        // Update existing question
        await Supabase.instance.client
            .from('questions')
            .update({
          'question_text': _questionController.text.trim(),
          'question_type': _questionType,
          'options': options,
          'correct_answer': _correctAnswer,
          'marks': marks,
          'explanation': _explanationController.text.trim().isNotEmpty
              ? _explanationController.text.trim()
              : null,
        }).eq('id', widget.existingQuestion!['id']);
      } else {
        // Add new question
        await _examService.addQuestion(
          examId: widget.examId,
          questionText: _questionController.text.trim(),
          questionType: _questionType,
          options: options,
          correctAnswer: _correctAnswer,
          marks: marks,
          explanation: _explanationController.text.trim().isNotEmpty
              ? _explanationController.text.trim()
              : null,
          displayOrder: 0,
        );
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
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

  @override
  void dispose() {
    _questionController.dispose();
    _marksController.dispose();
    _explanationController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _qFormKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEditing ? 'Edit Question' : 'Add Question',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 16),

              // Question Type
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'multiple_choice',
                    label: Text('MCQ', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.list, size: 16),
                  ),
                  ButtonSegment(
                    value: 'true_false',
                    label: Text('T/F', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.toggle_on, size: 16),
                  ),
                ],
                selected: {_questionType},
                onSelectionChanged: (v) {
                  setState(() {
                    _questionType = v.first;
                    _correctAnswer = '';
                  });
                },
              ),
              const SizedBox(height: 16),

              // Question Text
              TextFormField(
                controller: _questionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Question',
                  hintText: 'Enter your question',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) =>
                    v!.isEmpty ? 'Enter a question' : null,
              ),
              const SizedBox(height: 16),

              // Marks
              TextFormField(
                controller: _marksController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Points',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              // MCQ Options
              if (_questionType == 'multiple_choice') ...[
                Text(
                  'Options — select the correct one:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(4, (i) {
                  final optionText = _optionControllers[i].text;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Radio<String>(
                          value: optionText,
                          groupValue: _correctAnswer,
                          onChanged: optionText.isEmpty
                              ? null
                              : (v) => setState(
                                  () => _correctAnswer = v ?? ''),
                          activeColor: const Color(0xFF4CAF50),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _optionControllers[i],
                            decoration: InputDecoration(
                              hintText:
                                  'Option ${String.fromCharCode(65 + i)}',
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // True/False
              if (_questionType == 'true_false') ...[
                Text(
                  'Correct Answer:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _TrueFalseCard(
                        label: 'True',
                        isSelected: _correctAnswer == 'True',
                        onTap: () =>
                            setState(() => _correctAnswer = 'True'),
                        color: const Color(0xFF4CAF50),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TrueFalseCard(
                        label: 'False',
                        isSelected: _correctAnswer == 'False',
                        onTap: () =>
                            setState(() => _correctAnswer = 'False'),
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // Explanation
              TextFormField(
                controller: _explanationController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Explanation (optional)',
                  hintText: 'Shown to students after the exam',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          _isEditing
                              ? 'Update Question'
                              : 'Add Question',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrueFalseCard extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  const _TrueFalseCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isSelected ? color : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}