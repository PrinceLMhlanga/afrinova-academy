import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  const ShellAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.topbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: AppSpacing.topbarHeight,
      leadingWidth: 56,
      leading: onBack != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 22),
              onPressed: onBack,
              tooltip: 'Back',
            )
          : null,
      titleSpacing: 0,
      title: Text(
        title,
        style: AppTextStyles.headingLg.copyWith(
          color: AppColors.textInverse,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
      ),
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: Container(
        decoration: const BoxDecoration(gradient: AppColors.topbarGradient),
      ),
      actions: [...actions, const SizedBox(width: 8)],
    );
  }
}