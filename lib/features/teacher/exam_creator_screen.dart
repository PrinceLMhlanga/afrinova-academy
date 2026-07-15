import 'package:flutter/material.dart';
import '../../core/exam_service.dart';
import '../../core/auth_service.dart';
import '../../core/subject_service.dart';
import '../../core/teacher_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../teacher/drawing_canvas.dart';
import '../teacher/graph_plotter.dart';
import 'math_keyboard.dart';

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

  bool _showMathKeyboard = false;
TextEditingController? _activeMathController;
final FocusNode _questionFocus = FocusNode();
final List<FocusNode> _optionFocusNodes = [FocusNode(), FocusNode(), FocusNode(), FocusNode()];

  

  // Questions
  List<_QuestionData> _questions = [];

  @override
  void initState() {
    super.initState();
    _loadLevels();
  }

  // ✅ ADD: Level support
List<Map<String, dynamic>> _levels = [];
String? _selectedLevelId;

// ✅ REPLACE _loadSubjects with:
Future<void> _loadLevels() async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final response = await Supabase.instance.client
        .from('teacher_levels')
        .select('level_id, levels!inner(name)')
        .eq('teacher_id', userId);

    if (mounted) {
      setState(() {
        _levels = List<Map<String, dynamic>>.from(response);
        _isLoadingData = false;
      });
    }
  } catch (e) {
    if (mounted) setState(() => _isLoadingData = false);
  }
}

Future<void> _loadSubjectsForLevel(String levelId) async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final response = await Supabase.instance.client
        .from('teacher_subjects')
        .select('subject_id, subjects!inner(name)')
        .eq('teacher_id', userId)
        .eq('level_id', levelId);

    if (mounted) {
      setState(() {
        _subjects = List<Map<String, dynamic>>.from(response);
        _topics = [];
        _selectedTeacherTopicId = null;
      });
    }
  } catch (_) {}
}

Future<void> _loadTopicsForSubject(String subjectId) async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final filters = <String, Object>{'teacher_id': userId, 'subject_id': subjectId};
    final levelId = _selectedLevelId;
    if (levelId != null) filters['level_id'] = levelId;

    final response = await Supabase.instance.client
        .from('teacher_topics')
        .select()
        .match(filters)
        .order('display_order', ascending: true);

    if (mounted) {
      setState(() => _topics = List<Map<String, dynamic>>.from(response));
      _selectedTeacherTopicId = null;
    }
  } catch (_) {}
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
// ✅ New - looks inside the nested 'subjects' map
String? subjectId;
if (_selectedSubject != null) {
  final row = _subjects.firstWhere(
    (s) {
      final subject = s['subjects'] as Map<String, dynamic>?;
      return subject?['name'] == _selectedSubject;
    },
    orElse: () => {},
  );
  subjectId = row['subject_id'] as String?;  // ✅ Use subject_id from the row
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
  levelId: _selectedLevelId,
);
      if (examId != null) {
        // Add all questions
        for (int i = 0; i < _questions.length; i++) {
  final q = _questions[i];
  await _examService.addQuestion(
    examId: examId,
    questionText: q.text,  // ✅ Just clean text
    questionType: q.type,
    options: q.options,
    correctAnswer: q.correctAnswer,
    marks: q.marks,
    explanation: q.explanation,
    diagramUrl: q.diagramUrl,
    drawingData: q.drawingData,    // ✅ Pass separately
    graphData: q.graphData,        // ✅ Pass separately
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
      onSave: (question) => setState(() => _questions.add(question)),
      // Remove onPickDiagram, onOpenDrawing, onOpenGraph callbacks
      // Remove pendingDiagramUrl, pendingDrawingData, pendingGraphData
    ),
  );
}

