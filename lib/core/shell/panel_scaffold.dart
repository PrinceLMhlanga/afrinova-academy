import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Wrapper for screens that live inside [AppShell] as panels.
///
/// Behaves like a Scaffold but *without* an AppBar — the shell's
/// topbar owns the header. Panels use this instead of `Scaffold`
/// so they don't end up with two bars stacked on top of each other.
///
/// When a panel needs its own actions (e.g. a "New" button on the
/// flashcards screen), pass them via [actions] and they'll render
/// inline at the top of the panel content.
class PanelScaffold extends StatelessWidget {
  final Widget child;
  final List<Widget> actions;
  final EdgeInsets? padding;
  final Color? background;

  const PanelScaffold({
    super.key,
    required this.child,
    this.actions = const [],
    this.padding,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >=
        AppSpacing.breakpointDesktop;

    return Container(
      color: background ?? Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (actions.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? AppSpacing.xxl : AppSpacing.lg,
                AppSpacing.lg,
                isDesktop ? AppSpacing.xxl : AppSpacing.lg,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          Expanded(
            child: Padding(
              padding: padding ??
                  (isDesktop
                      ? AppSpacing.pagePaddingDesktop
                      : AppSpacing.pagePaddingMobile),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small helper for panels that want a section title inside the
/// panel body (distinct from the shell's topbar title).
class PanelSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const PanelSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.headingLg),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: AppTextStyles.bodySm),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}