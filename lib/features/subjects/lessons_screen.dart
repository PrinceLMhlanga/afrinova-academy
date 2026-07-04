import 'package:flutter/material.dart';
import '../../core/subject_service.dart';
import '../lessons/video_player_screen.dart';

class LessonsScreen extends StatefulWidget {
  final String topicId;
  final String topicName;
  final Color subjectColor;

  const LessonsScreen({
    super.key,
    required this.topicId,
    required this.topicName,
    required this.subjectColor,
  });

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  final SubjectService _subjectService = SubjectService();
  List<Map<String, dynamic>> _lessons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

 Future<void> _loadLessons() async {
  try {
    List<Map<String, dynamic>> lessons;
    
    // Try loading via teacher_topic_id first (new system)
    lessons = await _subjectService.getLessonsByTeacherTopic(widget.topicId);
    
    // If no lessons found, fall back to old topic_id
    if (lessons.isEmpty) {
      lessons = await _subjectService.getLessons(widget.topicId);
    }

    if (mounted) {
      setState(() {
        _lessons = lessons;
        _isLoading = false;
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load lessons: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

  String _formatDuration(int? minutes) {
    if (minutes == null) return 'Unknown duration';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topicName),
        backgroundColor: widget.subjectColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: widget.subjectColor),
            )
          : _lessons.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.video_library_outlined,
                              size: 80, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'No lessons available yet',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _lessons.length,
                  itemBuilder: (context, index) {
                    final lesson = _lessons[index];
                    final teacherName =
                        lesson['profiles']?['full_name'] ?? 'AfriNova Teacher';

                    return _LessonCard(
                      title: lesson['title'] ?? 'Untitled Lesson',
                      description: lesson['description'] ?? '',
                      teacherName: teacherName,
                      duration: _formatDuration(lesson['duration_minutes']),
                      isPremium: lesson['is_premium'] ?? false,
                      color: widget.subjectColor,
                      onTap: () {
  final videoUrl = lesson['video_url'];
  if (videoUrl != null && videoUrl.toString().isNotEmpty) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          lessonId: lesson['id'],
          lessonTitle: lesson['title'] ?? 'Untitled',
          videoUrl: videoUrl,
          lessonDescription: lesson['description'] ?? '',
          teacherName: teacherName,
        ),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video not available yet'),
        duration: Duration(seconds: 2),
      ),
    );
  }
},
                    );
                  },
                ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final String title;
  final String description;
  final String teacherName;
  final String duration;
  final bool isPremium;
  final Color color;
  final VoidCallback onTap;

  const _LessonCard({
    required this.title,
    required this.description,
    required this.teacherName,
    required this.duration,
    required this.isPremium,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail placeholder
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 64,
                      color: color.withOpacity(0.5),
                    ),
                  ),
                  if (isPremium)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Premium',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Lesson info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        teacherName,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      Icon(Icons.timer_outlined,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        duration,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}