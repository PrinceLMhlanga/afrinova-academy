import 'package:flutter/material.dart';
import '../../core/auth_service.dart';
import '../../core/subject_service.dart';
import 'my_lessons_screen.dart';
import 'exam_creator_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/exam_service.dart';
import 'my_exams_screen.dart';
import 'upload_resource_screen.dart';
import 'my_uploads_screen.dart';
import 'upload_lesson_screen.dart';

import 'enrollment_requests_screen.dart';
import 'my_students_screen.dart';
import 'go_live_screen.dart';
import 'scheduled_lessons_screen.dart';
import 'exam_paper_editor_screen.dart';
import 'manage_papers_screen.dart';
import 'student_performance_screen.dart';
import 'wallet_screen.dart';
import 'payout_account_screen.dart';
import 'my_classes_screen.dart';

class TeacherDashboard extends StatefulWidget {
  final String userName;
  final String userRole;
  final VoidCallback onLogout;
  final List<Widget>? extraActions;

  const TeacherDashboard({
    super.key,
    required this.userName,
    required this.userRole,
    required this.onLogout,
    this.extraActions,
  });

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard>
    with SingleTickerProviderStateMixin {
  final SubjectService _subjectService = SubjectService();
  final ExamService _examService = ExamService();
  int _totalLessons = 0;
  int _totalExams = 0;
  int _totalStudents = 0;
  bool _isLoading = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _loadDailyQuote();
    _loadStats();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Add this variable to your state class
Map<String, String> _dailyQuote = {'quote': '', 'author': ''};

// Add to initState or load method
Future<void> _loadDailyQuote() async {
  try {
    // Get random quote
    final response = await Supabase.instance.client
    .from('daily_quotes')
    .select('quote, author')
    .eq('is_active', true)
    .order('created_at', ascending: false);  // Get all

    if (response.isNotEmpty) {
  final random = response[DateTime.now().millisecond % response.length];
  _dailyQuote = {
    'quote': random['quote'] as String,
    'author': random['author'] as String,
  };
}
  } catch (e) {
    // Fallback quote if DB fails
    setState(() {
      _dailyQuote = {
        'quote': 'Education is the most powerful weapon which you can use to change the world.',
        'author': 'Nelson Mandela',
      };
    });
  }
}

  Future<void> _loadStats() async {
    try {
      final userId = AuthService().currentUserId;
      if (userId == null) return;

      // Get total exams
      final exams = await _examService.getTeacherExams(userId);
      
      // Get total lessons
      final lessonsResponse = await Supabase.instance.client
          .from('lessons')
          .select('id')
          .eq('teacher_id', userId);

      // ✅ Get students from enrollments (approved or paid)
      final enrollmentsResponse = await Supabase.instance.client
          .from('enrollments')
          .select('student_id')
          .eq('teacher_id', userId)
          .inFilter('status', ['paid', 'approved']);

      // Count unique students
      final uniqueStudents = enrollmentsResponse
          .map((e) => e['student_id'] as String)
          .toSet();

      if (mounted) {
        setState(() {
          _totalExams = exams.length;
          _totalLessons = lessonsResponse.length;
          _totalStudents = uniqueStudents.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) {
    return '☀️ Good Morning,';
  } else if (hour < 17) {
    return '🌤️ Good Afternoon,';
  } else {
    return '🌙 Good Evening,';
  }
}

String _getFormattedDate() {
  final now = DateTime.now();
  final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
}

String _getDailyQuote() {
  final quotes = [
    'Education is the most powerful weapon which you can use to change the world.',
    'The beautiful thing about learning is that no one can take it away from you.',
    'Teaching is the profession that teaches all other professions.',
    'A teacher affects eternity; he can never tell where his influence stops.',
    'The art of teaching is the art of assisting discovery.',
    'Education is not the filling of a pail, but the lighting of a fire.',
    'The best teachers are those who show you where to look but don\'t tell you what to see.',
    'Every student can learn, just not on the same day, or in the same way.',
    'Teaching is the greatest act of optimism.',
    'What the teacher is, is more important than what he teaches.',
  ];
  
  // Use the day of year to pick a consistent quote for the day
  final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
  return quotes[dayOfYear % quotes.length];
}

String _getQuoteAuthor() {
  final authors = [
    '— Nelson Mandela',
    '— B.B. King',
    '— Unknown',
    '— Henry Adams',
    '— Mark Van Doren',
    '— W.B. Yeats',
    '— Alexandra K. Trenfor',
    '— George Evans',
    '— Colleen Wilcox',
    '— Karl Menninger',
  ];
  
  final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
  return authors[dayOfYear % authors.length];
}

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)],
            ),
          ),
          child: Center(
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
                    Icons.school_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(
                  color: Color(0xFF1A237E),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Loading your dashboard...',
                  style: TextStyle(
                    color: Color(0xFF1A237E),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
            // Custom AppBar
           SliverAppBar(
  expandedHeight: 160,
  floating: false,
  pinned: true,
  backgroundColor: Colors.transparent,
  flexibleSpace: LayoutBuilder(
    builder: (context, constraints) {
      // When expanded, maxHeight is ~160, when collapsed it's ~56-60
      final isCollapsed = constraints.maxHeight < 100;
      return Container(
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
                  Icons.school_rounded,
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
              // ✅ Only show badge when collapsed (shrunk)
              if (isCollapsed) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.userRole == 'admin' ? 'Admin' : 'Teacher',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          centerTitle: false,
          titlePadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        ),
      );
    },
  ),
  actions: [
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
                  // Welcome Card
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
          // Top row: Role badge + Date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.userRole == 'admin'
                          ? 'Administrator'
                          : 'Teacher',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _getFormattedDate(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Dynamic greeting
          Text(
            _getGreeting(),
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          
          // User name
          Text(
            widget.userName,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          
          // Divider
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 16),
          
          // Quote of the day
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.format_quote_rounded,
                size: 24,
                color: Colors.white.withOpacity(0.4),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dailyQuote['quote'] ?? 'Education is the most powerful weapon...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.8),
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '— ${_dailyQuote['author'] ?? 'Nelson Mandela'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
),
                  const SizedBox(height: 24),

                  // Stats Cards
                  FadeTransition(
                    opacity: _animationController,
                    child: Row(
                      children: [
                        Expanded(
                          child: _AnimatedStatCard(
                            icon: Icons.video_library_rounded,
                            label: 'My Lessons',
                            value: '$_totalLessons',
                            color: const Color(0xFF1A237E),
                            index: 0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AnimatedStatCard(
                            icon: Icons.quiz_rounded,
                            label: 'My Exams',
                            value: '$_totalExams',
                            color: const Color(0xFFFF9800),
                            index: 1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AnimatedStatCard(
                            icon: Icons.people_rounded,
                            label: 'Students',
                            value: '$_totalStudents',
                            color: const Color(0xFF4CAF50),
                            index: 2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

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
                        'Teacher Tools',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E),
                          letterSpacing: 0.3,
                        ),
                      ),
                      const Spacer(),
                      
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Action Tiles with Animation
                  FadeTransition(
                    opacity: _animationController,
                    child: Column(
                      children: [
                        

_AnimatedActionTile(
  icon: Icons.account_balance_rounded,
  title: 'Payout Accounts',
  subtitle: 'Manage your payment methods',
  color: const Color(0xFF795548),
  index: 15,
  onTap: () {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoutAccountScreen()));
  },
),

const SizedBox(height: 8),                        

_AnimatedActionTile(
  icon: Icons.account_balance_wallet_rounded,
  title: 'My Wallet',
  subtitle: 'View earnings and withdraw funds',
  color: const Color(0xFF4CAF50),
  index: 14,
  onTap: () {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
  },
),
                        const SizedBox(height: 8),
                        _AnimatedActionTile(
                          icon: Icons.people_outline_rounded,
                          title: 'Student Requests',
                          subtitle: 'Approve or reject enrollment requests',
                          color: const Color(0xFF009688),
                          index: 0,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EnrollmentRequestsScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.video_call_rounded,
                          title: 'Upload New Lesson',
                          subtitle: 'Record or upload a video lesson',
                          color: const Color(0xFF1A237E),
                          index: 1,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UploadLessonScreen(),
                              ),
                            );
                            _loadStats();
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.live_tv_rounded,
                          title: 'Go Live',
                          subtitle: 'Start a live classroom session',
                          color: Colors.red,
                          index: 2,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const GoLiveScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.schedule_rounded,
                          title: 'My Live Lessons',
                          subtitle: 'View and start scheduled lessons',
                          color: const Color(0xFFE65100),
                          index: 3,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ScheduledLessonsScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
  icon: Icons.class_rounded,
  title: 'My Classes',
  subtitle: 'Manage subjects & topics by class level',
  color: Colors.blue,
  index: 4,
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TeacherClassesScreen(),  // ✅ Goes to classes first
      ),
    );
  },
),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.video_library_rounded,
                          title: 'My Lessons',
                          subtitle: 'View and manage your uploaded video lessons',
                          color: const Color(0xFF0288D1),
                          index: 5,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyLessonsScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.upload_file_rounded,
                          title: 'Upload Resources',
                          subtitle: 'Upload notes, question papers, and PDFs',
                          color: const Color(0xFF9C27B0),
                          index: 6,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UploadResourceScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.folder_open_rounded,
                          title: 'My Uploads',
                          subtitle: 'View and manage your uploaded files',
                          color: const Color(0xFF6A1B9A),
                          index: 7,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyUploadsScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.quiz_outlined,
                          title: 'Create MCQ Exam',
                          subtitle: 'Build a quiz or test for your students',
                          color: const Color(0xFFFF9800),
                          index: 8,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ExamCreatorScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.assignment_rounded,
                          title: 'Create Exam Paper',
                          subtitle: 'Build structured papers with math & diagrams',
                          color: const Color(0xFF00897B),
                          index: 9,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ExamPaperEditorScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.assignment_rounded,
                          title: 'Manage Papers',
                          subtitle: 'Create, manage, publish and mark exam papers',
                          color: const Color(0xFF5C6BC0),
                          index: 10,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManagePapersScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
  icon: Icons.analytics_outlined,
  title: 'Student Performance',
  subtitle: 'View grades and progress reports',
  color: const Color(0xFF4CAF50),
  index: 11,
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StudentPerformanceScreen(),
      ),
    );
  },
),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.people_rounded,
                          title: 'My Students',
                          subtitle: 'View your enrolled students',
                          color: const Color(0xFF4CAF50),
                          index: 12,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyStudentsScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        _AnimatedActionTile(
                          icon: Icons.folder_outlined,
                          title: 'My Exams',
                          subtitle: 'View and manage your created exams',
                          color: const Color(0xFFE65100),
                          index: 13,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyExamsScreen(),
                              ),
                            );
                          },
                        ),
                        // Admin-specific actions
if (widget.extraActions != null && widget.extraActions!.isNotEmpty) ...[
  const SizedBox(height: 24),
  Row(children: [
    Container(width: 4, height: 24,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF81C784)]),
          borderRadius: BorderRadius.circular(2),
        )),
    const SizedBox(width: 12),
    const Text('Admin Tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
  ]),
  const SizedBox(height: 16),
  ...widget.extraActions!,
],
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Footer
                  FadeTransition(
                    opacity: _animationController,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 16,
                                color: const Color(0xFF1A237E).withOpacity(0.6),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Smart learning for the next generation',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'AfriNova Academy',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ],
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

  int _getActionCount() {
    // Count actual action tiles
    return 14;
  }
}

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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
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
                        colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 28, color: color),
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    tween: Tween<double>(begin: 0, end: double.parse(value)),
                    builder: (context, animation, child) {
                      return Text(
                        animation.toInt().toString(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
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

class _AnimatedActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final int index;
  final VoidCallback onTap;

  const _AnimatedActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 400 + (index * 60)),
      curve: Curves.easeOut,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, animation, child) {
        return Transform.translate(
          offset: Offset(20 * (1 - animation), 0),
          child: Opacity(
            opacity: animation,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Color(0xFF1A237E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: color,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}