import '../../data/models/enums.dart';
import '../../data/models/reminder_model.dart';
import '../../data/repositories/reminder_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/task_repository.dart';
import 'notification_transport.dart';
import '../reminder/reminder_engine.dart';

/// A preset (or "custom") snooze length, matching the spec's required
/// options exactly: 5/10/15/30 minutes, 1 hour, "Tomorrow", and a custom
/// duration a caller supplies itself.
enum SnoozeOption {
  fiveMinutes(Duration(minutes: 5)),
  tenMinutes(Duration(minutes: 10)),
  fifteenMinutes(Duration(minutes: 15)),
  thirtyMinutes(Duration(minutes: 30)),
  oneHour(Duration(hours: 1)),

  /// Same time of day, next calendar day - not a raw 24-hour add, so a
  /// daylight-saving transition can never shift the wall-clock hour (see
  /// [NotificationScheduler._resolveSnoozeTime]).
  tomorrow(null),

  /// The caller supplies an explicit duration via
  /// [NotificationScheduler.snoozeReminder]'s `customDuration` parameter.
  custom(null);

  const SnoozeOption(this.fixedDuration);

  /// Null for [tomorrow] (computed specially) and [custom] (caller-
  /// supplied), set for every fixed-length preset.
  final Duration? fixedDuration;
}

/// Connects the pure scheduling decisions in [ReminderEngine] to an actual
/// platform notification via [NotificationTransport].
///
/// This is the "Notification Scheduler" layer of REmind's reminder
/// architecture (SQLite -> Reminder Engine -> Notification Scheduler ->
/// Android -> Notification): screens never talk to [NotificationTransport]
/// or [ReminderEngine] directly for anything reminder-related, they call
/// through here, so every reminder mutation and every notification action
/// goes through one place. A reminder's own `id` doubles as the Android
/// notification id for its notification, and is mirrored into
/// [ReminderModel.notificationId] - one reminder, one id, everywhere.
class NotificationScheduler {
  NotificationScheduler({
    required NotificationTransport transport,
    required TaskRepository taskRepository,
    required ReminderRepository reminderRepository,
    required ReminderEngine reminderEngine,
    required SettingsRepository settingsRepository,
  })  : _transport = transport,
        _taskRepository = taskRepository,
        _reminderRepository = reminderRepository,
        _reminderEngine = reminderEngine,
        _settingsRepository = settingsRepository;

  final NotificationTransport _transport;
  final TaskRepository _taskRepository;
  final ReminderRepository _reminderRepository;
  final ReminderEngine _reminderEngine;
  final SettingsRepository _settingsRepository;

  // Settings keys for this screen's in-app notification preferences -
  // deliberately separate from the OS-level permission state
  // ([notificationsEnabled]/[canScheduleExactAlarms]), which the app can
  // only ever read/request, never override. Unset means "on" for the
  // three booleans, matching the app's previous (pre-Part-11) behavior
  // exactly, so upgrading to this version never silently mutes an
  // existing install.
  static const String _keyMasterEnabled = 'notifications_master_enabled';
  static const String _keySoundEnabled = 'notifications_sound_enabled';
  static const String _keyVibrationEnabled = 'notifications_vibration_enabled';
  static const String _keyDefaultSnooze = 'notifications_default_snooze';

  /// The presets a user can pick as their default - [SnoozeOption.tomorrow]
  /// and [SnoozeOption.custom] are deliberately excluded: both need an
  /// explicit in-the-moment choice (a date, or a custom duration) that a
  /// stored "default" can't sensibly stand in for.
  static const List<SnoozeOption> defaultableSnoozeOptions = [
    SnoozeOption.fiveMinutes,
    SnoozeOption.tenMinutes,
    SnoozeOption.fifteenMinutes,
    SnoozeOption.thirtyMinutes,
    SnoozeOption.oneHour,
  ];

  static const List<NotificationAction> _actions = [
    NotificationAction(id: NotificationActionIds.complete, title: 'Complete'),
    // Snooze doesn't remove the notification - it should stay visible in the
    // tray, unchanged, until the snoozed time arrives and re-fires (see
    // NotificationAction.cancelNotification).
    NotificationAction(
      id: NotificationActionIds.snooze,
      title: 'Snooze',
      cancelNotification: false,
    ),
    NotificationAction(id: NotificationActionIds.dismiss, title: 'Dismiss'),
  ];

