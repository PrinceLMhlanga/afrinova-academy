import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// The single source of truth for the app's visual theme.
///
/// Usage in main.dart:
///   MaterialApp(
///     theme: AppTheme.light(),
///     ...
///   )
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final textTheme = AppTextStyles.textTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.backgroundTop,
      textTheme: textTheme,

      // ─────────────────────────────────────────────────────────
      // Color scheme
      // ─────────────────────────────────────────────────────────
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.textInverse,
        secondary: AppColors.accent,
        onSecondary: AppColors.textInverse,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: AppColors.divider,
        error: AppColors.danger,
        onError: AppColors.textInverse,
        outline: AppColors.border,
        outlineVariant: AppColors.divider,
      ),

      // ─────────────────────────────────────────────────────────
      // AppBar
      // ─────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
  backgroundColor: AppColors.primary,       // deep indigo
  foregroundColor: AppColors.textInverse,   // white text + white icons
  elevation: 0,
  scrolledUnderElevation: 0.5,
  centerTitle: false,
  titleTextStyle: AppTextStyles.headingLg.copyWith(
    color: AppColors.textInverse,
    fontSize: 22,
    letterSpacing: -0.5,
  ),
  iconTheme: const IconThemeData(
    color: AppColors.textInverse,
    size: 22,
  ),
  actionsIconTheme: const IconThemeData(
    color: AppColors.textInverse,
    size: 22,
  ),
),

      // ─────────────────────────────────────────────────────────
      // Cards
      // ─────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      // ─────────────────────────────────────────────────────────
      // Buttons
      // ─────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textInverse,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          ),
          textStyle: AppTextStyles.labelLg,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border, width: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          ),
          textStyle: AppTextStyles.labelLg,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          textStyle: AppTextStyles.labelMd,
        ),
      ),

      // ─────────────────────────────────────────────────────────
      // Inputs
      // ─────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: AppColors.surfaceSubtle,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  ),
  hintStyle: AppTextStyles.bodyMd.copyWith(
    color: AppColors.textTertiary,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusInput),
    borderSide: const BorderSide(
      color: AppColors.inputBorder,
      width: 1.2,
    ),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusInput),
    borderSide: const BorderSide(
      color: AppColors.inputBorder,
      width: 1.2,
    ),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusInput),
    borderSide: const BorderSide(
      color: AppColors.primary,
      width: 1.6,
    ),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusInput),
    borderSide: const BorderSide(
      color: AppColors.danger,
      width: 1.2,
    ),
  ),
),

      // ─────────────────────────────────────────────────────────
      // Dividers
      // ─────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ─────────────────────────────────────────────────────────
      // Chips
      // ─────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceSubtle,
        side: const BorderSide(color: AppColors.border, width: 1),
        labelStyle: AppTextStyles.labelSm,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        ),
      ),

      // ─────────────────────────────────────────────────────────
      // Misc
      // ─────────────────────────────────────────────────────────
      splashColor: AppColors.primary.withOpacity(0.06),
      highlightColor: AppColors.primary.withOpacity(0.04),
      hoverColor: AppColors.primary.withOpacity(0.04),
    );
  }

  /// A helper for hero containers with the brand gradient.
  /// Useful as a decoration for the greeting card / brand panel.
  static BoxDecoration brandPanelDecoration({double radius = AppSpacing.radiusCard}) {
    return BoxDecoration(
      gradient: AppColors.brandGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: AppColors.shadowPrimary,
    );
  }

  /// A helper for standard card surfaces.
  static BoxDecoration cardDecoration({double radius = AppSpacing.radiusCard}) {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border, width: 1),
      boxShadow: AppColors.shadowCard,
    );
  }
}