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

      // ✅ Load with level info
      final response = await Supabase.instance.client
          .from('enrollments')
          .select('id, status, level_id, approved_at, student_id, subject_id, subjects(name, color_hex), levels(name)')
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

      // ✅ Group by level → student
      final Map<String, Map<String, dynamic>> levelGroups = {};
      int totalStudents = 0;
      int totalPaid = 0;
      final allStudentIds = <String>{};

      for (final row in response) {
        final levelData = row['levels'] as Map<String, dynamic>?;
        final levelName = levelData?['name'] as String? ?? 'Unknown Level';
        final levelId = row['level_id'] as String? ?? 'unknown';
        final studentId = row['student_id'] as String;
        final status = row['status'] as String;
        final subject = row['subjects'] as Map<String, dynamic>?;

        allStudentIds.add(studentId);

        if (!levelGroups.containsKey(levelId)) {
          levelGroups[levelId] = {
            'level_id': levelId,
            'level_name': levelName,
            'students': <String, Map<String, dynamic>>{},
            'subject_counts': <String, int>{},
          };
        }

        final students = levelGroups[levelId]!['students'] as Map<String, Map<String, dynamic>>;
        final subjectCounts = levelGroups[levelId]!['subject_counts'] as Map<String, int>;

        if (!students.containsKey(studentId)) {
          students[studentId] = {
            'student_id': studentId,
            'profile': profiles[studentId] ?? {'full_name': 'Unknown Student'},
            'subjects': <Map<String, dynamic>>[],
            'isPaid': false,
          };
        }

        students[studentId]!['subjects'].add({
          'enrollment_id': row['id'],
          'subject_name': subject?['name'] ?? 'Unknown',
          'subject_color': subject?['color_hex'] ?? '#1A237E',
          'status': status,
        });

        // Track subject counts per level
        final subjectName = subject?['name'] ?? 'Unknown';
        subjectCounts[subjectName] = (subjectCounts[subjectName] ?? 0) + 1;

        if (status == 'paid') {
          students[studentId]!['isPaid'] = true;
        }
      }

      totalStudents = allStudentIds.length;
      for (final level in levelGroups.values) {
        final students = level['students'] as Map<String, Map<String, dynamic>>;
        totalPaid += students.values.where((s) => s['isPaid'] == true).length;
      }

      // Convert to sorted list
      final groupedStudents = levelGroups.values.map((level) {
        final students = (level['students'] as Map<String, Map<String, dynamic>>).values.toList();
        final subjectCounts = level['subject_counts'] as Map<String, int>;
        return {
          'level_name': level['level_name'],
          'students': students,
          'subject_counts': subjectCounts,
        };
      }).toList()
        ..sort((a, b) => (a['level_name'] as String).compareTo(b['level_name'] as String));

      if (mounted) {
        setState(() {
          _groupedStudents = groupedStudents;
          _totalStudents = totalStudents;
          _totalPaid = totalPaid;
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

Color _getLevelColor(String level) {
  switch (level) {
    case 'Form 1': return Colors.blue;
    case 'Form 2': return Colors.teal;
    case 'O-Level': return const Color(0xFFFF9800);
    case 'A-Level': return Colors.purple;
    default: return const Color(0xFF1A237E);
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

                // Student list grouped by level
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
                  ..._groupedStudents.map((levelGroup) {
                    final levelName = levelGroup['level_name'] as String;
                    final students = levelGroup['students'] as List<Map<String, dynamic>>;
                    final subjectCounts = levelGroup['subject_counts'] as Map<String, int>;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Level header card
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _getLevelColor(levelName).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _getLevelColor(levelName).withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 4, height: 20,
                                    decoration: BoxDecoration(
                                      color: _getLevelColor(levelName),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(levelName,
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getLevelColor(levelName))),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getLevelColor(levelName).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text('${students.length} students',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _getLevelColor(levelName))),
                                  ),
                                ],
                              ),
                              if (subjectCounts.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: subjectCounts.entries.map((entry) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Text('${entry.key}: ${entry.value}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Student cards under this level
                        ...students.map((student) {
                          final profile = student['profile'] as Map<String, dynamic>;
                          final subjects = student['subjects'] as List<Map<String, dynamic>>;
                          final isPaidOverall = student['isPaid'] as bool;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10, left: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.04), blurRadius: 6)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                                      child: Text((profile['full_name'] as String? ?? 'S')[0].toUpperCase(),
                                          style: const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(profile['full_name'] ?? 'Student', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          Text(profile['email'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isPaidOverall ? const Color(0xFF4CAF50).withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(isPaidOverall ? 'Paid' : 'Unpaid',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                              color: isPaidOverall ? const Color(0xFF4CAF50) : Colors.orange)),
                                    ),
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                                      onSelected: (action) {
                                        if (action == 'remove_all') {
                                          _removeStudentCompletely(student['student_id'] as String, profile['full_name'] ?? 'Student');
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(
                                          value: 'remove_all',
                                          child: Row(children: [
                                            Icon(Icons.remove_circle_outline, size: 16, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Remove completely', style: TextStyle(color: Colors.red, fontSize: 13)),
                                          ]),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: subjects.map((sub) {
                                    final subjectName = sub['subject_name'] as String;
                                    final subjectStatus = sub['status'] as String;
                                    final enrollmentId = sub['enrollment_id'] as String;
                                    final color = Color(int.parse('FF${(sub['subject_color'] as String).replaceAll('#', '')}', radix: 16));

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: color.withOpacity(0.2)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                          const SizedBox(width: 6),
                                          Text(subjectName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
                                          const SizedBox(width: 6),
                                          Text(subjectStatus == 'paid' ? 'Paid' : 'Pending',
                                              style: TextStyle(fontSize: 10, color: subjectStatus == 'paid' ? const Color(0xFF4CAF50) : Colors.grey)),
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            onTap: () => _removeStudent(enrollmentId, profile['full_name'] ?? 'Student', subjectName),
                                            child: const Icon(Icons.close, size: 14, color: Colors.red),
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
                        const SizedBox(height: 16),
                      ],
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