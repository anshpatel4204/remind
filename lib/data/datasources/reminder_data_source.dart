import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/reminder_model.dart';

/// Owns the raw SQLite access for the reminders table.
class ReminderDataSource {
  ReminderDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<int> insert(ReminderModel reminder) async {
    final Database db = await _appDatabase.database;
    return db.insert(RemindersTable.name, reminder.toMap());
  }

  Future<ReminderModel?> getById(int id) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      RemindersTable.name,
      where: '${RemindersTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReminderModel.fromMap(rows.first);
  }

  Future<List<ReminderModel>> getForTask(int taskId) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      RemindersTable.name,
      where: '${RemindersTable.taskId} = ?',
      whereArgs: [taskId],
      orderBy: RemindersTable.reminderTime,
    );
    return rows.map(ReminderModel.fromMap).toList();
  }

  Future<List<ReminderModel>> getAllEnabled() async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      RemindersTable.name,
      where: '${RemindersTable.isEnabled} = 1',
      orderBy: RemindersTable.reminderTime,
    );
    return rows.map(ReminderModel.fromMap).toList();
  }

  Future<int> update(ReminderModel reminder) async {
    final Database db = await _appDatabase.database;
    return db.update(
      RemindersTable.name,
      reminder.toMap(),
      where: '${RemindersTable.id} = ?',
      whereArgs: [reminder.id],
    );
  }

  Future<int> delete(int id) async {
    final Database db = await _appDatabase.database;
    return db.delete(RemindersTable.name,
        where: '${RemindersTable.id} = ?', whereArgs: [id]);
  }
}
