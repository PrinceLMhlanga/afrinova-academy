import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../payment/payment_screen.dart';
import 'teachers_by_subject_screen.dart';
import 'teacher_content_screen.dart';

class MySubjectsScreen extends StatefulWidget {
  const MySubjectsScreen({super.key});

  @override
  State<MySubjectsScreen> createState() => _MySubjectsScreenState();
}

class _MySubjectsScreenState extends State<MySubjectsScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _mySubjects = [];
  bool _isLoading = true;

  List<Map<String, dynamic>> _selfStudySubjects = [];

  @override
  void initState() {
    super.initState();
    _loadMySubjects();
  }

  Future<void> _loadMySubjects() async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    // Get enrollments with full trial + subscription info
    final response = await Supabase.instance.client
        .from('enrollments')
        .select('id, subject_id, level_id, teacher_id, status, trial_started_at, trial_ends_at, is_subscribed, subscription_expires_at, subjects(id, name, description, color_hex, icon_name)')
        .eq('student_id', userId)
        .inFilter('status', ['paid', 'approved']);

    for (final enrollment in response) {
      await Supabase.instance.client
          .from('student_subjects')
          .upsert({
            'student_id': userId,
            'subject_id': enrollment['subject_id'],
            'source': 'enrollment',
            'enrollment_id': enrollment['id'],
          }, onConflict: 'student_id, subject_id');
    }   

    // Get teacher profiles
    final teacherIds = response.map((e) => e['teacher_id'] as String).toSet().toList();
    Map<String, Map<String, dynamic>> teacherProfiles = {};
    if (teacherIds.isNotEmpty) {
      final profilesResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, display_name, avatar_url')
          .inFilter('id', teacherIds);
      for (final p in profilesResponse) {
        teacherProfiles[p['id'] as String] = p;
      }
    }

    // Group by subject
    final subjectMap = <String, Map<String, dynamic>>{};
    for (final enrollment in response) {
      final subject = enrollment['subjects'] as Map<String, dynamic>;
      final subjectId = enrollment['subject_id'] as String;
      final teacherId = enrollment['teacher_id'] as String;

      if (!subjectMap.containsKey(subjectId)) {
        subjectMap[subjectId] = {
          'subject': subject,
          'teachers': <Map<String, dynamic>>[],
        };
      }
      (subjectMap[subjectId]!['teachers'] as List).add({
        'teacher_id': teacherId,
        'profile': teacherProfiles[teacherId] ?? {'display_name': 'Teacher'},
        'enrollment_id': enrollment['id'],
        'status': enrollment['status'],
        'is_subscribed': enrollment['is_subscribed'] ?? false,
        'subscription_expires_at': enrollment['subscription_expires_at'],
        'trial_ends_at': enrollment['trial_ends_at'],
        'level_id': enrollment['level_id'],
        'subject_id': enrollment['subject_id'],
      });
    }

    final selfSubjects = await Supabase.instance.client
        .from('student_subjects')
        .select('id, subject_id, subjects(id, name, description, color_hex, icon_name)')
        .eq('student_id', userId)
        .eq('source', 'manual');

    if (mounted) {
      setState(() {
        _mySubjects = subjectMap.values.toList();
        _selfStudySubjects = List<Map<String, dynamic>>.from(selfSubjects);
        _isLoading = false;
      });
    }
  } catch (e) {
    debugPrint('Error loading subjects: $e');
    if (mounted) setState(() => _isLoading = false);
  }
}

