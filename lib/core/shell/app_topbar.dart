import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// The shell's top header.
///
/// Dark gradient background so the light content area below it has a
/// real anchor. White-on-indigo text.
class AppTopbar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isMobile;
  final bool sidebarCollapsed;
  final VoidCallback onOpenDrawer;
  final VoidCallback onToggleSidebar;
  final VoidCallback? onNotificationsTap;
  final int notificationCount;

  const AppTopbar({
    super.key,
    required this.title,
    this.subtitle,
    required this.isMobile,
    required this.sidebarCollapsed,
    required this.onOpenDrawer,
    required this.onToggleSidebar,
    this.onNotificationsTap,
    this.notificationCount = 0,
  });

  String get _dateLabel {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >=
        AppSpacing.breakpointDesktop;

    return Container(
      height: AppSpacing.topbarHeight,
      decoration: BoxDecoration(
        gradient: AppColors.topbarGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? AppSpacing.xl : AppSpacing.md,
      ),
      child: Row(
        children: [
          if (isMobile)
            _TopbarIconButton(
              icon: Icons.menu_rounded,
              onTap: onOpenDrawer,
              tooltip: 'Open menu',
            )
          else
            _TopbarIconButton(
              icon: sidebarCollapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              onTap: onToggleSidebar,
              tooltip: sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
            ),

          const SizedBox(width: AppSpacing.md),

                    Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.headingLg.copyWith(
                color: AppColors.textInverse,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
          ),
          
          if (!isMobile)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                border: Border.all(
                  color: Colors.white.withOpacity(0.12),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _dateLabel,
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(width: AppSpacing.sm),

          _TopbarIconButton(
            icon: Icons.notifications_none_rounded,
            onTap: onNotificationsTap,
            tooltip: 'Notifications',
            badge: notificationCount > 0 ? notificationCount : null,
          ),
        ],
      ),
    );
  }
}

class _TopbarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final int? badge;

  const _TopbarIconButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 20, color: Colors.white.withOpacity(0.9)),
              if (badge != null)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Text(
                      badge! > 9 ? '9+' : '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textInverse,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);
  }
}