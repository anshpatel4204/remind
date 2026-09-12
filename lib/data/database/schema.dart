import 'db_constants.dart';

/// SQL statements for the current (version 2) REmind schema.
class SchemaV2 {
  static const String createCategories = '''
CREATE TABLE ${CategoriesTable.name} (
  ${CategoriesTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
  ${CategoriesTable.categoryName} TEXT NOT NULL UNIQUE,
  ${CategoriesTable.color} TEXT,
  ${CategoriesTable.iconName} TEXT,
  ${CategoriesTable.isDefault} INTEGER NOT NULL DEFAULT 0,
  ${CategoriesTable.createdAt} INTEGER NOT NULL
)
''';

  static const String createTags = '''
CREATE TABLE ${TagsTable.name} (
  ${TagsTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
  ${TagsTable.tagName} TEXT NOT NULL UNIQUE,
  ${TagsTable.color} TEXT,
  ${TagsTable.createdAt} INTEGER NOT NULL
)
''';

  static const String createRecurrenceRules = '''
CREATE TABLE ${RecurrenceRulesTable.name} (
  ${RecurrenceRulesTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
  ${RecurrenceRulesTable.frequency} INTEGER NOT NULL,
  ${RecurrenceRulesTable.intervalValue} INTEGER NOT NULL DEFAULT 1,
  ${RecurrenceRulesTable.daysOfWeek} TEXT,
  ${RecurrenceRulesTable.startDate} INTEGER NOT NULL,
  ${RecurrenceRulesTable.endDate} INTEGER,
  ${RecurrenceRulesTable.occurrencesCount} INTEGER,
  ${RecurrenceRulesTable.createdAt} INTEGER NOT NULL
)
''';

  static const String createTasks = '''
CREATE TABLE ${TasksTable.name} (
  ${TasksTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
  ${TasksTable.title} TEXT NOT NULL,
  ${TasksTable.description} TEXT,
  ${TasksTable.priority} INTEGER NOT NULL DEFAULT 1,
  ${TasksTable.status} INTEGER NOT NULL DEFAULT 0,
  ${TasksTable.categoryId} INTEGER,
  ${TasksTable.recurrenceRuleId} INTEGER,
  ${TasksTable.dueDate} INTEGER,
  ${TasksTable.createdAt} INTEGER NOT NULL,
  ${TasksTable.updatedAt} INTEGER NOT NULL,
  ${TasksTable.completedAt} INTEGER,
  ${TasksTable.isPinned} INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (${TasksTable.categoryId}) REFERENCES ${CategoriesTable.name} (${CategoriesTable.id}) ON DELETE SET NULL,
  FOREIGN KEY (${TasksTable.recurrenceRuleId}) REFERENCES ${RecurrenceRulesTable.name} (${RecurrenceRulesTable.id}) ON DELETE SET NULL
)
''';

  static const String createTaskTags = '''
CREATE TABLE ${TaskTagsTable.name} (
  ${TaskTagsTable.taskId} INTEGER NOT NULL,
  ${TaskTagsTable.tagId} INTEGER NOT NULL,
  PRIMARY KEY (${TaskTagsTable.taskId}, ${TaskTagsTable.tagId}),
  FOREIGN KEY (${TaskTagsTable.taskId}) REFERENCES ${TasksTable.name} (${TasksTable.id}) ON DELETE CASCADE,
  FOREIGN KEY (${TaskTagsTable.tagId}) REFERENCES ${TagsTable.name} (${TagsTable.id}) ON DELETE CASCADE
)
''';

  static const String createReminders = '''
CREATE TABLE ${RemindersTable.name} (
  ${RemindersTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
  ${RemindersTable.taskId} INTEGER NOT NULL,
  ${RemindersTable.reminderTime} INTEGER NOT NULL,
  ${RemindersTable.reminderType} INTEGER NOT NULL DEFAULT 0,
  ${RemindersTable.isEnabled} INTEGER NOT NULL DEFAULT 1,
  ${RemindersTable.snoozeMinutes} INTEGER,
  ${RemindersTable.snoozedUntil} INTEGER,
  ${RemindersTable.notificationId} INTEGER,
  ${RemindersTable.createdAt} INTEGER NOT NULL,
  FOREIGN KEY (${RemindersTable.taskId}) REFERENCES ${TasksTable.name} (${TasksTable.id}) ON DELETE CASCADE
)
''';

