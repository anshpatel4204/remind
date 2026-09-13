/// REmind's spacing/sizing/radius scale.
///
/// Every screen should build its padding/gaps/corner-radii from these
/// constants instead of scattering ad-hoc numbers (`EdgeInsets.all(17)`,
/// `BorderRadius.circular(10)`, ...) - that scattering is exactly what made
/// spacing feel inconsistent screen-to-screen before this token pass.
/// [AppTheme] itself uses [radiusControl]/[radiusCard]/[radiusSheet] so
/// every themed widget (buttons, inputs, cards, dialogs, sheets) shares the
/// same rounding language.
class AppSpacing {
  AppSpacing._();

  // Spacing scale - use the smallest one that reads correctly rather than
  // picking a number in between.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Standard horizontal/vertical screen edge padding.
  static const double screenPadding = lg;

  // Corner radii.
  static const double radiusControl = 12; // buttons, inputs, list tiles
  static const double radiusCard = 16; // cards, stat tiles
  static const double radiusSheet = 24; // bottom sheets, dialogs
  static const double radiusPill = 999; // chips, badges

  // Icon sizes.
  static const double iconSmall = 16;
  static const double iconMedium = 22;
  static const double iconLarge = 28;
}
