import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

/// One quick action entry.
class QuickAction {
  final String navKey; // matches a NavItem.key in nav_registry
  final String label;
  final String? sublabel;
  final IconData icon;
  final Color accent;

  const QuickAction({
    required this.navKey,
    required this.label,
    this.sublabel,
    required this.icon,
    required this.accent,
  });
}

/// The five most-used destinations, exposed as a premium action row.
///
/// Desktop: 5 tiles in a row.
/// Tablet: wraps to 3+2.
/// Mobile: horizontal scroll row.
///
/// Tapping a tile routes through the same nav registry the sidebar
/// uses — so behavior is identical no matter where the tap came from.
class QuickActionsRow extends StatelessWidget {
  final void Function(String navKey) onNavigate;

  const QuickActionsRow({super.key, required this.onNavigate});

  static const List<QuickAction> _actions = [
    QuickAction(
      navKey: 'ai_tutor',
      label: 'AI Tutor',
      sublabel: 'Ask anything',
      icon: Icons.auto_awesome_rounded,
      accent: Color(0xFF6A1B9A),
    ),
    QuickAction(
      navKey: 'generate_exams',
      label: 'Practice Exam',
      sublabel: 'From question bank',
      icon: Icons.quiz_rounded,
      accent: AppColors.chartAi,
    ),
    QuickAction(
      navKey: 'flashcards',
      label: 'Flashcards',
      sublabel: 'Review & create',
      icon: Icons.style_rounded,
      accent: Color(0xFF8B5CF6),
    ),
    QuickAction(
      navKey: 'summaries',
      label: 'Summaries',
      sublabel: 'Study notes',
      icon: Icons.summarize_rounded,
      accent: Color(0xFF14B8A6),
    ),
    QuickAction(
      navKey: 'exam_history',
      label: 'Exam History',
      sublabel: 'Past attempts',
      icon: Icons.history_rounded,
      accent: AppColors.chartPaper,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            if (w < 560) {
              return _ScrollRow(
                actions: _actions,
                onNavigate: onNavigate,
              );
            }
            final columns = w < 900 ? 3 : 5;
            const gap = AppSpacing.md;
            final totalGap = gap * (columns - 1);
            final tileWidth = (w - totalGap) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < _actions.length; i++)
                  SizedBox(
                    width: tileWidth,
                    child: _QuickActionTile(
                      action: _actions[i],
                      index: i,
                      onTap: () => onNavigate(_actions[i].navKey),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTextStyles.headingMd),
        const SizedBox(height: 2),
        Text(
          'Jump straight into a task',
          style: AppTextStyles.captionXs,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Mobile horizontal scroll
// ─────────────────────────────────────────────────────────────

class _ScrollRow extends StatelessWidget {
  final List<QuickAction> actions;
  final ValueChanged<String> onNavigate;

  const _ScrollRow({required this.actions, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 156,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        padding: EdgeInsets.zero,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) => SizedBox(
          width: 150,
          child: _QuickActionTile(
            action: actions[i],
            index: i,
            onTap: () => onNavigate(actions[i].navKey),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tile
// ─────────────────────────────────────────────────────────────

class _QuickActionTile extends StatefulWidget {
  final QuickAction action;
  final int index;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.action,
    required this.index,
    required this.onTap,
  });

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
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
    final a = widget.action;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
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
            height: 156,
            padding: AppSpacing.kpiCardPadding,
            transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.kpiHoverTint(a.accent)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
              border: Border.all(
                color: _hovered
                    ? a.accent.withOpacity(0.28)
                    : AppColors.border,
                width: 1,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: a.accent.withOpacity(0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                      ...AppColors.shadowCard,
                    ]
                  : AppColors.shadowCard,
            ),
            child: Stack(
              children: [
                // Corner accent glow — appears on hover
                Positioned(
                  top: -30,
                  right: -30,
                  child: AnimatedOpacity(
                    duration: AppSpacing.fast,
                    opacity: _hovered ? 1 : 0,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            a.accent.withOpacity(0.18),
                            a.accent.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconBadge(icon: a.icon, accent: a.accent, hovered: _hovered),
                        const Spacer(),
                        AnimatedOpacity(
                          duration: AppSpacing.fast,
                          opacity: _hovered ? 1 : 0,
                          child: Icon(
                            Icons.arrow_outward_rounded,
                            size: 16,
                            color: a.accent,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headingSm.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (a.sublabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        a.sublabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.captionXs,
                      ),
                    ],
                  ],
                ),
              ],
            ),
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
      width: 42,
      height: 42,
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
          color: accent.withOpacity(hovered ? 0.32 : 0.16),
          width: 1,
        ),
      ),
      child: AnimatedScale(
        duration: AppSpacing.fast,
        scale: hovered ? 1.08 : 1.0,
        child: Icon(icon, size: 20, color: accent),
      ),
    );
  }
}