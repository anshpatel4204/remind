import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/repositories/app_repositories.dart';
import 'presentation/widgets/main_shell.dart';
import 'presentation/widgets/repository_scope.dart';
import 'services/notification/notification_service.dart';

Future<void> main() async {
  // Required before any platform channel call (notifications, sqflite)
  // runs ahead of runApp().
  WidgetsFlutterBinding.ensureInitialized();

  final notificationTransport = NotificationService();
  final repositories = AppRepositories(notificationTransport: notificationTransport);

  // Sets up the notification channel/timezone data and wires notification
  // taps back into the app; then asks for POST_NOTIFICATIONS if it hasn't
  // been decided yet (never assumed granted); then re-establishes every
  // enabled reminder's scheduled notification, as a defensive second layer
  // on top of Android's own native boot-restore (see AndroidManifest.xml).
  await repositories.notificationScheduler.initialize();
  await repositories.notificationScheduler.ensureNotificationPermission();
  await repositories.notificationScheduler.reconcileAfterStartup();

  runApp(RemindApp(repositories: repositories));
}

/// Root widget for REmind.
///
/// [repositories] is always supplied explicitly - by [main] for real use
/// (wired to the real on-device SQLite database and a real
/// [NotificationService]), or by a test (wired to an in-memory FFI
/// database and a [NoopNotificationTransport] or fake). [themeController]
/// is optional - when omitted (the normal case), one is created and loaded
/// automatically from [repositories]' own [AppRepositories.settingsRepository],
/// so existing call sites (including tests) do not need to know about it.
class RemindApp extends StatefulWidget {
  const RemindApp({super.key, required this.repositories, this.themeController});

  final AppRepositories repositories;
  final ThemeController? themeController;

  @override
  State<RemindApp> createState() => _RemindAppState();
}

class _RemindAppState extends State<RemindApp> {
  late final ThemeController _themeController;

  @override
  void initState() {
    super.initState();
    _themeController = widget.themeController ?? ThemeController(widget.repositories.settingsRepository);
    // Fire-and-forget: the app renders immediately with the ThemeMode.system
    // default, then flips (via notifyListeners, which ThemeControllerScope
    // listens to) once any previously-saved preference has loaded - a local
    // settings read is fast enough that this is never visibly janky.
    _themeController.load();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryScope(
      repositories: widget.repositories,
      child: ThemeControllerScope(
        controller: _themeController,
        child: const _RemindMaterialApp(),
      ),
    );
  }
}

class _RemindMaterialApp extends StatelessWidget {
  const _RemindMaterialApp();

  @override
  Widget build(BuildContext context) {
    final mode = ThemeControllerScope.of(context).mode;
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: const MainShell(),
    );
  }
}
