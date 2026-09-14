/// Table and column name constants for the REmind SQLite schema, plus
/// schema version metadata. Centralizing these avoids typo-driven runtime
/// failures across data sources and keeps the schema self-documenting.
library;

class DbConfig {
  static const String databaseName = 'remind.db';

  /// Current shipped schema version.
  ///
  /// Version 1 is a deliberately minimal, hypothetical "tasks only" schema
  /// (see `LegacySchemaV1`) used purely to exercise and test a real
  /// upgrade path through `AppDatabase`'s onUpgrade logic. REmind has no
  /// installed base on version 1 - Part 1 shipped no database at all - so
  /// this lets us prove the migration mechanism works correctly *before* a
  /// real future schema change ever needs it.
  ///
  /// Version 3 adds `recurrence_rules.custom_unit`, needed so a "custom"
  /// recurrence rule can record whether its intervalValue counts in days,
  /// weeks, months, or years (see [RecurrenceCustomUnit] in enums.dart).
  ///
  /// Version 4 (Part 12.5 - production recurring task & reminder system)
  /// adds:
  ///  - `recurrence_rules.monthly_mode` + `recurrence_rules.week_ordinal`,
  ///    so a monthly rule can repeat by weekday-position ("the second
  ///    Tuesday of every month") in addition to the existing day-of-month
  ///    behavior (see [RecurrenceMonthlyMode] in enums.dart). Existing
  ///    monthly rules default to `monthly_mode = 0` (day-of-month), which
  ///    is byte-for-byte their existing behavior - nothing about an
  ///    existing rule changes.
  ///  - `tasks.occurrence_original_date`, which records the *canonical*
  ///    (un-rescheduled) date/time of a recurring task's current active
  ///    occurrence, only ever set when that one occurrence has been moved
  ///    via "Reschedule this occurrence". Null (the default, and always
  ///    true for every pre-v4 row) means "the task's own due date already
  ///    is the canonical occurrence date" - i.e. exactly today's
  ///    behavior. See `ReminderEngine` for how this anchors recurrence
  ///    math back onto the original schedule after a one-off reschedule.
  ///  - the new `occurrence_exceptions` table, an additive, append-only
  ///    log of per-occurrence actions (skip / cancel / reschedule) a user
  ///    takes on a single occurrence of a recurring task without
  ///    affecting the rest of the series. See [OccurrenceExceptionsTable].
  static const int databaseVersion = 4;
}

class CategoriesTable {
  static const String name = 'categories';
  static const String id = 'id';
  static const String categoryName = 'name';
  static const String color = 'color';
  static const String iconName = 'icon_name';
  static const String isDefault = 'is_default';
  static const String createdAt = 'created_at';
}

class TagsTable {
  static const String name = 'tags';
  static const String id = 'id';
  static const String tagName = 'name';
  static const String color = 'color';
  static const String createdAt = 'created_at';
}

class RecurrenceRulesTable {
  static const String name = 'recurrence_rules';
  static const String id = 'id';
  static const String frequency = 'frequency';
  static const String intervalValue = 'interval_value';

  /// For [RecurrenceFrequency.weekly]: the set of ISO weekdays (1-7) the
  /// rule fires on, comma-joined (e.g. "1,3,5").
  ///
  /// Reused for [RecurrenceFrequency.monthly] when [monthlyMode] is
  /// [RecurrenceMonthlyMode.weekdayPosition]: holds exactly one ISO
  /// weekday - the target weekday of [weekOrdinal] (e.g. "2" for "every
  /// _Tuesday_" in "the second _Tuesday_ of every month"). Unused (null)
  /// for every other frequency/mode, exactly as before.
  static const String daysOfWeek = 'days_of_week';
  static const String startDate = 'start_date';
  static const String endDate = 'end_date';
  static const String occurrencesCount = 'occurrences_count';
  static const String createdAt = 'created_at';

  /// Added in schema v3. Only meaningful when [frequency] is `custom`;
  /// null for every other frequency.
  static const String customUnit = 'custom_unit';