void _editQuestion(int index) {
  final q = _questions[index];
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _QuestionEditorSheet(
      existingQuestion: q,
      onSave: (question) => setState(() => _questions[index] = question),
      // Remove callbacks and pending data - sheet manages its own state
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
                  // ✅ ADD: Level Dropdown (before Subject)
DropdownButtonFormField<String>(
  value: _selectedLevelId,
  decoration: InputDecoration(
    labelText: 'Class Level',
    prefixIcon: const Icon(Icons.school_rounded),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
  items: _levels.map((row) {
    final level = row['levels'] as Map<String, dynamic>;
    return DropdownMenuItem<String>(
      value: row['level_id'] as String,
      child: Text(level['name'] ?? ''),
    );
  }).toList(),
  onChanged: (value) {
    setState(() {
      _selectedLevelId = value;
      _selectedSubject = null;
      _subjects = [];
      _topics = [];
      _selectedTeacherTopicId = null;
    });
    if (value != null) _loadSubjectsForLevel(value);
  },
  validator: (v) => v == null ? 'Select a class' : null,
),
const SizedBox(height: 16),

// ✅ UPDATE: Subject Dropdown
DropdownButtonFormField<String>(
  value: _selectedSubject,
  decoration: InputDecoration(
    labelText: 'Subject',
    prefixIcon: const Icon(Icons.book),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
  items: _subjects.map<DropdownMenuItem<String>>((row) {
    final subject = row['subjects'] as Map<String, dynamic>;
    return DropdownMenuItem<String>(
      value: subject['name'] as String?,
      child: Text(subject['name'] ?? ''),
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
        (s) => (s['subjects'] as Map)['name'] == value,
        orElse: () => {},
      );
      final subjectId = subject['subject_id'] as String?;
      if (subjectId != null) _loadTopicsForSubject(subjectId);
    }
  },
  validator: (v) => v == null ? 'Select a subject' : null,
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
  final String? diagramUrl;      // ✅ Add
  final String? drawingData;     // ✅ Add
  final String? graphData;       // ✅ Add

  _QuestionData({
    required this.text,
    required this.type,
    required this.options,
    required this.correctAnswer,
    required this.marks,
    this.explanation,
    this.diagramUrl,
    this.drawingData,
    this.graphData,
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
  final VoidCallback? onPickDiagram;
  final VoidCallback? onOpenDrawing;
  final VoidCallback? onOpenGraph;
  final String? pendingDiagramUrl;    // ✅ Pass from parent
  final String? pendingDrawingData;   // ✅ Pass from parent
  final String? pendingGraphData;     // ✅ Pass from parent

  const _QuestionEditorSheet({
    this.existingQuestion,
    required this.onSave,
    this.onPickDiagram,
    this.onOpenDrawing,
    this.onOpenGraph,
    this.pendingDiagramUrl,
    this.pendingDrawingData,
    this.pendingGraphData,
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

  // In _QuestionEditorSheetState, add:
String? _pendingDiagramUrl;
String? _pendingDrawingData;
String? _pendingGraphData;

bool _showMathKeyboard = false;
TextEditingController? _activeMathController;

final FocusNode _questionFocusNode = FocusNode();
final List<FocusNode> _optionFocusNodes = [FocusNode(), FocusNode(), FocusNode(), FocusNode()];

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
    // Initialize media from existing question
    _pendingDiagramUrl = q.diagramUrl;
    _pendingDrawingData = q.drawingData;
    _pendingGraphData = q.graphData;
  }

  _questionFocusNode.addListener(_onFocusChange);
    for (final node in _optionFocusNodes) {
      node.addListener(_onFocusChange);
    }
}
void _onFocusChange() {
    // When a text field gains focus, set it as the active controller for math keyboard
    if (_questionFocusNode.hasFocus) {
      setState(() => _activeMathController = _questionController);
    } else {
      for (int i = 0; i < _optionFocusNodes.length; i++) {
        if (_optionFocusNodes[i].hasFocus) {
          setState(() => _activeMathController = _optionControllers[i]);
          break;
        }
      }
    }
  }

  // Toggle math keyboard for a specific controller
  void _toggleMathKeyboard(TextEditingController controller) {
    setState(() {
      if (_activeMathController == controller && _showMathKeyboard) {
        // If same controller and keyboard is showing, hide it
        _showMathKeyboard = false;
        _activeMathController = null;
      } else {
        // Show keyboard for this controller
        _activeMathController = controller;
        _showMathKeyboard = true;
      }
    });
  }

// Add methods to handle media pickers locally:
Future<void> _pickDiagram() async {
  try {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery, 
      imageQuality: 80
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'unknown';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
    final filePath = 'exam-diagrams/$userId/$fileName';

    await Supabase.instance.client
        .storage
        .from('resources')
        .uploadBinary(filePath, Uint8List.fromList(bytes));

    final url = Supabase.instance.client
        .storage
        .from('resources')
        .getPublicUrl(filePath);

    setState(() => _pendingDiagramUrl = url);
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading diagram: $e'), 
          backgroundColor: Colors.red
        ),
      );
    }
  }
}

void _openDrawingCanvas() {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => DrawingCanvas(onSave: (base64Image) {
      Navigator.pop(context);
      setState(() => _pendingDrawingData = '%%DRAWING:$base64Image%%');
    }),
  ));
}

void _openGraphPlotter() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: GraphPlotter(
        onInsertGraph: (graphData) {
          Navigator.pop(context);
          setState(() => _pendingGraphData = graphData);
        },
      ),
    ),
  );
}

