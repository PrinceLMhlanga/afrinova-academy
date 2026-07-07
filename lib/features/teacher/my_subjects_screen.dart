import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'topic_manager_screen.dart';

class TeacherLevelSubjectsScreen extends StatefulWidget {
  final String levelId;
  final String levelName;

  const TeacherLevelSubjectsScreen({
    super.key,
    required this.levelId,
    required this.levelName,
  });

  @override
  State<TeacherLevelSubjectsScreen> createState() => _TeacherLevelSubjectsScreenState();
}

class _TeacherLevelSubjectsScreenState extends State<TeacherLevelSubjectsScreen> {
  final AuthService _authService = AuthService();
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
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get teacher's subjects for this specific level
      final response = await Supabase.instance.client
          .from('teacher_subjects')
          .select('subject_id, subjects!inner(name, description, color_hex, icon_name)')
          .eq('teacher_id', userId)
          .eq('level_id', widget.levelId)
          .order('name', referencedTable: 'subjects');

      // Count topics per subject
      final topicCounts = <String, int>{};
      for (final row in response) {
        final subjectId = row['subject_id'] as String;
        final count = await Supabase.instance.client
            .from('teacher_topics')
            .select('id')
            .eq('teacher_id', userId)
            .eq('subject_id', subjectId)
            .eq('level_id', widget.levelId)
            .count(CountOption.exact);
        
        topicCounts[subjectId] = count.count ?? 0;
      }

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(response);
          _topicCounts = topicCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading subjects: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.levelName} Subjects'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _subjects.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.book_rounded, color: Color(0xFF1A237E), size: 20),
                          const SizedBox(width: 10),
                          Text(
                            '${_subjects.length} subject(s) assigned for ${widget.levelName}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1A237E)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Subject cards
                    ..._subjects.map((row) {
                      final subject = row['subjects'] as Map<String, dynamic>;
                      final subjectId = row['subject_id'] as String;
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
                                  builder: (_) => TopicManagerScreen(
                                    subjectId: subjectId,
                                    subjectName: subjectName,
                                    subjectColor: color,
                                    levelId: widget.levelId,
                                    levelName: widget.levelName,
                                  ),
                                ),
                              ).then((_) => _loadSubjects());
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: color.withOpacity(0.15)),
                              ),
                              child: Row(
                                children: [
                                  // Subject icon
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _getSubjectIcon(subject['icon_name'] as String?),
                                      color: color,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  
                                  // Subject info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          subjectName,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: color,
                                          ),
                                        ),
                                        if (subject['description'] != null && (subject['description'] as String).isNotEmpty)
                                          Text(
                                            subject['description'],
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.topic_rounded, size: 14, color: Colors.grey.shade400),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$topicCount topic(s)',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Arrow
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.chevron_right, color: color, size: 18),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.book_outlined, size: 48, color: Color(0xFF1A237E)),
            ),
            const SizedBox(height: 24),
            const Text('No subjects assigned',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            const SizedBox(height: 8),
            Text('No subjects are assigned for ${widget.levelName}.\nContact admin if you need changes.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  IconData _getSubjectIcon(String? iconName) {
    switch (iconName) {
      case 'calculate': return Icons.calculate;
      case 'science': return Icons.science;
      case 'nature': return Icons.eco;
      case 'computer': return Icons.computer;
      case 'menu_book': return Icons.menu_book;
      case 'history_edu': return Icons.history_edu;
      case 'public': return Icons.public;
      case 'business': return Icons.business;
      case 'language': return Icons.language;
      default: return Icons.school;
    }
  }
}