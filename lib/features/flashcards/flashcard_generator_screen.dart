import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/ai_service.dart';
import 'flashcard_study_screen.dart';

class FlashcardGeneratorScreen extends StatefulWidget {
  const FlashcardGeneratorScreen({super.key});

  @override
  State<FlashcardGeneratorScreen> createState() => _FlashcardGeneratorScreenState();
}

class _FlashcardGeneratorScreenState extends State<FlashcardGeneratorScreen> {
  final AuthService _authService = AuthService();
  final AIService _aiService = AIService();
  
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  String? _selectedSubjectId;
  String? _selectedTopicId;
  String? _studentLevelId;
  String? _studentLevelName;
  int _cardCount = 10;
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
        .select()
        .eq('subject_id', subjectId)
        .eq('level_id', _studentLevelId ?? '')
        .order('display_order');

    if (mounted) setState(() => _topics = List<Map<String, dynamic>>.from(topics));
  }

  Future<void> _generateFlashcards() async {
    if (_selectedSubjectId == null || _selectedTopicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select subject and topic'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isGenerating = true);

    final subjectName = _subjects.firstWhere((s) => s['id'] == _selectedSubjectId)['name'] ?? '';
    final topicName = _topics.firstWhere((t) => t['id'] == _selectedTopicId)['name'] ?? '';

    final cards = await _aiService.generateFlashcards(
      topic: topicName,
      subject: subjectName,
      level: _studentLevelName ?? 'Form 4',
      count: _cardCount,
    );

    if (cards.isNotEmpty && mounted) {
      // Save to database
      final userId = _authService.currentUserId;
      for (final card in cards) {
        await Supabase.instance.client.from('ai_flashcards').insert({
          'student_id': userId,
          'subject_id': _selectedSubjectId,
          'topic_id': _selectedTopicId,
          'question': card['question'],
          'answer': card['answer'],
        });
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FlashcardStudyScreen(
            cards: cards,
            topicName: topicName,
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
        title: const Text('AI Flashcard Generator'),
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
                  // Header card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade600, Colors.blue.shade600],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.white, size: 48),
                        const SizedBox(height: 12),
                        const Text('AI Flashcard Generator',
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
                    items: _topics.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['name'] ?? ''))).toList(),
                    onChanged: (v) => setState(() => _selectedTopicId = v),
                  ),
                  const SizedBox(height: 16),

                  // Card count
                  const Text('Number of Cards', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('5', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('$_cardCount cards', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E))),
                        const Text('20', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Slider(
                    value: _cardCount.toDouble(),
                    min: 5, max: 20, divisions: 3,
                    activeColor: const Color(0xFF1A237E),
                    onChanged: (v) => setState(() => _cardCount = v.round()),
                  ),
                  const SizedBox(height: 24),

                  // Generate button
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateFlashcards,
                      icon: _isGenerating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome),
                      label: Text(_isGenerating ? 'Generating...' : 'Generate $_cardCount Flashcards'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
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