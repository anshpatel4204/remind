import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
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
/// database and a [NoopNotificationTransport] or fake).
class RemindApp extends StatelessWidget {
  const RemindApp({super.key, required this.repositories});

  final AppRepositories repositories;

  @override
  Widget build(BuildContext context) {
    return RepositoryScope(
      repositories: repositories,
      child: MaterialApp(
        title: 'REmind',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const MainShell(),
      ),
    );
  }
}