  static const String createSettings = '''
CREATE TABLE ${SettingsTable.name} (
  ${SettingsTable.key} TEXT PRIMARY KEY,
  ${SettingsTable.value} TEXT,
  ${SettingsTable.updatedAt} INTEGER NOT NULL
)
''';

  /// Indexes on columns the application will frequently filter or sort by.
  /// Deliberately not indexing low-cardinality/rarely-filtered columns
  /// (e.g. is_pinned, reminder_type) to avoid unnecessary write overhead.
  ///
  /// task_tags.task_id is not given its own index here: it is the leading
  /// column of that table's composite PRIMARY KEY (task_id, tag_id), and
  /// SQLite already indexes a composite key's leftmost prefix, so a
  /// separate index on task_id would be redundant. The reverse lookup
  /// (tag_id -> tasks) has no such free index, hence idx_task_tags_tag_id.
  static const List<String> createIndexes = [
    'CREATE INDEX idx_tasks_due_date ON ${TasksTable.name} (${TasksTable.dueDate})',
    'CREATE INDEX idx_tasks_status ON ${TasksTable.name} (${TasksTable.status})',
    'CREATE INDEX idx_tasks_priority ON ${TasksTable.name} (${TasksTable.priority})',
    'CREATE INDEX idx_tasks_category_id ON ${TasksTable.name} (${TasksTable.categoryId})',
    'CREATE INDEX idx_reminders_reminder_time ON ${RemindersTable.name} (${RemindersTable.reminderTime})',
    'CREATE INDEX idx_reminders_task_id ON ${RemindersTable.name} (${RemindersTable.taskId})',
    'CREATE INDEX idx_task_tags_tag_id ON ${TaskTagsTable.name} (${TaskTagsTable.tagId})',
  ];

  static const List<String> createAllTables = [
    createCategories,
    createTags,
    createRecurrenceRules,
    createTasks,
    createTaskTags,
    createReminders,
    createSettings,
  ];
}

/// SQL statements for schema version 3.
///
/// The only change from [SchemaV2] is that `recurrence_rules` gains a
/// `custom_unit` column (see [RecurrenceRulesTable.customUnit]). Every
/// other table is byte-for-byte identical, so this class deliberately
/// reuses [SchemaV2]'s constants for them rather than redeclaring the SQL
/// - that keeps [SchemaV2] itself frozen/historical (still needed as-is by
/// the existing v1 -> v2 upgrade path) and means an unchanged table's SQL
/// only ever has to be correct in one place.
class SchemaV3 {
  static const String createCategories = SchemaV2.createCategories;
  static const String createTags = SchemaV2.createTags;

  static const String createRecurrenceRules = '''
CREATE TABLE ${RecurrenceRulesTable.name} (
  ${RecurrenceRulesTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
  ${RecurrenceRulesTable.frequency} INTEGER NOT NULL,
  ${RecurrenceRulesTable.intervalValue} INTEGER NOT NULL DEFAULT 1,
  ${RecurrenceRulesTable.daysOfWeek} TEXT,
  ${RecurrenceRulesTable.startDate} INTEGER NOT NULL,
  ${RecurrenceRulesTable.endDate} INTEGER,
  ${RecurrenceRulesTable.occurrencesCount} INTEGER,
  ${RecurrenceRulesTable.createdAt} INTEGER NOT NULL,
  ${RecurrenceRulesTable.customUnit} INTEGER
)
''';

  static const String createTasks = SchemaV2.createTasks;
  static const String createTaskTags = SchemaV2.createTaskTags;
  static const String createReminders = SchemaV2.createReminders;
  static const String createSettings = SchemaV2.createSettings;

  static const List<String> createIndexes = SchemaV2.createIndexes;

  static const List<String> createAllTables = [
    createCategories,
    createTags,
    createRecurrenceRules,
    createTasks,
    createTaskTags,
    createReminders,
    createSettings,
  ];
}
