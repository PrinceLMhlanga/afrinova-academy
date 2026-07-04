import 'package:flutter/material.dart';
import '../../core/subject_service.dart';
import '../../core/auth_service.dart';
import 'players/native_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
    

class VideoPlayerScreen extends StatefulWidget {
  final String lessonId;
  final String lessonTitle;
  final String videoUrl;
  final String lessonDescription;
  final String teacherName;

  const VideoPlayerScreen({
    super.key,
    required this.lessonId,
    required this.lessonTitle,
    required this.videoUrl,
    required this.lessonDescription,
    required this.teacherName,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  final SubjectService _subjectService = SubjectService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _resources = [];
  bool _isLoadingResources = true;

  @override
  void initState() {
    super.initState();
    _loadResources();
    _incrementViewCount();
  }

  Future<void> _incrementViewCount() async {
  try {
    await Supabase.instance.client.rpc('increment_lesson_view', params: {
      'lesson_id': widget.lessonId,
    });
  } catch (e) {
    debugPrint('View count error: $e');
  }
}
  Future<void> _markProgress({bool completed = false}) async {
    try {
      final studentId = _authService.currentUserId;
      if (studentId != null) {
        await _subjectService.updateProgress(
          lessonId: widget.lessonId,
          studentId: studentId,
          watchedPercentage: completed ? 100 : 0,
          lastPositionSeconds: 0,
          completed: completed,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadResources() async {
    try {
      final resources = await _subjectService.getResources(widget.lessonId);
      if (mounted) {
        setState(() {
          _resources = resources;
          _isLoadingResources = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingResources = false);
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String? type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
        return Icons.description;
      case 'ppt':
        return Icons.slideshow;
      default:
        return Icons.attach_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.lessonTitle,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Video Player
                  Container(
                    color: Colors.black,
                    width: double.infinity,
                    height: constraints.maxWidth * 9 / 16,
                    child: buildVideoPlayer(
                      widget.videoUrl,
                      () => _markProgress(completed: true),
                    ),
                  ),
                  // Info Section
                  Container(
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Teacher row
                              Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Color(0xFF1A237E),
                                    child: Icon(Icons.person,
                                        color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      widget.teacherName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A237E),
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        _markProgress(completed: true),
                                    icon: const Icon(
                                        Icons.check_circle_outline,
                                        color: Color(0xFF4CAF50),
                                        size: 16),
                                    label: const Text(
                                      'Complete',
                                      style: TextStyle(
                                          color: Color(0xFF4CAF50),
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Description
                              const Text(
                                'About this lesson',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.lessonDescription.isNotEmpty
                                    ? widget.lessonDescription
                                    : 'No description available.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Resources header
                              const Text(
                                'Lesson Resources',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                        // Resources list
                        _buildResourcesList(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResourcesList() {
    if (_isLoadingResources) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF1A237E)),
        ),
      );
    }

    if (_resources.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey, size: 18),
              SizedBox(width: 8),
              Text(
                'No resources for this lesson yet',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: _resources.map((r) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                _getFileIcon(r['file_type']),
                color: const Color(0xFF1A237E),
                size: 22,
              ),
              title: Text(
                r['title'] ?? 'Resource',
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13),
              ),
              subtitle: Text(
                _formatFileSize(r['file_size_bytes']),
                style: const TextStyle(fontSize: 11),
              ),
              trailing:
                  const Icon(Icons.download, color: Color(0xFFFF9800), size: 20),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Download coming soon! 📥'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}