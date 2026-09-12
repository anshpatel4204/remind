import '../datasources/settings_data_source.dart';
import '../models/setting_model.dart';

/// Application-facing operations for app settings, stored as key/value
/// pairs so new settings never require a schema change.
class SettingsRepository {
  SettingsRepository(this._dataSource);

  final SettingsDataSource _dataSource;

  Future<String?> getValue(String key) async {
    final setting = await _dataSource.getByKey(key);
    return setting?.value;
  }

  Future<void> setValue(String key, String? value) {
    return _dataSource.upsert(SettingModel(key: key, value: value, updatedAt: DateTime.now()));
  }

  Future<Map<String, String?>> getAllSettings() async {
    final settings = await _dataSource.getAll();
    return {for (final s in settings) s.key: s.value};
  }

  Future<void> deleteSetting(String key) => _dataSource.delete(key);
}
