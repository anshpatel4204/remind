import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/user_preferences_controller.dart';
import 'core/utils/date_formatting.dart';
import 'data/repositories/app_repositories.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'presentation/widgets/main_shell.dart';
import 'presentation/widgets/repository_scope.dart';
import 'services/notification/notification_service.dart';

Future<void> main() async {
  // Required before any platform channel call (notifications, sqflite)
  // runs ahead of runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Locale-aware date formatting (Part 13): resolves the device's own
  // locale for `intl`'s DateFormat, rather than always falling back to
  // `en_US`. Deliberately does not touch app-wide *text* localization
  // (no `flutter_localizations`/arb translations) - only how dates/times
  // are formatted, which is what the spec actually asks for.
  await initializeAppLocale(PlatformDispatcher.instance.locale.toString());

  final notificationTransport = NotificationService();
  final repositories =
      AppRepositories(notificationTransport: notificationTransport);

  // Notification bootstrap and permission request now happen inside
  // SplashScreen (see that file's doc comment for why), not here - main()
  // stays fast/synchronous so the branded splash shows immediately.
  runApp(AppBootGate(repositories: repositories));
}

/// Decides, before [RemindApp] ever mounts, what the user sees first:
/// [SplashScreen] while the app initializes, then either
/// `OnboardingScreen` (a fresh install) or [RemindApp] itself (a
/// returning user). Public (not a private `_` class) so it's directly
/// testable from `test/widget_test.dart`, the same way [RemindApp] is.
///
/// Deliberately NOT built as a route pushed inside [RemindApp]'s own
/// `MaterialApp`/`Navigator`: [RemindApp] is constructed directly by
/// every existing widget test and must keep behaving exactly as it did
/// before Part 13 (showing [MainShell] immediately, no splash/onboarding
/// gating) for none of that existing coverage to change. This widget's
/// `build` instead returns exactly one of three self-contained
/// alternatives - each phase either owns its own minimal `MaterialApp`
/// (Splash/Onboarding, whose fixed light look never depends on the
/// user's theme preference) or *is* [RemindApp] (which owns its own
/// `MaterialApp` internally) - so there is never more than one
/// `MaterialApp`/`Navigator` mounted at a time.
class AppBootGate extends StatefulWidget {
  const AppBootGate({super.key, required this.repositories});

  final AppRepositories repositories;

  @override
  State<AppBootGate> createState() => _AppBootGateState();
}

enum _BootPhase { splash, onboarding, ready }

class _AppBootGateState extends State<AppBootGate> {
  _BootPhase _phase = _BootPhase.splash;

  Future<void> _onSplashReady() async {
    final completed =
        await widget.repositories.settingsRepository.getOnboardingCompleted();
    if (!mounted) return;
    setState(() => _phase = completed ? _BootPhase.ready : _BootPhase.onboarding);
  }

  void _onOnboardingDone() {
    if (!mounted) return;
    setState(() => _phase = _BootPhase.ready);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _BootPhase.splash:
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: SplashScreen(
            repositories: widget.repositories,
            onReady: _onSplashReady,
          ),
        );
      case _BootPhase.onboarding:
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: OnboardingScreen(
            repositories: widget.repositories,
            onDone: _onOnboardingDone,
          ),
        );
      case _BootPhase.ready:
        return RemindApp(repositories: widget.repositories);
    }
  }
}

/// Root widget for REmind.
///
/// [repositories] is always supplied explicitly - by [AppBootGate] for
/// real use (wired to the real on-device SQLite database and a real
/// [NotificationService]), or by a test (wired to an in-memory FFI
/// database and a [NoopNotificationTransport] or fake). [themeController]/
/// [userPreferencesController] are optional - when omitted (the normal
/// case), each is created and loaded automatically from [repositories]'
/// own [AppRepositories.settingsRepository], so existing call sites
/// (including tests) do not need to know about them.
class RemindApp extends StatefulWidget {
  const RemindApp({
    super.key,
    required this.repositories,
    this.themeController,
    this.userPreferencesController,
  });

  final AppRepositories repositories;
  final ThemeController? themeController;
  final UserPreferencesController? userPreferencesController;

  @override
  State<RemindApp> createState() => _RemindAppState();
}

class _RemindAppState extends State<RemindApp> {
  late final ThemeController _themeController;
  late final UserPreferencesController _userPreferencesController;

  @override
  void initState() {
    super.initState();
    _themeController = widget.themeController ??
        ThemeController(widget.repositories.settingsRepository);
    _userPreferencesController = widget.userPreferencesController ??
        UserPreferencesController(widget.repositories.settingsRepository);
    // Fire-and-forget: the app renders immediately with each controller's
    // safe defaults, then updates (via notifyListeners, which each scope
    // listens to) once any previously-saved preference has loaded - a
    // local settings read is fast enough that this is never visibly janky.
    _themeController.load();
    _userPreferencesController.load();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryScope(
      repositories: widget.repositories,
      child: ThemeControllerScope(
        controller: _themeController,
        child: UserPreferencesScope(
          controller: _userPreferencesController,
          child: const _RemindMaterialApp(),
        ),
      ),
    );
  }
}

class _RemindMaterialApp extends StatelessWidget {
  const _RemindMaterialApp();

  @override
  Widget build(BuildContext context) {
    final mode = ThemeControllerScope.of(context).mode;
    final userPreferences = UserPreferencesScope.of(context);
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      builder: (context, child) {
        // App-wide accessibility text-scale and 12/24-hour time-format
        // preferences (Part 13): applied once here, on top of whatever
        // the device's own MediaQuery already says, so every screen -
        // including Flutter's own showTimePicker/TimeOfDay.format, not
        // just REmind's own formatTime/formatDateTime helpers - stays
        // consistent with what the user picked in Settings, and new
        // screens get it for free.
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(
              userPreferences.textScale.scaleFactor *
                  mediaQuery.textScaler.scale(1.0),
            ),
            alwaysUse24HourFormat: userPreferences.resolveUse24Hour(context),
          ),
          child: child!,
        );
      },
      home: const MainShell(),
    );
  }
}