  /// Wires the transport's interaction callback to [handleInteraction].
  /// Must be called once at app startup before scheduling anything.
  Future<void> initialize() {
    return _transport.initialize(onInteraction: handleInteraction);
  }

  /// Ensures the app can actually post notifications, prompting the user
  /// if permission hasn't been determined yet. Safe to call more than
  /// once - REmind never assumes permission is already granted just
  /// because it asked before. Returns the resulting grant state.
  Future<bool> ensureNotificationPermission() async {
    if (await _transport.areNotificationsEnabled()) return true;
    return _transport.requestNotificationsPermission();
  }

  /// Read-only status checks for a Settings-style screen: report the
  /// current state without ever prompting the user (unlike
  /// [ensureNotificationPermission], which requests permission if it
  /// hasn't been decided yet).
  Future<bool> notificationsEnabled() => _transport.areNotificationsEnabled();

  Future<bool> canScheduleExactAlarms() =>
      _transport.canScheduleExactNotifications();

  /// Whether REmind should post reminder notifications at all - an
  /// in-app master switch, independent of (and layered on top of) the
  /// OS-level permission [notificationsEnabled] reports. Reminder rows
  /// are always created/updated normally either way; this only decides
  /// whether [_scheduleNotificationFor] actually reaches the platform.
  Future<bool> notificationsMasterEnabled() async {
    final raw = await _settingsRepository.getValue(_keyMasterEnabled);
    return raw == null ? true : raw == 'true';
  }

  /// Turning this off immediately cancels every currently scheduled/shown
  /// notification (nothing left buzzing after the user says "stop").
  /// Turning it back on re-schedules everything that should currently be
  /// active, the same way app startup does.
  Future<void> setNotificationsMasterEnabled(bool enabled) async {
    await _settingsRepository.setValue(_keyMasterEnabled, enabled.toString());
    if (enabled) {
      await reconcileAfterStartup();
    } else {
      await _transport.cancelAll();
    }
  }

  Future<bool> soundEnabled() async {
    final raw = await _settingsRepository.getValue(_keySoundEnabled);
    return raw == null ? true : raw == 'true';
  }

  Future<void> setSoundEnabled(bool enabled) {
    return _settingsRepository.setValue(_keySoundEnabled, enabled.toString());
  }

  Future<bool> vibrationEnabled() async {
    final raw = await _settingsRepository.getValue(_keyVibrationEnabled);
    return raw == null ? true : raw == 'true';
  }

  Future<void> setVibrationEnabled(bool enabled) {
    return _settingsRepository.setValue(
        _keyVibrationEnabled, enabled.toString());
  }

  /// The [SnoozeOption] applied when a notification's own Snooze action
  /// button is tapped (see [handleInteraction]) - there is no way to show
  /// an in-app duration picker from a background/killed-app tap, so it
  /// always needs a concrete fallback. Defaults to [SnoozeOption.tenMinutes],
  /// matching the app's previous (pre-Part-11) hardcoded behavior.
  Future<SnoozeOption> defaultSnoozeOption() async {
    final raw = await _settingsRepository.getValue(_keyDefaultSnooze);
    for (final option in defaultableSnoozeOptions) {
      if (option.name == raw) return option;
    }
    return SnoozeOption.tenMinutes;
  }

  Future<void> setDefaultSnoozeOption(SnoozeOption option) {
    assert(
      defaultableSnoozeOptions.contains(option),
      'defaultSnoozeOption must be one of defaultableSnoozeOptions',
    );
    return _settingsRepository.setValue(_keyDefaultSnooze, option.name);
  }

  /// Creates a new reminder for [taskId] and schedules its notification in
  /// the same step, so a reminder row is never left without a matching
  /// scheduled notification (or vice versa).
  Future<ReminderModel> createAndScheduleReminder({
    required int taskId,
    required DateTime reminderTime,
    ReminderType reminderType = ReminderType.notification,
  }) async {
    final reminder = await _reminderEngine.scheduleReminder(
      taskId: taskId,
      reminderTime: reminderTime,
      reminderType: reminderType,
    );
    await _scheduleNotificationFor(reminder);
    return reminder;
  }

