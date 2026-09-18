import 'package:flutter/material.dart';

/// Spacing, radius, and motion tokens.
///
/// Use these instead of raw numbers so the layout rhythm stays consistent
/// across every screen. If we tighten or loosen the dashboard later, we
/// change it here — not in 30 files.
class AppSpacing {
  AppSpacing._();

  // ─────────────────────────────────────────────────────────────
  // Spacing scale (Tailwind-inspired: 4 / 8 / 12 / 16 / 24 / 32)
  // ─────────────────────────────────────────────────────────────

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // ─────────────────────────────────────────────────────────────
  // Radius scale
  // ─────────────────────────────────────────────────────────────

  static const double radiusChip = 8;
  static const double radiusButton = 12;
  static const double radiusInput = 12;
  static const double radiusCard = 16;
  static const double radiusSheet = 20;
  static const double radiusPill = 999;

  // ─────────────────────────────────────────────────────────────
  // EdgeInsets shortcuts
  // ─────────────────────────────────────────────────────────────

  /// Inner padding of a standard card.
  static const EdgeInsets cardPadding = EdgeInsets.all(20);

  /// Padding for a compact KPI card.
  static const EdgeInsets kpiCardPadding = EdgeInsets.all(16);

  /// Page-level padding on mobile and desktop respectively.
  static const EdgeInsets pagePaddingMobile = EdgeInsets.all(16);
  static const EdgeInsets pagePaddingDesktop = EdgeInsets.all(24);

  /// Vertical gap between dashboard sections.
  static const SizedBox gapXs = SizedBox(height: xs);
  static const SizedBox gapSm = SizedBox(height: sm);
  static const SizedBox gapMd = SizedBox(height: md);
  static const SizedBox gapLg = SizedBox(height: lg);
  static const SizedBox gapXl = SizedBox(height: xl);
  static const SizedBox gapXxl = SizedBox(height: xxl);

  /// Horizontal gaps (for Row spacing).
  static const SizedBox hGapSm = SizedBox(width: sm);
  static const SizedBox hGapMd = SizedBox(width: md);
  static const SizedBox hGapLg = SizedBox(width: lg);

  // ─────────────────────────────────────────────────────────────
  // Motion
  // ─────────────────────────────────────────────────────────────

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;

  // ─────────────────────────────────────────────────────────────
  // Breakpoints
  // ─────────────────────────────────────────────────────────────

  /// Mobile: < 900 — drawer nav only
  /// Tablet: 900–1200 — collapsed rail
  /// Desktop: >= 1200 — full sidebar
  static const double breakpointMobile = 900;
  static const double breakpointDesktop = 1200;

  /// Sidebar widths.
  static const double sidebarWidth = 240;
  static const double sidebarCollapsedWidth = 72;
  static const double topbarHeight = 68;
}