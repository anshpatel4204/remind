import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../data/repositories/app_repositories.dart';
import 'notification_transport.dart';

/// The real [NotificationTransport], backed by
/// `flutter_local_notifications`. This is the only file in the app that
/// imports that package (or `timezone`/`flutter_timezone`) - everything
/// else, including [NotificationScheduler]'s tests, only ever depends on
/// the plain [NotificationTransport] interface.
class NotificationService implements NotificationTransport {
  static const String _channelId = 'reminders';
  static const String _channelName = 'Task reminders';
  static const String _channelDescription = 'Notifications for REmind task reminders';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialize({
    required Future<void> Function(NotificationInteraction interaction) onInteraction,
  }) {
    return _initializePlugin(
      onForegroundResponse: (response) => onInteraction(_toInteraction(response)),
    );
  }

  /// Used only by [notificationBackgroundEntryPoint]. A background
  /// isolate handles the interaction itself, inline, right where it
  /// receives it - it has no in-app callback to forward to, so this skips
  /// that part of setup while still doing everything scheduling itself
  /// needs (timezone data, the plugin, the notification channel).
  Future<void> initializeForBackgroundIsolate() {
    return _initializePlugin(onForegroundResponse: null);
  }

  Future<void> _initializePlugin({
    required void Function(NotificationResponse response)? onForegroundResponse,
  }) async {
    if (_initialized) return;

    // Never hardcode a timezone: read the device's actual IANA timezone
    // identifier and use that, so a scheduled reminder always means what
    // the user actually meant by "5pm", on this device, wherever it is.
    tz.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    const androidInitializationSettings = AndroidInitializationSettings('notification_icon');
    const initializationSettings = InitializationSettings(android: androidInitializationSettings);

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundEntryPoint,
    );

    await _androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    return await _androidPlugin?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestNotificationsPermission() async {
    return await _androidPlugin?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<bool> canScheduleExactNotifications() async {
    return await _androidPlugin?.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    String? body,
    required DateTime scheduledTime,
    required List<NotificationAction> actions,
    String? payload,
    bool exact = true,
  }) async {
    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        actions: actions
            .map((action) => AndroidNotificationAction(
                  action.id,
                  action.title,
                  cancelNotification: action.cancelNotification,
                ))
            .toList(),
      ),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      // scheduledTime is already the device's real local wall-clock
      // moment (see RecurrenceCalculator/ReminderEngine, neither of which
      // ever touches UTC or a hardcoded offset). TZDateTime.from re-reads
      // that same absolute instant under tz.local - it does not shift it.
      scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails: notificationDetails,
      androidScheduleMode:
          exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<Set<int>> pendingIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((request) => request.id).toSet();
  }
}

NotificationInteraction _toInteraction(NotificationResponse response) {
  return NotificationInteraction(
    notificationId: response.id ?? -1,
    actionId: response.actionId,
    payload: response.payload,
  );
}

/// Entry point Android invokes when the user taps a notification or one of
/// its action buttons while the REmind app process is completely killed.
///
/// `flutter_local_notifications` starts a brand-new, isolated Flutter
/// engine to run this - it shares no state with the app's normal main()
/// isolate, which is why it builds its own [AppRepositories] (and, via
/// that, its own [NotificationService]) from scratch rather than reaching
/// for anything created at app startup. Must stay a top-level function
/// with this exact `@pragma('vm:entry-point')` annotation, or the Android
/// build will tree-shake it away and this path will silently never fire.
@pragma('vm:entry-point')
Future<void> notificationBackgroundEntryPoint(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  final transport = NotificationService();
  await transport.initializeForBackgroundIsolate();
  final repositories = AppRepositories(notificationTransport: transport);
  await repositories.notificationScheduler.handleInteraction(_toInteraction(response));
}
