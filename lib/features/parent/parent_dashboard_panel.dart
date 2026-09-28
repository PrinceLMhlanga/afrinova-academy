import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/shell/panel_scaffold.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../analytics/models/analytics_kpis.dart';
import '../analytics/models/subject_progress.dart';
import '../analytics/models/trend_point.dart';
import '../analytics/widgets/kpi_row.dart';
import '../analytics/widgets/subject_progress_list.dart';
import '../analytics/widgets/trend_chart.dart';
import 'models/child_summary.dart';
import 'services/parent_service.dart';
import '../analytics/widgets/subject_allocation_pie.dart';
import '../analytics/models/subject_allocation.dart';

/// The parent dashboard panel.
///
/// Loads the parent's active-linked children, then displays the
/// selected child's stats using the same widgets as the student
/// dashboard. Realtime refreshes on activity-table changes for the
/// currently selected child.
class ParentDashboardPanel extends StatefulWidget {
  final String userName;
  final void Function(String navKey)? onNavigate;

  const ParentDashboardPanel({
    super.key,
    required this.userName,
    this.onNavigate,
  });

  @override
  State<ParentDashboardPanel> createState() => _ParentDashboardPanelState();
}

class _ParentDashboardPanelState extends State<ParentDashboardPanel>
    with AutomaticKeepAliveClientMixin {
  final _service = ParentService();

  List<ChildSummary> _children = const [];
  ChildSummary? _selected;

  AnalyticsKpis _kpis = AnalyticsKpis.empty;
  List<TrendPoint> _trend = const [];
  List<SubjectProgress> _subjectProgress = const [];
  List<SubjectAllocation> _subjectAllocation = const [];

  bool _loading = true;
  bool _loadingChild = false;
  String? _error;

  // Realtime subscription for the current child's activity tables.
  final List<StreamSubscription> _activitySubs = [];
  Timer? _refetchDebounce;
  String? _subscribedChildId;

  @override
  bool get wantKeepAlive => true;

  StreamSubscription<List<Map<String, dynamic>>>? _linksSub;

@override
void initState() {
  super.initState();
  _bootstrap();
}

@override
void dispose() {
  _cancelActivitySubs();
  _linksSub?.cancel();
  _refetchDebounce?.cancel();
  super.dispose();
}

  // ─────────────────────────────────────────────────────────────
  // Bootstrap
  // ─────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
  // Wait for auth
  for (var i = 0; i < 30; i++) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session?.accessToken != null) break;
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
  }
  if (!mounted) return;

  await _loadChildren();
  _subscribeToLinks();
}

  void _subscribeToLinks() {
  final parentId = Supabase.instance.client.auth.currentUser?.id;
  if (parentId == null) return;

  var firstEventSeen = false;

  _linksSub = Supabase.instance.client
      .from('parent_student_links')
      .stream(primaryKey: ['id'])
      .eq('parent_id', parentId)
      .listen(
    (rows) {
      if (!firstEventSeen) {
        firstEventSeen = true;
        return;
      }
      // A link was added, changed status, or removed.
      _reloadChildrenFromStream(rows);
    },
    onError: (e) =>
        debugPrint('[ParentDashboardPanel] links stream error: $e'),
  );
}

Timer? _linksDebounce;