  /// Added in schema v4. Only meaningful when [frequency] is `monthly`:
  /// distinguishes day-of-month recurrence (0, the existing/default
  /// behavior - e.g. "the 15th of every month", using [startDate]'s day
  /// of month, clamped for short months) from weekday-position recurrence
  /// (1 - e.g. "the first Monday of every month", using [weekOrdinal] +
  /// [daysOfWeek]). Defaults to 0 for every existing row.
  static const String monthlyMode = 'monthly_mode';

  /// Added in schema v4. Only meaningful when [frequency] is `monthly`
  /// and [monthlyMode] is weekday-position: 1/2/3/4 for "first" through
  /// "fourth", or -1 for "last". Null otherwise.
  static const String weekOrdinal = 'week_ordinal';
}

class TasksTable {
  static const String name = 'tasks';
  static const String id = 'id';
  static const String title = 'title';
  static const String description = 'description';
  static const String priority = 'priority';
  static const String status = 'status';
  static const String categoryId = 'category_id';
  static const String recurrenceRuleId = 'recurrence_rule_id';
  static const String dueDate = 'due_date';
  static const String createdAt = 'created_at';
  static const String updatedAt = 'updated_at';
  static const String completedAt = 'completed_at';
  static const String isPinned = 'is_pinned';

  /// Added in schema v4. See [DbConfig.databaseVersion]'s v4 notes and
  /// `ReminderEngine` for how this anchors recurrence math after a
  /// single-occurrence reschedule. Null for every non-recurring task and
  /// for a recurring task whose current occurrence has not been
  /// individually rescheduled.
  static const String occurrenceOriginalDate = 'occurrence_original_date';
}

class TaskTagsTable {
  static const String name = 'task_tags';
  static const String taskId = 'task_id';
  static const String tagId = 'tag_id';
}

class RemindersTable {
  static const String name = 'reminders';
  static const String id = 'id';
  static const String taskId = 'task_id';
  static const String reminderTime = 'reminder_time';
  static const String reminderType = 'reminder_type';
  static const String isEnabled = 'is_enabled';
  static const String snoozeMinutes = 'snooze_minutes';
  static const String snoozedUntil = 'snoozed_until';
  static const String notificationId = 'notification_id';
  static const String createdAt = 'created_at';
}

/// Added in schema v4. An additive, append-only log of per-occurrence
/// actions (skip / cancel / reschedule) taken on a single dated occurrence
/// of a recurring task, without ever creating a row per *future*
/// occurrence and without mutating the recurrence rule or the task's own
/// stored fields (which continue to describe the series as a whole).
///
/// [recurrenceRuleId] + [occurrenceDate] together are the deterministic
/// occurrence identity the spec requires - the same pairing iCalendar
/// uses (RECURRENCE-ID). The unique index on that pair (see
/// `SchemaV4.createIndexes`) is what guarantees a duplicate occurrence
/// action can never be recorded twice.
class OccurrenceExceptionsTable {
  static const String name = 'occurrence_exceptions';
  static const String id = 'id';
  static const String recurrenceRuleId = 'recurrence_rule_id';

  /// The occurrence's own *canonical, un-rescheduled* date/time, as
  /// [RecurrenceCalculator] would compute it directly from the rule -
  /// i.e. the identity half of the (rule, date) key. This is never the
  /// rescheduled-to time.
  static const String occurrenceDate = 'occurrence_date';

  /// An [OccurrenceExceptionStatus.dbValue].
  static const String status = 'status';

  /// Only set when [status] is [OccurrenceExceptionStatus.rescheduled].
  static const String rescheduledTo = 'rescheduled_to';
  static const String createdAt = 'created_at';
}

class SettingsTable {
  static const String name = 'settings';
  static const String key = 'key';
  static const String value = 'value';
  static const String updatedAt = 'updated_at';
}

/// The 7 default categories seeded on first run.
const List<String> kDefaultCategoryNames = [
  'Work',
  'Study',
  'Personal',
  'Finance',
  'Shopping',
  'Health',
  'Other',
];