Future<void> _addSelfStudySubject() async {
  final userId = _authService.currentUserId;
  if (userId == null) return;

  // Show dialog to select subject
  final allSubjects = await Supabase.instance.client
      .from('subjects')
      .select()
      .eq('is_active', true)
      .order('name');

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final selectedIds = _selfStudySubjects
            .map((s) => s['subject_id'] as String)
            .toSet();
        
        return AlertDialog(
          title: const Text('Add Subjects You Study'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allSubjects.length,
              itemBuilder: (context, index) {
                final subject = allSubjects[index];
                final subjectId = subject['id'] as String;
                final isAlreadyEnrolled = _mySubjects.any(
                  (s) => (s['subject'] as Map)['id'] == subjectId
                );
                final isSelfStudy = selectedIds.contains(subjectId);

                return CheckboxListTile(
                  value: isSelfStudy,
                  enabled: !isAlreadyEnrolled,
                  onChanged: isAlreadyEnrolled ? null : (v) async {
                    if (v == true) {
                      await Supabase.instance.client
                          .from('student_subjects')
                          .insert({
                            'student_id': userId,
                            'subject_id': subjectId,
                            'source': 'manual',
                          });
                    } else {
                      await Supabase.instance.client
                          .from('student_subjects')
                          .delete()
                          .eq('student_id', userId)
                          .eq('subject_id', subjectId);
                    }
                    _loadMySubjects();
                    Navigator.pop(ctx);
                  },
                  title: Text(
                    subject['name'] ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: isAlreadyEnrolled ? Colors.grey : null,
                    ),
                  ),
                  subtitle: isAlreadyEnrolled
                      ? const Text('Already enrolled with a teacher', style: TextStyle(fontSize: 11))
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}

  // ✅ Full access check — trial + subscription
  bool _canAccess(Map<String, dynamic> teacher) {
    if (teacher['is_subscribed'] == true) {
      final expiresAt = teacher['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        if (expiry.isAfter(DateTime.now())) return true;
      }
    }

    final trialEndsAt = teacher['trial_ends_at'] as String?;
    if (trialEndsAt != null) {
      final trialEnd = DateTime.parse(trialEndsAt);
      return DateTime.now().isBefore(trialEnd);
    }

    return false;
  }

  // ✅ Status badge text
  String _getStatusText(Map<String, dynamic> teacher) {
    if (teacher['is_subscribed'] == true) {
      final expiresAt = teacher['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        final daysLeft = expiry.difference(DateTime.now()).inDays;
        if (daysLeft <= 0) return 'Subscription Ended';
        if (daysLeft <= 3) return 'Subscribed — $daysLeft days left ⚠️';
        return 'Subscribed ✅';
      }
    }

    final trialEndsAt = teacher['trial_ends_at'] as String?;
    if (trialEndsAt != null) {
      final trialEnd = DateTime.parse(trialEndsAt);
      final daysLeft = trialEnd.difference(DateTime.now()).inDays;
      if (daysLeft <= 0) return 'Trial Ended';
      if (daysLeft <= 3) return '$daysLeft days left ⚠️';
      return '$daysLeft days free';
    }

    return '';
  }

  // ✅ Status color
  Color _getStatusColor(String status) {
    if (status.contains('Ended')) return Colors.red;
    if (status.contains('⚠️')) return Colors.orange;
    if (status.contains('Subscribed')) return const Color(0xFF4CAF50);
    return Colors.green;
  }

  Color _getSubjectColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return const Color(0xFF1A237E);
    final hex = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: const Text('My Subjects'),
  backgroundColor: const Color(0xFF1A237E),
  foregroundColor: Colors.white,
  actions: [
    IconButton(
      icon: const Icon(Icons.add),
      tooltip: 'Add Subject',
      onPressed: _addSelfStudySubject, // ✅ Now opens subject selector
    ),
  ],
),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _mySubjects.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadMySubjects,
                  color: const Color(0xFFFF9800),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _mySubjects.length + (_selfStudySubjects.isNotEmpty ? 1 : 0), // +1 for self-study card
                    itemBuilder: (context, index) {
                      if (_selfStudySubjects.isNotEmpty && index == 0) {
                  return _buildSelfStudyCard();
                }
                      final subjectIndex = _selfStudySubjects.isNotEmpty ? index - 1 : index;
                final data = _mySubjects[subjectIndex];
                      final subject = data['subject'] as Map<String, dynamic>;
                      final teachers = data['teachers'] as List<Map<String, dynamic>>;
                      final color = _getSubjectColor(subject['color_hex'] as String?);
                      final icon = _getSubjectIcon(subject['icon_name'] as String?);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.05),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(icon, color: color, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(subject['name'] ?? '',
                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                                        Text('${teachers.length} teacher(s)',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...teachers.map((teacher) {
                              final profile = teacher['profile'] as Map<String, dynamic>;
                              final canAccess = _canAccess(teacher);
                              final statusText = _getStatusText(teacher);
                              final statusColor = _getStatusColor(statusText);
                              final teacherName = profile['display_name'] ?? profile['full_name'] ?? 'Teacher';
                              final isExpired = statusText.contains('Ended');

                              return Container(
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 0.5)),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: canAccess ? color.withOpacity(0.1) : Colors.grey.shade200,
                                    child: Icon(Icons.person, color: canAccess ? color : Colors.grey, size: 18),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(teacherName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: canAccess ? Colors.black87 : Colors.grey,
                                            )),
                                      ),
                                      if (statusText.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(statusText,
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: isExpired
                                      ? GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PaymentScreen(
                                                  teacherId: teacher['teacher_id'] as String,
                                                  teacherName: teacherName,
                                                  subjectName: subject['name'] ?? '',
                                                  enrollmentId: teacher['enrollment_id'] as String,
                                                  subjectId: teacher['subject_id'] as String?,   // ✅ Pass
                                                  levelId: teacher['level_id'] as String?,       // ✅ Pass
                                                  
                                                ),
                                              ),
                                            ).then((_) => _loadMySubjects());
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF1A237E), Color(0xFF283593)],
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              statusText.contains('Subscription') ? 'Renew' : 'Subscribe',
                                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        )
                                      : canAccess
                                          ? Icon(Icons.chevron_right, color: color)
                                          : const Icon(Icons.lock, color: Colors.grey, size: 20),
                                  onTap: canAccess
                                      ? () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TeacherContentScreen(
                                                teacherId: teacher['teacher_id'] as String,
                                                teacherName: teacherName,
                                                subjectName: subject['name'] ?? '',
                                                subjectColor: color,
                                                subjectId: teacher['subject_id'] as String,   // ✅ Pass
                                              ),
                                            ),
                                          );
                                        }
                                      : null,
                                ),
                                
                              );
                              
                            }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                
    );
  }

 Widget _buildSelfStudyCard() {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.teal.withOpacity(0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.teal.withOpacity(0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.self_improvement, color: Colors.teal, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('My Subjects',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addSelfStudySubject,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ✅ Enhanced subject cards
        ..._selfStudySubjects.map((s) {
          final subject = s['subjects'] as Map<String, dynamic>?;
          final subjectId = s['subject_id'] as String;
          final subjectName = subject?['name'] ?? 'Subject';
          final color = _getSubjectColor(subject?['color_hex'] as String?);
          final icon = _getSubjectIcon(subject?['icon_name'] as String?);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subjectName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('Self-study • No teacher yet',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                // Browse Teachers button
                // Browse Teachers button
TextButton.icon(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeachersBySubjectScreen(
          subjectId: subjectId,
          subjectName: subjectName,
          subjectColor: color,
        ),
      ),
    ).then((_) => _loadMySubjects()); // Reload after enrollment
  },
  icon: const Icon(Icons.search, size: 16),
  label: const Text('Find Teacher', style: TextStyle(fontSize: 12)),
  style: TextButton.styleFrom(
    foregroundColor: color,
    padding: const EdgeInsets.symmetric(horizontal: 8),
  ),
),
                // Remove button
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('student_subjects')
                        .delete()
                        .eq('id', s['id']);
                    _loadMySubjects();
                  },
                ),
              ],
            ),
          );
        }),
        if (_selfStudySubjects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton.icon(
                onPressed: _addSelfStudySubject,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add subjects you study',
                    style: TextStyle(fontSize: 12, color: Colors.teal)),
              ),
            ),
          ),
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
            width: 120, height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.school, size: 56, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 24),
          const Text('No subjects yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 8),
          const Text('Add the subjects you study to get started\nwith personalized learning',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: _addSelfStudySubject, // ✅ Directly add subjects
              icon: const Icon(Icons.add),
              label: const Text('Add Your Subjects'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}