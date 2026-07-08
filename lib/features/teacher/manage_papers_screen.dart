import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'exam_paper_editor_screen.dart';
import 'paper_submissions_screen.dart';

class ManagePapersScreen extends StatefulWidget {
  const ManagePapersScreen({super.key});

  @override
  State<ManagePapersScreen> createState() => _ManagePapersScreenState();
}

class _ManagePapersScreenState extends State<ManagePapersScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _papers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLevels();
    _loadPapers();
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
      setState(() => _levels = List<Map<String, dynamic>>.from(response));
    }
  } catch (_) {}
}

List<Map<String, dynamic>> get _filteredPapers {
  if (_selectedLevelId == null) return _papers;
  return _papers.where((p) => p['level_id'] == _selectedLevelId).toList();
}

  Future<void> _loadPapers() async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    // ✅ Load with level info
    final response = await Supabase.instance.client
        .from('exam_papers')
        .select('*, subjects(name), levels!exam_papers_level_id_fkey(name)')
        .eq('creator_id', userId)
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() {
        _papers = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    }
  } catch (e) {
    if (mounted) setState(() => _isLoading = false);
  }
}

// ✅ Group papers by subject
List<Map<String, dynamic>> get _groupedSubjects {
  final grouped = <String, List<Map<String, dynamic>>>{};
  
  for (final paper in _filteredPapers) {
    final subjectName = paper['subjects']?['name'] as String? ?? 'Uncategorized';
    if (!grouped.containsKey(subjectName)) {
      grouped[subjectName] = [];
    }
    grouped[subjectName]!.add(paper);
  }
  
  // Convert to list and sort by subject name
  return grouped.entries.map((entry) => {
    'subjectName': entry.key,
    'papers': entry.value,
  }).toList()
    ..sort((a, b) => (a['subjectName'] as String).compareTo(b['subjectName'] as String));
}

Color _getSubjectColor(String subject) {
  // Return consistent colors based on subject name
  final colors = {
    'Physics': Colors.blue,
    'Chemistry': Colors.green,
    'Biology': Colors.teal,
    'Mathematics': const Color(0xFFFF9800),
    'English': Colors.purple,
    'History': Colors.brown,
    'Geography': Colors.indigo,
    'Combined Science': const Color(0xFF1A237E),
  };
  return colors[subject] ?? const Color(0xFF1A237E);
}

  Future<void> _togglePublish(Map<String, dynamic> paper) async {
    final newStatus = !(paper['is_published'] ?? false);
    await Supabase.instance.client
        .from('exam_papers')
        .update({'is_published': newStatus})
        .eq('id', paper['id']);
    _loadPapers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus ? 'Paper published! ✅' : 'Paper unpublished'),
          backgroundColor: newStatus ? const Color(0xFF4CAF50) : Colors.orange,
        ),
      );
    }
  }

  Future<void> _deletePaper(Map<String, dynamic> paper) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Paper?'),
        content: Text('"${paper['title']}" will be permanently deleted.\n\nThis removes all questions and student submissions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.from('exam_papers').delete().eq('id', paper['id']);
      _loadPapers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paper deleted'), backgroundColor: Colors.red),
        );
      }
    }
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
            child: const Icon(Icons.assignment_outlined, size: 48, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 24),
          Text(
            _selectedLevelId == null 
                ? 'No exam papers yet' 
                : 'No papers for $_selectedLevelName',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Create your first exam paper to start testing your students',
            style: TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExamPaperEditorScreen()),
              ).then((_) => _loadPapers());
            },
            icon: const Icon(Icons.add),
            label: const Text('Create Your First Paper'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Exam Papers'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create New Paper',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExamPaperEditorScreen()),
              ).then((_) => _loadPapers());
            },
          ),
        ],
      ),
      body: Column(
  children: [
    // Level tabs (keep as is)
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
                count: _papers.length,
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
                final count = _papers.where((p) => p['level_id'] == levelId).length;
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

    // ✅ Grouped by subject
    Expanded(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _filteredPapers.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadPapers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _groupedSubjects.length,
                    itemBuilder: (context, index) {
                      final group = _groupedSubjects[index];
                      final subjectName = group['subjectName'] as String;
                      final papers = group['papers'] as List<Map<String, dynamic>>;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Subject header
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, top: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 4, height: 20,
                                  decoration: BoxDecoration(
                                    color: _getSubjectColor(subjectName),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  subjectName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _getSubjectColor(subjectName),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getSubjectColor(subjectName).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${papers.length} paper(s)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _getSubjectColor(subjectName),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Papers under this subject
                          ...papers.map((paper) {
                            final isPublished = paper['is_published'] ?? false;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title + Status
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            paper['title'] ?? 'Untitled',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isPublished
                                                ? const Color(0xFF4CAF50).withOpacity(0.1)
                                                : Colors.orange.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            isPublished ? 'Published' : 'Draft',
                                            style: TextStyle(
                                              fontSize: 10, fontWeight: FontWeight.w600,
                                              color: isPublished ? const Color(0xFF4CAF50) : Colors.orange,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Info chips
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (paper['levels']?['name'] != null)
                                          _InfoChip(icon: Icons.school_rounded, text: paper['levels']['name'] as String),
                                        _InfoChip(icon: Icons.school, text: paper['curriculum'] ?? 'ZIMSEC'),
                                        _InfoChip(icon: Icons.description, text: paper['paper_type'] ?? 'Paper 1'),
                                        _InfoChip(icon: Icons.grade, text: '${paper['total_marks'] ?? 0} marks'),
                                        _InfoChip(icon: Icons.timer, text: '${paper['duration_minutes'] ?? 0} min'),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Actions
                                    Row(
                                      children: [
                                        _ActionButton(icon: Icons.people_outline, label: 'Submissions', color: const Color(0xFF1A237E),
                                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaperSubmissionsScreen(paper: paper)))),
                                        _ActionButton(icon: isPublished ? Icons.unpublished : Icons.publish,
                                          label: isPublished ? 'Unpublish' : 'Publish',
                                          color: isPublished ? Colors.orange : const Color(0xFF4CAF50),
                                          onTap: () => _togglePublish(paper)),
                                        _ActionButton(icon: Icons.edit_outlined, label: 'Edit', color: Colors.blue,
                                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExamPaperEditorScreen(existingPaper: paper))).then((_) => _loadPapers())),
                                        _ActionButton(icon: Icons.delete_outline, label: 'Delete', color: Colors.red,
                                          onTap: () => _deletePaper(paper)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade600),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
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

  const _LevelTab({required this.label, required this.count, required this.isSelected, this.color, required this.onTap});

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
          border: Border.all(color: isSelected ? tabColor : Colors.grey.shade300, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? tabColor : Colors.grey.shade600)),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: isSelected ? tabColor.withOpacity(0.2) : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
              child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? tabColor : Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}