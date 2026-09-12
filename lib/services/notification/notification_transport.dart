/// Action identifiers shown on every reminder notification. Plain string
/// constants rather than an enum tied to any notification package's own
/// action type, so both the real transport ([NotificationService]) and a
/// test fake can agree on them without either depending on the other.
class NotificationActionIds {
  NotificationActionIds._();

  static const String complete = 'complete';
  static const String snooze = 'snooze';
  static const String dismiss = 'dismiss';
}

/// One action button to show on a notification.
class NotificationAction {
  const NotificationAction({
    required this.id,
    required this.title,
    this.cancelNotification = true,
  });

  /// One of [NotificationActionIds], round-tripped back via
  /// [NotificationInteraction.actionId] when the user taps this button.
  final String id;
  final String title;

  /// Whether tapping this action removes the notification from the tray.
  /// True (the default) is right for a terminal action like Complete or
  /// Dismiss. Snooze sets this false: the notification should stay visible,
  /// unchanged, until the snoozed time arrives and the same notification id
  /// is re-shown for the new time - not disappear the instant it's tapped.
  final bool cancelNotification;
}

/// What happened when the user interacted with a notification - either
/// tapping its body, or tapping one of its action buttons.
///
/// Deliberately a plain Dart class with no dependency on any notification
/// package's own response type, so [NotificationScheduler] (and its tests)
/// never need to import one.
class NotificationInteraction {
  const NotificationInteraction({required this.notificationId, this.actionId, this.payload});

  final int notificationId;

  /// Null when the user tapped the notification's body rather than one of
  /// its action buttons.
  final String? actionId;

  /// Round-tripped back exactly as it was passed to
  /// [NotificationTransport.schedule].
  final String? payload;
}

/// Everything [NotificationScheduler] needs from the underlying platform
/// notification system, and nothing more.
///
/// This is the seam that keeps scheduling *decisions* (which id to reuse,
/// whether to cancel-before-reschedule, what each action means) unit
/// testable without a real Android device: production code is backed by
/// [NotificationService] (wrapping `flutter_local_notifications`); tests
/// use an in-memory fake that implements this same interface.
abstract class NotificationTransport {
  /// Must be called once, before any other method. [onInteraction] is
  /// invoked whenever the user interacts with a notification while the
  /// app process is still alive (foreground or background) - a killed
  /// app is handled separately by a fixed top-level entry point (see
  /// `NotificationService`'s background handler), since Android starts an
  /// entirely new, isolated Flutter engine for that case rather than
  /// calling back into this one.
  /// [onInteraction] must return the Future for its own async work (not
  /// just fire tasks off in the background) so a caller that needs to
  /// know an interaction has been fully handled - notably
  /// [NotificationScheduler]'s tests - can await it deterministically.
  Future<void> initialize({
    required Future<void> Function(NotificationInteraction interaction) onInteraction,
  });

  /// Whether the user currently allows this app to post notifications at
  /// all. Android 13+ requires explicit grant for this; earlier versions
  /// always report true. Never prompts.
  Future<bool> areNotificationsEnabled();

  /// Prompts the user for notification permission if it hasn't already
  /// been determined, and returns the resulting grant state. Safe to call
  /// even where no prompt is needed (e.g. below Android 13) - it simply
  /// returns the existing state.
  Future<bool> requestNotificationsPermission();

  /// Whether exact-time alarms can currently be scheduled. When false, a
  /// [schedule] call falls back to inexact timing rather than throwing -
  /// this is REmind's answer to "do not assume permissions are
  /// automatically granted".
  Future<bool> canScheduleExactNotifications();

  /// Schedules a notification to fire at [scheduledTime]. If [id] is
  /// already scheduled, it is replaced - callers should still explicitly
  /// [cancel] an old [id] first when the *time itself* is changing (see
  /// [NotificationScheduler.rescheduleForReminder]), so there is never a
  /// window where two notifications for the same reminder both exist.
  ///
  /// [payload] round-trips back through [NotificationInteraction.payload]
  /// untouched - REmind uses it to carry the reminder's database id.
  /// [exact] false requests inexact (battery-friendlier, OS-batched)
  /// timing instead, used when [canScheduleExactNotifications] is false.
  Future<void> schedule({
    required int id,
    required String title,
    String? body,
    required DateTime scheduledTime,
    required List<NotificationAction> actions,
    String? payload,
    bool exact = true,
  });

  /// Cancels a scheduled or currently-showing notification. Safe to call
  /// for an id that isn't actually scheduled.
  Future<void> cancel(int id);

  Future<void> cancelAll();

  /// IDs of every notification currently scheduled (not yet fired or
  /// cancelled). Used by [NotificationScheduler]'s startup reconciliation
  /// pass to detect drift between the database and what the OS actually
  /// has scheduled.
  Future<Set<int>> pendingIds();
}

/// A [NotificationTransport] that does nothing. Useful anywhere a working
/// [AppRepositories] is needed but there is no interest in (and no real
/// platform to back) actual notifications - e.g. widget tests that only
/// exercise task/category/tag screens.
class NoopNotificationTransport implements NotificationTransport {
  const NoopNotificationTransport();

  @override
  Future<void> initialize({
    required Future<void> Function(NotificationInteraction interaction) onInteraction,
  }) async {}

  @override
  Future<bool> areNotificationsEnabled() async => false;

  @override
  Future<bool> requestNotificationsPermission() async => false;

  @override
  Future<bool> canScheduleExactNotifications() async => false;

  @override
  Future<void> schedule({
    required int id,
    required String title,
    String? body,
    required DateTime scheduledTime,
    required List<NotificationAction> actions,
    String? payload,
    bool exact = true,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<Set<int>> pendingIds() async => const <int>{};
}
