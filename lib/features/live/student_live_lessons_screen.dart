import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/live_lesson_service.dart';
import '../../core/auth_service.dart';
import '../payment/payment_screen.dart';

class StudentLiveLessonsScreen extends StatefulWidget {
  const StudentLiveLessonsScreen({super.key});

  @override
  State<StudentLiveLessonsScreen> createState() => _StudentLiveLessonsScreenState();
}

class _StudentLiveLessonsScreenState extends State<StudentLiveLessonsScreen> {
  final LiveLessonService _liveService = LiveLessonService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _lessons = [];
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

      // Get enrollments with trial + subscription info
      final enrollments = await Supabase.instance.client
          .from('enrollments')
          .select('id, teacher_id, subject_id, status, trial_ends_at, is_subscribed, subscription_expires_at')
          .eq('student_id', userId)
          .inFilter('status', ['approved', 'paid']);

      final enrollmentMap = <String, Map<String, dynamic>>{};
      final teacherIds = <String>{};
      for (final e in enrollments) {
        final teacherId = e['teacher_id'] as String;
        teacherIds.add(teacherId);
        enrollmentMap[teacherId] = e;
      }

      // Get live lessons only from enrolled teachers
      List<Map<String, dynamic>> lessons = [];
      if (teacherIds.isNotEmpty) {
        lessons = await _liveService.getStudentLiveLessons(userId);
        // Filter to only enrolled teachers
        lessons = lessons.where((l) => teacherIds.contains(l['teacher_id'] as String)).toList();
      }

      if (mounted) {
        setState(() {
          _lessons = lessons;
          _enrollments = enrollmentMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ Access check
  bool _canAccess(Map<String, dynamic> lesson) {
    final teacherId = lesson['teacher_id'] as String?;
    if (teacherId == null) return false;

    final enrollment = _enrollments[teacherId];
    if (enrollment == null) return false;

    if (enrollment['is_subscribed'] == true) {
      final expiresAt = enrollment['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        if (expiry.isAfter(DateTime.now())) return true;
      }
    }

    if (enrollment['is_subscribed'] != true) {
      final trialEndsAt = enrollment['trial_ends_at'] as String?;
      if (trialEndsAt != null) {
        final trialEnd = DateTime.parse(trialEndsAt);
        return DateTime.now().isBefore(trialEnd);
      }
    }

    return false;
  }

  // ✅ Status text
  String _getStatusText(Map<String, dynamic> lesson) {
    final teacherId = lesson['teacher_id'] as String?;
    if (teacherId == null) return '';

    final enrollment = _enrollments[teacherId];
    if (enrollment == null) return '';

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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  String _formatScheduledTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = date.difference(now);
      if (diff.inMinutes < 0) return 'Started ${-diff.inMinutes}m ago';
      if (diff.inMinutes < 60) return 'Starts in ${diff.inMinutes}min';
      if (diff.inHours < 24) return 'Today at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      if (diff.inDays < 2) return 'Tomorrow at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      return '${date.day}/${date.month} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  Future<void> _joinLesson(Map<String, dynamic> lesson) async {
    final profile = await _authService.getProfile();
    final studentName = profile?['full_name'] ?? "Student";
    await _liveService.joinLesson(
      context: context,
      roomName: lesson['room_id'] as String,
      userName: studentName,
      lessonId: lesson['id'] as String,
      isTeacher: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveLessons = _lessons.where((l) => l['status'] == 'live').toList();
    final upcomingLessons = _lessons.where((l) => l['status'] == 'scheduled').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Lessons'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : _lessons.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 100, height: 100,
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.live_tv, size: 48, color: Colors.red),
                      ),
                      const SizedBox(height: 20),
                      const Text('No live lessons', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                      const SizedBox(height: 8),
                      const Text('Live lessons from your teachers\nwill appear here', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (liveLessons.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(children: [
                            Icon(Icons.circle, color: Colors.red, size: 12),
                            SizedBox(width: 6),
                            Text('LIVE NOW', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                          ]),
                        ),
                        ...liveLessons.map((lesson) => _buildLessonCard(lesson, isLive: true)),
                        const SizedBox(height: 20),
                      ],
                      if (upcomingLessons.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('UPCOMING', style: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        ...upcomingLessons.map((lesson) => _buildLessonCard(lesson, isLive: false)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildLessonCard(Map<String, dynamic> lesson, {required bool isLive}) {
    final canAccess = _canAccess(lesson);
    final statusText = _getStatusText(lesson);
    final statusColor = _getStatusColor(statusText);
    final isExpired = statusText.contains('Ended');
    final isSubscriptionExpired = statusText == 'Subscription Ended';
    final teacherName = lesson['profiles']?['full_name'] ?? 'Teacher';
    final teacherId = lesson['teacher_id'] as String? ?? '';
    final subjectName = lesson['subjects']?['name'] ?? '';
    final enrollment = _enrollments[teacherId];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isLive ? Border.all(color: Colors.red.shade300, width: 2) : null,
        boxShadow: [BoxShadow(
          color: isLive ? Colors.red.withOpacity(0.1) : Colors.black.withOpacity(0.04),
          blurRadius: 12, offset: const Offset(0, 3),
        )],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (isLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle, color: Colors.white, size: 8), SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ]),
                ),
              if (isLive) const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(lesson['topic'] ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                  if (!isLive && lesson['scheduled_at'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const Icon(Icons.access_time, size: 14, color: Color(0xFF1A237E)),
                        const SizedBox(width: 4),
                        Text(_formatScheduledTime(lesson['scheduled_at'] as String?),
                            style: const TextStyle(fontSize: 13, color: Color(0xFF1A237E), fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ]),
              ),
              // Status badge
              if (statusText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.person_outline, size: 14, color: Colors.grey), const SizedBox(width: 4),
              Text(teacherName, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(width: 12),
              const Icon(Icons.book_outlined, size: 14, color: Colors.grey), const SizedBox(width: 4),
              Text(subjectName, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ]),
            if (lesson['description']?.toString().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(lesson['description'] ?? '', style: const TextStyle(fontSize: 13, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_formatDate(isLive ? lesson['started_at'] as String? : lesson['created_at'] as String?),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              if (isLive)
                isExpired
                    ? GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PaymentScreen(
                              teacherId: teacherId,
                              teacherName: teacherName,
                              subjectName: subjectName,
                              enrollmentId: enrollment?['id'] as String? ?? '',
                            ),
                          )).then((_) => _loadData());
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF283593)]),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(isSubscriptionExpired ? 'Renew' : 'Subscribe',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      )
                    : canAccess
                        ? ElevatedButton.icon(
                            onPressed: () => _joinLesson(lesson),
                            icon: const Icon(Icons.video_call, size: 18),
                            label: const Text('Join Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red, foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                          )
                        : const Icon(Icons.lock, color: Colors.grey, size: 20),
            ]),
          ],
        ),
      ),
    );
  }
}