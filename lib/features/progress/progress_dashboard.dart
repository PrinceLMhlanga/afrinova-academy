import 'package:flutter/material.dart';
import '../../core/progress_service.dart';
import '../../core/auth_service.dart';

class ProgressDashboard extends StatefulWidget {
  const ProgressDashboard({super.key});

  @override
  State<ProgressDashboard> createState() => _ProgressDashboardState();
}

class _ProgressDashboardState extends State<ProgressDashboard>
    with SingleTickerProviderStateMixin {
  final ProgressService _progressService = ProgressService();
  final AuthService _authService = AuthService();

  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _subjectProgress = [];
  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoading = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadData();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final stats = await _progressService.getStudentStats(userId);
      final subjects = await _progressService.getSubjectProgress(userId);
      final activity = await _progressService.getRecentActivity(userId);

      if (mounted) {
        setState(() {
          _stats = stats;
          _subjectProgress = subjects;
          _recentActivity = activity;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Progress load error: $e');
      if (mounted) setState(() => _isLoading = false);
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
            // Custom AppBar with gradient
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: const BackButton(color: Colors.white),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D1B4C),
                      Color(0xFF1A237E),
                      Color(0xFF283593),
                    ],
                  ),
                ),
                child: FlexibleSpaceBar(
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.analytics_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'My Progress',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                ),
              ),
            ),

            // Content
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(60),
                        child: Column(
                          children: [
                            CircularProgressIndicator(color: Color(0xFF1A237E)),
                            SizedBox(height: 16),
                            Text('Loading your progress...',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // Streak Card - Fixed overflow
                    FadeTransition(
                      opacity: _animationController,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.1),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _animationController,
                          curve: Curves.easeOut,
                        )),
                        child: _buildStreakCard(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Stats Grid
                    FadeTransition(
                      opacity: _animationController,
                      child: _buildStatsGrid(),
                    ),

                    const SizedBox(height: 24),

                    // Section Header
                    FadeTransition(
                      opacity: _animationController,
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Subject Progress',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_subjectProgress.length} subjects',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Subject Progress
                    if (_subjectProgress.isNotEmpty)
                      FadeTransition(
                        opacity: _animationController,
                        child: _buildSubjectProgress(),
                      ),

                    const SizedBox(height: 24),

                    // Section Header - Recent Activity
                    FadeTransition(
                      opacity: _animationController,
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Recent Activity',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_recentActivity.length} items',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Recent Activity
                    FadeTransition(
                      opacity: _animationController,
                      child: _buildRecentActivity(),
                    ),

                    const SizedBox(height: 20),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== STREAK CARD - FIXED OVERFLOW =====
  Widget _buildStreakCard() {
    final streak = _stats['streak_days'] ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF3949AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.local_fire_department,
                color: Color(0xFFFF9800),
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$streak Day Streak! 🔥',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  streak > 0
                      ? 'Keep it up! You\'re on fire!'
                      : 'Start learning to build your streak!',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== STATS GRID =====
  Widget _buildStatsGrid() {
    return Row(
      children: [
        Expanded(
          child: _AnimatedStatCard(
            icon: Icons.play_circle_rounded,
            label: 'Lessons',
            value: '${_stats['lessons_completed'] ?? 0}',
            color: const Color(0xFF1A237E),
            index: 0,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AnimatedStatCard(
            icon: Icons.quiz_rounded,
            label: 'Exams',
            value: '${_stats['exams_taken'] ?? 0}',
            color: const Color(0xFFFF9800),
            index: 1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AnimatedStatCard(
            icon: Icons.grade_rounded,
            label: 'Avg Score',
            value: '${(_stats['average_score'] ?? 0).toStringAsFixed(0)}%',
            color: const Color(0xFF4CAF50),
            index: 2,
          ),
        ),
      ],
    );
  }

  // ===== SUBJECT PROGRESS =====
  Widget _buildSubjectProgress() {
    return Column(
      children: _subjectProgress.map((s) {
        final completed = (s['completed_lessons'] as num?)?.toInt() ?? 0;
        final total = (s['total_lessons'] as num?)?.toInt() ?? 10;
        final progress = total > 0 ? completed / total : 0.0;
        final color = _parseColor(s['color'] as String?);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s['subject_name'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$completed / $total',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade200,
                  color: color,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(progress * 100).toStringAsFixed(0)}% complete',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ===== RECENT ACTIVITY =====
  Widget _buildRecentActivity() {
    if (_recentActivity.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.timeline_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No recent activity',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text(
                'Start learning to see your progress!',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _recentActivity.take(8).map((activity) {
        final type = activity['type'] as String? ?? '';
        final title = activity['title'] as String? ?? '';
        final dateStr = activity['date'] as String? ?? '';
        final date = _formatDate(dateStr);
        final isExam = type == 'exam' || type == 'mcq' || type == 'paper';
        final isLesson = type == 'lesson';

        IconData icon;
        Color iconColor;
        Color bgColor;

        if (isExam) {
          icon = Icons.quiz_rounded;
          iconColor = const Color(0xFFFF9800);
          bgColor = const Color(0xFFFF9800).withOpacity(0.1);
        } else if (isLesson) {
          icon = Icons.play_circle_rounded;
          iconColor = const Color(0xFF1A237E);
          bgColor = const Color(0xFF1A237E).withOpacity(0.1);
        } else {
          icon = Icons.assignment_rounded;
          iconColor = const Color(0xFF00897B);
          bgColor = const Color(0xFF00897B).withOpacity(0.1);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLesson
                          ? 'Completed ✓'
                          : isExam
                              ? 'Score: ${(activity['percentage'] as num?)?.toStringAsFixed(0) ?? '0'}%'
                              : '${activity['percentage'] ?? 0}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: isLesson ? Colors.green : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ===== HELPERS =====
  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF1A237E);
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }
}

// ===== ANIMATED STAT CARD =====
class _AnimatedStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final int index;

  const _AnimatedStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 400 + (index * 80)),
      curve: Curves.easeOut,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, animation, child) {
        return Transform.scale(
          scale: 0.9 + (0.1 * animation),
          child: Opacity(
            opacity: animation,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: color.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withOpacity(0.15),
                          color.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 24, color: color),
                  ),
                  const SizedBox(height: 6),
                  TweenAnimationBuilder(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    tween: Tween<double>(
                        begin: 0,
                        end: double.tryParse(value.replaceAll('%', '')) ?? 0),
                    builder: (context, animation, child) {
                      final displayValue = value.contains('%')
                          ? '${animation.toInt()}%'
                          : animation.toInt().toString();
                      return Text(
                        displayValue,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}