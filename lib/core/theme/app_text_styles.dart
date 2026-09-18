import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Typography system.
///
/// Two families:
///   • Plus Jakarta Sans — display/headings (extra bold, tight tracking)
///   • Inter — body, labels, captions (clean, legible at small sizes)
class AppTextStyles {
  AppTextStyles._();

  // ─────────────────────────────────────────────────────────────
  // Display — hero numbers, greeting
  // ─────────────────────────────────────────────────────────────

  static TextStyle get displayLarge => GoogleFonts.plusJakartaSans(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.1,
        color: AppColors.textPrimary,
      );

  static TextStyle get displayMedium => GoogleFonts.plusJakartaSans(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
        height: 1.15,
        color: AppColors.textPrimary,
      );

  /// Ideal for KPI numbers.
  static TextStyle get displayStat => GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        height: 1.1,
        color: AppColors.textPrimary,
      );

  // ─────────────────────────────────────────────────────────────
  // Headings — section titles
  // ─────────────────────────────────────────────────────────────

  static TextStyle get headingLg => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.25,
        color: AppColors.textPrimary,
      );

  static TextStyle get headingMd => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.3,
        color: AppColors.textPrimary,
      );

  static TextStyle get headingSm => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.3,
        color: AppColors.textPrimary,
      );

  // ─────────────────────────────────────────────────────────────
  // Body
  // ─────────────────────────────────────────────────────────────

  static TextStyle get bodyLg => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMd => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodySm => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: AppColors.textSecondary,
      );

  // ─────────────────────────────────────────────────────────────
  // Labels
  // ─────────────────────────────────────────────────────────────

  static TextStyle get labelLg => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.3,
        color: AppColors.textPrimary,
      );

  static TextStyle get labelMd => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.3,
        color: AppColors.textPrimary,
      );

  static TextStyle get labelSm => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        height: 1.2,
        color: AppColors.textSecondary,
      );

  /// Uppercase, tracked-out caption — section eyebrows.
  static TextStyle get overline => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        height: 1.2,
        color: AppColors.textTertiary,
      );

  // ─────────────────────────────────────────────────────────────
  // Captions
  // ─────────────────────────────────────────────────────────────

  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: AppColors.textSecondary,
      );

  static TextStyle get captionXs => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: AppColors.textTertiary,
      );

  // ─────────────────────────────────────────────────────────────
  // Wordmark — used by the sidebar brand block
  // ─────────────────────────────────────────────────────────────

  /// "AfriNova" — light weight, tight.
  static TextStyle get wordmarkLight => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.2,
        height: 1.0,
        color: AppColors.textPrimary,
      );

  /// "Academy" — extra bold, artistic contrast against the light.
  static TextStyle get wordmarkBold => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
        height: 1.0,
        color: AppColors.textPrimary,
      );

  // ─────────────────────────────────────────────────────────────
  // Modifiers
  // ─────────────────────────────────────────────────────────────

  static TextStyle muted(TextStyle base) =>
      base.copyWith(color: AppColors.textSecondary);

  static TextStyle strong(TextStyle base) =>
      base.copyWith(fontWeight: FontWeight.w700);

  // ─────────────────────────────────────────────────────────────
  // Full TextTheme for ThemeData
  // ─────────────────────────────────────────────────────────────

  static TextTheme textTheme() => TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        headlineLarge: headingLg,
        headlineMedium: headingMd,
        headlineSmall: headingSm,
        titleLarge: headingLg,
        titleMedium: headingMd,
        titleSmall: headingSm,
        bodyLarge: bodyLg,
        bodyMedium: bodyMd,
        bodySmall: bodySm,
        labelLarge: labelLg,
        labelMedium: labelMd,
        labelSmall: labelSm,
      );
}