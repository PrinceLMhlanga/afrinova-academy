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
    _loadPapers();
  }

  Future<void> _loadPapers() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('exam_papers')
          .select('*, subjects(name)')
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _papers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No exam papers yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
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
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPapers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _papers.length,
                    itemBuilder: (context, index) {
                      final paper = _papers[index];
                      final isPublished = paper['is_published'] ?? false;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title + Status
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      paper['title'] ?? 'Untitled',
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isPublished
                                          ? const Color(0xFF4CAF50).withOpacity(0.1)
                                          : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isPublished ? const Color(0xFF4CAF50) : Colors.orange,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isPublished ? Icons.check_circle : Icons.edit_note,
                                          size: 16,
                                          color: isPublished ? const Color(0xFF4CAF50) : Colors.orange,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isPublished ? 'Published' : 'Draft',
                                          style: TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w600,
                                            color: isPublished ? const Color(0xFF4CAF50) : Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Info row
                              Row(
                                children: [
                                  _InfoChip(icon: Icons.book, text: paper['subjects']?['name'] ?? 'No subject'),
                                  const SizedBox(width: 8),
                                  _InfoChip(icon: Icons.school, text: paper['curriculum'] ?? 'ZIMSEC'),
                                  const SizedBox(width: 8),
                                  _InfoChip(icon: Icons.description, text: paper['paper_type'] ?? 'Paper 1'),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _InfoChip(icon: Icons.grade, text: '${paper['total_marks'] ?? 0} marks'),
                                  const SizedBox(width: 8),
                                  _InfoChip(icon: Icons.timer, text: '${paper['duration_minutes'] ?? 0} min'),
                                ],
                              ),

                              const SizedBox(height: 14),
                              const Divider(height: 1),
                              const SizedBox(height: 8),

                              // Action buttons
                              Row(
                                children: [
                                  // View Submissions
                                  _ActionButton(
                                    icon: Icons.people_outline,
                                    label: 'Submissions',
                                    color: const Color(0xFF1A237E),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PaperSubmissionsScreen(paper: paper),
                                        ),
                                      );
                                    },
                                  ),

                                  // Publish/Unpublish
                                  _ActionButton(
                                    icon: isPublished ? Icons.unpublished : Icons.publish,
                                    label: isPublished ? 'Unpublish' : 'Publish',
                                    color: isPublished ? Colors.orange : const Color(0xFF4CAF50),
                                    onTap: () => _togglePublish(paper),
                                  ),

                                  // Edit
                                  _ActionButton(
                                    icon: Icons.edit_outlined,
                                    label: 'Edit',
                                    color: Colors.blue,
                                    onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ExamPaperEditorScreen(existingPaper: paper), // ← Pass paper
    ),
  ).then((_) => _loadPapers());
},
                                  ),

                                  // Delete
                                  _ActionButton(
                                    icon: Icons.delete_outline,
                                    label: 'Delete',
                                    color: Colors.red,
                                    onTap: () => _deletePaper(paper),
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
    );
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