import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/subject_progress.dart';

/// Per-subject progress list with animated bars.
///
/// Each row shows:
///   • subject name + color dot
///   • a gradient progress bar filled to `passing_potential`
///   • the percentage on the right
///   • an objective count + practice rate line under the bar
///
/// On hover (desktop) the row expands to reveal the full breakdown:
/// objectives, practice pass rate, flashcard mastery, and the blend.
class SubjectProgressList extends StatefulWidget {
  final List<SubjectProgress> subjects;

  const SubjectProgressList({super.key, required this.subjects});

  @override
  State<SubjectProgressList> createState() => _SubjectProgressListState();
}

class _SubjectProgressListState extends State<SubjectProgressList> {
  /// The subject currently hovered (desktop) — reveals the breakdown.
  String? _hoveredId;

  /// Subjects with at least one meaningful metric.
  List<SubjectProgress> _active() {
    final list = widget.subjects.where((s) => !s.isEmpty).toList()
      ..sort((a, b) => b.passingPotential.compareTo(a.passingPotential));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _active();

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(),
          const SizedBox(height: AppSpacing.xl),
          if (subjects.isEmpty)
            const _EmptyState()
          else
            for (var i = 0; i < subjects.length; i++) ...[
              _SubjectRow(
                subject: subjects[i],
                index: i,
                hovered: _hoveredId == subjects[i].subjectId,
                onHover: (h) => setState(
                  () => _hoveredId = h ? subjects[i].subjectId : null,
                ),
              ),
              if (i < subjects.length - 1)
                const SizedBox(height: AppSpacing.lg),
            ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Subject Progress', style: AppTextStyles.headingMd),
              const SizedBox(height: 2),
              Text(
                'Mastery blended from practice, objectives and flashcards',
                style: AppTextStyles.captionXs,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            'Passing potential',
            style: AppTextStyles.captionXs.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// One subject row
// ─────────────────────────────────────────────────────────────

class _SubjectRow extends StatefulWidget {
  final SubjectProgress subject;
  final int index;
  final bool hovered;
  final ValueChanged<bool> onHover;

  const _SubjectRow({
    required this.subject,
    required this.index,
    required this.hovered,
    required this.onHover,
  });

  @override
  State<_SubjectRow> createState() => _SubjectRowState();
}

class _SubjectRowState extends State<_SubjectRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fill;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fill = Tween<double>(
      begin: 0,
      end: (widget.subject.passingPotential / 100).clamp(0.0, 1.0),
    ).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic),
    );
    // Stagger by row.
    Future.delayed(Duration(milliseconds: 60 * widget.index.clamp(0, 8)), () {
      if (mounted) _entrance.forward();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final color = AppColors.fromHex(s.colorHex);

    return MouseRegion(
      onEnter: (_) => widget.onHover(true),
      onExit: (_) => widget.onHover(false),
      child: AnimatedContainer(
        duration: AppSpacing.fast,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: widget.hovered
              ? color.withOpacity(0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          border: Border.all(
            color: widget.hovered
                ? color.withOpacity(0.16)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top row: dot + name ..................... percentage
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    s.subjectName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: AppTextStyles.labelLg.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${s.passingPotential.toStringAsFixed(0)}%',
                  style: AppTextStyles.headingMd.copyWith(
                    color: AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Animated progress bar
            AnimatedBuilder(
              animation: _fill,
              builder: (context, _) {
                return _ProgressBar(
                  fill: _fill.value,
                  color: color,
                  glow: widget.hovered,
                );
              },
            ),

            const SizedBox(height: AppSpacing.sm),

            // Secondary line: objectives + practice
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${s.objectivesMastered} / ${s.objectivesTotal} objectives',
                    style: AppTextStyles.captionXs,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '${s.practicePassRate.toStringAsFixed(0)}% practice',
                  style: AppTextStyles.captionXs.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),

            // Hover breakdown
            AnimatedSize(
              duration: AppSpacing.normal,
              curve: AppSpacing.easeOut,
              child: widget.hovered
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: _Breakdown(subject: s, accent: color),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Progress bar
// ─────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double fill; // 0..1
  final Color color;
  final bool glow;

  const _ProgressBar({
    required this.fill,
    required this.color,
    required this.glow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            // Track fills full width — this is what the bar sits on.
            const SizedBox.expand(),
            // Filled portion
            FractionallySizedBox(
              widthFactor: fill.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withOpacity(0.75),
                      color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: glow
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.35),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Hover breakdown
// ─────────────────────────────────────────────────────────────

class _Breakdown extends StatelessWidget {
  final SubjectProgress subject;
  final Color accent;

  const _Breakdown({required this.subject, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BreakdownRow(
            label: 'Practice pass rate',
            value: '${subject.practicePassRate.toStringAsFixed(0)}%',
            weightLabel: '×50%',
            color: accent,
          ),
          const SizedBox(height: AppSpacing.sm),
          _BreakdownRow(
            label: 'Objectives mastered',
            value: subject.objectivesTotal == 0
                ? '—'
                : '${(subject.objectiveRatio * 100).toStringAsFixed(0)}%',
            weightLabel: '×30%',
            color: accent,
          ),
          const SizedBox(height: AppSpacing.sm),
          _BreakdownRow(
            label: 'Flashcard mastery',
            value: '${subject.flashcardMastery.toStringAsFixed(0)}%',
            weightLabel: '×20%',
            color: accent,
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final String weightLabel;
  final Color color;

  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.weightLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: color.withOpacity(0.6),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          weightLabel,
          style: AppTextStyles.captionXs.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 52,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.labelMd.copyWith(
              color: AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.insights_rounded,
                size: 26,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No subject progress yet',
              style: AppTextStyles.headingSm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Practice exams will start filling these bars.',
              style: AppTextStyles.captionXs,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}