  /// Moves an existing reminder to [newReminderTime]. The currently
  /// scheduled notification is always cancelled *before* the replacement
  /// is scheduled, so there is never a moment where two notifications
  /// exist for the same reminder - REmind's answer to "if a reminder is
  /// rescheduled, cancel the old scheduled notification before creating
  /// the new one".
  Future<void> updateAndRescheduleReminder(
      int reminderId, DateTime newReminderTime) async {
    await _transport.cancel(reminderId);
    await _reminderEngine.rescheduleReminder(reminderId, newReminderTime);
    final reminder = await _reminderRepository.getReminder(reminderId);
    if (reminder != null) await _scheduleNotificationFor(reminder);
  }

  /// Cancels a reminder's notification and disables the reminder itself
  /// (the row is kept - see [ReminderEngine.cancelReminder] - so it can be
  /// re-enabled later without losing its history).
  Future<void> cancelReminder(int reminderId) async {
    await _transport.cancel(reminderId);
    await _reminderEngine.cancelReminder(reminderId);
  }

  /// Deletes a reminder outright, cancelling its notification first. Used
  /// when a task's reminder is turned off entirely (as opposed to merely
  /// disabled) - e.g. from the task edit form.
  Future<void> deleteReminder(int reminderId) async {
    await _transport.cancel(reminderId);
    await _reminderRepository.deleteReminder(reminderId);
  }

