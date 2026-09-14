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

/// For a [RecurrenceFrequency.monthly] rule, which of two ways it repeats
/// each month, stored in SQLite as a plain integer. Every other frequency
/// ignores this field entirely.
enum RecurrenceMonthlyMode {
  /// "The 15th of every month" - uses the recurrence's start date's day
  /// of month (see [RecurrenceCalculator]'s month-end clamping for what
  /// happens when a target month is too short to have that day). This is
  /// REmind's original (pre-Part-12.5) monthly behavior, and remains the
  /// default for every existing rule.
  dayOfMonth,

  /// "The first Monday of every month" (or "the last Friday...") - uses
  /// [RecurrenceRuleModel.weekOrdinal] plus the single weekday stored in
  /// [RecurrenceRuleModel.daysOfWeek].
  weekdayPosition;

  int get dbValue => index;

  static RecurrenceMonthlyMode fromDbValue(int value) =>
      RecurrenceMonthlyMode.values[value];
}

/// Which occurrence, within a month, a [RecurrenceMonthlyMode.weekdayPosition]
/// rule targets. Not stored directly - [value] is what's persisted in
/// [RecurrenceRuleModel.weekOrdinal].
enum WeekOrdinal {
  first(1),
  second(2),
  third(3),
  fourth(4),

  /// The last occurrence of the target weekday in the month, whichever
  /// calendar date that lands on - always exists, unlike [fourth], which
  /// a very small fraction of month/weekday combinations lack.
  last(-1);

  const WeekOrdinal(this.value);

  final int value;

  static WeekOrdinal fromValue(int value) =>
      WeekOrdinal.values.firstWhere((o) => o.value == value);
}

/// The kind of per-occurrence override recorded for a single dated
/// occurrence of a recurring task, stored in SQLite as a plain integer.
/// See [OccurrenceExceptionsTable].
enum OccurrenceExceptionStatus {
  /// The user chose "Skip this occurrence" (or "Delete this occurrence") -
  /// this one date is removed from the series; the next occurrence after
  /// it fires normally.
  skipped,

  /// Recorded when "Cancel future occurrences" is used, against the last
  /// occurrence date the series will still fire for context/history. The
  /// actual stopping mechanism is the recurrence rule's own end date -
  /// see `ReminderEngine.cancelFutureOccurrences`.
  cancelled,

  /// The user chose "Reschedule this occurrence" - [rescheduledTo] holds
  /// the new date/time; the *next* occurrence after this one is still
  /// computed from the original (un-rescheduled) [occurrenceDate], so a
  /// one-off reschedule never drifts the rest of the series.
  rescheduled,

  /// The user completed this specific occurrence - recorded for history
  /// even though the task row's own `completedAt` already reflects the
  /// most recent completion, so a later query can tell an occurrence was
  /// completed out of the usual on-time flow (e.g. after being
  /// individually rescheduled).
  completed;

  int get dbValue => index;

  static OccurrenceExceptionStatus fromDbValue(int value) =>
      OccurrenceExceptionStatus.values[value];
}

/// The user's preferred clock format for every time REmind displays,
/// stored as a plain string setting (`name`) in the `settings` key/value
/// table - unlike the enums above, this is never a SQLite table column,
/// so there's no `dbValue`/`fromDbValue` integer pair to keep stable
/// across releases.
enum TimeFormatPreference {
  /// Follow the device's own 12/24-hour setting (`MediaQuery`'s
  /// `alwaysUse24HourFormat`). The default for every user until they
  /// explicitly choose otherwise.
  system,
  h12,
  h24;

  static TimeFormatPreference fromName(String? name) {
    return TimeFormatPreference.values
        .firstWhere((v) => v.name == name, orElse: () => system);
  }
}

/// Which weekday REmind's Calendar week view starts on, stored as a plain
/// string setting (see [TimeFormatPreference]'s doc comment for why this
/// isn't a table-column enum).
enum FirstDayOfWeekPreference {
  /// Monday for most locales; REmind has no per-locale first-day table,
  /// so "system" currently resolves to Monday, matching REmind's existing
  /// (pre-Part-13) Calendar/Statistics behavior exactly until a user
  /// picks something else.
  system,
  monday,
  sunday;

  static FirstDayOfWeekPreference fromName(String? name) {
    return FirstDayOfWeekPreference.values
        .firstWhere((v) => v.name == name, orElse: () => system);
  }
}

/// App-wide text scale preference (an accessibility setting), stored as a
/// plain string setting (see [TimeFormatPreference]'s doc comment).
/// Applied via a `MediaQuery` override wrapping the whole app rather than
/// per-widget, so every screen scales consistently.
enum TextScalePreference {
  small(0.85),
  standard(1.0),
  large(1.15),
  extraLarge(1.3);

  const TextScalePreference(this.scaleFactor);

  final double scaleFactor;

  static TextScalePreference fromName(String? name) {
    return TextScalePreference.values
        .firstWhere((v) => v.name == name, orElse: () => standard);
  }
}
