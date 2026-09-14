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

  /// Added for backup schema v2 (Part 12.5). Absent entirely in a backup
  /// made by an older REmind version - see [BackupRepository] for how
  /// that absence is treated as "no exceptions" rather than a validation
  /// error.
  static const String occurrenceExceptions = 'occurrenceExceptions';
}

/// The backup *file format* version - separate from the on-device SQLite
/// schema version (`DbConfig.databaseVersion`). This only changes when the
/// shape of the backup JSON itself changes (a field added, renamed, or
/// restructured), so a backup made by an older REmind version can still be
/// recognised - and, where the shape actually changed, upgraded - on the
/// way back in, instead of just rejected.
///
/// Version 2 (Part 12.5) adds the [BackupJsonKeys.occurrenceExceptions]
/// table and new fields on `recurrenceRules` (`monthlyMode`,
/// `weekOrdinal`) and `tasks` (`occurrenceOriginalDate`). A v1 backup
/// restores perfectly well on a v2+ app: the new table is simply absent
/// (treated as empty) and the new row fields are absent (their models
/// already treat a missing key exactly like an explicit `null`, which is
/// each new field's own "not set" state) - see
/// [RecurrenceRuleModel.fromMap] and [TaskModel.fromMap].
const int kBackupSchemaVersion = 2;
