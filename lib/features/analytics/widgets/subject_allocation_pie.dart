import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/subject_allocation.dart';

/// Donut chart showing how the student's activity is distributed
/// across subjects.
///
/// Interaction model:
///   • Desktop: hovering a slice or a legend row shows a floating
///     tooltip near the pointer with the activity breakdown.
///   • Mobile: tapping a legend row expands it inline to reveal the
///     same breakdown beneath.
///
/// The legend is a vertical list with name + percentage right-aligned,
/// so the numbers line up in a column like a proper table.
class SubjectAllocationPie extends StatefulWidget {
  final List<SubjectAllocation> allocation;
  final String windowLabel;

  const SubjectAllocationPie({
    super.key,
    required this.allocation,
    this.windowLabel = 'last 30 days',
  });

  @override
  State<SubjectAllocationPie> createState() => _SubjectAllocationPieState();
}

class _SubjectAllocationPieState extends State<SubjectAllocationPie> {
  /// Index of the slice currently under the pointer (desktop hover).
  /// -1 = nothing hovered.
  int _hoveredIndex = -1;

  /// Index of the legend row currently expanded (mobile tap).
  /// -1 = nothing expanded.
  int _expandedIndex = -1;

  /// Cached layout geometry so we can position the floating tooltip
  /// relative to the donut on desktop.
  
  List<_Slice> _buildSlices() {
    final active = widget.allocation.where((a) => a.total > 0).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    if (active.isEmpty) return [];

    if (active.length <= 6) {
      return active
          .map(
            (a) => _Slice(
              label: a.subjectName,
              color: AppColors.fromHex(a.colorHex),
              value: a.total,
              raw: a,
            ),
          )
          .toList();
    }

    final top5 = active.take(5).toList();
    final rest = active.skip(5).toList();
    final otherTotal = rest.fold<int>(0, (s, a) => s + a.total);

    return [
      ...top5.map(
        (a) => _Slice(
          label: a.subjectName,
          color: AppColors.fromHex(a.colorHex),
          value: a.total,
          raw: a,
        ),
      ),
      _Slice(
        label: 'Other',
        color: AppColors.textTertiary,
        value: otherTotal,
        raw: null,
      ),
    ];
  }

