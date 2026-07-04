import 'package:flutter/material.dart';
import '../../core/auth_service.dart';
import '../auth/welcome_screen.dart';
import '../live/student_live_lessons_screen.dart';
import '../teacher/teacher_dashboard.dart';
import '../exams/student_exams_screen.dart';
import '../resources/resource_library_screen.dart';
import '../progress/progress_dashboard.dart';
import '../ai/ai_tutor_screen.dart';
import '../subjects/my_subjects_screen.dart';
import '../exams/student_papers_screen.dart';
import '../../core/progress_service.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../badges/badges_screen.dart';
import '../admin/admin_dashboard.dart';
import '../trial/trial_banner.dart';
import '../account/my_account_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  String _userName = '';
  String _userRole = '';
  bool _isLoading = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _loadProfile();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _authService.getProfile();
    if (profile != null && mounted) {
      setState(() {
        _userName = profile['full_name'] ?? '';
        _userRole = profile['role'] ?? 'student';
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(
                color: Color(0xFF1A237E),
                strokeWidth: 3,
              ),
            ],
          ),
        ),
      );
    }

    if (_userRole == 'admin') {
  return AdminDashboard(
    userName: _userName,
    onLogout: _logout,
  );
}

if (_userRole == 'teacher') {
  return TeacherDashboard(
    userName: _userName,
    userRole: _userRole,
    onLogout: _logout,
  );
}

    return _StudentHome(
      userName: _userName,
      onLogout: _logout,
      animationController: _animationController,
    );
  }
}

// ==================== STUDENT HOME ====================
class _StudentHome extends StatefulWidget {
  final String userName;
  final VoidCallback onLogout;
  final AnimationController animationController;

  const _StudentHome({
    required this.userName,
    required this.onLogout,
    required this.animationController,
  });

  @override
  State<_StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<_StudentHome> {
  final ProgressService _progressService = ProgressService();
  final AuthService _authService = AuthService();
  Map<String, dynamic> _stats = {};
  bool _statsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }
   Future<void> _loadStats() async {
    try {
      final userId = _authService.currentUserId;
      if (userId != null) {
        final stats = await _progressService.getQuickStats(userId);
        if (mounted) {
          setState(() {
            _stats = stats;
            _statsLoaded = true;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoaded = true);
    }
  }

  int _getActionCount() {
    return 9;
  }
 @override
Widget build(BuildContext context) {
  return Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF5F7FA),
            Color(0xFFE8ECF1),
          ],
        ),
      ),
      
      child: CustomScrollView(
        slivers: [
          // Custom AppBar
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            backgroundColor: Colors.transparent,
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
                        Icons.auto_awesome,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'AfriNova',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Academy',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                centerTitle: false,
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              ),
            ),
            actions: [
  // Account icon
  Container(
    margin: const EdgeInsets.only(right: 4),
    child: IconButton(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.account_circle_outlined,
          color: Colors.white,
          size: 22,
        ),
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyAccountScreen()),
        );
      },
    ),
  ),
  // Logout icon
  Container(
    margin: const EdgeInsets.only(right: 8),
    child: IconButton(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.logout_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
      onPressed: widget.onLogout,
    ),
  ),
],
           
          ),
          
          // Content
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Welcome Card with Animation
                FadeTransition(
                  opacity: widget.animationController,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: widget.animationController,
                      curve: Curves.easeOut,
                    )),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF1A237E),
                            Color(0xFF283593),
                            Color(0xFF3949AB),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1A237E).withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.waving_hand,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Student',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Welcome back,',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.userName,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.school_rounded,
                                size: 16,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Continue your learning journey',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.7),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // ✅ TRIAL BANNER - ADDED HERE (Right after welcome card)
                const SizedBox(height: 16),
                TrialBanner(),
                
                const SizedBox(height: 16),
                
                // Section Header
                Row(
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
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_getActionCount()} features',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Quick Action Cards with staggered animation
                // Quick Action Cards with staggered animation - RESPONSIVE
