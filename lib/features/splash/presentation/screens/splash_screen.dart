import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/repositories/app_repositories.dart';

/// REmind's branded first screen, shown immediately when the Flutter side
/// of the app takes over from Android's native launch background (see
/// `android/app/src/main/res/drawable/launch_background.xml`), matching
/// the design reference's gradient/logo/progress-bar splash.
///
/// Two things happen here concurrently, both gating [onReady]:
///  - the same notification bootstrap (`initialize`, permission request,
///    `reconcileAfterStartup`) that used to block `main()` before
///    `runApp()` ran at all - moved here so the branded screen shows
///    immediately instead of a blank/native-only gap while that work
///    happens;
///  - a short minimum display duration, so the splash never flashes by
///    too quickly to read on a fast device/cold cache.
///
/// [AppBootGate] (see `main.dart`) is what decides where [onReady] leads
/// - straight to [RemindApp] for a returning user, or through
/// `OnboardingScreen` first for a fresh install. This widget itself makes
/// no such decision; it only reports "initialization is done".
class SplashScreen extends StatefulWidget {
  const SplashScreen(
      {super.key, required this.repositories, required this.onReady});

  final AppRepositories repositories;
  final VoidCallback onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final minimumDisplay =
        Future<void>.delayed(const Duration(milliseconds: 900));
    await Future.wait([minimumDisplay, _initialize()]);
    if (!mounted) return;
    widget.onReady();
  }

  /// Sets up the notification channel/timezone data and wires notification
  /// taps back into the app; then asks for POST_NOTIFICATIONS if it hasn't
  /// been decided yet (never assumed granted); then re-establishes every
  /// enabled reminder's scheduled notification, as a defensive second layer
  /// on top of Android's own native boot-restore (see AndroidManifest.xml).
  /// Identical to what `main()` ran before Part 13 - only the timing (now
  /// after first frame, not before `runApp()`) changed.
  Future<void> _initialize() async {
    final scheduler = widget.repositories.notificationScheduler;
    await scheduler.initialize();
    await scheduler.ensureNotificationPermission();
    await scheduler.reconcileAfterStartup();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.splashGradientStart, AppColors.splashGradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  AppConstants.brandLogoAsset,
                  width: 100,
                  height: 100,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.brandNavy,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                AppConstants.appTagline,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.brandNavy.withValues(alpha: 0.7),
                    ),
              ),
              const Spacer(flex: 3),
              Text(
                AppConstants.splashCaptionLine1,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.brandNavy.withValues(alpha: 0.7),
                    ),
              ),
              Text(
                AppConstants.splashCaptionLine2,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.brandNavy,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: Colors.white,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.brandPurple),
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
