import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/ai_service.dart';
import 'summary_viewer_screen.dart';

class SummaryGeneratorScreen extends StatefulWidget {
  const SummaryGeneratorScreen({super.key});

  @override
  State<SummaryGeneratorScreen> createState() => _SummaryGeneratorScreenState();
}

class _SummaryGeneratorScreenState extends State<SummaryGeneratorScreen> {
  final AuthService _authService = AuthService();
  final AIService _aiService = AIService();
  
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  String? _selectedSubjectId;
  String? _selectedTopicId;
  String? _syllabusOutline;
  String? _studentLevelId;
  String? _studentLevelName;
  bool _isGenerating = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
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

      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .order('name');

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTopics(String subjectId) async {
    final topics = await Supabase.instance.client
        .from('topics')
        .select('*')
        .eq('subject_id', subjectId)
        .eq('level_id', _studentLevelId ?? '')
        .order('display_order');

    if (mounted) setState(() => _topics = List<Map<String, dynamic>>.from(topics));
  }

  void _onTopicSelected(String? topicId) {
    setState(() {
      _selectedTopicId = topicId;
      if (topicId != null) {
        final topic = _topics.firstWhere((t) => t['id'] == topicId);
        _syllabusOutline = topic['syllabus_outline'] as String?;
      } else {
        _syllabusOutline = null;
      }
    });
  }

  Future<void> _generateSummary() async {
    if (_selectedSubjectId == null || _selectedTopicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select subject and topic'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isGenerating = true);

    final subjectName = _subjects.firstWhere((s) => s['id'] == _selectedSubjectId)['name'] ?? '';
    final topicName = _topics.firstWhere((t) => t['id'] == _selectedTopicId)['name'] ?? '';
    final title = '$topicName - $subjectName';

    final summary = await _aiService.generateSummary(
      topic: topicName,
      subject: subjectName,
      level: _studentLevelName ?? 'Form 4',
      syllabusOutline: _syllabusOutline,
    );

    if (summary.isNotEmpty && mounted) {
      // Save to database
      final userId = _authService.currentUserId;
      await Supabase.instance.client.from('ai_summaries').insert({
        'student_id': userId,
        'subject_id': _selectedSubjectId,
        'topic_id': _selectedTopicId,
        'title': title,
        'content': summary,
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SummaryViewerScreen(
            title: title,
            content: summary,
          ),
        ),
      );
    }

    if (mounted) setState(() => _isGenerating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Study Summary Generator'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade600, Colors.green.shade600],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.summarize_rounded, color: Colors.white, size: 48),
                        const SizedBox(height: 12),
                        const Text('AI Study Summary',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(_studentLevelName ?? 'Select level',
                            style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Subject
                  const Text('Subject', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedSubjectId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.book_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _subjects.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] ?? ''))).toList(),
                    onChanged: (v) {
                      setState(() { _selectedSubjectId = v; _selectedTopicId = null; _syllabusOutline = null; });
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
                    items: _topics.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['name'] ?? ''))).toList(),
                    onChanged: _onTopicSelected,
                  ),
                  const SizedBox(height: 16),

                  // Syllabus indicator
                  if (_syllabusOutline != null && _syllabusOutline!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('ZIMSEC syllabus outline available',
                                style: TextStyle(fontSize: 13, color: Colors.green)),
                          ),
                        ],
                      ),
                    )
                  else if (_selectedTopicId != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('No syllabus outline yet. AI will generate based on topic name.',
                                style: TextStyle(fontSize: 13, color: Colors.orange)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Generate button
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateSummary,
                      icon: _isGenerating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome),
                      label: Text(_isGenerating ? 'Generating...' : 'Generate Summary'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}