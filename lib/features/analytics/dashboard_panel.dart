import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/shell/panel_scaffold.dart';
import 'models/analytics_kpis.dart';
import 'services/analytics_service.dart';
import 'widgets/kpi_row.dart';
import 'widgets/trend_chart.dart';
import 'widgets/subject_allocation_pie.dart';
import 'widgets/subject_progress_list.dart';
import 'widgets/quick_actions_row.dart';

/// The dashboard's main content panel.
///
/// Owns the data lifecycle:
///   1. On first build, fetch [AnalyticsSnapshot] via [AnalyticsService].
///   2. Render loading → loaded (or empty) → error.
///   3. Support pull-to-refresh.
///
/// Section layout (top to bottom):
///   • Greeting header
///   • KPI row
///   • Trend chart  (placeholder for now)
///   • Subject pie  (placeholder for now)
///   • Progress list (placeholder for now)
///   • Quick actions (placeholder for now)
class DashboardPanel extends StatefulWidget {
  final String userName;
   final void Function(String navKey) onNavigate;

  const DashboardPanel({super.key, required this.userName, required this.onNavigate});

  @override
  State<DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<DashboardPanel>
    with AutomaticKeepAliveClientMixin {
  final _service = AnalyticsService();
  final _auth = AuthService();

  AnalyticsSnapshot _snapshot = AnalyticsSnapshot.empty;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = _auth.currentUserId;
      if (userId == null) {
        setState(() {
          _loading = false;
          _error = 'Not signed in';
        });
        return;
      }
      final snapshot = await _service.fetchAll(userId);
      
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PanelScaffold(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return _LoadingSkeleton();
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        _GreetingHeader(userName: widget.userName),
        const SizedBox(height: AppSpacing.xl),
        KpiRow(kpis: _snapshot.kpis),
        const SizedBox(height: AppSpacing.xl),
                TrendChart(points: _snapshot.trend),
        const SizedBox(height: AppSpacing.xl),
                SubjectAllocationPie(
          allocation: _snapshot.allocation,
          windowLabel: 'last 30 days',
        ),
        const SizedBox(height: AppSpacing.xl),
                SubjectProgressList(subjects: _snapshot.subjectProgress),
        const SizedBox(height: AppSpacing.xl),
                QuickActionsRow(onNavigate: widget.onNavigate),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Greeting
// ─────────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final String userName;
  const _GreetingHeader({required this.userName});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _dateLabel() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final name = userName.trim().isEmpty ? 'there' : userName.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_dateLabel().toUpperCase(), style: AppTextStyles.overline),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${_greeting()}, $name',
          style: AppTextStyles.displayMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Here\'s how your learning is tracking.',
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Section placeholder — sits where a real widget will land soon.
// ─────────────────────────────────────────────────────────────

class _SectionPlaceholder extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionPlaceholder({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.headingMd),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: AppTextStyles.captionXs),
          const SizedBox(height: AppSpacing.xl),
          Container(
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.insights_rounded,
              size: 32,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Loading + error
// ─────────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: const [
        SizedBox(height: AppSpacing.xxl),
        Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        Center(
          child: Text(
            'Loading your dashboard…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        const Icon(
          Icons.cloud_off_rounded,
          size: 48,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Couldn\'t load your dashboard',
          textAlign: TextAlign.center,
          style: AppTextStyles.headingMd,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: OutlinedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}