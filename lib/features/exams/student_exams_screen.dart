import 'package:flutter/material.dart';
import '../../core/exam_service.dart';
import '../../core/auth_service.dart';
import '../payment/payment_screen.dart';
import 'exam_taker_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentExamsScreen extends StatefulWidget {
  const StudentExamsScreen({super.key});

  @override
  State<StudentExamsScreen> createState() => _StudentExamsScreenState();
}

class _StudentExamsScreenState extends State<StudentExamsScreen> {
  final ExamService _examService = ExamService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _availableExams = [];
  List<Map<String, dynamic>> _completedAttempts = [];
  Map<String, Map<String, dynamic>> _enrollments = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get enrollments with full trial + subscription info
      final enrollments = await Supabase.instance.client
          .from('enrollments')
          .select('id, teacher_id, subject_id, status, trial_ends_at, is_subscribed, subscription_expires_at, profiles!teacher_id(full_name), subjects(name)')
          .eq('student_id', userId)
          .inFilter('status', ['approved', 'paid']);

      final enrollmentMap = <String, Map<String, dynamic>>{};
      final teacherIds = <String>{};

      for (final e in enrollments) {
        final teacherId = e['teacher_id'] as String;
        teacherIds.add(teacherId);
        enrollmentMap[teacherId] = e;
      }

      // Get exams from enrolled teachers only
   List<Map<String, dynamic>> allExams = [];
if (teacherIds.isNotEmpty) {
  String? studentLevelId;
  if (userId != null) {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('level_id')
        .eq('id', userId)
        .maybeSingle();
    studentLevelId = profile?['level_id'] as String?;
  }

  final response = await Supabase.instance.client
      .from('exams')
      .select('*, teacher_topics(subject_id, subjects(name)), profiles!creator_id(display_name, full_name), levels(name)')
      .eq('is_published', true)
      .eq('level_id', studentLevelId ?? '')
      .inFilter('creator_id', teacherIds.toList())
      .order('created_at', ascending: false);

  allExams = List<Map<String, dynamic>>.from(response);
}
      // Get completed attempts
      List<Map<String, dynamic>> attempts = [];
      attempts = await Supabase.instance.client
          .from('exam_attempts')
          .select('exam_id, score, total_marks, percentage, completed_at, exams(title)')
          .eq('student_id', userId)
          .not('completed_at', 'is', null);

      final completedExamIds = attempts.map((a) => a['exam_id']).toSet();

