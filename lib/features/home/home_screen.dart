import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_service.dart';
import '../../core/shell/app_shell.dart';
import '../../core/shell/nav_registry.dart';
import '../auth/welcome_screen.dart';
import '../live/student_live_lessons_screen.dart';
import '../teacher/teacher_dashboard.dart';
import '../exams/student_exams_screen.dart';
import '../resources/resource_library_screen.dart';
import '../progress/progress_dashboard.dart';
import '../subjects/my_subjects_screen.dart';
import '../exams/student_papers_screen.dart';
import '../leaderboard/subject_leaderboard_screen.dart';
import '../badges/badges_screen.dart';
import '../admin/admin_dashboard.dart';
import '../trial/trial_banner.dart';
import '../account/my_account_screen.dart';
import '../tutoring/my_tutors_screen.dart';
import '../referrals/referral_screen.dart';
// Analytics panel — the new dashboard
import '../analytics/dashboard_panel.dart';
import '../generated_exams/exam_generator_screen.dart';
import '../generated_exams/exam_history_screen.dart';
import '../flashcards/my_flashcards_screen.dart';
import '../summaries/my_summaries_screen.dart';
import '../ai/ai_tutor_screen.dart';
import '../ai/expert_tutor_selection_screen.dart';
import '../../widgets/ai_feature_guard.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  String _userName = '';
  String? _userDisplayName = '';
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
    try {
      final profile = await _authService.getProfile();
      if (profile != null && mounted) {
        setState(() {
          _userName = profile['full_name'] ?? '';
          _userDisplayName = profile['display_name'] ?? '';
          _userRole = profile['role'] ?? 'student';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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

    // ─────────────────────────────────────────────────────────────
    // Role-based routing
    // ─────────────────────────────────────────────────────────────

    if (_userRole == 'admin') {
      return AdminDashboard(
        userName: _userName,
        userDisplayName:
            _userDisplayName?.isNotEmpty == true ? _userDisplayName : null,
        onLogout: _logout,
      );
    }

    if (_userRole == 'teacher') {
      return TeacherDashboard(
        userName: _userName,
        userDisplayName:
            _userDisplayName?.isNotEmpty == true ? _userDisplayName : null,
        userRole: _userRole,
        onLogout: _logout,
      );
    }

    // ─────────────────────────────────────────────────────────────
    // Student: shell-driven navigation
    // ─────────────────────────────────────────────────────────────

    return _StudentShell(
      userName: _userName,
      onLogout: _logout,
    );
  }
}

// ==================== STUDENT SHELL ====================
//
// Thin wrapper around [AppShell]. Registers the panel builders once,
// then hands off all rendering and navigation to the shell.
//
// This replaces the old feature-grid dashboard. The old greeting card,
// Core Learning grid, Achievements section, and Premium Features
// section are no longer rendered here — the shell's sidebar IS the
// navigation now, and the Dashboard panel (in `analytics/`) is the
// landing content.
class _StudentShell extends StatefulWidget {
  final String userName;
  final VoidCallback onLogout;

  const _StudentShell({
    required this.userName,
    required this.onLogout,
  });

  @override
  State<_StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<_StudentShell> {
  final GlobalKey<AppShellState> _shellKey = GlobalKey<AppShellState>();
  @override
  void initState() {
    super.initState();
    _registerPanels();
  }

  /// Registers all panel builders. Called once at startup — idempotent
  /// so hot-reload doesn't duplicate registrations.
  void _registerPanels() {
  // Dashboard — free
  NavRegistry.registerPanel(
    'dashboard',
    (context) => DashboardPanel(
      userName: widget.userName,
      onNavigate: (key) => _shellKey.currentState?.navigateTo(key),
    ),
  );

  // Achievements — free
  NavRegistry.registerPanel(
    'leaderboard',
    (context) => const SubjectLeaderboardScreen(embedded: true),
  );
  NavRegistry.registerPanel(
    'badges',
    (context) => const BadgesScreen(embedded: true),
  );
  NavRegistry.registerPanel(
    'referrals',
    (context) => const ReferralScreen(embedded: true),
  );

  // Premium panels — guarded
  NavRegistry.registerPanel(
    'ai_tutor',
    (context) => const AIFeatureGuard(
      featureName: 'AI Tutor',
      embedded: true,
      child: AITutorScreen(embedded: true),
    ),
  );
  NavRegistry.registerPanel(
    'expert_tutor',
    (context) => const AIFeatureGuard(
      featureName: 'Expert Tutor',
      embedded: true,
      child: ExpertTutorSelectionScreen(embedded: true),
    ),
  );
  NavRegistry.registerPanel(
    'generate_exams',
    (context) => const AIFeatureGuard(
      featureName: 'Exam Generator',
      embedded: true,
      child: ExamGeneratorScreen(embedded: true),
    ),
  );
  NavRegistry.registerPanel(
    'exam_history',
    (context) => const AIFeatureGuard(
      featureName: 'Exam History',
      embedded: true,
      child: ExamHistoryScreen(embedded: true),
    ),
  );
  NavRegistry.registerPanel(
    'flashcards',
    (context) => const AIFeatureGuard(
      featureName: 'Flashcards',
      embedded: true,
      child: MyFlashcardsScreen(embedded: true),
    ),
  );
  NavRegistry.registerPanel(
    'summaries',
    (context) => const AIFeatureGuard(
      featureName: 'Summaries',
      embedded: true,
      child: MySummariesScreen(embedded: true),
    ),
  );
}

  /// Routes push-behavior nav items to existing full-screen pages.
  /// Called by [AppShell] when the user taps a non-panel nav item.
  void _pushRoute(BuildContext context, String key) {
  Widget? target;
  switch (key) {
    case 'my_subjects':
      target = const MySubjectsScreen();
      break;
    case 'my_tutors':
      target = const MyTutorsScreen();
      break;
    case 'mcq_exams':
      target = const StudentExamsScreen();
      break;
    case 'exam_papers':
      target = const StudentPapersScreen();
      break;
    case 'progress':
      target = const ProgressDashboard();
      break;
    case 'resources':
      target = const ResourceLibraryScreen();
      break;
    case 'live_lessons':
      target = const StudentLiveLessonsScreen();
      break;
    case 'my_account':                              // NEW
      target = const MyAccountScreen();
      break;
  }
  if (target != null && context.mounted) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => target!),
    );
  }
}

  @override
Widget build(BuildContext context) {
  return AppShell(
    key: _shellKey,
    userName: widget.userName,
    userRole: 'student',
    onPushRoute: _pushRoute,
    onNotificationsTap: () {
      // Hook up to a notifications screen when one exists.
    },
    notificationCount: 0,
    onAccountTap: () => _pushRoute(context, 'my_account'),   // NEW
  );
}
}

// ==================== PANEL PLACEHOLDER ====================
//
// Temporary body for premium panels that haven't been migrated yet.
// Will disappear once every screen renders cleanly inside the shell.
class _PanelPlaceholder extends StatelessWidget {
  final String label;
  const _PanelPlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.construction_rounded,
            size: 48,
            color: Colors.grey,
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coming online shortly.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}