import 'package:flutter/material.dart';
import '../../core/exam_service.dart';
import '../../core/auth_service.dart';
import '../../core/subject_service.dart';
import '../../core/teacher_service.dart';

class ExamCreatorScreen extends StatefulWidget {
  const ExamCreatorScreen({super.key});

  @override
  State<ExamCreatorScreen> createState() => _ExamCreatorScreenState();
}

class _ExamCreatorScreenState extends State<ExamCreatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final ExamService _examService = ExamService();
  final AuthService _authService = AuthService();
  final SubjectService _subjectService = SubjectService();
  

  // Exam fields
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController();
  final _passingController = TextEditingController(text: '50');

  // Dropdown values
  String? _selectedSubject;
  String? _selectedTeacherTopicId;  // Replace _selectedTopicId
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  bool _isLoadingData = true;
  bool _isSaving = false;

  // Questions
  List<_QuestionData> _questions = [];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

 final TeacherService  _teacherService = TeacherService();
  Future<void> _loadSubjects() async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final mySubjects = await _teacherService.getMySubjects(userId);
    final subjects = mySubjects
        .where((s) => s['subjects'] != null)
        .map((s) => s['subjects'] as Map<String, dynamic>)
        .toList();

    if (mounted) {
      setState(() {
        _subjects = subjects;
        _isLoadingData = false;
      });
    }
  } catch (e) {
    if (mounted) setState(() => _isLoadingData = false);
  }
}

  // Change the dropdown onChanged to pass subject ID instead of name
Future<void> _loadTopics(String subjectId) async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final topics = await _teacherService.getMyTopics(userId, subjectId);

    if (mounted) {
      setState(() {
        _topics = topics;
        _selectedTeacherTopicId = null;
      });
    }
  } catch (_) {}
}

  Future<void> _saveExam() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeacherTopicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a topic'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one question'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = _authService.currentUserId!;
      final totalMarks =
          _questions.fold<int>(0, (sum, q) => sum + q.marks);

      // Create exam
      // Find the subject ID from the selected subject name
String? subjectId;
if (_selectedSubject != null) {
  final subject = _subjects.firstWhere(
    (s) => s['name'] == _selectedSubject,
    orElse: () => {'id': null},
  );
  subjectId = subject['id'] as String?;
}

