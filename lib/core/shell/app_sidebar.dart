import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'nav_registry.dart';

/// Desktop / tablet sidebar.
///
/// Collapses between wide (240px, labels visible) and narrow (72px,
/// icons only). The two states are separate widget trees swapped via
/// [AnimatedSwitcher] — not a single tree resized mid-animation, which
/// causes transient layout overflows during the transition.
class AppSidebar extends StatelessWidget {
  final List<NavItem> items;
  final String activeKey;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final ValueChanged<NavItem> onSelect;
  final String userName;
  final String userRole;
  final VoidCallback? onAccountTap;

  const AppSidebar({
    super.key,
    required this.items,
    required this.activeKey,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onSelect,
    required this.userName,
    required this.userRole,
    this.onAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppSpacing.normal,
      curve: AppSpacing.easeOut,
      width: collapsed
          ? AppSpacing.sidebarCollapsedWidth
          : AppSpacing.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      // Clip so nothing pokes out during the width tween.
      child: ClipRect(
        child: OverflowBox(
          // Force children to always render at a fixed max width so
          // layout never runs against an intermediate constraint.
          minWidth: 0,
          maxWidth: collapsed
              ? AppSpacing.sidebarCollapsedWidth
              : AppSpacing.sidebarWidth,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: collapsed
                ? AppSpacing.sidebarCollapsedWidth
                : AppSpacing.sidebarWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BrandHeader(collapsed: collapsed),
                const Divider(height: 1, color: AppColors.divider),
                Expanded(
                  child: _NavList(
                    items: items,
                    activeKey: activeKey,
                    collapsed: collapsed,
                    onSelect: onSelect,
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                _UserBlock(
                  collapsed: collapsed,
                  userName: userName,
                  userRole: userRole,
                  onTap: onAccountTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Internal widgets
// ─────────────────────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  final bool collapsed;
  const _BrandHeader({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.topbarHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? AppSpacing.md : AppSpacing.lg,
        ),
        child: Row(
          mainAxisAlignment:
              collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            // Logo — no wrapper. Your PNG already has rounded corners
            // and its own visual identity; the container was fighting it.
            Image.asset(
              'assets/images/logo.png',
              width: collapsed ? 32 : 40,
              height: collapsed ? 32 : 40,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.textInverse,
                  size: 20,
                ),
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(width: AppSpacing.md),
              // Stacked wordmark — AfriNova on top, Academy beneath.
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AfriNova',
                      style: AppTextStyles.wordmarkLight.copyWith(
                        fontSize: 20,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Academy',
                      style: AppTextStyles.wordmarkBold.copyWith(
                        fontSize: 20,
                        color: AppColors.primary,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavList extends StatelessWidget {
  final List<NavItem> items;
  final String activeKey;
  final bool collapsed;
  final ValueChanged<NavItem> onSelect;

  const _NavList({
    required this.items,
    required this.activeKey,
    required this.collapsed,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <String, List<NavItem>>{};
    for (final item in items) {
      final key = item.section ?? '';
      sections.putIfAbsent(key, () => []).add(item);
    }

    return ClipRect(
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        children: [
          for (final entry in sections.entries) ...[
            if (!collapsed && entry.key.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Text(
                  entry.key.toUpperCase(),
                  style: AppTextStyles.overline,
                ),
              ),
            for (final item in entry.value)
              _NavTile(
                item: item,
                active: item.key == activeKey,
                collapsed: collapsed,
                onTap: () => onSelect(item),
              ),
          ],
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.primary : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withOpacity(0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            ),
            child: collapsed
                ? Icon(item.resolvedIcon, size: 20, color: fg)
                : Row(
  mainAxisAlignment: collapsed
      ? MainAxisAlignment.center
      : MainAxisAlignment.start,
  children: [
    Icon(item.resolvedIcon, size: 20, color: fg),
    if (!collapsed) ...[
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Text(
          item.label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          softWrap: false,
          style: AppTextStyles.labelMd.copyWith(color: fg),
        ),
      ),
      // Premium marker: purple diamond, CapCut-style.
            // Premium marker: purple diamond (CapCut-style). When a push
      // item is also premium, we show only the diamond — the arrow
      // and diamond together read as cluttered.
      if (item.isPremium)
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Icon(
            Icons.diamond_rounded,
            size: 14,
            color: Color(0xFF8B5CF6),
          ),
        )
      else if (item.behavior == NavBehavior.push)
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(
            Icons.open_in_new_rounded,
            size: 12,
            color: AppColors.textTertiary,
          ),
        ),
    ],
  ],
),
          ),
        ),
      ),
    );
  }
}

class _UserBlock extends StatelessWidget {
  final bool collapsed;
  final String userName;
  final String userRole;
  final VoidCallback? onTap;

  const _UserBlock({
    required this.collapsed,
    required this.userName,
    required this.userRole,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = userName.trim().isEmpty
        ? '?'
        : userName.trim().split(RegExp(r'\s+')).take(2).map((s) => s[0]).join();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initials.toUpperCase(),
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.textInverse,
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          userName.isEmpty ? 'Student' : userName,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelMd,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userRole.toUpperCase(),
                          style: AppTextStyles.overline,
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}