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
import '../account/my_account_screen.dart';
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
import 'teacher_pricing_screen.dart';
import '../tutoring/teacher_students_screen.dart';

// ===== ADMIN ACTION DATA CLASS =====
class AdminActionData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const AdminActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class TeacherDashboard extends StatefulWidget {
  final String userName;
  final String? userDisplayName;
  final String userRole;
  final VoidCallback onLogout;
  final List<AdminActionData>? extraActions; // Updated type

  const TeacherDashboard({
    super.key,
    required this.userName,
    this.userDisplayName,
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
  Map<String, String> _dailyQuote = {'quote': '', 'author': ''};

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

  Future<void> _loadDailyQuote() async {
    try {
      final response = await Supabase.instance.client
          .from('daily_quotes')
          .select('quote, author')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      if (response.isNotEmpty) {
        final random = response[DateTime.now().millisecond % response.length];
        _dailyQuote = {
          'quote': random['quote'] as String,
          'author': random['author'] as String,
        };
      }
    } catch (e) {
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

      final exams = await _examService.getTeacherExams(userId);
      final lessonsResponse = await Supabase.instance.client
          .from('lessons')
          .select('id')
          .eq('teacher_id', userId);

      final enrollmentsResponse = await Supabase.instance.client
          .from('enrollments')
          .select('student_id')
          .eq('teacher_id', userId)
          .inFilter('status', ['paid', 'approved']);

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
    if (hour < 12) return '☀️ Good Morning,';
    if (hour < 17) return '🌤️ Good Afternoon,';
    return '🌙 Good Evening,';
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
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
            ],
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
            // AppBar
            SliverAppBar(
              expandedHeight: 160,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
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
                  _buildWelcomeCard(),
                  const SizedBox(height: 20),

                  // Stats Row
                  _buildStatsRow(),
                  const SizedBox(height: 28),

                  // ===== TEACHER TOOLS CATEGORIES =====
                  // Content Management
                  _buildCategoryCard(
                    title: 'Content Management',
                    icon: Icons.folder_rounded,
                    color: const Color(0xFF1A237E),
                    features: [
                      _FeatureItem(
                        icon: Icons.video_call_rounded,
                        label: 'Upload Lesson',
                        color: const Color(0xFF1A237E),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const UploadLessonScreen()),
                          );
                          _loadStats();
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.upload_file_rounded,
                        label: 'Upload Resources',
                        color: const Color(0xFF9C27B0),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const UploadResourceScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.folder_open_rounded,
                        label: 'My Uploads',
                        color: const Color(0xFF6A1B9A),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MyUploadsScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.video_library_rounded,
                        label: 'My Lessons',
                        color: const Color(0xFF0288D1),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MyLessonsScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Exams & Assessments
                  _buildCategoryCard(
                    title: 'Exams & Assessments',
                    icon: Icons.quiz_rounded,
                    color: const Color(0xFFFF9800),
                    features: [
                      _FeatureItem(
                        icon: Icons.quiz_outlined,
                        label: 'Create MCQ Exam',
                        color: const Color(0xFFFF9800),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ExamCreatorScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.assignment_rounded,
                        label: 'Create Paper',
                        color: const Color(0xFF00897B),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ExamPaperEditorScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.assignment_rounded,
                        label: 'Manage Papers',
                        color: const Color(0xFF5C6BC0),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ManagePapersScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.folder_outlined,
                        label: 'My Exams',
                        color: const Color(0xFFE65100),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MyExamsScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Live Teaching
                  _buildCategoryCard(
                    title: 'Live Teaching',
                    icon: Icons.live_tv_rounded,
                    color: Colors.red,
                    features: [
                      _FeatureItem(
                        icon: Icons.live_tv_rounded,
                        label: 'Go Live',
                        color: Colors.red,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GoLiveScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.schedule_rounded,
                        label: 'Live Lessons',
                        color: const Color(0xFFE65100),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ScheduledLessonsScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  // One-on-One Tutoring
_buildCategoryCard(
  title: 'One-on-One Tutoring',
  icon: Icons.chat_rounded,
  color: const Color(0xFF5C6BC0),
  features: [
    _FeatureItem(
      icon: Icons.chat_rounded,
      label: 'Student Chats',
      color: const Color(0xFF5C6BC0),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeacherStudentsScreen()),
        );
      },
    ),
   
  ],
),
                  const SizedBox(height: 24),


                  // Class Management
                  _buildCategoryCard(
                    title: 'Class Management',
                    icon: Icons.people_rounded,
                    color: const Color(0xFF4CAF50),
                    features: [
                      _FeatureItem(
                        icon: Icons.class_rounded,
                        label: 'My Classes',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TeacherClassesScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.people_outline_rounded,
                        label: 'Student Requests',
                        color: const Color(0xFF009688),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const EnrollmentRequestsScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.people_rounded,
                        label: 'My Students',
                        color: const Color(0xFF4CAF50),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MyStudentsScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
                        icon: Icons.analytics_outlined,
                        label: 'Performance',
                        color: const Color(0xFF4CAF50),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const StudentPerformanceScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Finances
                  _buildCategoryCard(
                    title: 'Finances',
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF795548),
                    features: [
                      _FeatureItem(
                        icon: Icons.account_balance_wallet_rounded,
                        label: 'My Wallet',
                        color: const Color(0xFF4CAF50),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const WalletScreen()),
                          );
                        },
                      ),
                      _FeatureItem(
      icon: Icons.price_change,           // ✅ New
      label: 'My Pricing',                // ✅ New
      color: const Color(0xFFFF9800),     // ✅ New
      onTap: () {                         // ✅ New
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeacherPricingScreen()),
        );
      },
    ),
                      _FeatureItem(
                        icon: Icons.account_balance_rounded,
                        label: 'Payout Accounts',
                        color: const Color(0xFF795548),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PayoutAccountScreen()),
                          );
                        },
                      ),
                    ],
                  ),

  if (widget.userRole == 'admin' && widget.extraActions != null && widget.extraActions!.isNotEmpty) ...[
  const SizedBox(height: 24),
  _buildAdminToolsCard(widget.extraActions!),
],

                  const SizedBox(height: 30),

                  // Footer
                  _buildFooter(),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

 

  

  // ===== BUILD ADMIN TOOLS CARD =====
// ===== BUILD ADMIN TOOLS CARD =====
Widget _buildAdminToolsCard(List<AdminActionData> actions) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFF4CAF50).withOpacity(0.08),
          const Color(0xFF4CAF50).withOpacity(0.03),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: const Color(0xFF4CAF50).withOpacity(0.3),
        width: 2,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Admin Tools',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4CAF50),
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${actions.length} items',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Platform administration and oversight',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 16),

