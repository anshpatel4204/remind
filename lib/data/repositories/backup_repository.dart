import 'dart:convert';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/category_model.dart';
import '../models/recurrence_rule_model.dart';
import '../models/reminder_model.dart';
import '../models/setting_model.dart';
import '../models/tag_model.dart';
import '../models/task_model.dart';
import '../backup/backup_constants.dart';
import '../backup/backup_data.dart';
import '../backup/backup_exception.dart';

/// Builds and restores REmind's local JSON backup.
///
/// The whole of Part 10's "Backup" and "Restore" logic lives here as
/// plain, file-I/O-free code, so it can be unit tested against an
/// in-memory database exactly like every other repository in this project.
/// Turning the resulting JSON string into an actual file (and reading one
/// back) is left to `BackupFileService` in the services layer - this class
/// never imports `dart:io`.
class BackupRepository {
  BackupRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  /// Exports every table this app persists into one JSON document: tasks,
  /// reminders, recurrence rules, categories, tags, the task/tag
  /// relationship table, and settings - exactly the Part 10 "Backup" list.
  ///
  /// Rows are pulled as raw column maps (the same shape a model's
  /// `toMap(includeId: true)` produces) rather than round-tripped through
  /// model objects first, since a raw `Map<String, Object?>` of
  /// ints/strings/nulls is already directly JSON-encodable - this is
  /// simply a straight dump of what's on disk.
  Future<String> exportToJson() async {
    final db = await _appDatabase.database;

    final categories = await db.query(CategoriesTable.name);
    final tags = await db.query(TagsTable.name);
    final recurrenceRules = await db.query(RecurrenceRulesTable.name);
    final tasks = await db.query(TasksTable.name);
    final taskTags = await db.query(TaskTagsTable.name);
    final reminders = await db.query(RemindersTable.name);
    final settings = await db.query(SettingsTable.name);

    final backup = <String, Object?>{
      BackupJsonKeys.schemaVersion: kBackupSchemaVersion,
      BackupJsonKeys.appDatabaseVersion: DbConfig.databaseVersion,
      BackupJsonKeys.exportedAt: DateTime.now().millisecondsSinceEpoch,
      BackupJsonKeys.data: {
        BackupJsonKeys.categories: categories,
        BackupJsonKeys.tags: tags,
        BackupJsonKeys.recurrenceRules: recurrenceRules,
        BackupJsonKeys.tasks: tasks,
        BackupJsonKeys.taskTags: taskTags,
        BackupJsonKeys.reminders: reminders,
        BackupJsonKeys.settings: settings,
      },
    };
    return jsonEncode(backup);
  }

  /// Parses [jsonString] and validates it as a REmind backup, never
  /// throwing anything but [BackupValidationException] - every failure
  /// mode Part 10 calls out (invalid file, corrupted file, duplicate ids,
  /// a too-new backup version) is caught here and turned into one clear
  /// message, so the UI layer never has to know *why* parsing failed
  /// beyond that message.
  BackupData parseAndValidate(String jsonString) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      throw const BackupValidationException(
        'This file is not valid JSON and cannot be read as a REmind backup.',
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const BackupValidationException('This does not look like a REmind backup file.');
    }

    final schemaVersion = decoded[BackupJsonKeys.schemaVersion];
    if (schemaVersion is! int) {
      throw const BackupValidationException(
        'This backup is missing its format version and cannot be read.',
      );
    }
    if (schemaVersion > kBackupSchemaVersion) {
      throw BackupValidationException(
        'This backup was made with a newer version of REmind (format $schemaVersion). '
        'Update the app before restoring it.',
      );
    }

    final appDatabaseVersion = decoded[BackupJsonKeys.appDatabaseVersion];
    if (appDatabaseVersion is! int) {
      throw const BackupValidationException(
        'This backup is missing required information and cannot be read.',
      );
    }

    final exportedAtRaw = decoded[BackupJsonKeys.exportedAt];
    if (exportedAtRaw is! int) {
      throw const BackupValidationException(
        'This backup is missing required information and cannot be read.',
      );
    }

    final data = decoded[BackupJsonKeys.data];
    if (data is! Map<String, Object?>) {
      throw const BackupValidationException('This backup has no data section and cannot be read.');
    }

    final categories = _parseRows(data, BackupJsonKeys.categories, CategoryModel.fromMap, CategoriesTable.id);
    final tags = _parseRows(data, BackupJsonKeys.tags, TagModel.fromMap, TagsTable.id);
    final recurrenceRules = _parseRows(
      data,
      BackupJsonKeys.recurrenceRules,
      RecurrenceRuleModel.fromMap,
      RecurrenceRulesTable.id,
    );
    final tasks = _parseRows(data, BackupJsonKeys.tasks, TaskModel.fromMap, TasksTable.id);
    final reminders = _parseRows(data, BackupJsonKeys.reminders, ReminderModel.fromMap, RemindersTable.id);
    final settings = _parseSettings(data);
    final taskTags = _parseTaskTags(data);

    final categoryIds = {for (final c in categories) c.id!};
    final recurrenceRuleIds = {for (final r in recurrenceRules) r.id!};
    final tagIds = {for (final t in tags) t.id!};
    final taskIds = {for (final t in tasks) t.id!};

