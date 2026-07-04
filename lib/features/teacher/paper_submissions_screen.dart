import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'marking_screen.dart';

class PaperSubmissionsScreen extends StatefulWidget {
  final Map<String, dynamic> paper;

  const PaperSubmissionsScreen({super.key, required this.paper});

  @override
  State<PaperSubmissionsScreen> createState() => _PaperSubmissionsScreenState();
}

class _PaperSubmissionsScreenState extends State<PaperSubmissionsScreen> {
  List<Map<String, dynamic>> _submissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    try {
      // Get all students who submitted for this paper (grouped by student)
      final response = await Supabase.instance.client
          .from('exam_answers')
          .select('student_id, status, profiles!student_id(full_name, email)')
          .eq('paper_id', widget.paper['id'])
          .order('submitted_at', ascending: false);

      // Group by student_id
      final Map<String, Map<String, dynamic>> studentMap = {};
      for (final row in response) {
        final studentId = row['student_id'] as String;
        if (!studentMap.containsKey(studentId)) {
          studentMap[studentId] = {
            'student_id': studentId,
            'profile': row['profiles'],
            'status': row['status'],
            'answered_count': 0,
            'total_marks_awarded': 0,
          };
        }
        if (row['status'] == 'submitted' || row['status'] == 'marked') {
          studentMap[studentId]!['answered_count'] = (studentMap[studentId]!['answered_count'] as int) + 1;
        }
        if (row['marks_awarded'] != null) {
          studentMap[studentId]!['total_marks_awarded'] = 
              (studentMap[studentId]!['total_marks_awarded'] as int) + (row['marks_awarded'] as int);
        }
      }

      if (mounted) {
        setState(() {
          _submissions = studentMap.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getStatus(String? status) {
    switch (status) {
      case 'submitted': return 'Submitted';
      case 'marked': return 'Marked';
      case 'draft': return 'In Progress';
      default: return 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'submitted': return Colors.orange;
      case 'marked': return const Color(0xFF4CAF50);
      case 'draft': return Colors.grey;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalQuestions = widget.paper['total_marks'] ?? 0;
    final submittedCount = _submissions.where((s) => 
        s['status'] == 'submitted' || s['status'] == 'marked').length;
    final markedCount = _submissions.where((s) => s['status'] == 'marked').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.paper['title'] ?? 'Submissions'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : Column(
              children: [
                // Stats bar
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      _StatChip(label: 'Total', value: '${_submissions.length}', color: const Color(0xFF1A237E)),
                      const SizedBox(width: 12),
                      _StatChip(label: 'Submitted', value: '$submittedCount', color: Colors.orange),
                      const SizedBox(width: 12),
                      _StatChip(label: 'Marked', value: '$markedCount', color: const Color(0xFF4CAF50)),
                    ],
                  ),
                ),

                Expanded(
                  child: _submissions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              const Text('No submissions yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadSubmissions,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _submissions.length,
                            itemBuilder: (context, index) {
                              final sub = _submissions[index];
                              final profile = sub['profile'] as Map<String, dynamic>?;
                              final status = sub['status'] as String?;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(14),
                                  leading: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                                    child: Text(
                                      (profile?['full_name'] ?? 'S')[0].toUpperCase(),
                                      style: const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                  ),
                                  title: Text(profile?['full_name'] ?? 'Student',
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(profile?['email'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      if (sub['total_marks_awarded'] > 0)
                                        Text('Marks: ${sub['total_marks_awarded']}',
                                            style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(status).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _getStatus(status),
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _getStatusColor(status)),
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MarkingScreen(
                                          paper: widget.paper,
                                          studentId: sub['student_id'] as String,
                                          studentName: profile?['full_name'] ?? 'Student',
                                        ),
                                      ),
                                    ).then((_) => _loadSubmissions());
                                  },
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
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}