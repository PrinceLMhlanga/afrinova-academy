import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/subject_service.dart';
import '../../core/auth_service.dart';
import '../lessons/video_player_screen.dart';
import 'upload_lesson_screen.dart';

class MyLessonsScreen extends StatefulWidget {
  const MyLessonsScreen({super.key});

  @override
  State<MyLessonsScreen> createState() => _MyLessonsScreenState();
}

class _MyLessonsScreenState extends State<MyLessonsScreen> {
  final SubjectService _subjectService = SubjectService();
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
      if (userId != null) {
        final lessons = await _subjectService.getTeacherLessons(userId);
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          setState(() {
            _lessons = lessons;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteLesson(String lessonId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Lesson?'),
        content: Text('"$title" will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _subjectService.deleteLesson(lessonId);
        _loadLessons();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lesson deleted'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return '';
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  String _formatViews(int? views) {
    if (views == null || views == 0) return 'No views';
    if (views < 1000) return '$views views';
    if (views < 1000000) return '${(views / 1000).toStringAsFixed(1)}K views';
    return '${(views / 1000000).toStringAsFixed(1)}M views';
  }

  String _timeAgo(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('My Lessons'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: 'Upload New Lesson',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UploadLessonScreen()),
              );
              _loadLessons();
            },
          ),
        ],
      ),
      body: _isLoading
          ? _buildSkeletonGrid()
          : _lessons.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadLessons,
                  color: const Color(0xFFFF9800),
                  child: _buildVideoGrid(),
                ),
    );
  }

  // ===== RESPONSIVE VIDEO GRID =====
  Widget _buildVideoGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate columns based on screen width
        final crossAxisCount = constraints.maxWidth > 900
            ? 3
            : constraints.maxWidth > 600
                ? 2
                : 1;

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: _lessons.length,
          itemBuilder: (context, index) {
            final lesson = _lessons[index];
            return _VideoGridCard(
              title: lesson['title'] ?? 'Untitled',
              description: lesson['description'] ?? '',
              subjectName: lesson['teacher_topics']?['subjects']?['name'] ?? '',
topicName: lesson['teacher_topics']?['name'] ?? '',
              duration: _formatDuration(lesson['duration_minutes']),
              views: _formatViews(lesson['view_count']),
              timeAgo: _timeAgo(lesson['created_at']),
              isPublished: lesson['is_published'] ?? false,
              isPremium: lesson['is_premium'] ?? false,
              videoUrl: lesson['video_url'],
              teacherName: 'You',
              lessonDescription: lesson['description'] ?? '',
              onDelete: () =>
                  _deleteLesson(lesson['id'], lesson['title'] ?? 'Untitled'),
              onPlay: () {
                final url = lesson['video_url'];
                if (url != null && url.toString().isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoPlayerScreen(
                        lessonId: lesson['id'],
                        lessonTitle: lesson['title'] ?? 'Untitled',
                        videoUrl: url,
                        lessonDescription: lesson['description'] ?? '',
                        teacherName: 'You',
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Video URL not available'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  // ===== SKELETON LOADING GRID =====
  Widget _buildSkeletonGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 3
            : constraints.maxWidth > 600
                ? 2
                : 1;

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: 6,
          itemBuilder: (context, index) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail skeleton
                Expanded(
                  flex: 3,
                  child: _ShimmerBox(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 8),
                // Title skeleton
                _ShimmerBox(
                  height: 12,
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                _ShimmerBox(
                  height: 10,
                  width: 100,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                _ShimmerBox(
                  height: 10,
                  width: 140,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===== EMPTY STATE =====
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 160,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 10, left: 10, right: 10,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 70, left: 10, right: 40,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 84, left: 10, right: 60,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const Center(
                    child: Icon(Icons.play_circle_outline, size: 36, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No lessons uploaded yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload your first video lesson\nand start teaching',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UploadLessonScreen()),
                );
                _loadLessons();
              },
              icon: const Icon(Icons.upload),
              label: const Text('Upload Your First Lesson'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== VIDEO GRID CARD =====
class _VideoGridCard extends StatefulWidget {
  final String title;
  final String description;
  final String subjectName;
  final String topicName;
  final String duration;
  final String views;
  final String timeAgo;
  final bool isPublished;
  final bool isPremium;
  final String? videoUrl;
  final String teacherName;
  final String lessonDescription;
  final VoidCallback onDelete;
  final VoidCallback onPlay;

  const _VideoGridCard({
    required this.title,
    required this.description,
    required this.subjectName,
    required this.topicName,
    required this.duration,
    required this.views,
    required this.timeAgo,
    required this.isPublished,
    required this.isPremium,
    this.videoUrl,
    required this.teacherName,
    required this.lessonDescription,
    required this.onDelete,
    required this.onPlay,
  });

  @override
  State<_VideoGridCard> createState() => _VideoGridCardState();
}

class _VideoGridCardState extends State<_VideoGridCard> {
  VideoPlayerController? _previewController;
  bool _isHovering = false;
  bool _showMenu = false;

  @override
  void initState() {
    super.initState();
    _initPreview();
  }

  void _initPreview() {
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      try {
        _previewController = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl!),
        )..initialize().then((_) {
            if (mounted) setState(() {});
            _previewController?.setLooping(true);
            _previewController?.setVolume(0);
            _previewController?.play();
          });
      } catch (_) {
        // Video preview not available
      }
    }
  }

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onPlay,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    // Thumbnail background
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12)),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: const Color(0xFF1A237E).withOpacity(0.06),
                        child: _buildThumbnailContent(),
                      ),
                    ),

                    // Duration badge (bottom right)
                    if (widget.duration.isNotEmpty)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            widget.duration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                    // Status badges (top left)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.isPublished
                                  ? const Color(0xFF4CAF50)
                                  : Colors.orange,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              widget.isPublished ? 'Live' : 'Draft',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (widget.isPremium) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'Premium',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Play button overlay (on hover)
                    if (_isHovering)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.3),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                    // Menu button (top right)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _showMenu = !_showMenu),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),

                    // Dropdown menu
                    if (_showMenu)
                      Positioned(
                        top: 28,
                        right: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MenuOption(
                                icon: Icons.edit,
                                label: 'Edit',
                                onTap: () {
                                  setState(() => _showMenu = false);
                                },
                              ),
                              _MenuOption(
                                icon: Icons.delete_outline,
                                label: 'Delete',
                                color: Colors.red,
                                onTap: () {
                                  setState(() => _showMenu = false);
                                  widget.onDelete();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Video info
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A237E),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // Views + Time
                      Row(
                        children: [
                          if (widget.views.isNotEmpty)
                            Flexible(
                              child: Text(
                                widget.views,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (widget.views.isNotEmpty &&
                              widget.timeAgo.isNotEmpty)
                            Text(
                              ' • ',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade400),
                            ),
                          if (widget.timeAgo.isNotEmpty)
                            Flexible(
                              child: Text(
                                widget.timeAgo,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),

                      // Subject tag
                      if (widget.subjectName.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF1A237E).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.subjectName,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF1A237E),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    // Show actual video preview if available
    if (_previewController != null &&
        _previewController!.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(_previewController!),
          // Gradient overlay at bottom for text readability
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Fallback: gradient placeholder
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A237E).withOpacity(0.05),
            const Color(0xFF1A237E).withOpacity(0.15),
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.videocam,
          size: 36,
          color: Colors.grey,
        ),
      ),
    );
  }
}

// ===== MENU OPTION =====
class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _MenuOption({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color ?? Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color ?? Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== SHIMMER BOX =====
class _ShimmerBox extends StatefulWidget {
  final double? height;
  final double? width;
  final BorderRadiusGeometry borderRadius;

  const _ShimmerBox({
    this.height,
    this.width,
    required this.borderRadius,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height ?? double.infinity,
          width: widget.width ?? double.infinity,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: const [
                Color(0xFFEEEEEE),
                Color(0xFFE0E0E0),
                Color(0xFFEEEEEE),
              ],
            ),
          ),
        );
      },
    );
  }
}
// Simple AnimatedBuilder since we're not importing the full animation package
