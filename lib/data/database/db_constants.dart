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
  static const int databaseVersion = 2;
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
  static const String daysOfWeek = 'days_of_week';
  static const String startDate = 'start_date';
  static const String endDate = 'end_date';
  static const String occurrencesCount = 'occurrences_count';
  static const String createdAt = 'created_at';
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
