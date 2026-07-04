import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'student_performance_screen.dart';


class MyStudentsScreen extends StatefulWidget {
  const MyStudentsScreen({super.key});

  @override
  State<MyStudentsScreen> createState() => _MyStudentsScreenState();
}

class _MyStudentsScreenState extends State<MyStudentsScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _groupedStudents = [];
  Map<String, int> _subjectStats = {};
  int _totalStudents = 0;
  int _totalPaid = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('enrollments')
          .select('id, status, approved_at, student_id, subject_id, subjects(name, color_hex)')
          .eq('teacher_id', userId)
          .inFilter('status', ['paid', 'approved'])
          .order('approved_at', ascending: false);

      // Get all student profiles
      final studentIds = response.map((e) => e['student_id'] as String).toSet().toList();
      Map<String, Map<String, dynamic>> profiles = {};
      if (studentIds.isNotEmpty) {
        final profilesResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, email, phone_number')
            .inFilter('id', studentIds);
        for (final p in profilesResponse) {
          profiles[p['id'] as String] = p;
        }
      }

      // Group by student_id
      final Map<String, Map<String, dynamic>> grouped = {};
      for (final row in response) {
        final studentId = row['student_id'] as String;
        final status = row['status'] as String;
        final subject = row['subjects'] as Map<String, dynamic>?;

        if (!grouped.containsKey(studentId)) {
          grouped[studentId] = {
            'student_id': studentId,
            'profile': profiles[studentId] ?? {'full_name': 'Unknown Student'},
            'subjects': <Map<String, dynamic>>[],
            'isPaid': false,
          };
        }

        grouped[studentId]!['subjects'].add({
          'enrollment_id': row['id'],
          'subject_name': subject?['name'] ?? 'Unknown',
          'subject_color': subject?['color_hex'] ?? '#1A237E',
          'status': status,
        });

        // If ANY subject is paid, mark student as paid
        if (status == 'paid') {
          grouped[studentId]!['isPaid'] = true;
        }
      }

      // Calculate stats
      final allStudents = grouped.values.toList();
      _totalStudents = allStudents.length;
      _totalPaid = allStudents.where((s) => s['isPaid'] == true).length;

      // Per-subject stats
      final subjectStats = <String, int>{};
      for (final student in allStudents) {
        for (final subject in (student['subjects'] as List<Map<String, dynamic>>)) {
          final name = subject['subject_name'] as String;
          subjectStats[name] = (subjectStats[name] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _groupedStudents = allStudents;
          _subjectStats = subjectStats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeStudent(String enrollmentId, String studentName, String subjectName) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Remove Student?'),
      content: Text('Remove $studentName from $subjectName?\n\nThis will delete the enrollment record.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await Supabase.instance.client.from('enrollments').delete().eq('id', enrollmentId);
    _loadStudents();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$studentName removed from $subjectName'), backgroundColor: Colors.orange),
      );
    }
  }
}





Future<void> _removeStudentCompletely(String studentId, String studentName) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Remove Student Completely?'),
      content: Text('Remove $studentName from ALL subjects?\n\nThis will delete all their enrollments with you.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Remove All'),
        ),
      ],
    ),
  );
  if (confirm == true) {
    final teacherId = _authService.currentUserId;
    if (teacherId == null) return; // ✅ Guard against null
    
    await Supabase.instance.client
        .from('enrollments')
        .delete()
        .eq('student_id', studentId)
        .eq('teacher_id', teacherId); // ✅ Now non-null
    
    _loadStudents();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$studentName removed completely'), backgroundColor: Colors.red),
      );
    }
  }
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)],
        ),
      ),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 130,
            floating: false,
            pinned: true,
            backgroundColor: Colors.transparent,
            leading: const BackButton(color: Colors.white),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)],
                ),
              ),
              child: FlexibleSpaceBar(
                title: const Text('My Students',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                centerTitle: false,
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Overall stats
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10)],
                  ),
                  child: Row(
                    children: [
                      _StatBadge(label: 'Total Students', count: _totalStudents, color: const Color(0xFF1A237E)),
                      const SizedBox(width: 12),
                      _StatBadge(label: 'Paid', count: _totalPaid, color: const Color(0xFF4CAF50)),
                      const SizedBox(width: 12),
                      _StatBadge(label: 'Unpaid', count: _totalStudents - _totalPaid, color: Colors.orange),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Per-subject stats
                if (_subjectStats.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('By Subject',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _subjectStats.entries.map((entry) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${entry.key}: ${entry.value} students',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                // Student list
                if (_isLoading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFF1A237E)),
                  ))
                else if (_groupedStudents.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('No students yet', style: TextStyle(color: Colors.grey)),
                  ))
                else
                  ..._groupedStudents.map((student) {
                    final profile = student['profile'] as Map<String, dynamic>;
                    final subjects = student['subjects'] as List<Map<String, dynamic>>;
                    final isPaidOverall = student['isPaid'] as bool;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Student header
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                                child: Text(
                                  (profile['full_name'] as String? ?? 'S')[0].toUpperCase(),
                                  style: const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(profile['full_name'] ?? 'Student',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    Text(profile['email'] ?? '',
                                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isPaidOverall
                                      ? const Color(0xFF4CAF50).withOpacity(0.1)
                                      : Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isPaidOverall ? 'Paid ✅' : 'Unpaid',
                                  style: TextStyle(
                                    color: isPaidOverall ? const Color(0xFF4CAF50) : Colors.orange,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Analytics
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const StudentPerformanceScreen()),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A237E).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.analytics_outlined, size: 18, color: Color(0xFF1A237E)),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // More menu
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                                ),
                                onSelected: (action) {
                                  if (action == 'remove_all') {
                                    _removeStudentCompletely(
                                      student['student_id'] as String,
                                      profile['full_name'] ?? 'Student',
                                    );
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'remove_all',
                                    child: Row(children: [
                                      Icon(Icons.remove_circle_outline, size: 18, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Remove from all subjects', style: TextStyle(color: Colors.red)),
                                    ]),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),

                          // Subjects list with actions
                        // Subjects list - Simplified (no manual paid/unpaid buttons)
Wrap(
  spacing: 6,
  runSpacing: 6,
  children: subjects.map((sub) {
    final subjectName = sub['subject_name'] as String;
    final subjectStatus = sub['status'] as String;
    final enrollmentId = sub['enrollment_id'] as String;
    final color = Color(int.parse('FF${(sub['subject_color'] as String).replaceAll('#', '')}', radix: 16));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Subject color dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          // Subject name
          Expanded(
            child: Text(
              subjectName,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ),
          const SizedBox(width: 8),
          // Status badge (read-only)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: subjectStatus == 'paid'
                  ? const Color(0xFF4CAF50).withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  subjectStatus == 'paid' ? Icons.check_circle : Icons.pending,
                  size: 12,
                  color: subjectStatus == 'paid' ? const Color(0xFF4CAF50) : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  subjectStatus == 'paid' ? 'Paid' : 'Pending',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: subjectStatus == 'paid' ? const Color(0xFF4CAF50) : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Remove button only
          Tooltip(
            message: 'Remove from $subjectName',
            child: GestureDetector(
              onTap: () => _removeStudent(enrollmentId, profile['full_name'] ?? 'Student', subjectName),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }).toList(),
),
                        ],
                      ),
                    );
                  }),
              ]),
            ),
          ),
        ],
      ),
    ),
  );
}
}

class _StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatBadge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}