FadeTransition(
  opacity: widget.animationController,
  child: LayoutBuilder(
    builder: (context, constraints) {
      // Determine columns based on screen width
      final isSmallScreen = constraints.maxWidth < 400;
      final crossAxisCount = isSmallScreen ? 3 : 4;
      
      // Calculate card width based on available space
      final spacing = 12.0;
      final totalSpacing = spacing * (crossAxisCount - 1);
      final cardWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;
      
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          _AnimatedQuickActionCard(
            icon: Icons.book_rounded,
            label: 'My Subjects',
            color: const Color(0xFF1A237E),
            index: 0,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MySubjectsScreen(),
                ),
              );
            },
          ),
          _AnimatedQuickActionCard(
            icon: Icons.quiz_rounded,
            label: 'MCQ Exams',
            color: const Color(0xFFFF9800),
            index: 1,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudentExamsScreen(),
                ),
              );
            },
          ),
          _AnimatedQuickActionCard(
            icon: Icons.assignment_rounded,
            label: 'Exam Papers',
            color: const Color(0xFF00897B),
            index: 2,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudentPapersScreen(),
                ),
              );
            },
          ),
          _AnimatedQuickActionCard(
            icon: Icons.analytics_rounded,
            label: 'Progress',
            color: const Color(0xFF4CAF50),
            index: 3,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProgressDashboard(),
                ),
              );
            },
          ),
          _AnimatedQuickActionCard(
            icon: Icons.library_books_rounded,
            label: 'Resources',
            color: const Color(0xFF9C27B0),
            index: 4,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ResourceLibraryScreen(),
                ),
              );
            },
          ),
          _AnimatedQuickActionCard(
            icon: Icons.auto_awesome_rounded,
            label: 'AI Tutor',
            color: const Color(0xFFE91E63),
            index: 5,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AITutorScreen(),
                ),
              );
            },
          ),
          _AnimatedQuickActionCard(
            icon: Icons.live_tv_rounded,
            label: 'Live Lessons',
            color: Colors.red,
            index: 6,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudentLiveLessonsScreen(),
                ),
              );
            },
          ),
          _AnimatedQuickActionCard(
            icon: Icons.leaderboard_rounded,
            label: 'Leaderboard',
            color: const Color(0xFFFFD700),
            index: 7,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LeaderboardScreen(),
                ),
              );
            },
          ),
          _AnimatedQuickActionCard(
            icon: Icons.military_tech_rounded,
            label: 'Badges',
            color: const Color(0xFFFFA000),
            index: 8,
            width: cardWidth,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BadgesScreen(),
                ),
              );
            },
          ),
        ],
      );
    },
  ),
),
                
                const SizedBox(height: 30),
                
                // Bottom Stats Card
                if (_statsLoaded)
                  FadeTransition(
                    opacity: widget.animationController,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: widget.animationController,
                        curve: Curves.easeOut,
                      )),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatItem(
                              icon: Icons.play_circle_outline_rounded,
                              label: 'Lessons',
                              value: '${_stats['lessons_completed'] ?? 0}',
                              color: const Color(0xFF1A237E),
                            ),
                            Container(width: 1, height: 40, color: Colors.grey[300]),
                            _StatItem(
                              icon: Icons.assignment_turned_in_rounded,
                              label: 'Papers',
                              value: '${_stats['papers_attempted'] ?? 0}',
                              color: const Color(0xFF00897B),
                            ),
                            Container(width: 1, height: 40, color: Colors.grey[300]),
                            _StatItem(
                              icon: Icons.quiz_rounded,
                              label: 'MCQ Score',
                              value: (_stats['mcq_exams_taken'] ?? 0) > 0 
                                  ? '${((_stats['avg_mcq_score'] ?? 0) as double).toStringAsFixed(0)}%'
                                  : '--',
                              color: const Color(0xFFFF9800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    ),
  );
}

  
}

class _AnimatedQuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int index;
  final VoidCallback onTap;
  final double? width;  // ✅ Add this

  const _AnimatedQuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.index,
    required this.onTap,
    this.width,  // ✅ Add this
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 400 + (index * 80)),
      curve: Curves.easeOut,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * value),
          child: Opacity(
            opacity: value,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: width,  // ✅ Use width parameter
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: color.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            color.withOpacity(0.15),
                            color.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        size: 28,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: color.withOpacity(0.15),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withOpacity(0.15),
                    color.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 28,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}