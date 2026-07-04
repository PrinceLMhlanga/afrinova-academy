import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';

class EnrollmentRequestsScreen extends StatefulWidget {
  const EnrollmentRequestsScreen({super.key});

  @override
  State<EnrollmentRequestsScreen> createState() => _EnrollmentRequestsScreenState();
}

class _EnrollmentRequestsScreenState extends State<EnrollmentRequestsScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _groupedRequests = [];
  int _totalPending = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('enrollments')
          .select('id, status, student_id, subject_id, subjects(name, color_hex), profiles!student_id(full_name, email)')
          .eq('teacher_id', userId)
          .eq('status', 'pending')
          .order('requested_at', ascending: false);

      // Group by student_id
      final Map<String, Map<String, dynamic>> grouped = {};
      for (final row in response) {
        final studentId = row['student_id'] as String;
        final profile = row['profiles'] as Map<String, dynamic>?;
        final subject = row['subjects'] as Map<String, dynamic>?;

        if (!grouped.containsKey(studentId)) {
          grouped[studentId] = {
            'student_id': studentId,
            'profile': profile ?? {'full_name': 'Unknown Student', 'email': ''},
            'requests': <Map<String, dynamic>>[],
          };
        }

        grouped[studentId]!['requests'].add({
          'enrollment_id': row['id'],
          'subject_name': subject?['name'] ?? 'Unknown',
          'subject_color': subject?['color_hex'] ?? '#1A237E',
        });
      }

      final allRequests = grouped.values.toList();
      _totalPending = allRequests.fold(0, (sum, s) => sum + (s['requests'] as List).length);

      if (mounted) {
        setState(() {
          _groupedRequests = allRequests;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveAll(Map<String, dynamic> student) async {
  final requests = student['requests'] as List<Map<String, dynamic>>;
  for (final req in requests) {
    await Supabase.instance.client.from('enrollments').update({
      'status': 'approved',
      'trial_started_at': DateTime.now().toIso8601String(),
      'trial_ends_at': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', req['enrollment_id']);
  }
  _loadRequests();
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${student['profile']['full_name']} approved for ${requests.length} subject(s). 5-day trial started! ✅'),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
  }
}

  Future<void> _rejectAll(Map<String, dynamic> student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject All?'),
        content: Text('Reject all requests from ${student['profile']['full_name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Reject')),
        ],
      ),
    );
    if (confirm != true) return;

    final requests = student['requests'] as List<Map<String, dynamic>>;
    for (final req in requests) {
      await Supabase.instance.client.from('enrollments').update({
        'status': 'rejected',
      }).eq('id', req['enrollment_id']);
    }
    _loadRequests();
  }

  Future<void> _approveSingle(String enrollmentId, String subjectName) async {
  await Supabase.instance.client.from('enrollments').update({
    'status': 'approved',
    'trial_started_at': DateTime.now().toIso8601String(),
    'trial_ends_at': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
    'approved_at': DateTime.now().toIso8601String(),
  }).eq('id', enrollmentId);
  _loadRequests();
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$subjectName approved! 5-day trial started ✅'),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
  }
}

  Future<void> _rejectSingle(String enrollmentId, String subjectName) async {
    await Supabase.instance.client.from('enrollments').update({
      'status': 'rejected',
    }).eq('id', enrollmentId);
    _loadRequests();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$subjectName rejected'), backgroundColor: Colors.red),
      );
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
              expandedHeight: 120,
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
                  title: Row(
                    children: [
                      const Text('Enrollment Requests',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(width: 8),
                      if (_totalPending > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$_totalPending',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                    ],
                  ),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(60),
                      child: CircularProgressIndicator(color: Color(0xFF1A237E)),
                    ))
                  else if (_groupedRequests.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(60),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text('No pending requests', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._groupedRequests.map((student) {
                      final profile = student['profile'] as Map<String, dynamic>;
                      final requests = student['requests'] as List<Map<String, dynamic>>;

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
                                // Approve All
                                GestureDetector(
                                  onTap: () => _approveAll(student),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4CAF50).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 22),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Reject All
                                GestureDetector(
                                  onTap: () => _rejectAll(student),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.cancel, color: Colors.red, size: 22),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 8),

                            // Subject requests
                            ...requests.map((req) {
                              final subjectName = req['subject_name'] as String;
                              final color = Color(int.parse('FF${(req['subject_color'] as String).replaceAll('#', '')}', radix: 16));

                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: color.withOpacity(0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(subjectName,
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
                                    ),
                                    GestureDetector(
                                      onTap: () => _approveSingle(req['enrollment_id'] as String, subjectName),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4CAF50).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.check, color: Color(0xFF4CAF50), size: 16),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => _rejectSingle(req['enrollment_id'] as String, subjectName),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.close, color: Colors.red, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
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