final examId = await _examService.createExamWithTeacherTopic(
  teacherTopicId: _selectedTeacherTopicId!,
  creatorId: userId,
  title: _titleController.text.trim(),
  description: _descriptionController.text.trim(),
  durationMinutes: int.tryParse(_durationController.text),
  totalMarks: totalMarks,
  passingPercentage: int.tryParse(_passingController.text) ?? 50,
  subjectId: subjectId, // ✅ Add this
);
      if (examId != null) {
        // Add all questions
        for (int i = 0; i < _questions.length; i++) {
          final q = _questions[i];
          await _examService.addQuestion(
            examId: examId,
            questionText: q.text,
            questionType: q.type,
            options: q.options,
            correctAnswer: q.correctAnswer,
            marks: q.marks,
            explanation: q.explanation,
            displayOrder: i + 1,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exam created successfully! ✅'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
        onSave: (question) {
          setState(() => _questions.add(question));
        },
      ),
    );
  }

  void _editQuestion(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuestionEditorSheet(
        existingQuestion: _questions[index],
        onSave: (question) {
          setState(() => _questions[index] = question);
        },
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _passingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Exam'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoadingData
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Exam Title
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Exam Title',
                      hintText: 'e.g., Mechanics Mid-Term Test',
                      prefixIcon: const Icon(Icons.quiz),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                        v!.isEmpty ? 'Enter exam title' : null,
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      hintText: 'Brief description of the exam',
                      prefixIcon: const Icon(Icons.description),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Subject Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedSubject,
                    decoration: InputDecoration(
                      labelText: 'Subject',
                      prefixIcon: const Icon(Icons.book),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _subjects.map<DropdownMenuItem<String>>((s) {
  return DropdownMenuItem<String>(
    value: s['name'] as String?,
    child: Text(s['name'] ?? ''),
  );
}).toList(),
                   onChanged: (value) {
  setState(() {
    _selectedSubject = value;
    _topics = [];
    _selectedTeacherTopicId = null;
  });
  if (value != null) {
    final subject = _subjects.firstWhere(
      (s) => s['name'] == value,
      orElse: () => {'id': ''},
    );
    final subjectId = subject['id'] as String?;
    if (subjectId != null) {
      _loadTopics(subjectId);  // ✅ Pass ID, not name
    }
  }
},
                    validator: (v) =>
                        v == null ? 'Select a subject' : null,
                  ),
                  const SizedBox(height: 16),

                  // Topic Dropdown
                  DropdownButtonFormField<String>(
  value: _selectedTeacherTopicId,
  decoration: InputDecoration(
    labelText: 'Topic',
    prefixIcon: const Icon(Icons.topic),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
  items: _topics.map<DropdownMenuItem<String>>((t) {
    return DropdownMenuItem<String>(
      value: t['id'] as String?,
      child: Text(t['name'] ?? ''),
    );
  }).toList(),
  onChanged: (value) => setState(() => _selectedTeacherTopicId = value),
  validator: (v) => v == null ? 'Select a topic' : null,
),
                  const SizedBox(height: 16),

                  // Duration & Passing %
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _durationController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Duration (min)',
                            hintText: '30',
                            prefixIcon:
                                const Icon(Icons.timer_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _passingController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Passing %',
                            hintText: '50',
                            prefixIcon:
                                const Icon(Icons.check_circle_outline),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Questions Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Questions (${_questions.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addQuestion,
                        icon: const Icon(Icons.add_circle,
                            color: Color(0xFFFF9800)),
                        label: const Text('Add Question',
                            style: TextStyle(color: Color(0xFFFF9800))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Question List
                  ..._questions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final question = entry.value;
                    return _QuestionCard(
                      index: index + 1,
                      question: question,
                      onEdit: () => _editQuestion(index),
                      onDelete: () {
                        setState(() => _questions.removeAt(index));
                      },
                    );
                  }),

                  if (_questions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          children: [
                            Icon(Icons.help_outline,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'No questions added yet',
                              style: TextStyle(
                                  fontSize: 15, color: Colors.grey),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tap "Add Question" to start building your exam',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveExam,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(
                              color: Colors.white)
                          : const Text(
                              'Save Exam',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

// ==================== QUESTION DATA MODEL ====================
class _QuestionData {
  final String text;
  final String type;
  final List<String> options;
  final String correctAnswer;
  final int marks;
  final String? explanation;

  _QuestionData({
    required this.text,
    required this.type,
    required this.options,
    required this.correctAnswer,
    required this.marks,
    this.explanation,
  });
}

// ==================== QUESTION CARD ====================
class _QuestionCard extends StatelessWidget {
  final int index;
  final _QuestionData question;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabel = question.type == 'multiple_choice'
        ? 'Multiple Choice'
        : question.type == 'true_false'
            ? 'True/False'
            : 'Short Answer';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Q$index',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
                const Spacer(),
                Text(
                  '${question.marks} pts',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF9800),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onEdit,
                  child: const Icon(Icons.edit,
                      size: 18, color: Colors.grey),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              question.text,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (question.options.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...question.options.map((opt) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Row(
                      children: [
                        Icon(
                          opt == question.correctAnswer
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 14,
                          color: opt == question.correctAnswer
                              ? const Color(0xFF4CAF50)
                              : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(opt,
                            style: TextStyle(
                              fontSize: 13,
                              color: opt == question.correctAnswer
                                  ? const Color(0xFF4CAF50)
                                  : Colors.grey.shade700,
                            )),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== QUESTION EDITOR BOTTOM SHEET ====================
class _QuestionEditorSheet extends StatefulWidget {
  final _QuestionData? existingQuestion;
  final void Function(_QuestionData) onSave;

  const _QuestionEditorSheet({
    this.existingQuestion,
    required this.onSave,
  });

  @override
  State<_QuestionEditorSheet> createState() => _QuestionEditorSheetState();
}

class _QuestionEditorSheetState extends State<_QuestionEditorSheet> {
  final _qFormKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final _marksController = TextEditingController(text: '1');
  final _explanationController = TextEditingController();
  String _questionType = 'multiple_choice';
  List<TextEditingController> _optionControllers = [];
  String _correctAnswer = '';

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
      _questionController.text = q.text;
      _questionType = q.type;
      _marksController.text = q.marks.toString();
      _explanationController.text = q.explanation ?? '';
      _correctAnswer = q.correctAnswer;
      for (int i = 0; i < q.options.length && i < 4; i++) {
        _optionControllers[i].text = q.options[i];
      }
    }
  }

  void _save() {
    if (!_qFormKey.currentState!.validate()) return;

    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final question = _QuestionData(
      text: _questionController.text.trim(),
      type: _questionType,
      options: options,
      correctAnswer: _correctAnswer,
      marks: int.tryParse(_marksController.text) ?? 1,
      explanation: _explanationController.text.trim().isNotEmpty
          ? _explanationController.text.trim()
          : null,
    );

    widget.onSave(question);
    Navigator.pop(context);
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
                      label: Text('Multiple Choice', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.list, size: 16)),
                  ButtonSegment(
                      value: 'true_false',
                      label: Text('True/False', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.toggle_on, size: 16)),
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

              // Options for Multiple Choice
              // Options for Multiple Choice
if (_questionType == 'multiple_choice') ...[
  const Text('Options (mark the correct one):',
      style: TextStyle(fontWeight: FontWeight.w600)),
  const SizedBox(height: 8),
  ...List.generate(4, (i) {
    final hasText = _optionControllers[i].text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Radio<String>(
            value: _optionControllers[i].text,
            groupValue: _correctAnswer,
            // ✅ Enabled only if this option has text
            onChanged: hasText
                ? (v) => setState(() => _correctAnswer = v ?? '')
                : null,
            activeColor: const Color(0xFF4CAF50),
          ),
          Expanded(
            child: TextFormField(
              controller: _optionControllers[i],
              decoration: InputDecoration(
                hintText: 'Option ${String.fromCharCode(65 + i)}',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
              // ✅ No auto-select — just refresh UI so radio enables
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }),
],
              // True/False
              if (_questionType == 'true_false') ...[
                const Text('Correct Answer:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
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
                  hintText: 'Shown after student answers',
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
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _isEditing ? 'Update Question' : 'Add Question',
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