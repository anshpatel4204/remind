import '../database/db_constants.dart';
import 'enums.dart';

/// A scheduled reminder tied to a task.
class ReminderModel {
  const ReminderModel({
    this.id,
    required this.taskId,
    required this.reminderTime,
    this.reminderType = ReminderType.notification,
    this.isEnabled = true,
    this.snoozeMinutes,
    this.snoozedUntil,
    this.notificationId,
    required this.createdAt,
  });

  final int? id;
  final int taskId;
  final DateTime reminderTime;
  final ReminderType reminderType;
  final bool isEnabled;

  /// Length of the most recent snooze, in minutes. Null if never snoozed.
  final int? snoozeMinutes;

  /// When set, the reminder is currently snoozed until this time.
  final DateTime? snoozedUntil;

  /// The OS notification id this reminder was last scheduled under, so it
  /// can be cancelled/updated later. Null until the notification/reminder
  /// scheduling engine (a later part of this project) assigns one.
  final int? notificationId;
  final DateTime createdAt;

  factory ReminderModel.fromMap(Map<String, Object?> map) {
    return ReminderModel(
      id: map[RemindersTable.id] as int?,
      taskId: map[RemindersTable.taskId] as int,
      reminderTime: DateTime.fromMillisecondsSinceEpoch(map[RemindersTable.reminderTime] as int),
      reminderType: ReminderType.fromDbValue(map[RemindersTable.reminderType] as int),
      isEnabled: (map[RemindersTable.isEnabled] as int) == 1,
      snoozeMinutes: map[RemindersTable.snoozeMinutes] as int?,
      snoozedUntil: map[RemindersTable.snoozedUntil] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map[RemindersTable.snoozedUntil] as int),
      notificationId: map[RemindersTable.notificationId] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[RemindersTable.createdAt] as int),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    final map = <String, Object?>{
      RemindersTable.taskId: taskId,
      RemindersTable.reminderTime: reminderTime.millisecondsSinceEpoch,
      RemindersTable.reminderType: reminderType.dbValue,
      RemindersTable.isEnabled: isEnabled ? 1 : 0,
      RemindersTable.snoozeMinutes: snoozeMinutes,
      RemindersTable.snoozedUntil: snoozedUntil?.millisecondsSinceEpoch,
      RemindersTable.notificationId: notificationId,
      RemindersTable.createdAt: createdAt.millisecondsSinceEpoch,
    };
    if (includeId && id != null) {
      map[RemindersTable.id] = id;
    }
    return map;
  }

  ReminderModel copyWith({
    int? id,
    int? taskId,
    DateTime? reminderTime,
    ReminderType? reminderType,
    bool? isEnabled,
    int? snoozeMinutes,
    DateTime? snoozedUntil,
    /// Clears [snoozeMinutes] and [snoozedUntil] together - a reminder is
    /// never meaningfully "half snoozed", so these two always change as a
    /// pair rather than needing separate clear flags.
    bool clearSnooze = false,
    int? notificationId,
    DateTime? createdAt,
  }) {
    return ReminderModel(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      reminderTime: reminderTime ?? this.reminderTime,
      reminderType: reminderType ?? this.reminderType,
      isEnabled: isEnabled ?? this.isEnabled,
      snoozeMinutes: clearSnooze ? null : (snoozeMinutes ?? this.snoozeMinutes),
      snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
      notificationId: notificationId ?? this.notificationId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'ReminderModel(id: $id, taskId: $taskId, reminderTime: $reminderTime)';
}