    for (final task in tasks) {
      if (task.categoryId != null && !categoryIds.contains(task.categoryId)) {
        throw BackupValidationException(
          'Backup is inconsistent: task ${task.id} refers to a category that is not in the backup.',
        );
      }
      if (task.recurrenceRuleId != null && !recurrenceRuleIds.contains(task.recurrenceRuleId)) {
        throw BackupValidationException(
          'Backup is inconsistent: task ${task.id} refers to a recurrence rule that is not in the backup.',
        );
      }
    }
    for (final link in taskTags) {
      if (!taskIds.contains(link.taskId) || !tagIds.contains(link.tagId)) {
        throw const BackupValidationException(
          'Backup is inconsistent: a task/tag relationship refers to a task or tag that is not in the backup.',
        );
      }
    }
    for (final reminder in reminders) {
      if (!taskIds.contains(reminder.taskId)) {
        throw BackupValidationException(
          'Backup is inconsistent: reminder ${reminder.id} refers to a task that is not in the backup.',
        );
      }
    }

    return BackupData(
      schemaVersion: schemaVersion,
      appDatabaseVersion: appDatabaseVersion,
      exportedAt: DateTime.fromMillisecondsSinceEpoch(exportedAtRaw),
      categories: categories,
      tags: tags,
      recurrenceRules: recurrenceRules,
      tasks: tasks,
      taskTags: taskTags,
      reminders: reminders,
      settings: settings,
    );
  }

  /// Parses one table's row list out of [data], using [fromMap] - the same
  /// factory the app already trusts for reading its own database - to
  /// check every field's presence and type in one place, then separately
  /// requiring [idKey] to be present: `fromMap` treats id as optional
  /// (rows destined for a fresh insert never have one yet), but a restore
  /// can only preserve relationships if every row's original id survived
  /// the round trip, so backup rows are held to a stricter rule than a
  /// plain insert is.
  List<T> _parseRows<T>(
    Map<String, Object?> data,
    String key,
    T Function(Map<String, Object?>) fromMap,
    String idKey,
  ) {
    final raw = data[key];
    if (raw is! List) {
      throw BackupValidationException('Backup is missing its "$key" section.');
    }

    final seenIds = <Object?>{};
    final result = <T>[];
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i];
      if (row is! Map) {
        throw BackupValidationException('Backup entry $key[$i] is not a valid record.');
      }
      final map = Map<String, Object?>.from(row);
      final id = map[idKey];
      if (id is! int) {
        throw BackupValidationException('Backup entry $key[$i] is missing its id.');
      }
      if (!seenIds.add(id)) {
        throw BackupValidationException('Backup has duplicate ids in "$key": $id.');
      }
      try {
        result.add(fromMap(map));
      } catch (_) {
        throw BackupValidationException('Backup entry $key[$i] has an invalid or corrupted field.');
      }
    }
    return result;
  }

  List<SettingModel> _parseSettings(Map<String, Object?> data) {
    final raw = data[BackupJsonKeys.settings];
    if (raw is! List) {
      throw const BackupValidationException('Backup is missing its "settings" section.');
    }
    final seenKeys = <Object?>{};
    final result = <SettingModel>[];
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i];
      if (row is! Map) {
        throw BackupValidationException('Backup entry settings[$i] is not a valid record.');
      }
      final map = Map<String, Object?>.from(row);
      final key = map[SettingsTable.key];
      if (key is! String) {
        throw BackupValidationException('Backup entry settings[$i] is missing its key.');
      }
      if (!seenKeys.add(key)) {
        throw BackupValidationException('Backup has a duplicate setting key: $key.');
      }
      try {
        result.add(SettingModel.fromMap(map));
      } catch (_) {
        throw BackupValidationException('Backup entry settings[$i] has an invalid or corrupted field.');
      }
    }
    return result;
  }

  List<TaskTagLink> _parseTaskTags(Map<String, Object?> data) {
    final raw = data[BackupJsonKeys.taskTags];
    if (raw is! List) {
      throw const BackupValidationException('Backup is missing its "taskTags" section.');
    }
    final seenLinks = <String>{};
    final result = <TaskTagLink>[];
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i];
      if (row is! Map) {
        throw BackupValidationException('Backup entry taskTags[$i] is not a valid record.');
      }
      final map = Map<String, Object?>.from(row);
      final taskId = map[TaskTagsTable.taskId];
      final tagId = map[TaskTagsTable.tagId];
      if (taskId is! int || tagId is! int) {
        throw BackupValidationException('Backup entry taskTags[$i] has an invalid or corrupted field.');
      }
      final linkKey = '$taskId:$tagId';
      if (!seenLinks.add(linkKey)) {
        throw BackupValidationException('Backup has a duplicate task/tag relationship: $linkKey.');
      }
      result.add(TaskTagLink(taskId: taskId, tagId: tagId));
    }
    return result;
  }

  /// Replaces every row this app persists with the contents of [data], all
  /// inside one transaction (see [AppDatabase.replaceAllData]): either the
  /// whole database ends up exactly matching the backup, or - on any
  /// failure - nothing changes at all. Callers are responsible for
  /// confirming with the user and taking a safety backup first; by the
  /// time this runs, the destructive part is unconditional.
  Future<void> restore(BackupData data) {
    return _appDatabase.replaceAllData(
      categories: [for (final c in data.categories) c.toMap(includeId: true)],
      tags: [for (final t in data.tags) t.toMap(includeId: true)],
      recurrenceRules: [for (final r in data.recurrenceRules) r.toMap(includeId: true)],
      tasks: [for (final t in data.tasks) t.toMap(includeId: true)],
      taskTags: [
        for (final link in data.taskTags)
          {TaskTagsTable.taskId: link.taskId, TaskTagsTable.tagId: link.tagId},
      ],
      reminders: [for (final r in data.reminders) r.toMap(includeId: true)],
      settings: [for (final s in data.settings) s.toMap()],
    );
  }
}
