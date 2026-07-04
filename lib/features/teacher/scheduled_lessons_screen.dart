import 'package:flutter/material.dart';
import '../../core/live_lesson_service.dart';
import '../../core/auth_service.dart';

class ScheduledLessonsScreen extends StatefulWidget {
  const ScheduledLessonsScreen({super.key});

  @override
  State<ScheduledLessonsScreen> createState() => _ScheduledLessonsScreenState();
}

class _ScheduledLessonsScreenState extends State<ScheduledLessonsScreen> {
  final LiveLessonService _liveService = LiveLessonService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _lessons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final lessons = await _liveService.getTeacherLiveLessons(userId);
      if (mounted) {
        setState(() {
          _lessons = lessons;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startLesson(Map<String, dynamic> lesson) async {
    final lessonId = lesson['id'] as String;
    final roomId = lesson['room_id'] as String;

    await _liveService.updateStatus(lessonId, 'live');

    await _liveService.joinLesson(
      context: context,
      roomName: roomId,
      userName: "Teacher",
      lessonId: lessonId,
      isTeacher: true,
    );

    _loadLessons();
  }

  Future<void> _cancelLesson(String lessonId) async {
    await _liveService.updateStatus(lessonId, 'cancelled');
    _loadLessons();
  }

  

  @override
  Widget build(BuildContext context) {
    final scheduled = _lessons.where((l) => l['status'] == 'scheduled').toList();
    final live = _lessons.where((l) => l['status'] == 'live').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Lessons'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : RefreshIndicator(
              onRefresh: _loadLessons,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (live.isNotEmpty) ...[
                    const Text('LIVE NOW', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...live.map((l) => _TeacherLessonCard(
                          lesson: l,
                          isLive: true,
                          onStart: () => _startLesson(l),
                          onCancel: () => _cancelLesson(l['id'] as String),
                        )),
                    const SizedBox(height: 20),
                  ],
                  if (scheduled.isNotEmpty) ...[
                    const Text('SCHEDULED', style: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...scheduled.map((l) => _TeacherLessonCard(
                          lesson: l,
                          isLive: false,
                          onStart: () => _startLesson(l),
                          onCancel: () => _cancelLesson(l['id'] as String),
                        )),
                  ],
                  if (live.isEmpty && scheduled.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('No lessons yet', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _TeacherLessonCard extends StatelessWidget {
  final Map<String, dynamic> lesson;
  final bool isLive;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  const _TeacherLessonCard({
    required this.lesson,
    required this.isLive,
    required this.onStart,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: isLive ? Colors.red.withOpacity(0.1) : const Color(0xFF1A237E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isLive ? Icons.live_tv : Icons.schedule,
            color: isLive ? Colors.red : const Color(0xFF1A237E),
          ),
        ),
        title: Text(lesson['topic'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
  '${lesson['subjects']?['name'] ?? ''} • ${_formatScheduledTime(lesson['scheduled_at'] as String?)}',
),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLive)
              ElevatedButton(
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: const Text('Start', style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onCancel,
              child: const Icon(Icons.close, color: Colors.grey, size: 20),
            ),
          ],
        ),
      ),
    );
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
  } catch (_) {
    return '';
  }
}
}