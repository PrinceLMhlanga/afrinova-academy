import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

/// A single KPI tile for the dashboard's headline row.
///
/// Premium details:
///   • Fixed height so cards align regardless of footer line count.
///   • Hover lifts the card 2px and reveals a soft accent glow.
///   • Icon badge uses a two-stop gradient, not flat color.
///   • Entrance animation: fade + 4px slide, staggered by [index].
class KpiCard extends StatefulWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String? value;
  final String? footer;
  final Widget? trendChip;

  /// Used to stagger the entrance animation across the row.
  final int index;

  const KpiCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.footer,
    this.trendChip,
    this.index = 0,
  });

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Stagger by index — 60ms per card, capped so the last card
    // doesn't arrive absurdly late on long rows.
    Future.delayed(Duration(milliseconds: 60 * widget.index.clamp(0, 6)), () {
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
    final isEmpty = widget.value == null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.basic,
      child: AnimatedBuilder(
        animation: _entrance,
        builder: (context, child) {
          final t = Curves.easeOut.transform(_entrance.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 6),
              child: child,
            ),
          );
        },
        child: AnimatedContainer(
          duration: AppSpacing.fast,
          curve: AppSpacing.easeOut,
          height: 168,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.kpiHoverTint(widget.accent)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
            border: Border.all(
              color: _hovered
                  ? widget.accent.withOpacity(0.24)
                  : AppColors.border,
              width: 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.accent.withOpacity(0.14),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                    ...AppColors.shadowCard,
                  ]
                : AppColors.shadowCard,
          ),
          child: Stack(
            children: [
              // Corner accent — soft radial hint of the metric color
              Positioned(
                top: -30,
                right: -30,
                child: AnimatedOpacity(
                  duration: AppSpacing.fast,
                  opacity: _hovered ? 1 : 0.35,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          widget.accent.withOpacity(0.16),
                          widget.accent.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Foreground content
              Padding(
                padding: AppSpacing.kpiCardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconBadge(
                          icon: widget.icon,
                          accent: widget.accent,
                          hovered: _hovered,
                        ),
                        const Spacer(),
                        if (widget.trendChip != null) widget.trendChip!,
                      ],
                    ),
                    const Spacer(),
                    Text(
                      isEmpty ? '--' : widget.value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.displayStat.copyWith(
                        color: isEmpty
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (widget.footer != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.footer!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.captionXs,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final bool hovered;

  const _IconBadge({
    required this.icon,
    required this.accent,
    required this.hovered,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppSpacing.fast,
      curve: AppSpacing.easeOut,
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(hovered ? 0.24 : 0.14),
            accent.withOpacity(hovered ? 0.12 : 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        border: Border.all(
          color: accent.withOpacity(hovered ? 0.30 : 0.16),
          width: 1,
        ),
      ),
      child: AnimatedScale(
        duration: AppSpacing.fast,
        scale: hovered ? 1.08 : 1.0,
        child: Icon(icon, size: 18, color: accent),
      ),
    );
  }
}