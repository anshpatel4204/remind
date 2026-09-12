import 'package:remind/services/notification/notification_transport.dart';

/// What [FakeNotificationTransport.schedule] recorded for one notification
/// id, so tests can assert on exactly what would have been shown/fired.
class ScheduledNotification {
  ScheduledNotification({
    required this.id,
    required this.title,
    this.body,
    required this.scheduledTime,
    required this.actions,
    this.payload,
    required this.exact,
  });

  final int id;
  final String title;
  final String? body;
  final DateTime scheduledTime;
  final List<NotificationAction> actions;
  final String? payload;
  final bool exact;
}

/// An in-memory [NotificationTransport] for tests.
///
/// Tracks every schedule/cancel call so [NotificationScheduler]'s
/// orchestration decisions (which id to reuse, cancel-before-reschedule,
/// permission handling, action routing, and so on) can be asserted
/// directly, with no real Android device or platform channel involved.
class FakeNotificationTransport implements NotificationTransport {
  final Map<int, ScheduledNotification> scheduled = {};

  /// Every call this transport received, in order (e.g. `schedule:5`,
  /// `cancel:5`) - use this where the *order* of calls matters, such as
  /// proving a reschedule cancels the old notification before scheduling
  /// the replacement.
  final List<String> calls = [];

  /// Simulates the current OS-level "does the user allow notifications"
  /// state. Tests can flip this to simulate permission being denied.
  bool notificationsEnabled = true;

  /// Whether [requestNotificationsPermission] simulates the user granting
  /// the request. Defaults to granting, matching [notificationsEnabled]'s
  /// default.
  bool grantPermissionOnRequest = true;

  /// Simulates whether the OS currently allows exact-time alarms.
  bool exactAlarmsAllowed = true;

  Future<void> Function(NotificationInteraction interaction)? _onInteraction;

  @override
  Future<void> initialize({
    required Future<void> Function(NotificationInteraction interaction) onInteraction,
  }) async {
    _onInteraction = onInteraction;
  }

  @override
  Future<bool> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<bool> requestNotificationsPermission() async {
    notificationsEnabled = grantPermissionOnRequest;
    return notificationsEnabled;
  }

  @override
  Future<bool> canScheduleExactNotifications() async => exactAlarmsAllowed;

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
    calls.add('schedule:$id');
    scheduled[id] = ScheduledNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      actions: actions,
      payload: payload,
      exact: exact,
    );
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel:$id');
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    scheduled.clear();
  }

  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();

  /// Test helper: simulates the OS delivering a notification tap/action,
  /// exactly as it would arrive via the real
  /// `onDidReceiveNotificationResponse` callback - i.e. through whatever
  /// [NotificationScheduler.initialize] registered as this transport's
  /// `onInteraction`, rather than by calling scheduler methods directly.
  Future<void> simulateInteraction(NotificationInteraction interaction) async {
    final callback = _onInteraction;
    if (callback != null) await callback(interaction);
  }
}
