/// The hypothetical "version 1" schema: a bare-bones tasks table with none
/// of the relational structure introduced in version 2 (no categories,
/// tags, reminders, recurrence, or settings tables).
///
/// REmind has no real users on this schema - Part 1 shipped no database at
/// all - so this exists purely so `AppDatabase`'s upgrade path (version 1
/// to version 2) has a genuine, testable predecessor schema to migrate
/// from, rather than leaving the migration machinery unexercised until a
/// real future schema change comes along.
class LegacySchemaV1 {
  static const String tableName = 'tasks';

  static const String createTasks = '''
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  is_done INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
)
''';
}
