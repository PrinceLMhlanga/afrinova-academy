import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/access_checker.dart';
import '../lessons/video_player_screen.dart';
import '../pdf/pdf_viewer_screen.dart';

class TopicContentScreen extends StatefulWidget {
  final String topicId;
  final String topicName;
  final Color subjectColor;
  final String teacherId;
  final String? subjectId;

  const TopicContentScreen({
    super.key,
    required this.topicId,
    required this.topicName,
    required this.subjectColor,
    required this.teacherId,
    this.subjectId,
  });

  @override
  State<TopicContentScreen> createState() => _TopicContentScreenState();
}

class _TopicContentScreenState extends State<TopicContentScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  late TabController _tabController;

  List<Map<String, dynamic>> _lessons = [];
  List<Map<String, dynamic>> _resources = [];
  List<Map<String, dynamic>> _mcqExams = [];
  Map<String, dynamic>? _enrollment;
  bool _isLoading = true;
  bool _isRefreshing = false;

  // Colors for random thumbnails
  final List<Color> _thumbnailColors = [
    const Color(0xFF1A237E),
    const Color(0xFF283593),
    const Color(0xFF3949AB),
    const Color(0xFF4CAF50),
    const Color(0xFFFF9800),
    const Color(0xFFE91E63),
    const Color(0xFF9C27B0),
    const Color(0xFF00897B),
    const Color(0xFF5C6BC0),
    const Color(0xFFFF6B00),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  
  

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _authService.currentUserId;

      // Load enrollment for feature check
      if (userId != null) {
        final enrollments = await Supabase.instance.client
            .from('enrollments')
            .select('plan_features, is_subscribed, subscription_expires_at, trial_ends_at, subject_id')
            .eq('student_id', userId)
            .eq('teacher_id', widget.teacherId);

        if (enrollments.isNotEmpty) {
          _enrollment = enrollments.first as Map<String, dynamic>;
        }
      }

      // Load lessons
      final lessonsResponse = await Supabase.instance.client
          .from('lessons')
          .select('*, profiles!teacher_id(display_name, full_name)')
          .eq('teacher_topic_id', widget.topicId)
          .eq('is_published', true)
          .order('created_at', ascending: false);

      _lessons = List<Map<String, dynamic>>.from(lessonsResponse);

      // Load resources
      final resourcesResponse = await Supabase.instance.client
          .from('resources')
          .select('*, profiles!teacher_id(display_name, full_name)')
          .eq('teacher_topic_id', widget.topicId)
          .order('created_at', ascending: false);

      _resources = List<Map<String, dynamic>>.from(resourcesResponse);

      // Load MCQ exams
      final examsResponse = await Supabase.instance.client
          .from('exams')
          .select('*, profiles!creator_id(display_name, full_name)')
          .eq('teacher_topic_id', widget.topicId)
          .eq('is_published', true)
          .order('created_at', ascending: false);

      _mcqExams = List<Map<String, dynamic>>.from(examsResponse);

     if (mounted) {
  setState(() => _isLoading = false);
}
    } catch (e) {
      debugPrint('Error loading content: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }
  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await _loadData();
    if (mounted) setState(() => _isRefreshing = false);
  }

 bool _canAccessFeature(String feature) {
  if (_enrollment == null) return true; // Default to true if no enrollment data
  return AccessChecker.hasFeature(_enrollment, feature);
}

  String _formatDuration(int? minutes) {
    if (minutes == null) return '';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _timeAgo(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
      if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'T';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }

  Color _getRandomColor(String id) {
    final int hash = id.hashCode.abs();
    return _thumbnailColors[hash % _thumbnailColors.length];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  final canAccessLessons = _canAccessFeature('Recorded Lessons');
  final canAccessResources = _canAccessFeature('Notes & Resources');
  final canAccessMCQ = _canAccessFeature('MCQ Practice');

  return Scaffold(
    backgroundColor: Colors.grey.shade50,
    appBar: AppBar(
      title: Text(widget.topicName, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: widget.subjectColor,
      foregroundColor: Colors.white,
      elevation: 0,
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        tabs: [
          Tab(text: 'Lessons (${_lessons.length})'),
          Tab(text: 'Resources (${_resources.length})'),
          Tab(text: 'MCQs (${_mcqExams.length})'),
        ],
      ),
    ),
    body: _isLoading
        ? _buildLoadingSkeleton()
        : TabBarView(
            controller: _tabController,
            children: [
              canAccessLessons ? _buildLessonsTab() : _buildUpgradePrompt('Recorded Lessons'),
              canAccessResources ? _buildResourcesTab() : _buildUpgradePrompt('Notes & Resources'),
              canAccessMCQ ? _buildMCQTab() : _buildUpgradePrompt('MCQ Practice'),
            ],
          ),
  );
}

Widget _buildUpgradePrompt(String feature) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock, size: 48, color: Colors.orange),
          ),
          const SizedBox(height: 24),
          const Text('Premium Feature',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 8),
          Text(
            '$feature requires a premium plan. Upgrade your subscription to unlock this content.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

  // ===== LOADING SKELETON =====
  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 500;
          final crossAxisCount = _getGridColumns(constraints.maxWidth);
          final spacing = 16.0;
          final totalSpacing = spacing * (crossAxisCount - 1);
          final cardWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: List.generate(
              6,
              (index) => SizedBox(
                width: cardWidth,
                child: _LessonSkeletonCard(
                  color: _thumbnailColors[index % _thumbnailColors.length],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  int _getGridColumns(double width) {
    if (width < 500) return 1;
    if (width < 700) return 2;
    return 3;
  }

  // ===== LESSONS TAB =====
  Widget _buildLessonsTab() {
    if (_lessons.isEmpty) {
      return _buildEmptyState(
        icon: Icons.video_library_outlined,
        title: 'No lessons yet',
        subtitle: 'Lessons for this topic will appear here',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = _getGridColumns(constraints.maxWidth);
          final spacing = 16.0;
          final totalSpacing = spacing * (crossAxisCount - 1);
          final cardWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: _lessons.asMap().entries.map((entry) {
              final index = entry.key;
              final lesson = entry.value;
              final teacherName = lesson['profiles']?['display_name'] ??
                  lesson['profiles']?['full_name'] ??
                  'Teacher';

              return SizedBox(
                width: cardWidth,
                child: _LessonGridCard(
                  title: lesson['title'] ?? 'Untitled',
                  teacherName: teacherName,
                  duration: _formatDuration(lesson['duration_minutes'] as int?),
                  timeAgo: _timeAgo(lesson['created_at'] as String?),
                  description: lesson['description'] as String?,
                  color: _getRandomColor(lesson['id'] ?? index.toString()),
                  onTap: () {
                    final videoUrl = lesson['video_url'];
                    if (videoUrl != null && videoUrl.toString().isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            lessonId: lesson['id'] as String,
                            lessonTitle: lesson['title'] ?? '',
                            videoUrl: videoUrl.toString(),
                            lessonDescription: lesson['description'] ?? '',
                            teacherName: teacherName,
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  // ===== RESOURCES TAB =====
  Widget _buildResourcesTab() {
    if (_resources.isEmpty) {
      return _buildEmptyState(
        icon: Icons.folder_outlined,
        title: 'No resources yet',
        subtitle: 'Study materials for this topic will appear here',
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _resources.length,
        itemBuilder: (context, index) {
          final r = _resources[index];
          final teacherName = r['profiles']?['display_name'] ??
              r['profiles']?['full_name'] ??
              'Teacher';

          return _ResourceCard(
            title: r['title'] ?? 'Resource',
            teacherName: teacherName,
            fileSize: _formatFileSize(r['file_size_bytes'] as int?),
            fileType: r['file_type'] as String?,
            timeAgo: _timeAgo(r['created_at'] as String?),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PdfViewerScreen(
                    url: r['file_url'] ?? '',
                    title: r['title'] ?? 'Resource',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ===== MCQ TAB =====
  Widget _buildMCQTab() {
    if (_mcqExams.isEmpty) {
      return _buildEmptyState(
        icon: Icons.quiz_outlined,
        title: 'No MCQ exams yet',
        subtitle: 'Practice tests for this topic will appear here',
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _mcqExams.length,
        itemBuilder: (context, index) {
          final exam = _mcqExams[index];
          final creatorName = exam['profiles']?['display_name'] ??
              exam['profiles']?['full_name'] ??
              'Teacher';

          return _MCQCard(
            title: exam['title'] ?? 'MCQ Exam',
            creatorName: creatorName,
            totalMarks: exam['total_marks'] ?? 0,
            timeAgo: _timeAgo(exam['created_at'] as String?),
            onTap: () {
              // Navigate to exam taker
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Exam taking feature coming soon!'),
                  backgroundColor: Color(0xFFFF9800),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

// ===== LESSON GRID CARD =====
class _LessonGridCard extends StatelessWidget {
  final String title;
  final String teacherName;
  final String duration;
  final String timeAgo;
  final String? description;
  final Color color;
  final VoidCallback onTap;

  const _LessonGridCard({
    required this.title,
    required this.teacherName,
    required this.duration,
    required this.timeAgo,
    this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
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
            // Thumbnail with static image
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  // Gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withOpacity(0.4),
                            color.withOpacity(0.05),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Static thumbnail placeholder with lesson title
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.play_circle_filled_rounded,
                          size: 56,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            title.length > 30 ? '${title.substring(0, 30)}...' : title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Duration badge
                  if (duration.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              duration,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A237E),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          teacherName,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  if (description != null && description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== LESSON SKELETON CARD =====
class _LessonSkeletonCard extends StatelessWidget {
  final Color color;

  const _LessonSkeletonCard({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          // Thumbnail skeleton
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                // Animated shimmer
                Positioned.fill(
                  child: Shimmer(
                    color: color,
                  ),
                ),
                Center(
                  child: Icon(
                    Icons.play_circle_filled_rounded,
                    size: 48,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
          // Info skeleton
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      height: 12,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 12,
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== SHIMMER ANIMATION =====
class Shimmer extends StatefulWidget {
  final Color color;

  const Shimmer({super.key, required this.color});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + _controller.value * 2, 0),
              end: Alignment(1 + _controller.value * 2, 0),
              colors: [
                widget.color.withOpacity(0.1),
                widget.color.withOpacity(0.2),
                widget.color.withOpacity(0.1),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===== RESOURCE CARD =====
class _ResourceCard extends StatelessWidget {
  final String title;
  final String teacherName;
  final String fileSize;
  final String? fileType;
  final String timeAgo;
  final VoidCallback onTap;

  const _ResourceCard({
    required this.title,
    required this.teacherName,
    required this.fileSize,
    this.fileType,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getFileColor(fileType);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getFileIcon(fileType),
            color: color,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Color(0xFF1A237E),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'By $teacherName • $fileSize',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              timeAgo,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.download,
            color: Color(0xFFFF9800),
            size: 20,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  IconData _getFileIcon(String? type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'image':
      case 'png':
      case 'jpg':
      case 'jpeg':
        return Icons.image;
      default:
        return Icons.attach_file;
    }
  }

  Color _getFileColor(String? type) {
    switch (type) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'image':
      case 'png':
      case 'jpg':
      case 'jpeg':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

// ===== MCQ CARD =====
class _MCQCard extends StatelessWidget {
  final String title;
  final String creatorName;
  final int totalMarks;
  final String timeAgo;
  final VoidCallback onTap;

  const _MCQCard({
    required this.title,
    required this.creatorName,
    required this.totalMarks,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.quiz_rounded,
            color: Color(0xFFFF9800),
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Color(0xFF1A237E),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'By $creatorName • $totalMarks marks',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              timeAgo,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Color(0xFFFF9800),
            size: 20,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}