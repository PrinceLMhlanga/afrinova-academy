import 'package:flutter/material.dart';
import '../../core/exam_service.dart';
import '../../core/auth_service.dart';
import 'exam_creator_screen.dart';
import 'exam_questions_screen.dart';
import 'edit_exam_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyExamsScreen extends StatefulWidget {
  const MyExamsScreen({super.key});

  @override
  State<MyExamsScreen> createState() => _MyExamsScreenState();
}

class _MyExamsScreenState extends State<MyExamsScreen> {
  final ExamService _examService = ExamService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _exams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLevels();
    _loadExams();
  }

  // ✅ ADD: Level tab support
List<Map<String, dynamic>> _levels = [];
String? _selectedLevelId;
String _selectedLevelName = 'All';

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
      });
    }
  } catch (_) {}
}

List<Map<String, dynamic>> get _filteredExams {
  if (_selectedLevelId == null) return _exams;
  return _exams.where((e) => e['level_id'] == _selectedLevelId).toList();
}

  Future<void> _loadExams() async {
  try {
    final userId = _authService.currentUserId;
    if (userId != null) {
      // ✅ Load with level info
      final response = await Supabase.instance.client
          .from('exams')
          .select('*, teacher_topics!inner(name, subjects!inner(name), levels!inner(name))')
          .eq('creator_id', userId)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _exams = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    }
  } catch (e) {
    debugPrint('Error loading exams: $e');
    if (mounted) setState(() => _isLoading = false);
  }
}

  Future<void> _publishExam(String examId) async {
    try {
      await _examService.publishExam(examId);
      _loadExams();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exam published! Students can now take it. ✅'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _unpublishExam(String examId) async {
    try {
      await Supabase.instance.client
          .from('exams')
          .update({'is_published': false}).eq('id', examId);
      _loadExams();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exam unpublished.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteExam(String examId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Exam?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "$title"?'),
            const SizedBox(height: 8),
            const Text(
              'This will permanently delete the exam and all its questions. This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client
            .from('exams')
            .delete()
            .eq('id', examId);
        _loadExams();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exam deleted successfully.'),
              backgroundColor: Color(0xFF4CAF50),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting exam: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Exams'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create New Exam',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ExamCreatorScreen()),
              );
              _loadExams();
            },
          ),
        ],
      ),
      body: Column(
  children: [
    // ✅ Level tabs
    if (_levels.isNotEmpty)
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.white,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _LevelTab(
                label: 'All',
                count: _exams.length,
                isSelected: _selectedLevelId == null,
                onTap: () => setState(() {
                  _selectedLevelId = null;
                  _selectedLevelName = 'All';
                }),
              ),
              ..._levels.map((row) {
                final level = row['levels'] as Map<String, dynamic>;
                final levelId = row['level_id'] as String;
                final levelName = level['name'] as String;
                final count = _exams.where((e) => e['level_id'] == levelId).length;
                return _LevelTab(
                  label: levelName,
                  count: count,
                  isSelected: _selectedLevelId == levelId,
                  color: _getLevelColor(levelName),
                  onTap: () => setState(() {
                    _selectedLevelId = levelId;
                    _selectedLevelName = levelName;
                  }),
                );
              }),
            ],
          ),
        ),
      ),
    const Divider(height: 1),

    // ✅ Use _filteredExams instead of _exams
    Expanded(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _filteredExams.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.quiz_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        _selectedLevelId == null ? 'No exams created yet' : 'No exams for $_selectedLevelName',
                        style: const TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text('Create your first exam to test your students',
                          style: TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamCreatorScreen()));
                          _loadExams();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Create Your First Exam'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadExams,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredExams.length,
                    itemBuilder: (context, index) {
                      final exam = _filteredExams[index];  // ✅ Use filtered
                      
                      final isPublished = exam['is_published'] ?? false;
                      final examId = exam['id'] as String;
                      final title = exam['title'] as String? ?? 'Untitled';
                      final description =
                          exam['description'] as String? ?? '';
                      final topicName = exam['teacher_topics']?['name'] ?? '';
                      final subjectName = exam['teacher_topics']?['subjects']?['name'] ?? '';
                      final durationMin = exam['duration_minutes'];
                      final totalMarks = exam['total_marks'] ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title + Status
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A237E),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isPublished
                                          ? const Color(0xFF4CAF50)
                                              .withOpacity(0.1)
                                          : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isPublished
                                            ? const Color(0xFF4CAF50)
                                            : Colors.orange,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isPublished
                                              ? Icons.check_circle
                                              : Icons.edit_note,
                                          size: 16,
                                          color: isPublished
                                              ? const Color(0xFF4CAF50)
                                              : Colors.orange,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isPublished
                                              ? 'Published'
                                              : 'Draft',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isPublished
                                                ? const Color(0xFF4CAF50)
                                                : Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 12),

                              // Info chips
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (exam['teacher_topics']?['levels']?['name'] != null)
      _InfoChip(
        icon: Icons.school_rounded,
        text: exam['teacher_topics']['levels']['name'] as String,
      ),
                                  if (subjectName.isNotEmpty)
                                    _InfoChip(
                                        icon: Icons.book,
                                        text: subjectName),
                                  if (topicName.isNotEmpty)
                                    _InfoChip(
                                        icon: Icons.topic, text: topicName),
                                  _InfoChip(
                                    icon: Icons.timer_outlined,
                                    text: durationMin != null
                                        ? '${durationMin} min'
                                        : 'No limit',
                                  ),
                                  _InfoChip(
                                    icon: Icons.grade,
                                    text: '$totalMarks pts',
                                  ),
                                  _InfoChip(
                                    icon: Icons.help_outline,
                                    text: 'Pass: ${exam['passing_percentage'] ?? 50}%',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Action buttons
                              Row(
                                children: [
                                  // View Questions
                                  _ActionButton(
                                    icon: Icons.visibility_outlined,
                                    label: 'Questions',
                                    color: const Color(0xFF1A237E),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ExamQuestionsScreen(
                                            examId: examId,
                                            examTitle: title,
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  // Edit
                                  _ActionButton(
                                    icon: Icons.edit_outlined,
                                    label: 'Edit',
                                    color: Colors.blue,
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EditExamScreen(
                                            examId: examId,
                                            examData: exam,
                                          ),
                                        ),
                                      );
                                      _loadExams();
                                    },
                                  ),

                                  // Publish/Unpublish
                                  _ActionButton(
                                    icon: isPublished
                                        ? Icons.unpublished_outlined
                                        : Icons.publish_outlined,
                                    label: isPublished
                                        ? 'Unpublish'
                                        : 'Publish',
                                    color: isPublished
                                        ? Colors.orange
                                        : const Color(0xFF4CAF50),
                                    onTap: () {
                                      if (isPublished) {
                                        _unpublishExam(examId);
                                      } else {
                                        _publishExam(examId);
                                      }
                                    },
                                  ),

                                  // Delete
                                  _ActionButton(
                                    icon: Icons.delete_outline,
                                    label: 'Delete',
                                    color: Colors.red,
                                    onTap: () =>
                                        _deleteExam(examId, title),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    
                  ),
                ),
    ),
  ],
),
    );
  }

  Color _getLevelColor(String level) {
  switch (level) {
    case 'Form 1': return Colors.blue;
    case 'Form 2': return Colors.teal;
    case 'O-Level': return const Color(0xFFFF9800);
    case 'A-Level': return Colors.purple;
    default: return const Color(0xFF1A237E);
  }
}
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade600),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _LevelTab extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _LevelTab({
    required this.label,
    required this.count,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tabColor = color ?? const Color(0xFF1A237E);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? tabColor.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? tabColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? tabColor : Colors.grey.shade600,
            )),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? tabColor.withOpacity(0.2) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count', style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? tabColor : Colors.grey,
              )),
            ),
          ],
        ),
      ),
    );
  }
}