    @override
  Widget build(BuildContext context) {
    final slices = _buildSlices();
    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppSpacing.breakpointDesktop;
    final total = slices.fold<int>(0, (s, e) => s + e.value);
    final showTooltip = isDesktop && _hoveredIndex >= 0 && slices.isNotEmpty;

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: AppColors.shadowCard,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(windowLabel: widget.windowLabel),
              const SizedBox(height: AppSpacing.xl),
              if (slices.isEmpty)
                const _EmptyState()
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 620;
                    return isWide
                        ? _WideLayout(
                            slices: slices,
                            hoveredIndex: _hoveredIndex,
                            expandedIndex: _expandedIndex,
                            isDesktop: isDesktop,
                            onHover: (i) => setState(() => _hoveredIndex = i),
                            onExpand: (i) => setState(() {
                              _expandedIndex =
                                  _expandedIndex == i ? -1 : i;
                            }),
                          )
                        : _NarrowLayout(
                            slices: slices,
                            hoveredIndex: _hoveredIndex,
                            expandedIndex: _expandedIndex,
                            isDesktop: isDesktop,
                            onHover: (i) => setState(() => _hoveredIndex = i),
                            onExpand: (i) => setState(() {
                              _expandedIndex =
                                  _expandedIndex == i ? -1 : i;
                            }),
                          );
                  },
                ),
            ],
          ),
          // Tooltip anchored to top-right of the card body. Never
          // overlaps the header (left) or the legend (bottom-right).
          if (showTooltip)
            Positioned(
              top: 0,
              right: 0,
              child: IgnorePointer(
                child: _FloatingTooltip(
                  slice: slices[_hoveredIndex],
                  total: total,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Layout variants
// ─────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final List<_Slice> slices;
  final int hoveredIndex;
  final int expandedIndex;
  final bool isDesktop;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onExpand;

  const _WideLayout({
    required this.slices,
    required this.hoveredIndex,
    required this.expandedIndex,
    required this.isDesktop,
    required this.onHover,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 280,
          height: 280,
          child: RepaintBoundary(
            child: _Donut(
              slices: slices,
              hoveredIndex: hoveredIndex,
              onHover: onHover,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxl),
        Expanded(
          child: _Legend(
            slices: slices,
            hoveredIndex: hoveredIndex,
            expandedIndex: expandedIndex,
            isDesktop: isDesktop,
            onHover: onHover,
            onExpand: onExpand,
          ),
        ),
      ],
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  final List<_Slice> slices;
  final int hoveredIndex;
  final int expandedIndex;
  final bool isDesktop;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onExpand;

  const _NarrowLayout({
    required this.slices,
    required this.hoveredIndex,
    required this.expandedIndex,
    required this.isDesktop,
    required this.onHover,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 240,
          height: 240,
          child: RepaintBoundary(
            child: _Donut(
              slices: slices,
              hoveredIndex: hoveredIndex,
              onHover: onHover,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Legend(
          slices: slices,
          hoveredIndex: hoveredIndex,
          expandedIndex: expandedIndex,
          isDesktop: false,
          onHover: onHover,
          onExpand: onExpand,
        ),
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────
// Donut
// ─────────────────────────────────────────────────────────────

class _Donut extends StatelessWidget {
  final List<_Slice> slices;
  final int hoveredIndex;
  final ValueChanged<int> onHover;

  const _Donut({
    required this.slices,
    required this.hoveredIndex,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (s, e) => s + e.value);

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 68,
            startDegreeOffset: -90,
            sections: [
              for (var i = 0; i < slices.length; i++)
                PieChartSectionData(
                  value: slices[i].value.toDouble(),
                  color: slices[i].color,
                  radius: hoveredIndex == i ? 30 : 26,
                  showTitle: false,
                  borderSide: hoveredIndex == i
                      ? const BorderSide(color: Colors.white, width: 2)
                      : BorderSide.none,
                ),
            ],
            pieTouchData: PieTouchData(
              enabled: true,
              touchCallback: (event, response) {
                if (event is FlPointerExitEvent) {
                  onHover(-1);
                  return;
                }
                final section = response?.touchedSection;
                if (section != null) {
                  onHover(section.touchedSectionIndex);
                } else {
                  onHover(-1);
                }
              },
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _compactNumber(total),
              style: AppTextStyles.displayStat.copyWith(
                fontSize: 30,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'activities',
              style: AppTextStyles.captionXs.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────
// Legend — vertical rows with right-aligned percentages
// ─────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final List<_Slice> slices;
  final int hoveredIndex;
  final int expandedIndex;
  final bool isDesktop;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onExpand;

  const _Legend({
    required this.slices,
    required this.hoveredIndex,
    required this.expandedIndex,
    required this.isDesktop,
    required this.onHover,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < slices.length; i++)
          _LegendRow(
            slice: slices[i],
            percent: total == 0 ? 0 : (slices[i].value / total) * 100,
            highlighted: hoveredIndex == i,
            expanded: expandedIndex == i,
            isDesktop: isDesktop,
            onHover: (h) => onHover(h ? i : -1),
            onTap: () => onExpand(i),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final _Slice slice;
  final double percent;
  final bool highlighted;
  final bool expanded;
  final bool isDesktop;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  const _LegendRow({
    required this.slice,
    required this.percent,
    required this.highlighted,
    required this.expanded,
    required this.isDesktop,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: isDesktop ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isDesktop ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppSpacing.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: highlighted || expanded
                ? slice.color.withOpacity(0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            border: Border.all(
              color: highlighted || expanded
                  ? slice.color.withOpacity(0.20)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: AppSpacing.fast,
                    width: highlighted ? 12 : 10,
                    height: highlighted ? 12 : 10,
                    decoration: BoxDecoration(
                      color: slice.color,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: highlighted
                          ? [
                              BoxShadow(
                                color: slice.color.withOpacity(0.4),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      slice.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: highlighted
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Percentage — right-aligned, monospace-ish for
                  // column alignment across rows.
                  Text(
                    '${percent.toStringAsFixed(0)}%',
                    style: AppTextStyles.labelMd.copyWith(
                      color: highlighted
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
              // Expanded breakdown (mobile tap)
              AnimatedSize(
                duration: AppSpacing.normal,
                curve: AppSpacing.easeOut,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.md,
                          left: 22,
                        ),
                        child: _Breakdown(slice: slice),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Breakdown (used inside expanded legend + floating tooltip)
// ─────────────────────────────────────────────────────────────

class _Breakdown extends StatelessWidget {
  final _Slice slice;
  final bool compact;

  const _Breakdown({required this.slice, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final entries = slice.raw?.breakdown ?? const <MapEntry<String, int>>[];

    if (entries.isEmpty) {
      return Text(
        '${slice.value} activities',
        style: AppTextStyles.caption,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: slice.color.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    e.key,
                    style: compact
                        ? AppTextStyles.captionXs.copyWith(
                            color: Colors.white.withOpacity(0.75),
                          )
                        : AppTextStyles.caption,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '${e.value}',
                  style: (compact
                          ? AppTextStyles.captionXs
                          : AppTextStyles.caption)
                      .copyWith(
                    fontWeight: FontWeight.w700,
                    color: compact ? Colors.white : AppColors.textPrimary,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Floating tooltip (desktop)
// ─────────────────────────────────────────────────────────────

class _FloatingTooltip extends StatelessWidget {
  final _Slice slice;
  final int total;

  const _FloatingTooltip({
    required this.slice,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: slice.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  slice.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${slice.value}',
                style: AppTextStyles.labelMd.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: Colors.white.withOpacity(0.12)),
          const SizedBox(height: 6),
          _Breakdown(slice: slice, compact: true),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header + Empty
// ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String windowLabel;
  const _Header({required this.windowLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Subject Focus', style: AppTextStyles.headingMd),
              const SizedBox(height: 2),
              Text(
                'Tap a subject to see the breakdown',
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
            windowLabel,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
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
                Icons.pie_chart_outline_rounded,
                size: 26,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No activity yet',
              style: AppTextStyles.headingSm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Start studying to see your subject mix.',
              style: AppTextStyles.captionXs,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────

class _Slice {
  final String label;
  final Color color;
  final int value;
  final SubjectAllocation? raw;

  const _Slice({
    required this.label,
    required this.color,
    required this.value,
    required this.raw,
  });
}

String _compactNumber(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '${(n / 1000).toStringAsFixed(0)}k';
}