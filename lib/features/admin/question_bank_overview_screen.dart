import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuestionBankOverviewScreen extends StatefulWidget {
  const QuestionBankOverviewScreen({super.key});

  @override
  State<QuestionBankOverviewScreen> createState() => _QuestionBankOverviewScreenState();
}

class _QuestionBankOverviewScreenState extends State<QuestionBankOverviewScreen> {
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _topics = [];
  
  String? _selectedSubjectId;
  String? _selectedLevelId;
  String? _selectedTopicId;
  
  // Stats
  int _totalQuestions = 0;
  Map<String, int> _subjectCounts = {};
  Map<String, int> _levelCounts = {};
  Map<String, int> _topicCounts = {};
  Map<String, Map<String, int>> _difficultyCounts = {}; // subject -> {easy, medium, hard}
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load subjects, levels
      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true);

      final levels = await Supabase.instance.client
          .from('levels')
          .select()
          .order('display_order', ascending: true);

      // Load all question counts
      await _loadStats();

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _levels = List<Map<String, dynamic>>.from(levels);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      // Total questions
      final totalCount = await Supabase.instance.client
          .from('question_bank')
          .select('id')
          .eq('is_approved', true)
          .count(CountOption.exact);
      _totalQuestions = totalCount.count ?? 0;

      // Per subject
      final subjectData = await Supabase.instance.client
          .from('question_bank')
          .select('subject_id, subjects(name, color_hex), difficulty')
          .eq('is_approved', true);

      final subjectCounts = <String, int>{};
      final difficultyCounts = <String, Map<String, int>>{};
      
      for (final row in subjectData) {
        final subjectName = row['subjects']?['name'] as String? ?? 'Unknown';
        final difficulty = row['difficulty'] as String? ?? 'medium';
        
        subjectCounts[subjectName] = (subjectCounts[subjectName] ?? 0) + 1;
        
        difficultyCounts.putIfAbsent(subjectName, () => {'easy': 0, 'medium': 0, 'hard': 0});
        difficultyCounts[subjectName]![difficulty] = (difficultyCounts[subjectName]![difficulty] ?? 0) + 1;
      }

      // Per level (with optional subject filter)
      var levelQuery = Supabase.instance.client
          .from('question_bank')
          .select('level_id, levels(name)')
          .eq('is_approved', true);
      
      if (_selectedSubjectId != null) {
        levelQuery = levelQuery.eq('subject_id', _selectedSubjectId!);
      }

      final levelData = await levelQuery;
      final levelCounts = <String, int>{};
      for (final row in levelData) {
        final levelName = row['levels']?['name'] as String? ?? 'Unknown';
        levelCounts[levelName] = (levelCounts[levelName] ?? 0) + 1;
      }

      // Per topic (with optional subject + level filter)
      var topicQuery = Supabase.instance.client
          .from('question_bank')
          .select('topic_id, topics(name)')
          .eq('is_approved', true);
      
      if (_selectedSubjectId != null) {
        topicQuery = topicQuery.eq('subject_id', _selectedSubjectId!);
      }
      if (_selectedLevelId != null) {
        topicQuery = topicQuery.eq('level_id', _selectedLevelId!);
      }

      final topicData = await topicQuery;
      final topicCounts = <String, int>{};
      for (final row in topicData) {
        final topicName = row['topics']?['name'] as String?;
        if (topicName != null) {
          topicCounts[topicName] = (topicCounts[topicName] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _subjectCounts = subjectCounts;
          _levelCounts = levelCounts;
          _topicCounts = topicCounts;
          _difficultyCounts = difficultyCounts;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  Future<void> _loadTopics() async {
    if (_selectedSubjectId == null) {
      setState(() => _topics = []);
      return;
    }
    try {
      var query = Supabase.instance.client
          .from('topics')
          .select()
          .eq('subject_id', _selectedSubjectId!);
      
      if (_selectedLevelId != null && _selectedLevelId!.isNotEmpty) {
        query = query.eq('level_id', _selectedLevelId!);
      }

      final response = await query.order('display_order', ascending: true);
      if (mounted) {
        setState(() {
          _topics = List<Map<String, dynamic>>.from(response);
          // ✅ Reset topic if current selection is not in the new list
          if (_selectedTopicId != null && !_topics.any((t) => t['id'] == _selectedTopicId)) {
            _selectedTopicId = null;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading topics: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Bank Overview'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Total count
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A237E), Color(0xFF283593)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.quiz_rounded, color: Colors.white, size: 40),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$_totalQuestions', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                            const Text('Total Questions', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                 // Filters
Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: Colors.grey.shade200),
  ),
  child: Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          value: _selectedSubjectId,
          decoration: _dropdownDeco('Subject'),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('All Subjects', style: TextStyle(fontSize: 13))),
            ..._subjects.map((s) => DropdownMenuItem<String>(
              value: s['id'] as String, child: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13)),
            )),
          ],
          onChanged: (v) {
            setState(() { 
              _selectedSubjectId = v; 
              _selectedLevelId = null;
            });
            _loadStats();
          },
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: DropdownButtonFormField<String>(
          value: _selectedLevelId,
          decoration: _dropdownDeco('Level'),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('All Levels', style: TextStyle(fontSize: 13))),
            ..._levels.map((l) => DropdownMenuItem<String>(
              value: l['id'] as String, child: Text(l['name'] ?? '', style: const TextStyle(fontSize: 13)),
            )),
          ],
          onChanged: (v) {
            setState(() => _selectedLevelId = v);
            _loadStats();
          },
        ),
      ),
    ],
  ),
),
                  const SizedBox(height: 20),

                  // Subject stats cards
                  if (_selectedSubjectId == null) ...[
                    const Text('Questions by Subject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._subjectCounts.entries.map((entry) {
                      final subject = _subjects.firstWhere(
                        (s) => s['name'] == entry.key,
                        orElse: () => {'color_hex': '#1A237E'},
                      );
                      final color = Color(int.parse('FF${(subject['color_hex'] as String? ?? '1A237E').replaceAll('#', '')}', radix: 16));
                      final difficulties = _difficultyCounts[entry.key] ?? {};

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: color.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
                                const SizedBox(height: 4),
                                Text('${entry.value} questions', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ]),
                            ),
                            // Difficulty breakdown
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _DiffBadge(label: 'E', count: difficulties['easy'] ?? 0, color: const Color(0xFF4CAF50)),
                                const SizedBox(width: 4),
                                _DiffBadge(label: 'M', count: difficulties['medium'] ?? 0, color: const Color(0xFFFF9800)),
                                const SizedBox(width: 4),
                                _DiffBadge(label: 'H', count: difficulties['hard'] ?? 0, color: Colors.red),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  // Level stats (when subject selected)
                  if (_selectedSubjectId != null && _levelCounts.isNotEmpty) ...[
                    const Text('Questions by Level', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._levelCounts.entries.map((entry) {
                      final color = _getLevelColor(entry.key);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(entry.key, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color))),
                            Text('${entry.value}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
                          ],
                        ),
                      );
                    }),
                  ],

                  // Topic stats (when level selected)
                  if (_selectedLevelId != null && _topicCounts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Questions by Topic', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._topicCounts.entries.map((entry) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.topic_rounded, size: 16, color: Color(0xFF1A237E)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 13))),
                            Text('${entry.value}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }

  InputDecoration _dropdownDeco(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'Form 1': return Colors.blue;
      case 'Form 2': return Colors.teal;
      case 'O-Level': return const Color(0xFFFF9800);
      case 'A-Level': return Colors.purple;
      default: return Colors.grey;
    }
  }
}

class _DiffBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _DiffBadge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label:$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}