import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'nav_registry.dart';

/// Mobile navigation drawer.
///
/// 100% opaque (no backdrop blur) so nav items stay legible over any
/// content. Slides in from the left; closes on tap. Uses the exact
/// same [NavRegistry] as the sidebar.
class AppDrawer extends StatelessWidget {
  final List<NavItem> items;
  final String activeKey;
  final ValueChanged<NavItem> onSelect;
  final String userName;
  final String userRole;
  final VoidCallback? onAccountTap;

  const AppDrawer({
    super.key,
    required this.items,
    required this.activeKey,
    required this.onSelect,
    required this.userName,
    required this.userRole,
    this.onAccountTap,
    
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(AppSpacing.radiusSheet),
          bottomRight: Radius.circular(AppSpacing.radiusSheet),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand block
                        // Brand block — matches the sidebar's white treatment.
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.divider, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 40,
                    height: 40,
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
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'AfriNova',
                          style: AppTextStyles.wordmarkLight.copyWith(
                            fontSize: 18,
                            height: 1.0,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Academy',
                          style: AppTextStyles.wordmarkBold.copyWith(
                            fontSize: 18,
                            height: 1.0,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Nav
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                children: _buildGroupedItems(),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
                     _DrawerUserBlock(
            userName: userName,
            userRole: userRole,
            onTap: onAccountTap,
          ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedItems() {
    final sections = <String, List<NavItem>>{};
    for (final item in items) {
      final key = item.section ?? '';
      sections.putIfAbsent(key, () => []).add(item);
    }

    final widgets = <Widget>[];
    for (final entry in sections.entries) {
      if (entry.key.isNotEmpty) {
        widgets.add(
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
        );
      }
      for (final item in entry.value) {
        widgets.add(_DrawerTile(
          item: item,
          active: item.key == activeKey,
          onTap: () => onSelect(item),
        ));
      }
    }
    return widgets;
  }
}

class _DrawerTile extends StatelessWidget {
  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.item,
    required this.active,
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withOpacity(0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            ),
            child: Row(
  children: [
    Icon(item.resolvedIcon, size: 20, color: fg),
    const SizedBox(width: AppSpacing.md),
    Expanded(
      child: Text(
        item.label,
        style: AppTextStyles.labelMd.copyWith(color: fg),
      ),
    ),
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
),
          ),
        ),
      ),
    );
  }
}

class _DrawerUserBlock extends StatelessWidget {
  final String userName;
  final String userRole;
  final VoidCallback? onTap;

  const _DrawerUserBlock({
    required this.userName,
    required this.userRole,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = userName.trim().isEmpty
        ? '?'
        : userName.trim().split(RegExp(r'\s+')).take(2).map((s) => s[0]).join();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
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
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName.isEmpty ? 'Student' : userName,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMd,
                    ),
                    const SizedBox(height: 2),
                    Text(userRole.toUpperCase(), style: AppTextStyles.overline),
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
          ),
        ),
      ),
    );
  }
}