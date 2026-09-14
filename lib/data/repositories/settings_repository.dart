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

  // --- Part 13: local profile & preferences ---------------------------

  static const String _keyDisplayName = 'profile_display_name';
  static const String _keyOnboardingCompleted = 'onboarding_completed';
  static const String _keyTimeFormat = 'time_format_preference';
  static const String _keyFirstDayOfWeek = 'first_day_of_week_preference';
  static const String _keyDefaultReminderTimeMinutes =
      'default_reminder_time_minutes';
  static const String _keyTextScale = 'text_scale_preference';

  /// The user's optional, local-only display name - never required, never
  /// validated as a "real" name, shown nowhere outside this device (About
  /// dialog and the Settings > Profile row). An empty/whitespace-only
  /// value is stored as `null` (i.e. "not set"), so a user who types
  /// something in and then deletes it again gets exactly the same "no
  /// name set" state as one who never typed anything.
  Future<String?> getDisplayName() => getValue(_keyDisplayName);

  Future<void> setDisplayName(String? name) {
    final trimmed = name?.trim();
    return setValue(
        _keyDisplayName, (trimmed == null || trimmed.isEmpty) ? null : trimmed);
  }

  /// Whether the first-launch onboarding flow has been completed
  /// (finished normally or explicitly skipped - both count, since the
  /// point is only "don't show this again", not "the user configured
  /// every preference"). Defaults to `false` for a fresh install/fresh
  /// database, which is exactly what a fresh `onCreate` produces (no row
  /// for this key at all).
  Future<bool> getOnboardingCompleted() async {
    return (await getValue(_keyOnboardingCompleted)) == 'true';
  }

  Future<void> setOnboardingCompleted(bool completed) {
    return setValue(_keyOnboardingCompleted, completed ? 'true' : 'false');
  }

  Future<TimeFormatPreference> getTimeFormatPreference() async {
    return TimeFormatPreference.fromName(await getValue(_keyTimeFormat));
  }

  Future<void> setTimeFormatPreference(TimeFormatPreference preference) {
    return setValue(_keyTimeFormat, preference.name);
  }

  Future<FirstDayOfWeekPreference> getFirstDayOfWeekPreference() async {
    return FirstDayOfWeekPreference.fromName(
        await getValue(_keyFirstDayOfWeek));
  }

  Future<void> setFirstDayOfWeekPreference(FirstDayOfWeekPreference preference) {
    return setValue(_keyFirstDayOfWeek, preference.name);
  }

  /// Minutes since midnight (0-1439) pre-filled as a new task's reminder
  /// time when the user turns "Remind me" on without having picked a
  /// time yet. Defaults to 540 (9:00 AM) - REmind's existing hardcoded
  /// default from before this setting existed (see
  /// `task_form_screen.dart`), so a user who never visits this setting
  /// sees no behavior change at all.
  Future<int> getDefaultReminderTimeMinutes() async {
    final raw = await getValue(_keyDefaultReminderTimeMinutes);
    final parsed = raw == null ? null : int.tryParse(raw);
    if (parsed == null || parsed < 0 || parsed > 1439) return 540;
    return parsed;
  }

  Future<void> setDefaultReminderTimeMinutes(int minutesSinceMidnight) {
    assert(minutesSinceMidnight >= 0 && minutesSinceMidnight <= 1439);
    return setValue(
        _keyDefaultReminderTimeMinutes, minutesSinceMidnight.toString());
  }

  Future<TextScalePreference> getTextScalePreference() async {
    return TextScalePreference.fromName(await getValue(_keyTextScale));
  }

  Future<void> setTextScalePreference(TextScalePreference preference) {
    return setValue(_keyTextScale, preference.name);
  }
}
