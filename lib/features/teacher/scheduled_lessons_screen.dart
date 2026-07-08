import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/live_lesson_service.dart';

class ScheduledLessonsScreen extends StatefulWidget {
  const ScheduledLessonsScreen({super.key});

  @override
  State<ScheduledLessonsScreen> createState() => _ScheduledLessonsScreenState();
}

class _ScheduledLessonsScreenState extends State<ScheduledLessonsScreen> {
  final AuthService _authService = AuthService();
  final LiveLessonService _liveService = LiveLessonService();
  List<Map<String, dynamic>> _lessons = [];
  bool _isLoading = true;
  String? _activeLessonId;
  String? _activeRoomId;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // ✅ Load with level, subject, topic info
      final response = await Supabase.instance.client
          .from('live_lessons')
          .select('*, subjects(name), levels(name), teacher_topics(name)')
          .eq('teacher_id', userId)
          .inFilter('status', ['scheduled', 'live'])
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _lessons = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading lessons: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startLesson(Map<String, dynamic> lesson) async {
    final lessonId = lesson['id'] as String;
    final roomId = lesson['room_id'] as String;

    await Supabase.instance.client
        .from('live_lessons')
        .update({'status': 'live', 'started_at': DateTime.now().toIso8601String()})
        .eq('id', lessonId);

    if (kIsWeb) {
      // ✅ Web: Open Jitsi in new tab + show end lesson banner
      final uri = Uri.parse('https://meet.ffmuc.net/$roomId#userInfo.displayName=Teacher&config.prejoinPageEnabled=false');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      
      setState(() {
        _activeLessonId = lessonId;
        _activeRoomId = roomId;
      });
    } else {
      // Mobile: Join in-app
      if (mounted) {
        await _joinInApp(roomId, lessonId);
      }
    }

    _loadLessons();
  }

  Future<void> _joinInApp(String roomId, String lessonId) async {
    await _liveService.updateStatus(lessonId, 'live');

    await _liveService.joinLesson(
      context: context,
      roomName: roomId,
      userName: "Teacher",
      lessonId: lessonId,
      isTeacher: true,
    );
  }

  Future<void> _endLesson() async {
    if (_activeLessonId == null) return;
    
    await Supabase.instance.client
        .from('live_lessons')
        .update({'status': 'ended', 'ended_at': DateTime.now().toIso8601String()})
        .eq('id', _activeLessonId!);
    
    setState(() {
      _activeLessonId = null;
      _activeRoomId = null;
    });
    
    _loadLessons();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lesson ended ✅'), backgroundColor: Color(0xFF4CAF50)),
      );
    }
  }

  Future<void> _cancelLesson(String lessonId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Lesson?'),
        content: const Text('This will mark the lesson as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Cancel Lesson'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client
          .from('live_lessons')
          .update({'status': 'cancelled'})
          .eq('id', lessonId);
      _loadLessons();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lesson cancelled'), backgroundColor: Colors.orange),
        );
      }
    }
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
      body: Column(
        children: [
          // ✅ Active lesson banner (for web)
          if (_activeLessonId != null)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.red.shade600, Colors.red.shade800]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Lesson is LIVE in another tab', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final uri = Uri.parse('https://meet.ffmuc.net/$_activeRoomId');
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Rejoin'),
                  ),
                  ElevatedButton(
                    onPressed: _endLesson,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red),
                    child: const Text('End Lesson'),
                  ),
                ],
              ),
            ),

          // Lesson list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
                : RefreshIndicator(
                    onRefresh: _loadLessons,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (live.isNotEmpty) ...[
                          const Text('🟢 LIVE NOW', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
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
                          const Text('📅 SCHEDULED', style: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 14)),
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
                              child: Column(
                                children: [
                                  Icon(Icons.live_tv_outlined, size: 64, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text('No lessons yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
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
    final levelName = lesson['levels']?['name'] as String?;
    final subjectName = lesson['subjects']?['name'] as String?;
    final topicName = lesson['teacher_topics']?['name'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icon
            Container(
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
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson['topic'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  // ✅ Level → Subject → Topic
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (levelName != null)
                        _LevelBadge(label: levelName, color: _getLevelColor(levelName)),
                      if (subjectName != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(subjectName, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                      if (topicName != null)
                        Text(topicName, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatScheduledTime(lesson['scheduled_at'] as String?),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            // Actions
            Row(
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
          ],
        ),
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'Form 1': return Colors.blue;
      case 'Form 2': return Colors.teal;
      case 'O-Level': return const Color(0xFFFF9800);
      case 'A-Level': return Colors.purple;
      default: return Colors.grey;
    }
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

class _LevelBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _LevelBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}