      if (mounted) {
        setState(() {
          _availableExams = allExams
              .where((e) => !completedExamIds.contains(e['id']))
              .toList();
          _completedAttempts = attempts;
          _enrollments = enrollmentMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ Priority-based access check
  bool _canAccess(String teacherId) {
    final enrollment = _enrollments[teacherId];
    if (enrollment == null) return false;

    // Priority 1: Active subscription
    if (enrollment['is_subscribed'] == true) {
      final expiresAt = enrollment['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        if (expiry.isAfter(DateTime.now())) return true;
      }
    }

    // Priority 2: Active trial
    if (enrollment['is_subscribed'] != true) {
      final trialEndsAt = enrollment['trial_ends_at'] as String?;
      if (trialEndsAt != null) {
        final trialEnd = DateTime.parse(trialEndsAt);
        return DateTime.now().isBefore(trialEnd);
      }
    }

    return false;
  }

  // ✅ Priority-based status text
  String _getStatusText(String teacherId) {
    final enrollment = _enrollments[teacherId];
    if (enrollment == null) return '';

    // Priority 1: Subscription
    if (enrollment['is_subscribed'] == true) {
      final expiresAt = enrollment['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        final daysLeft = expiry.difference(DateTime.now()).inDays;
        if (daysLeft <= 0) return 'Subscription Ended';
        if (daysLeft <= 3) return 'Subscribed — $daysLeft days left ⚠️';
        return 'Subscribed ✅';
      }
    }

    // Priority 2: Trial
    final trialEndsAt = enrollment['trial_ends_at'] as String?;
    if (trialEndsAt != null) {
      final trialEnd = DateTime.parse(trialEndsAt);
      final daysLeft = trialEnd.difference(DateTime.now()).inDays;
      if (daysLeft <= 0) return 'Trial Ended';
      if (daysLeft <= 3) return '$daysLeft days left ⚠️';
      return '$daysLeft days free';
    }

    return '';
  }

  Color _getStatusColor(String status) {
    if (status.contains('Ended')) return Colors.red;
    if (status.contains('⚠️')) return Colors.orange;
    if (status.contains('Subscribed')) return const Color(0xFF4CAF50);
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCQ Exams'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Exams',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                  ),
                  const SizedBox(height: 12),
                  if (_availableExams.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          children: [
                            Icon(Icons.quiz_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('No exams available yet', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._availableExams.map((exam) {
                      final creatorId = exam['creator_id'] as String? ?? '';
                      final canAccess = _canAccess(creatorId);
                      final statusText = _getStatusText(creatorId);
                      final statusColor = _getStatusColor(statusText);
                      final creatorName = exam['profiles']?['display_name'] ?? exam['profiles']?['full_name'] ?? 'Teacher';
                      final subjectName = exam['teacher_topics']?['subjects']?['name'] ?? '';
                      final isExpired = statusText.contains('Ended');
                      final isSubscriptionExpired = statusText == 'Subscription Ended';

                      return _ExamCard(
                        title: exam['title'] ?? 'Untitled',
                        subject: subjectName,
                        teacherName: creatorName,
                        duration: exam['duration_minutes'] != null
                            ? '${exam['duration_minutes']} min'
                            : 'No limit',
                        totalMarks: '${exam['total_marks'] ?? 0} pts',
                        statusText: statusText,
                        statusColor: statusColor,
                        canAccess: canAccess,
                        isExpired: isExpired,
                        isSubscriptionExpired: isSubscriptionExpired,
                        onTap: canAccess
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ExamTakerScreen(exam: exam),
                                  ),
                                ).then((_) => _loadData());
                              }
                            : null,
                        onSubscribe: isExpired
                            ? () {
                                final enrollment = _enrollments[creatorId];
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentScreen(
                                      teacherId: creatorId,
                                      teacherName: creatorName,
                                      subjectName: subjectName,
                                      enrollmentId: enrollment?['id'] as String? ?? '',
                                    ),
                                  ),
                                ).then((_) => _loadData());
                              }
                            : null,
                      );
                    }),
                  const SizedBox(height: 24),

                  if (_completedAttempts.isNotEmpty) ...[
                    const Text(
                      'Completed',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                    ),
                    const SizedBox(height: 12),
                    ..._completedAttempts.map((attempt) {
                      final percentage = (attempt['percentage'] as num?)?.toStringAsFixed(0) ?? '0';
                      final examTitle = attempt['exams']?['title'] ?? 'Exam';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: (attempt['percentage'] ?? 0) >= 50
                                ? const Color(0xFF4CAF50)
                                : Colors.red,
                            child: Text('$percentage%',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(examTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Score: ${attempt['score']}/${attempt['total_marks']}'),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  final String title;
  final String subject;
  final String teacherName;
  final String duration;
  final String totalMarks;
  final String statusText;
  final Color statusColor;
  final bool canAccess;
  final bool isExpired;
  final bool isSubscriptionExpired;
  final VoidCallback? onTap;
  final VoidCallback? onSubscribe;

  const _ExamCard({
    required this.title,
    required this.subject,
    required this.teacherName,
    required this.duration,
    required this.totalMarks,
    required this.statusText,
    required this.statusColor,
    required this.canAccess,
    required this.isExpired,
    required this.isSubscriptionExpired,
    this.onTap,
    this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: canAccess ? const Color(0xFFFF9800).withOpacity(0.1) : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            canAccess ? Icons.quiz : Icons.lock_outline,
            color: canAccess ? const Color(0xFFFF9800) : Colors.grey,
          ),
        ),
        title: Text(title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: canAccess ? const Color(0xFF1A237E) : Colors.grey,
            )),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('$subject • $teacherName',
                style: TextStyle(fontSize: 12, color: canAccess ? Colors.grey : Colors.grey.shade400)),
            const SizedBox(height: 2),
            Text('$duration • $totalMarks',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (statusText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(statusText,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
              ),
            ],
          ],
        ),
        trailing: isExpired
            ? GestureDetector(
                onTap: onSubscribe,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A237E), Color(0xFF283593)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isSubscriptionExpired ? 'Renew' : 'Subscribe',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            : canAccess
                ? const Icon(Icons.play_arrow, color: Color(0xFFFF9800))
                : const Icon(Icons.lock, color: Colors.grey, size: 20),
        onTap: onTap,
      ),
    );
  }
}