void _reloadChildrenFromStream(List<Map<String, dynamic>> rows) {
  _linksDebounce?.cancel();
  _linksDebounce = Timer(const Duration(milliseconds: 500), () {
    if (mounted) _loadChildren();
  });
}

  Future<void> _loadChildren() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final children = await _service.getActiveChildrenTyped();
      if (!mounted) return;

      setState(() {
        _children = children;
        _selected = children.isNotEmpty ? children.first : null;
      });

      if (_selected != null) {
        await _loadChildData(_selected!.studentId);
        _subscribeToActivity(_selected!.studentId);
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadChildData(String studentId) async {
  setState(() => _loadingChild = true);

  try {
    final results = await Future.wait([
      _service.getChildKpis(studentId),
      _service.getChildTrend(studentId),
      _service.getChildSubjectProgress(studentId),
      _service.getChildAllocation(studentId),   // ← new
    ]);

    if (!mounted) return;
    setState(() {
      _kpis = results[0] as AnalyticsKpis;
      _trend = results[1] as List<TrendPoint>;
      _subjectProgress = results[2] as List<SubjectProgress>;
      _subjectAllocation = results[3] as List<SubjectAllocation>;  // ← new
      _loadingChild = false;
      _loading = false;
    });
  } catch (e) {
    debugPrint('[ParentDashboardPanel] _loadChildData failed: $e');
    if (!mounted) return;
    setState(() {
      _loadingChild = false;
      _loading = false;
    });
  }
}

 

  // ─────────────────────────────────────────────────────────────
  // Realtime
  // ─────────────────────────────────────────────────────────────

  void _subscribeToActivity(String studentId) {
    // Don't double-subscribe.
    if (_subscribedChildId == studentId && _activitySubs.isNotEmpty) return;
    _cancelActivitySubs();
    _subscribedChildId = studentId;

    const tables = [
      'practice_exam_history',
      'exam_attempts',
      'exam_answers',
    ];

    for (final table in tables) {
      var firstEventSeen = false;
      final sub = Supabase.instance.client
          .from(table)
          .stream(primaryKey: ['id'])
          .eq('student_id', studentId)
          .listen(
        (_) {
          if (!firstEventSeen) {
            firstEventSeen = true;
            return;
          }
          _scheduleRefetch();
        },
        onError: (e) => debugPrint(
          '[ParentDashboardPanel] $table stream error: $e',
        ),
      );
      _activitySubs.add(sub);
    }
  }

  void _cancelActivitySubs() {
    for (final s in _activitySubs) {
      s.cancel();
    }
    _activitySubs.clear();
    _subscribedChildId = null;
  }

  void _scheduleRefetch() {
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(
      const Duration(milliseconds: 800),
      () {
        if (mounted && _selected != null) {
          _loadChildData(_selected!.studentId);
        }
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Selection
  // ─────────────────────────────────────────────────────────────

  Future<void> _selectChild(ChildSummary child) async {
    if (_selected?.studentId == child.studentId) return;
    setState(() => _selected = child);
    await _loadChildData(child.studentId);
    if (mounted) _subscribeToActivity(child.studentId);
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PanelScaffold(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          if (_selected != null) {
            await _loadChildData(_selected!.studentId);
          } else {
            await _loadChildren();
          }
        },
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _LoadingState();
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _loadChildren);
    }
    if (_children.isEmpty) {
      return const _EmptyState();
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        _GreetingHeader(
  userName: widget.userName,
  childCount: _children.length,
),

        // Child selector (chips) — only if more than one active child.
        if (_children.length > 1) ...[
          const SizedBox(height: AppSpacing.lg),
          _ChildSelector(
            children: _children,
            selectedId: _selected?.studentId,
            onSelect: _selectChild,
          ),
        ] else if (_selected != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ChildHeader(child: _selected!),
        ],

        const SizedBox(height: AppSpacing.xl),

        if (_loadingChild)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else ...[
          KpiRow(kpis: _kpis),
          const SizedBox(height: AppSpacing.xl),

          if (_trend.any((t) => !t.isEmpty)) ...[
            TrendChart(points: _trend),
            const SizedBox(height: AppSpacing.xl),
          ],

          if (_subjectAllocation.isNotEmpty) ...[
  SubjectAllocationPie(
    allocation: _subjectAllocation,
    windowLabel: 'last 30 days',
  ),
  const SizedBox(height: AppSpacing.xl),
],

          if (_subjectProgress.isNotEmpty) ...[
            SubjectProgressList(subjects: _subjectProgress),
            const SizedBox(height: AppSpacing.xl),
          ],
        ],

        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header + child selector
// ─────────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final String userName;
  final int childCount;

  const _GreetingHeader({
    required this.userName,
    required this.childCount,
  });

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
    final name = userName.trim();
    final greeting = name.isEmpty
        ? _greeting()
        : '${_greeting()}, $name';

    final subtitle = childCount == 1
        ? "Here's how your child is progressing."
        : "Here's how your $childCount children are progressing.";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_dateLabel().toUpperCase(), style: AppTextStyles.overline),
        const SizedBox(height: AppSpacing.sm),
        Text(greeting, style: AppTextStyles.displayMedium),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ChildHeader extends StatelessWidget {
  final ChildSummary child;
  const _ChildHeader({required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: AppColors.brandGradient,
            shape: BoxShape.circle,
          ),
          child: Text(
            child.initials,
            style: AppTextStyles.headingMd.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(child.preferredName, style: AppTextStyles.headingLg),
              const SizedBox(height: 2),
              Text(
                child.levelName ?? 'Student',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChildSelector extends StatelessWidget {
  final List<ChildSummary> children;
  final String? selectedId;
  final ValueChanged<ChildSummary> onSelect;

  const _ChildSelector({
    required this.children,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final c = children[i];
          final selected = c.studentId == selectedId;
          return GestureDetector(
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration: AppSpacing.fast,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withOpacity(0.2)
                          : AppColors.surfaceSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      c.initials,
                      style: AppTextStyles.captionXs.copyWith(
                        color: selected
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    c.preferredName,
                    style: AppTextStyles.labelMd.copyWith(
                      color: selected
                          ? Colors.white
                          : AppColors.textPrimary,
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
}

// ─────────────────────────────────────────────────────────────
// States
// ─────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

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
            'Loading your children…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Center(
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.family_restroom_rounded,
              size: 32,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'No linked students yet',
          textAlign: TextAlign.center,
          style: AppTextStyles.headingMd,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Link your child\'s account to see their progress. '
          'Open the Children tab to send a link request.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm,
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