// Update _save method to use local state:
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
    diagramUrl: _pendingDiagramUrl,      // Use local state
    drawingData: _pendingDrawingData,    // Use local state
    graphData: _pendingGraphData,        // Use local state
  );
  widget.onSave(question);
  Navigator.pop(context);
}

  @override
  void dispose() {
    _questionFocusNode.removeListener(_onFocusChange);
    _questionFocusNode.dispose();
    for (final node in _optionFocusNodes) {
      node.removeListener(_onFocusChange);
      node.dispose();
    }
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
              // Question Text
// Question Text
              TextFormField(
              controller: _questionController,
              maxLines: 3,
              focusNode: _questionFocusNode,
              decoration: InputDecoration(
                labelText: 'Question',
                hintText: 'Enter your question',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.functions, 
                    size: 18,
                    color: _activeMathController == _questionController && _showMathKeyboard
                        ? const Color(0xFF1A237E)
                        : Colors.grey,
                  ),
                  onPressed: () => _toggleMathKeyboard(_questionController),
                ),
              ),
              validator: (v) => v!.isEmpty ? 'Enter a question' : null,
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
                        onChanged: hasText
                            ? (v) => setState(() => _correctAnswer = v ?? '')
                            : null,
                        activeColor: const Color(0xFF4CAF50),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _optionControllers[i],
                          focusNode: _optionFocusNodes[i],
                          decoration: InputDecoration(
                            hintText: 'Option ${String.fromCharCode(65 + i)}',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            suffixIcon: IconButton(
                              icon: Icon(
                                Icons.functions, 
                                size: 14,
                                color: _activeMathController == _optionControllers[i] && _showMathKeyboard
                                    ? const Color(0xFF1A237E)
                                    : Colors.grey,
                              ),
                              onPressed: () => _toggleMathKeyboard(_optionControllers[i]),
                            ),
                          ),
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

Row(
  children: [
    Expanded(
      child: OutlinedButton.icon(
        onPressed: _pickDiagram,  // ✅ Use local method
        icon: const Icon(Icons.image_outlined, size: 16),
        label: const Text('Diagram', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.blue,
          side: const BorderSide(color: Colors.blue),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: OutlinedButton.icon(
        onPressed: _openDrawingCanvas,  // ✅ Use local method
        icon: const Icon(Icons.draw_outlined, size: 16),
        label: const Text('Drawing', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.purple,
          side: const BorderSide(color: Colors.purple),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: OutlinedButton.icon(
        onPressed: _openGraphPlotter,  // ✅ Use local method
        icon: const Icon(Icons.insert_chart_outlined, size: 16),
        label: const Text('Graph', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green,
          side: const BorderSide(color: Colors.green),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    ),

     
  ],
),
// Math keyboard (appears when toggled)
              if (_showMathKeyboard && _activeMathController != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: MathKeyboard(
                    controller: _activeMathController!,
                    onClose: () => setState(() {
                      _showMathKeyboard = false;
                      _activeMathController = null;
                    }),
                  ),
                ),
              ],

// ✅ Show pending media indicators
if (_pendingDiagramUrl != null || 
    _pendingDrawingData != null || 
    _pendingGraphData != null) ...[
  const SizedBox(height: 12),
  Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.green.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.green.shade200),
    ),
    child: Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            [
              if (_pendingDiagramUrl != null) '📷 Diagram attached',
              if (_pendingDrawingData != null) '✏️ Drawing attached',
              if (_pendingGraphData != null) '📊 Graph attached',
            ].join(', '),
            style: const TextStyle(fontSize: 11, color: Colors.green),
          ),
        ),
      ],
    ),
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
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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