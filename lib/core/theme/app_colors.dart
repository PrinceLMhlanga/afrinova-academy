import 'package:flutter/material.dart';

/// Central color palette for AfriNova Academy.
///
/// Every widget should reference these constants — never raw hex values.
/// This keeps the dashboard visually consistent and makes rebranding a
/// single-file change.
class AppColors {
  AppColors._();

  // ─────────────────────────────────────────────────────────────
  // Brand
  // ─────────────────────────────────────────────────────────────

  /// Primary brand indigo. Matches the existing app identity.
  static const Color primary = Color(0xFF1A237E);
  static const Color primaryDark = Color(0xFF0D1B4C);
  static const Color primaryLight = Color(0xFF3949AB);

  /// Active/hover accent — one step lighter than primary.
  static const Color accent = Color(0xFF3949AB);
  static const Color accentSoft = Color(0xFF5C6BC0);

  // ─────────────────────────────────────────────────────────────
  // Surfaces
  // ─────────────────────────────────────────────────────────────

  /// Page background — subtle gradient between these two.
  static const Color backgroundTop = Color(0xFFF5F7FA);
  static const Color backgroundBottom = Color(0xFFE8ECF1);

    /// Dark topbar gradient for light mode — anchors the app.
  static const LinearGradient topbarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D1B4C), Color(0xFF1A237E)],
  );

  /// Hover-tint for KPI cards — very subtle accent wash.
  static Color kpiHoverTint(Color accent) =>
      Color.lerp(Colors.white, accent, 0.04)!;

  /// Card and sheet surfaces.
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFFAFBFD);
  static const Color surfaceRaised = Color(0xFFFFFFFF);

  /// Borders and dividers.
  static const Color border = Color(0xFFE5E9F0);
  static const Color borderStrong = Color(0xFFD1D9E6);
  static const Color divider = Color(0xFFEEF1F6);

  // ─────────────────────────────────────────────────────────────
  // Text
  // ─────────────────────────────────────────────────────────────

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textInverse = Color(0xFFFFFFFF);

  // ─────────────────────────────────────────────────────────────
  // Semantic
  // ─────────────────────────────────────────────────────────────

  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color successBorder = Color(0xFFA7F3D0);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);

  static const Color danger = Color(0xFFEF4444);
  static const Color dangerBg = Color(0xFFFEF2F2);
  static const Color dangerBorder = Color(0xFFFECACA);

  static const Color info = Color(0xFF3B82F6);
  static const Color infoBg = Color(0xFFEFF6FF);
  static const Color infoBorder = Color(0xFFBFDBFE);

  // ─────────────────────────────────────────────────────────────
  // Chart series — one color per data source
  // ─────────────────────────────────────────────────────────────

  /// Input field borders — stronger than card borders because inputs
/// need to be discoverable, not just outlined.
static const Color inputBorder = Color(0xFFCBD2E0);
static const Color inputBorderFocused = primary;

  /// AI practice exams line.
  static const Color chartAi = Color(0xFF3B82F6);

  /// Teacher-assigned MCQ exams line.
  static const Color chartMcq = Color(0xFF10B981);

  /// Marked exam papers line.
  static const Color chartPaper = Color(0xFFF59E0B);

  /// Blended average line (used sparingly).
  static const Color chartBlended = Color(0xFF8B5CF6);

  /// Grid and axis lines on charts.
  static const Color chartGrid = Color(0xFFEEF1F6);
  static const Color chartAxis = Color(0xFF94A3B8);

  // ─────────────────────────────────────────────────────────────
  // Gradients
  // ─────────────────────────────────────────────────────────────

  /// Used by the app shell header, brand marks, etc.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, primaryLight],
  );

  /// The page-level background.
  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, backgroundBottom],
  );

  // ─────────────────────────────────────────────────────────────
  // Shadows
  // ─────────────────────────────────────────────────────────────

  /// Card resting shadow — barely visible, gives depth without weight.
  static const List<BoxShadow> shadowCard = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 24,
      offset: Offset(0, 4),
    ),
  ];

  /// Slightly stronger — for hovered cards, popovers.
  static const List<BoxShadow> shadowRaised = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 32,
      offset: Offset(0, 8),
    ),
  ];

  /// Brand-tinted shadow for primary buttons and hero cards.
  static const List<BoxShadow> shadowPrimary = [
    BoxShadow(
      color: Color(0x331A237E),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  /// Parses a `#RRGGBB` hex string from the database (`subjects.color_hex`).
  /// Falls back to [primary] if parsing fails.
  static Color fromHex(String? hex) {
    if (hex == null || hex.isEmpty) return primary;
    var cleaned = hex.replaceFirst('#', '').trim();
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    final value = int.tryParse(cleaned, radix: 16);
    return value != null ? Color(value) : primary;
  }

  /// Returns a color that reads well on top of [background].
  static Color onColor(Color background) {
    // Use relative luminance to decide black or white text.
    return background.computeLuminance() > 0.5
        ? textPrimary
        : textInverse;
  }
}