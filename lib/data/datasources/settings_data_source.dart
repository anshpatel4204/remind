import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/setting_model.dart';

/// Owns the raw SQLite access for the settings key/value table.
class SettingsDataSource {
  SettingsDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<void> upsert(SettingModel setting) async {
    final Database db = await _appDatabase.database;
    await db.insert(
      SettingsTable.name,
      setting.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SettingModel?> getByKey(String key) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      SettingsTable.name,
      where: '${SettingsTable.key} = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SettingModel.fromMap(rows.first);
  }

  Future<List<SettingModel>> getAll() async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(SettingsTable.name);
    return rows.map(SettingModel.fromMap).toList();
  }

  Future<int> delete(String key) async {
    final Database db = await _appDatabase.database;
    return db.delete(SettingsTable.name, where: '${SettingsTable.key} = ?', whereArgs: [key]);
  }
}
