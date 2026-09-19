import 'package:flutter/material.dart';

import '../../features/ai/ai_tutor_screen.dart';
import '../../features/ai/expert_tutor_selection_screen.dart';
import '../../features/flashcards/my_flashcards_screen.dart';
import '../../features/generated_exams/exam_generator_screen.dart';
import '../../features/generated_exams/exam_history_screen.dart';
import '../../features/summaries/my_summaries_screen.dart';

/// How a nav item behaves when tapped.
enum NavBehavior {
  /// Swaps the content panel inside [AppShell] — no Navigator push.
  /// Requires the target widget to render without its own AppBar
  /// (use [PanelScaffold]).
  panel,

  /// Pushes a full screen onto the Navigator — used for top-level
  /// destinations that still own their AppBar and back button.
  push,
}

/// One entry in the app's navigation.
///
/// `builder` is used for [NavBehavior.panel] items.
/// `onPush` is used for [NavBehavior.push] items.
/// Exactly one of them must be provided.
class NavItem {
  final String key;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final NavBehavior behavior;
  final WidgetBuilder? builder;
  final void Function(BuildContext context)? onPush;
  final String? section;

  /// When true, this item requires an AI subscription / active trial.
  /// The shell itself does not enforce this — premium items are
  /// wrapped in [AIFeatureGuard] at their panel registration site.
  /// The flag exists so the sidebar can show a "PRO" badge next to
  /// the label, and so future code can reason about it uniformly.
  final bool isPremium;

  const NavItem({
    required this.key,
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.behavior,
    this.builder,
    this.onPush,
    this.section,
    this.isPremium = false,
  });

  IconData get resolvedIcon => selectedIcon ?? icon;
}

/// The single source of truth for navigation.
///
/// Both [AppSidebar] and [AppDrawer] read from this list, so the two
/// can never drift. To add a screen to the app, add it here once.
///
/// NOTE: `push` handlers reference screens we haven't migrated yet.
/// They live in the existing app and are pulled in lazily via the
/// route registry in `home_screen.dart` — see Message 4.
class NavRegistry {
  NavRegistry._();

  static const String sectionLearning = 'Learning';
  static const String sectionAchievements = 'Achievements';  
  static const String sectionAi = 'AI Tools';

  /// Panel-backed items — these swap the viewport inside AppShell.
  /// Their widgets must render without their own AppBar.
  static List<NavItem> panels() => const [
        NavItem(
          key: 'dashboard',
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          behavior: NavBehavior.panel,
          section: sectionLearning,
          // builder filled in Message 4 (DashboardPanel)
        ),

        // ── ACHIEVEMENTS ────────────────────────────────────────
        NavItem(
          key: 'leaderboard',
          label: 'Leaderboard',
          icon: Icons.leaderboard_outlined,
          selectedIcon: Icons.leaderboard_rounded,
          behavior: NavBehavior.panel,
          section: sectionAchievements,
        ),
        NavItem(
          key: 'badges',
          label: 'Badges',
          icon: Icons.military_tech_outlined,
          selectedIcon: Icons.military_tech_rounded,
          behavior: NavBehavior.panel,
          section: sectionAchievements,
        ),
        NavItem(
          key: 'referrals',
          label: 'Refer & Earn',
          icon: Icons.card_giftcard_outlined,
          selectedIcon: Icons.card_giftcard_rounded,
          behavior: NavBehavior.panel,
          section: sectionAchievements,
        ),
        // ── AI TOOLS ───────────────────────────────────────────
        
NavItem(
  key: 'expert_tutor',
  label: 'Expert Tutor',
  icon: Icons.school_outlined,
  selectedIcon: Icons.school_rounded,
  behavior: NavBehavior.panel,
  section: sectionAi,
  isPremium: true,
),
NavItem(
  key: 'generate_exams',
  label: 'Generate Exams',
  icon: Icons.generating_tokens_outlined,
  selectedIcon: Icons.generating_tokens_rounded,
  behavior: NavBehavior.panel,
  section: sectionAi,
  isPremium: true,
),
NavItem(
  key: 'exam_history',
  label: 'Exam History',
  icon: Icons.history_outlined,
  selectedIcon: Icons.history_rounded,
  behavior: NavBehavior.panel,
  section: sectionAi,
  isPremium: true,
),
NavItem(
  key: 'flashcards',
  label: 'Flashcards',
  icon: Icons.style_outlined,
  selectedIcon: Icons.style_rounded,
  behavior: NavBehavior.panel,
  section: sectionAi,
  isPremium: true,
),
NavItem(
  key: 'summaries',
  label: 'Summaries',
  icon: Icons.summarize_outlined,
  selectedIcon: Icons.summarize_rounded,
  behavior: NavBehavior.panel,
  section: sectionAi,
  isPremium: true,
),
      ];

