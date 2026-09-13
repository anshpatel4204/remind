import '../models/category_model.dart';
import '../models/recurrence_rule_model.dart';
import '../models/reminder_model.dart';
import '../models/setting_model.dart';
import '../models/tag_model.dart';
import '../models/task_model.dart';

/// One row of the task_tags many-to-many join table, as recorded in a
/// backup. There's no model class for this table elsewhere in the app (it
/// has no id column of its own), so backup code gets its own tiny one.
class TaskTagLink {
  const TaskTagLink({required this.taskId, required this.tagId});

  final int taskId;
  final int tagId;
}

/// A fully parsed and validated REmind backup.
///
/// Every list here is guaranteed - by
/// [BackupRepository.parseAndValidate], the only place a [BackupData] is
/// ever constructed - to have passed field/type checks, unique-id checks,
/// and cross-table relationship checks. By the time a [BackupData] exists
/// it is always safe to hand straight to [BackupRepository.restore].
class BackupData {
  const BackupData({
    required this.schemaVersion,
    required this.appDatabaseVersion,
    required this.exportedAt,
    required this.categories,
    required this.tags,
    required this.recurrenceRules,
    required this.tasks,
    required this.taskTags,
    required this.reminders,
    required this.settings,
  });

  final int schemaVersion;
  final int appDatabaseVersion;
  final DateTime exportedAt;

  final List<CategoryModel> categories;
  final List<TagModel> tags;
  final List<RecurrenceRuleModel> recurrenceRules;
  final List<TaskModel> tasks;
  final List<TaskTagLink> taskTags;
  final List<ReminderModel> reminders;
  final List<SettingModel> settings;

  /// Total row count across every table - shown on the restore
  /// confirmation dialog so the user has a concrete sense of how much
  /// data they're about to bring in (and, implicitly, whether a backup is
  /// empty).
  int get totalRows =>
      categories.length +
      tags.length +
      recurrenceRules.length +
      tasks.length +
      taskTags.length +
      reminders.length +
      settings.length;
}
