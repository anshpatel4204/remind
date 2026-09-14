/// App-wide constant values shared across REmind.
class AppConstants {
  AppConstants._();

  static const String appName = 'REmind';
  static const String appTagline = 'Remember. Organize. Achieve.';
  static const String brandLogoAsset = 'assets/branding/remind_logo.png';

  /// Displayed in Settings > Data and in the About dialog. Bump this by
  /// hand alongside pubspec.yaml's own version when it changes - the two
  /// are not linked automatically.
  static const String appVersion = '1.0.0-beta.1';

  /// The two-line loading caption shown under the wordmark on
  /// [SplashScreen] - kept separate from [appTagline] since About/onboarding
  /// use the tagline, while the splash screen (per the design reference)
  /// uses this pair instead.
  static const String splashCaptionLine1 = 'A More Organized';
  static const String splashCaptionLine2 = 'A Brighter You';

  /// A short quotable line shown on the About screen, matching the design
  /// reference exactly.
  static const String aboutQuote = 'Small Reminders, Big Changes';
}
