/// Priority level for a [TaskModel], stored in SQLite as a plain integer.
enum TaskPriority {
  low,
  medium,
  high,
  urgent;

  int get dbValue => index;

  static TaskPriority fromDbValue(int value) => TaskPriority.values[value];
}

/// Lifecycle status for a [TaskModel], stored in SQLite as a plain integer.
enum TaskStatus {
  pending,
  inProgress,
  completed,
  cancelled;

  int get dbValue => index;

  static TaskStatus fromDbValue(int value) => TaskStatus.values[value];
}

/// How a [ReminderModel] should surface to the user, stored in SQLite as a
/// plain integer.
enum ReminderType {
  notification,
  alarm,
  silent;

  int get dbValue => index;

  static ReminderType fromDbValue(int value) => ReminderType.values[value];
}

/// How often a [RecurrenceRuleModel] repeats, stored in SQLite as a plain
/// integer.
enum RecurrenceFrequency {
  daily,
  weekly,
  monthly,
  yearly,
  custom;

  int get dbValue => index;

  static RecurrenceFrequency fromDbValue(int value) =>
      RecurrenceFrequency.values[value];
}

/// The unit that a [RecurrenceFrequency.custom] rule's `intervalValue`
/// counts in (e.g. "every 3 days" vs "every 3 months"), stored in SQLite
/// as a plain integer. Only meaningful when a rule's frequency is
/// [RecurrenceFrequency.custom].
enum RecurrenceCustomUnit {
  days,
  weeks,
  months,
  years;

  int get dbValue => index;

  static RecurrenceCustomUnit fromDbValue(int value) =>
      RecurrenceCustomUnit.values[value];
}
