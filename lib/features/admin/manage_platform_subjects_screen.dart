import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'manage_topics_screen.dart';

class ManagePlatformSubjectsScreen extends StatefulWidget {
  const ManagePlatformSubjectsScreen({super.key});

  @override
  State<ManagePlatformSubjectsScreen> createState() => _ManagePlatformSubjectsScreenState();
}

class _ManagePlatformSubjectsScreenState extends State<ManagePlatformSubjectsScreen> {
  List<Map<String, dynamic>> _subjects = [];
  Map<String, int> _topicCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .order('name', ascending: true);

      // Count topics per subject
      final topicCounts = <String, int>{};
      for (final s in subjects) {
        final count = await Supabase.instance.client
            .from('topics')
            .select('id')
            .eq('subject_id', s['id'] as String)
            .count(CountOption.exact);
        topicCounts[s['id'] as String] = count.count ?? 0;
      }

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _topicCounts = topicCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Subjects & Topics'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _subjects.isEmpty
              ? const Center(child: Text('No subjects available', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _subjects.length,
                  itemBuilder: (context, index) {
                    final subject = _subjects[index];
                    final subjectId = subject['id'] as String;
                    final subjectName = subject['name'] as String;
                    final color = Color(
                      int.parse('FF${(subject['color_hex'] as String? ?? '1A237E').replaceAll('#', '')}', radix: 16),
                    );
                    final topicCount = _topicCounts[subjectId] ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        elevation: 1,
                        shadowColor: color.withOpacity(0.2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ManageTopicsScreen(
                                  subjectId: subjectId,
                                  subjectName: subjectName,
                                  subjectColor: color,
                                ),
                              ),
                            ).then((_) => _loadSubjects());
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: color.withOpacity(0.15)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 56, height: 56,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(Icons.book_rounded, color: color, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(subjectName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.topic_rounded, size: 14, color: Colors.grey.shade400),
                                          const SizedBox(width: 4),
                                          Text('$topicCount topics', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Text('Manage Topics →', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}