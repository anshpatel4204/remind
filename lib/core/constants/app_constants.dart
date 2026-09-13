/// App-wide constant values shared across REmind.
class AppConstants {
  AppConstants._();

  static const String appName = 'REmind';
  static const String appTagline = 'Remember. Organize. Achieve.';
  static const String brandLogoAsset = 'assets/branding/remind_logo.png';

  /// Displayed in Settings > Data and in the About dialog. Bump this by
  /// hand alongside pubspec.yaml's own version when it changes - the two
  /// are not linked automatically.
  static const String appVersion = '1.0.0';
}