  /// Push-backed items — these are top-level destinations that still
  /// own their AppBar. They are intentionally NOT in the panel list.
  ///
  /// The handlers are wired in `home_screen.dart` (Message 4) where
  /// all the existing screen imports live. For now the registry just
  /// declares the shape; the wiring happens at the shell's entry point.
  static List<NavItem> pushes({
    required void Function(BuildContext, String) onPush,
  }) =>
      [
        NavItem(
          key: 'my_subjects',
          label: 'My Subjects',
          icon: Icons.book_outlined,
          selectedIcon: Icons.book_rounded,
          behavior: NavBehavior.push,
          section: sectionLearning,
          onPush: (ctx) => onPush(ctx, 'my_subjects'),
        ),
        NavItem(
          key: 'my_tutors',
          label: 'My Tutors',
          icon: Icons.people_outline,
          selectedIcon: Icons.people_rounded,
          behavior: NavBehavior.push,
          section: sectionLearning,
          onPush: (ctx) => onPush(ctx, 'my_tutors'),
        ),
        NavItem(
          key: 'mcq_exams',
          label: 'MCQ Exams',
          icon: Icons.quiz_outlined,
          selectedIcon: Icons.quiz_rounded,
          behavior: NavBehavior.push,
          section: sectionLearning,
          onPush: (ctx) => onPush(ctx, 'mcq_exams'),
        ),
        NavItem(
          key: 'exam_papers',
          label: 'Exam Papers',
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment_rounded,
          behavior: NavBehavior.push,
          section: sectionLearning,
          onPush: (ctx) => onPush(ctx, 'exam_papers'),
        ),
        NavItem(
          key: 'progress',
          label: 'Progress',
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics_rounded,
          behavior: NavBehavior.push,
          section: sectionLearning,
          onPush: (ctx) => onPush(ctx, 'progress'),
        ),
        NavItem(
          key: 'resources',
          label: 'Resources',
          icon: Icons.library_books_outlined,
          selectedIcon: Icons.library_books_rounded,
          behavior: NavBehavior.push,
          section: sectionLearning,
          onPush: (ctx) => onPush(ctx, 'resources'),
        ),
        NavItem(
          key: 'live_lessons',
          label: 'Live Lessons',
          icon: Icons.live_tv_outlined,
          selectedIcon: Icons.live_tv_rounded,
          behavior: NavBehavior.push,
          section: sectionLearning,
          onPush: (ctx) => onPush(ctx, 'live_lessons'),
        ),
        NavItem(
  key: 'ai_tutor',
  label: 'AI Tutor',
  icon: Icons.auto_awesome_outlined,
  selectedIcon: Icons.auto_awesome_rounded,
  behavior: NavBehavior.push,
  section: sectionAi,
  isPremium: true,
  onPush: (ctx) => onPush(ctx, 'ai_tutor'),
),
      ];

  /// Full nav list in render order: panels first (grouped), then pushes.
  static List<NavItem> all({
    required void Function(BuildContext, String) onPush,
  }) =>
      [...panels(), ...pushes(onPush: onPush)];

  /// Builder lookup for panel items by key.
  /// Populated in Message 4 when DashboardPanel and the migrated
  /// premium screens are ready. Kept here so the sidebar/drawer can
  /// resolve a `builder` from a `NavItem` without knowing the screens.
  static final Map<String, WidgetBuilder> _panelBuilders = {};

  static void registerPanel(String key, WidgetBuilder builder) {
    _panelBuilders[key] = builder;
  }

  static WidgetBuilder? panelBuilderFor(String key) => _panelBuilders[key];
}