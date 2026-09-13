import 'package:flutter/material.dart';

/// REmind's type scale - one deliberate size/weight per role, reused by
/// every screen via `Theme.of(context).textTheme.*` instead of screens
/// choosing their own `fontSize`/`fontWeight` inline.
///
/// Deliberately stays on the platform's default font family rather than
/// bundling a custom brand font (e.g. via `google_fonts`, which fetches
/// glyphs over the network at first use): REmind is described as an
/// offline-first app, and a typeface that has to download before the UI
/// looks "right" would quietly break that guarantee on a fresh install
/// with no connectivity. The hierarchy below is what actually reads as
/// "designed" - consistent scale and weight - independent of typeface.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(ColorScheme colorScheme) {
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    return TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      titleLarge: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: onSurface),
      titleMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
      titleSmall: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
      bodyLarge: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w400, color: onSurface),
      bodyMedium: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w400, color: onSurface),
      bodySmall: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w400, color: onSurfaceVariant),
      labelLarge: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
      labelMedium: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: onSurfaceVariant),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: onSurfaceVariant,
      ),
    );
  }
}