  /// Snoozes [reminderId] by [option] (or, for [SnoozeOption.custom], by
  /// [customDuration]), then reschedules its notification for the new
  /// time. Returns the updated reminder, or null if it no longer exists.
  Future<ReminderModel?> snoozeReminder(
    int reminderId, {
    required SnoozeOption option,
    Duration? customDuration,
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final snoozeUntil =
        _resolveSnoozeTime(option, customDuration, effectiveNow);
    final snoozeMinutes = snoozeUntil.difference(effectiveNow).inMinutes;

    final updated = await _reminderEngine.handleSnoozedReminder(
      reminderId,
      snoozeMinutes: snoozeMinutes,
      now: effectiveNow,
    );
    if (updated == null) return null;

    await _transport.cancel(reminderId);
    await _scheduleNotificationFor(updated);
    return updated;
  }

  DateTime _resolveSnoozeTime(
      SnoozeOption option, Duration? customDuration, DateTime now) {
    switch (option) {
      case SnoozeOption.tomorrow:
        // Component-wise, not a 24-hour Duration add, so a daylight-saving
        // transition between now and tomorrow can't shift the hour.
        final tomorrowDate = DateTime(now.year, now.month, now.day + 1);
        return DateTime(
          tomorrowDate.year,
          tomorrowDate.month,
          tomorrowDate.day,
          now.hour,
          now.minute,
          now.second,
        );
      case SnoozeOption.custom:
        if (customDuration == null) {
          throw ArgumentError(
              'customDuration is required when option is SnoozeOption.custom');
        }
        return now.add(customDuration);
      default:
        return now.add(option.fixedDuration!);
    }
  }

  /// Routes a notification interaction (a tap on the body, or on one of
  /// the Complete/Snooze/Dismiss action buttons) to the right effect. The
  /// same method handles this whether the app is in the foreground,
  /// backgrounded, or was completely killed (see
  /// `notificationBackgroundEntryPoint` in notification_service.dart for
  /// the killed-app case, which calls this on its own freshly built
  /// instance).
  Future<void> handleInteraction(NotificationInteraction interaction) async {
    final reminderId = interaction.notificationId;
    switch (interaction.actionId) {
      case NotificationActionIds.complete:
        await _handleComplete(reminderId);
        return;
      case NotificationActionIds.snooze:
        // A notification action button fires immediately - there is no
        // way to show an in-app duration picker from it, so it applies
        // the user's configured default (see [defaultSnoozeOption]). The
        // full set of presets (and a custom duration) is available via
        // [snoozeReminder] for an in-app snooze control.
        await snoozeReminder(reminderId, option: await defaultSnoozeOption());
        return;
      case NotificationActionIds.dismiss:
        await _transport.cancel(reminderId);
        return;
      default:
        // A plain tap on the notification body (actionId is null) just
        // brings the app to the foreground, which the OS already does on
        // its own - nothing further to do here.
        return;
    }
  }

  Future<void> _handleComplete(int reminderId) async {
    final reminder = await _reminderRepository.getReminder(reminderId);
    if (reminder == null) return;
    await completeTask(reminder.taskId);
  }

  /// Marks [taskId] complete and applies whatever follow-up that implies
  /// for its reminders: every one of its currently scheduled notifications
  /// is cancelled, then - mirroring the calling convention
  /// [ReminderEngine.handleCompletedRecurringTask] expects - the task is
  /// marked complete and the engine decides whether to roll it forward to
  /// another occurrence. If it rolls forward, every reminder is
  /// rescheduled for its (engine-shifted) new time; if not - because the
  /// task isn't recurring, or its recurrence has ended - it simply stays
  /// completed, which is correct in both cases.
  ///
  /// Used both by a notification's own Complete action and by completing
  /// a task from within the app - either way, the task's reminder(s)
  /// should never still buzz the user again for an occurrence that's
  /// already done.
  Future<void> completeTask(int taskId) async {
    final reminders = await _reminderRepository.getRemindersForTask(taskId);
    for (final reminder in reminders) {
      final id = reminder.id;
      if (id != null) await _transport.cancel(id);
    }

    await _taskRepository.completeTask(taskId);
    final rolled = await _reminderEngine.handleCompletedRecurringTask(taskId);
    if (rolled == null) return;

    for (final reminder in reminders) {
      final id = reminder.id;
      if (id == null) continue;
      final shifted = await _reminderRepository.getReminder(id);
      if (shifted != null) await _scheduleNotificationFor(shifted);
    }
  }

  /// "Skip this occurrence" (and, equivalently, "Delete this occurrence")
  /// for a recurring task: cancels the current occurrence's scheduled
  /// notification, rolls the task forward to whatever occurrence comes
  /// after it (see [ReminderEngine.skipCurrentOccurrence] - the rest of
  /// the series, and the task's own completion history, are untouched),
  /// and schedules a notification for that new occurrence. If the
  /// recurrence has no occurrence left after the skipped one, nothing is
  /// rescheduled - mirroring how [completeTask] handles a recurrence
  /// that has ended.
  Future<void> skipOccurrence(int taskId, {DateTime? now}) async {
    final reminders = await _reminderRepository.getRemindersForTask(taskId);
    for (final reminder in reminders) {
      final id = reminder.id;
      if (id != null) await _transport.cancel(id);
    }

    final rolled =
        await _reminderEngine.skipCurrentOccurrence(taskId, now: now);
    if (rolled == null) return;

    for (final reminder in reminders) {
      final id = reminder.id;
      if (id == null) continue;
      final shifted = await _reminderRepository.getReminder(id);
      if (shifted != null) await _scheduleNotificationFor(shifted);
    }
  }

  /// "Reschedule this occurrence" (and, with this pass's scope, "Edit
  /// this occurrence") for a recurring task: moves just the current
  /// occurrence to [newDateTime] via
  /// [ReminderEngine.rescheduleCurrentOccurrence], which keeps the rest
  /// of the series on its original schedule. The occurrence's existing
  /// notification(s) are always cancelled *before* the replacement is
  /// scheduled, so there is never a moment where two notifications exist
  /// for the same reminder - the same guarantee
  /// [updateAndRescheduleReminder] gives a plain one-off reminder.
  Future<void> rescheduleOccurrence(
    int taskId,
    DateTime newDateTime, {
    DateTime? now,
  }) async {
    final reminders = await _reminderRepository.getRemindersForTask(taskId);
    for (final reminder in reminders) {
      final id = reminder.id;
      if (id != null) await _transport.cancel(id);
    }

    final updated = await _reminderEngine.rescheduleCurrentOccurrence(
      taskId,
      newDateTime,
      now: now,
    );
    if (updated == null) return;

    for (final reminder in reminders) {
      final id = reminder.id;
      if (id == null) continue;
      final shifted = await _reminderRepository.getReminder(id);
      if (shifted != null) await _scheduleNotificationFor(shifted);
    }
  }

  /// "Cancel future occurrences" for a recurring task: the current
  /// occurrence's own scheduled notification is left exactly as it is
  /// (it still fires normally, and can still be completed/snoozed/
  /// rescheduled) - only the recurrence rule itself is closed off (see
  /// [ReminderEngine.cancelFutureOccurrences]) so nothing new ever gets
  /// generated after it. Nothing here needs to touch the platform
  /// notification layer at all.
  Future<void> cancelFutureOccurrences(int taskId, {DateTime? now}) async {
    await _reminderEngine.cancelFutureOccurrences(taskId, now: now);
  }

  /// Cancels the scheduled notification for every reminder attached to
  /// [taskId], without touching any database row. Call this before
  /// deleting a task: its reminders will be cascade-deleted from the
  /// database, but that alone does not cancel their already-scheduled
  /// platform notifications.
  Future<void> cancelNotificationsForTask(int taskId) async {
    final reminders = await _reminderRepository.getRemindersForTask(taskId);
    for (final reminder in reminders) {
      final id = reminder.id;
      if (id != null) await _transport.cancel(id);
    }
  }

  /// Re-establishes every enabled, still-future reminder's scheduled
  /// notification, catches up any enabled reminder whose time has
  /// already passed to its recurring task's next valid future occurrence
  /// (see [ReminderEngine.catchUpMissedOccurrence]), and cancels any
  /// stray platform notification that no longer matches an enabled
  /// reminder.
  ///
  /// The Android boot receiver (see AndroidManifest.xml) already restores
  /// scheduled notifications natively after a device reboot without any
  /// Dart code running, so this is a defensive second layer rather than
  /// the only mechanism: it also catches drift from any other cause (an
  /// interrupted schedule call, a future data migration, and similar),
  /// and is cheap enough to run unconditionally on every app start.
  Future<void> reconcileAfterStartup({DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();
    final enabledReminders = await _reminderRepository.getAllEnabledReminders();
    final pendingIds = await _transport.pendingIds();
    final exact = await _transport.canScheduleExactNotifications();

    final enabledIds = <int>{};
    for (final reminder in enabledReminders) {
      final id = reminder.id;
      if (id == null) continue;
      enabledIds.add(id);

      final fireTime = reminder.snoozedUntil ?? reminder.reminderTime;
      if (!fireTime.isAfter(effectiveNow)) {
        // Already in the past (e.g. the app was closed for days, or a
        // snooze expired unattended). For a recurring task, jump straight
        // to the next still-future occurrence instead of leaving it stuck
        // in the past forever or queuing a notification for every
        // occurrence missed in between - see
        // ReminderEngine.catchUpMissedOccurrence. A non-recurring
        // reminder has no schedule to catch up to, so it is simply left
        // as a single overdue reminder, exactly as before.
        final caughtUp = await _reminderEngine.catchUpMissedOccurrence(id,
            now: effectiveNow);
        if (caughtUp != null) {
          await _scheduleNotificationFor(caughtUp, exactOverride: exact);
        }
        continue;
      }
      if (!pendingIds.contains(id)) {
        await _scheduleNotificationFor(reminder, exactOverride: exact);
      }
    }

    for (final pendingId in pendingIds) {
      if (!enabledIds.contains(pendingId)) {
        await _transport.cancel(pendingId);
      }
    }
  }

  Future<void> _scheduleNotificationFor(ReminderModel reminder,
      {bool? exactOverride}) async {
    final reminderId = reminder.id;
    if (reminderId == null) return;

    // The in-app master switch is checked here, in the one place every
    // scheduling path funnels through, rather than in each caller - the
    // reminder row itself is always created/updated normally either way,
    // only the actual platform notification is skipped while this is off.
    if (!await notificationsMasterEnabled()) return;

    final task = await _taskRepository.getTask(reminder.taskId);
    final exact =
        exactOverride ?? await _transport.canScheduleExactNotifications();
    final sound = await soundEnabled();
    final vibration = await vibrationEnabled();

    await _transport.schedule(
      id: reminderId,
      title: task?.title ?? 'Reminder',
      body: task?.description,
      scheduledTime: reminder.snoozedUntil ?? reminder.reminderTime,
      actions: _actions,
      payload: reminderId.toString(),
      exact: exact,
      soundEnabled: sound,
      vibrationEnabled: vibration,
    );

    if (reminder.notificationId != reminderId) {
      await _reminderRepository
          .updateReminder(reminder.copyWith(notificationId: reminderId));
    }
  }
}