        // Admin Features Grid
        // Admin Features Grid
LayoutBuilder(
  builder: (context, constraints) {
    final isSmallScreen = constraints.maxWidth < 400;
    final isVerySmallScreen = constraints.maxWidth < 350;
final crossAxisCount = isVerySmallScreen ? 2 : (isSmallScreen ? 3 : 4);
    
    final spacing = 12.0;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final cardWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: actions.asMap().entries.map((entry) {
                final index = entry.key;
                final action = entry.value;
                return _AnimatedFeatureCard(
                  icon: action.icon,
                  label: action.title,
                  color: action.color,
                  index: index,
                  width: cardWidth,
                  onTap: action.onTap,
                );
              }).toList(),
            );
          },
        ),
      ],
    ),
  );
}

  // ===== WELCOME CARD =====
  Widget _buildWelcomeCard() {
    return FadeTransition(
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                          widget.userRole == 'admin' ? 'Administrator' : 'Teacher',
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
              Text(
                _getGreeting(),
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.userDisplayName ?? widget.userName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 1,
                color: Colors.white.withOpacity(0.15),
              ),
              const SizedBox(height: 16),
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
    );
  }

  // ===== STATS ROW =====
  Widget _buildStatsRow() {
    return FadeTransition(
      opacity: _animationController,
      child: Row(
        children: [
          Expanded(
            child: _AnimatedStatCard(
              icon: Icons.video_library_rounded,
              label: 'Lessons',
              value: '$_totalLessons',
              color: const Color(0xFF1A237E),
              index: 0,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _AnimatedStatCard(
              icon: Icons.quiz_rounded,
              label: 'Exams',
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
    );
  }

  // ===== CATEGORY CARD (matches premium features style) =====
  Widget _buildCategoryCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<_FeatureItem> features,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.08),
            color.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${features.length} items',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _getCategorySubtitle(title),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),

          // Features Grid
          // Features Grid
LayoutBuilder(
  builder: (context, constraints) {
    final isSmallScreen = constraints.maxWidth < 400;
    final isVerySmallScreen = constraints.maxWidth < 350;
final crossAxisCount = isVerySmallScreen ? 2 : (isSmallScreen ? 3 : 4);
    final spacing = 12.0;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final cardWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: features.asMap().entries.map((entry) {
                  final index = entry.key;
                  final feature = entry.value;
                  return _AnimatedFeatureCard(
                    icon: feature.icon,
                    label: feature.label,
                    color: feature.color,
                    index: index,
                    width: cardWidth,
                    onTap: feature.onTap,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _getCategorySubtitle(String title) {
    switch (title) {
      case 'Content Management':
        return 'Create and manage your teaching materials';
      case 'Exams & Assessments':
        return 'Build exams, papers, and track progress';
      case 'Live Teaching':
        return 'Go live and schedule lessons';
      case 'One-on-One Tutoring':
        return 'Beta';
      case 'Class Management':
        return 'Manage students, classes, and requests';
      case 'Finances':
        return 'Track earnings and manage payments';
      case 'Admin Tools':
        return 'Platform administration and oversight';
      default:
        return '';
    }
  }

  // ===== FOOTER =====
  Widget _buildFooter() {
    return FadeTransition(
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
    );
  }
}

// ===== FEATURE ITEM MODEL =====
class _FeatureItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  _FeatureItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

// ===== ADMIN ACTION (for extraActions) =====
class _AdminAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // This is just a data container - actual rendering happens in TeacherDashboard
    return const SizedBox.shrink();
  }

  // Expose properties for extraction
  IconData get getIcon => icon;
  String get getTitle => title;
  String get getSubtitle => subtitle;
  Color get getColor => color;
  VoidCallback get getOnTap => onTap;
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
                    child: Icon(icon, size: 24, color: color),
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    tween: Tween<double>(begin: 0, end: double.tryParse(value) ?? 0),
                    builder: (context, animation, child) {
                      return Text(
                        animation.toInt().toString(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
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

// ===== ANIMATED FEATURE CARD =====
class _AnimatedFeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int index;
  final VoidCallback onTap;
  final double width;

  const _AnimatedFeatureCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.index,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 400 + (index * 80)),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * value),
          child: Opacity(
            opacity: value,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: width,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.12),
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
                  mainAxisSize: MainAxisSize.min,
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
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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