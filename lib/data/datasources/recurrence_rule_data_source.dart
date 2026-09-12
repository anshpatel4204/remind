import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/recurrence_rule_model.dart';

/// Owns the raw SQLite access for the recurrence_rules table.
class RecurrenceRuleDataSource {
  RecurrenceRuleDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<int> insert(RecurrenceRuleModel rule) async {
    final Database db = await _appDatabase.database;
    return db.insert(RecurrenceRulesTable.name, rule.toMap());
  }

  Future<RecurrenceRuleModel?> getById(int id) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      RecurrenceRulesTable.name,
      where: '${RecurrenceRulesTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RecurrenceRuleModel.fromMap(rows.first);
  }

  Future<int> update(RecurrenceRuleModel rule) async {
    final Database db = await _appDatabase.database;
    return db.update(
      RecurrenceRulesTable.name,
      rule.toMap(),
      where: '${RecurrenceRulesTable.id} = ?',
      whereArgs: [rule.id],
    );
  }

  Future<int> delete(int id) async {
    final Database db = await _appDatabase.database;
    return db.delete(
      RecurrenceRulesTable.name,
      where: '${RecurrenceRulesTable.id} = ?',
      whereArgs: [id],
    );
  }
}
