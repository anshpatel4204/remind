import '../datasources/settings_data_source.dart';
import '../models/enums.dart';
import '../models/setting_model.dart';

/// Application-facing operations for app settings, stored as key/value
/// pairs so new settings never require a schema change.
class SettingsRepository {
  SettingsRepository(this._dataSource);

  final SettingsDataSource _dataSource;

  static const String _keyDefaultTaskPriority = 'default_task_priority';
  static const String _keyDefaultCategoryId = 'default_category_id';

  Future<String?> getValue(String key) async {
    final setting = await _dataSource.getByKey(key);
    return setting?.value;
  }

  Future<void> setValue(String key, String? value) {
    return _dataSource.upsert(
        SettingModel(key: key, value: value, updatedAt: DateTime.now()));
  }

  Future<Map<String, String?>> getAllSettings() async {
    final settings = await _dataSource.getAll();
    return {for (final s in settings) s.key: s.value};
  }

  Future<void> deleteSetting(String key) => _dataSource.delete(key);

  /// The priority pre-selected when creating a new task (Part 11's Tasks
  /// settings). Null means no default has been chosen - callers fall back
  /// to [TaskPriority.medium], matching REmind's behavior before this
  /// setting existed.
  Future<TaskPriority?> getDefaultTaskPriority() async {
    final raw = await getValue(_keyDefaultTaskPriority);
    if (raw == null) return null;
    final index = int.tryParse(raw);
    if (index == null || index < 0 || index >= TaskPriority.values.length) {
      return null;
    }
    return TaskPriority.values[index];
  }

  Future<void> setDefaultTaskPriority(TaskPriority? priority) {
    return setValue(_keyDefaultTaskPriority, priority?.dbValue.toString());
  }

  /// The category pre-selected when creating a new task. Null means "no
  /// default" (the new task starts uncategorized) - deliberately not
  /// validated against the categories table here, since that would make
  /// this a category-aware repository; a category that's since been
  /// deleted is instead handled where this is consumed (the task form
  /// already has to handle "selected category no longer exists" for the
  /// exact same reason when editing a task).
  Future<int?> getDefaultCategoryId() async {
    final raw = await getValue(_keyDefaultCategoryId);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> setDefaultCategoryId(int? categoryId) {
    return setValue(_keyDefaultCategoryId, categoryId?.toString());
  }
}
