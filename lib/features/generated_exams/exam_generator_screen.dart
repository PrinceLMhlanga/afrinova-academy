import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'student_exam_taker_screen.dart';

class ExamGeneratorScreen extends StatefulWidget {
  const ExamGeneratorScreen({super.key});

  @override
  State<ExamGeneratorScreen> createState() => _ExamGeneratorScreenState();
}

class _ExamGeneratorScreenState extends State<ExamGeneratorScreen> {
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  
  String? _selectedSubjectId;
  String? _studentLevelId;
  String? _studentLevelName;
  String? _selectedTopicId;
  int _questionCount = 20;
  bool _isLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
      
      // Load student's level from profile
      if (userId != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('level_id, levels(name)')
            .eq('id', userId)
            .maybeSingle();
        
        if (profile != null) {
          _studentLevelId = profile['level_id'] as String?;
          _studentLevelName = profile['levels']?['name'] as String?;
        }
      }

      // Load subjects
      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTopics(String subjectId) async {
    try {
      // ✅ Use filter instead of eq after select
      final response = await Supabase.instance.client
          .from('topics')
          .select()
          .eq('subject_id', subjectId)
          .order('display_order', ascending: true);

      if (mounted) setState(() => _topics = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint('Error loading topics: $e');
    }
  }

  Future<void> _generateExam() async {
  if (_selectedSubjectId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select a subject'), backgroundColor: Colors.red),
    );
    return;
  }

  if (_studentLevelId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please set your class level in My Account'), backgroundColor: Colors.red),
    );
    return;
  }

  setState(() => _isGenerating = true);

  try {
    // ✅ Build the query as a PostgrestFilterBuilder first
    final filterQuery = Supabase.instance.client
        .from('question_bank')
        .select('*, levels(name)')
        .eq('subject_id', _selectedSubjectId!)
        .eq('level_id', _studentLevelId!)
        .eq('is_approved', true);

    // ✅ Apply topic filter if selected
    final filteredQuery = _selectedTopicId != null && _selectedTopicId!.isNotEmpty
        ? filterQuery.eq('topic_id', _selectedTopicId!)
        : filterQuery;

    // ✅ Apply limit LAST - this returns PostgrestTransformBuilder
    final finalQuery = filteredQuery.limit(_questionCount);

    final response = await finalQuery;
    final questions = List<Map<String, dynamic>>.from(response);

    if (questions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No questions found for this selection'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    // Shuffle questions
    questions.shuffle(Random());

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentExamTakerScreen(
            questions: questions,
            subjectName: _subjects.firstWhere((s) => s['id'] == _selectedSubjectId)['name'] ?? 'Exam',
            totalQuestions: questions.length,
            timeMinutes: questions.length,
          ),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => _isGenerating = false);
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice Exam'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [const Color(0xFF1A237E), const Color(0xFF1A237E).withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.white, size: 40),
                        const SizedBox(height: 12),
                        const Text('Practice Exam Generator',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          _studentLevelName != null 
                              ? 'Generating questions for $_studentLevelName'
                              : 'Set your class level in My Account',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Level (read-only)
                  if (_studentLevelName != null) ...[
                    const Text('Your Level', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.school_rounded, color: Color(0xFF1A237E)),
                          const SizedBox(width: 10),
                          Text(_studentLevelName!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              // Navigate to My Account to change level
                            },
                            child: const Text('Change', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Subject
                  const Text('Subject', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedSubjectId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.book_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _subjects.map((s) => DropdownMenuItem<String>(
                      value: s['id'] as String, child: Text(s['name'] ?? ''),
                    )).toList(),
                    onChanged: (v) {
                      setState(() { _selectedSubjectId = v; _selectedTopicId = null; });
                      if (v != null) _loadTopics(v);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Topic
                  const Text('Topic', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedTopicId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.topic_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('All Topics')),
                      ..._topics.map((t) => DropdownMenuItem<String>(
                        value: t['id'] as String, child: Text(t['name'] ?? ''),
                      )),
                    ],
                    onChanged: (v) => setState(() => _selectedTopicId = v),
                  ),
                  const SizedBox(height: 16),

                  // Question count
                  const Text('Number of Questions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('10', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('$_questionCount questions',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E))),
                            const Text('40', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        Slider(
                          value: _questionCount.toDouble(),
                          min: 10,
                          max: 40,
                          divisions: 6,
                          activeColor: const Color(0xFF1A237E),
                          onChanged: (v) => setState(() => _questionCount = v.round()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Generate button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: (_isGenerating || _studentLevelId == null) ? null : _generateExam,
                      icon: _isGenerating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome),
                      label: Text(_isGenerating ? 'Generating...' : 'Generate $_questionCount Questions'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Approx. ${_questionCount} minutes',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}