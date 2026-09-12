import '../database/db_constants.dart';

/// A single application setting, stored as a key/value pair so new settings
/// never require a schema change.
class SettingModel {
  const SettingModel({required this.key, this.value, required this.updatedAt});

  final String key;
  final String? value;
  final DateTime updatedAt;

  factory SettingModel.fromMap(Map<String, Object?> map) {
    return SettingModel(
      key: map[SettingsTable.key] as String,
      value: map[SettingsTable.value] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map[SettingsTable.updatedAt] as int),
    );
  }

  Map<String, Object?> toMap() {
    return {
      SettingsTable.key: key,
      SettingsTable.value: value,
      SettingsTable.updatedAt: updatedAt.millisecondsSinceEpoch,
    };
  }

  SettingModel copyWith({String? key, String? value, DateTime? updatedAt}) {
    return SettingModel(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'SettingModel(key: $key, value: $value)';
}
