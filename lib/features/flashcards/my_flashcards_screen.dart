import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'flashcard_study_screen.dart';
import 'flashcard_generator_screen.dart';

class MyFlashcardsScreen extends StatefulWidget {
  const MyFlashcardsScreen({super.key});

  @override
  State<MyFlashcardsScreen> createState() => _MyFlashcardsScreenState();
}

class _MyFlashcardsScreenState extends State<MyFlashcardsScreen> {
  final AuthService _authService = AuthService();
  Map<String, List<Map<String, dynamic>>> _groupedBySubject = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFlashcards();
  }

  Future<void> _loadFlashcards() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final flashcards = await Supabase.instance.client
          .from('ai_flashcards')
          .select('''
            *,
            subject:subject_id(name, color_hex, icon_name),
            topic:topic_id(name)
          ''')
          .eq('student_id', userId)
          .order('created_at', ascending: false);

      // Group by subject
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final card in flashcards) {
        final subjectName = card['subject']?['name'] as String? ?? 'General';
        if (!grouped.containsKey(subjectName)) {
          grouped[subjectName] = [];
        }
        grouped[subjectName]!.add(card);
      }

      if (mounted) {
        setState(() {
          _groupedBySubject = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading flashcards: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFlashcard(String id) async {
    await Supabase.instance.client
        .from('ai_flashcards')
        .delete()
        .eq('id', id);
    _loadFlashcards();
  }

  void _studyFlashcards(String subjectName, List<Map<String, dynamic>> cards) {
    final studyCards = cards.map((c) => {
      'question': c['question'] as String,
      'answer': c['answer'] as String,
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FlashcardStudyScreen(
          cards: studyCards,
          topicName: subjectName,
        ),
      ),
    ).then((_) => _loadFlashcards());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Flashcards'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FlashcardGeneratorScreen()),
              ).then((_) => _loadFlashcards());
            },
            tooltip: 'Generate New',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _groupedBySubject.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadFlashcards,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _groupedBySubject.entries.map((entry) {
                      return _buildSubjectGroup(entry.key, entry.value);
                    }).toList(),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.style_rounded, size: 48, color: Colors.purple),
          ),
          const SizedBox(height: 24),
          const Text('No Flashcards Yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 8),
          const Text('Generate AI-powered flashcards\nto start studying', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FlashcardGeneratorScreen()),
              ).then((_) => _loadFlashcards());
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate Flashcards'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectGroup(String subjectName, List<Map<String, dynamic>> cards) {
    // Group by topic within subject
    final byTopic = <String, List<Map<String, dynamic>>>{};
    for (final card in cards) {
      final topicName = card['topic']?['name'] as String? ?? 'General';
      if (!byTopic.containsKey(topicName)) {
        byTopic[topicName] = [];
      }
      byTopic[topicName]!.add(card);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subject header
        Container(
          margin: const EdgeInsets.only(bottom: 12, top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade600, Colors.blue.shade600],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.style_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(subjectName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${cards.length} cards',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ),

        // Topic sub-groups
        ...byTopic.entries.map((topicEntry) => _buildTopicGroup(topicEntry.key, topicEntry.value)),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTopicGroup(String topicName, List<Map<String, dynamic>> cards) {
    // Calculate stats
    final totalReviewed = cards.fold<int>(0, (sum, c) => sum + (c['times_reviewed'] as int? ?? 0));
    final totalCorrect = cards.fold<int>(0, (sum, c) => sum + (c['times_correct'] as int? ?? 0));
    final mastery = totalReviewed > 0 ? (totalCorrect / cards.length * 100).round() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(topicName, style: const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 8),
              Text('${cards.length} cards', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),

        // Study button + stats
        GestureDetector(
          onTap: () => _studyFlashcards('$topicName Flashcards', cards),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.purple, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Study Flashcards', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Color(0xFF1A237E))),
                      const SizedBox(height: 4),
                      Text(
                        totalReviewed > 0
                            ? '$mastery% mastery • Reviewed $totalReviewed times'
                            : 'Tap to start studying',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}