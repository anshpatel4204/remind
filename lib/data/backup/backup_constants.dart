/// Key names used in the REmind backup JSON format. Centralized so the
/// export side and the validate/restore side can never drift out of sync
/// with each other the way two independently-typed string literals could.
class BackupJsonKeys {
  static const String schemaVersion = 'schemaVersion';
  static const String appDatabaseVersion = 'appDatabaseVersion';
  static const String exportedAt = 'exportedAt';
  static const String data = 'data';

  static const String categories = 'categories';
  static const String tags = 'tags';
  static const String recurrenceRules = 'recurrenceRules';
  static const String tasks = 'tasks';
  static const String taskTags = 'taskTags';
  static const String reminders = 'reminders';
  static const String settings = 'settings';
}

/// The backup *file format* version - separate from the on-device SQLite
/// schema version (`DbConfig.databaseVersion`). This only changes when the
/// shape of the backup JSON itself changes (a field added, renamed, or
/// restructured), so a backup made by an older REmind version can still be
/// recognised - and, where the shape actually changed, upgraded - on the
/// way back in, instead of just rejected.
const int kBackupSchemaVersion = 1;
