import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/trend_point.dart';

/// The dashboard's performance trend chart.
///
/// Three series (AI exams, MCQ exams, exam papers). Days with no data
/// for a series leave a gap in that series' line rather than dropping
/// to zero — that's the honest representation of "no activity".
///
/// Design notes:
///   • Gradient area fill under each line for depth.
///   • Soft shadow on the stroke — not a hard edge.
///   • Vertical crosshair + pill tooltip on touch.
///   • Legend only shows series that have data in this window.
///   • Wrapped in [RepaintBoundary] so scrolling/sidebar toggles
///     don't force a repaint of the chart painter.
class TrendChart extends StatelessWidget {
  final List<TrendPoint> points;

  const TrendChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final hasAnyData = points.any((p) => !p.isEmpty);

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
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 260,
            child: hasAnyData
                ? RepaintBoundary(
                    child: _Chart(points: points),
                  )
                : const _EmptyChartState(),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Legend(points: points),
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
              Text('Performance Trend', style: AppTextStyles.headingMd),
              const SizedBox(height: 2),
              Text(
                'Daily average across your last 10 days',
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
            '0–100%',
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
// Chart
// ─────────────────────────────────────────────────────────────

class _Chart extends StatelessWidget {
  final List<TrendPoint> points;

  const _Chart({required this.points});

  @override
  Widget build(BuildContext context) {
    final series = <_Series>[
      _Series(
        key: 'ai',
        label: 'AI Exams',
        color: AppColors.chartAi,
        spots: _spots(points, (p) => p.aiAvg),
      ),
      _Series(
        key: 'mcq',
        label: 'MCQ Exams',
        color: AppColors.chartMcq,
        spots: _spots(points, (p) => p.mcqAvg),
      ),
      _Series(
        key: 'paper',
        label: 'Exam Papers',
        color: AppColors.chartPaper,
        spots: _spots(points, (p) => p.paperAvg),
      ),
    ].where((s) => s.spots.isNotEmpty).toList();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppColors.chartGrid,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 25,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value < 0 || value > 100) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '${value.toInt()}%',
                    style: AppTextStyles.captionXs.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 30,
    interval: 1,
    getTitlesWidget: (value, meta) {
      final i = value.toInt();
      if (i < 0 || i >= points.length) {
        return const SizedBox.shrink();
      }

      // Adaptive label density: on narrow screens, only show the
      // first, last, and every Nth day in between. Tooltips still
      // reveal the full date on hover/tap.
      final width = MediaQuery.sizeOf(context).width;
      final total = points.length;
      final int step;
      if (width < 400) {
        // Phone — show ~3 labels
        step = (total / 3).ceil().clamp(1, total);
      } else if (width < 700) {
        // Tablet — show ~5 labels
        step = (total / 5).ceil().clamp(1, total);
      } else {
        // Desktop — show all
        step = 1;
      }

      final isFirst = i == 0;
      final isLast = i == total - 1;
      final isStep = (total - 1 - i) % step == 0;

      if (!isFirst && !isLast && !isStep) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _dayLabel(points[i].day),
          style: AppTextStyles.captionXs.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      );
    },
  ),
),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchSpotThreshold: 24,
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((index) {
              return TouchedSpotIndicatorData(
                FlLine(
                  color: barData.color?.withOpacity(0.35) ??
                      AppColors.textTertiary,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
                FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, i) =>
                      FlDotCirclePainter(
                    radius: 5,
                    color: AppColors.surface,
                    strokeWidth: 2.5,
                    strokeColor: bar.color ?? AppColors.primary,
                  ),
                ),
              );
            }).toList();
          },
          touchTooltipData: LineTouchTooltipData(
            // fl_chart 1.2.0 API
            getTooltipColor: (_) => AppColors.textPrimary,
            tooltipBorderRadius:
                BorderRadius.circular(AppSpacing.radiusButton),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            tooltipMargin: 12,
            maxContentWidth: 240,
            getTooltipItems: (touchedSpots) {
              // IMPORTANT: return exactly one item per touched spot.
              // The date is shown once on the first item's title; other
              // items show only their series label + value.
              final dayIndex = touchedSpots.first.x.toInt();
              final day = points[dayIndex].day;

              return touchedSpots.asMap().entries.map((entry) {
                final i = entry.key;
                final spot = entry.value;
                final seriesMeta = series.firstWhere(
                  (s) => s.color == spot.bar.color,
                  orElse: () => series.first,
                );

                // First touched item carries the date as a small
                // eyebrow. Subsequent items skip it.
                final isFirst = i == 0;

                return LineTooltipItem(
                  '',
                  const TextStyle(fontSize: 0, height: 0),
                  children: [
                    if (isFirst)
                      TextSpan(
                        text: '${_fullDateLabel(day)}\n',
                        style: AppTextStyles.overline.copyWith(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 10,
                        ),
                      ),
                    TextSpan(
                      text: '${seriesMeta.label}   ',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withOpacity(0.75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: '${spot.y.toStringAsFixed(1)}%',
                      style: AppTextStyles.labelMd.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          for (final s in series) _lineData(s),
        ],
      ),
    );
  }

  List<FlSpot> _spots(
    List<TrendPoint> points,
    double? Function(TrendPoint) selector,
  ) {
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final v = selector(points[i]);
      if (v != null) {
        spots.add(FlSpot(i.toDouble(), v.clamp(0, 100)));
      }
    }
    return spots;
  }

  LineChartBarData _lineData(_Series s) {
    return LineChartBarData(
      spots: s.spots,
      isCurved: true,
      curveSmoothness: 0.38,
      color: s.color,
      barWidth: 3,
      isStrokeCapRound: true,
      shadow: Shadow(
        color: s.color.withOpacity(0.35),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
          radius: 3.5,
          color: AppColors.surface,
          strokeWidth: 2.5,
          strokeColor: s.color,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            s.color.withOpacity(0.22),
            s.color.withOpacity(0.02),
          ],
        ),
      ),
    );
  }

  String _dayLabel(DateTime day) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${day.day} ${months[day.month - 1]}';
  }

  String _fullDateLabel(DateTime day) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    return '${days[day.weekday - 1]}, ${day.day} ${months[day.month - 1]}';
  }
}

class _Series {
  final String key;
  final String label;
  final Color color;
  final List<FlSpot> spots;

  const _Series({
    required this.key,
    required this.label,
    required this.color,
    required this.spots,
  });
}

// ─────────────────────────────────────────────────────────────
// Legend — only shows series with data in the window
// ─────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final List<TrendPoint> points;

  const _Legend({required this.points});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (points.any((p) => p.aiAvg != null)) {
      chips.add(const _LegendChip(color: AppColors.chartAi, label: 'AI Exams'));
    }
    if (points.any((p) => p.mcqAvg != null)) {
      chips.add(
        const _LegendChip(color: AppColors.chartMcq, label: 'MCQ Exams'),
      );
    }
    if (points.any((p) => p.paperAvg != null)) {
      chips.add(
        const _LegendChip(color: AppColors.chartPaper, label: 'Exam Papers'),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: chips,
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────

class _EmptyChartState extends StatelessWidget {
  const _EmptyChartState();

  @override
  Widget build(BuildContext context) {
    return Center(
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
              Icons.show_chart_rounded,
              size: 26,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No activity in this window',
            style: AppTextStyles.headingSm.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Take a practice exam to start your trend.',
            style: AppTextStyles.captionXs,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}