import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/enums.dart';
import '../models/task_model.dart';

/// Owns the raw SQLite access for the tasks table.
class TaskDataSource {
  TaskDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<int> insert(TaskModel task) async {
    final Database db = await _appDatabase.database;
    return db.insert(TasksTable.name, task.toMap());
  }

  Future<TaskModel?> getById(int id) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      TasksTable.name,
      where: '${TasksTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TaskModel.fromMap(rows.first);
  }

  /// Fetches tasks, optionally filtered by [status], [categoryId], and/or
  /// [pinnedOnly]. All filters are AND-ed together when more than one is
  /// supplied. Results are ordered pinned-first, then by due date.
  Future<List<TaskModel>> getAll({
    TaskStatus? status,
    int? categoryId,
    bool? pinnedOnly,
  }) async {
    final Database db = await _appDatabase.database;
    final conditions = <String>[];
    final args = <Object?>[];

    if (status != null) {
      conditions.add('${TasksTable.status} = ?');
      args.add(status.dbValue);
    }
    if (categoryId != null) {
      conditions.add('${TasksTable.categoryId} = ?');
      args.add(categoryId);
    }
    if (pinnedOnly == true) {
      conditions.add('${TasksTable.isPinned} = 1');
    }

    final rows = await db.query(
      TasksTable.name,
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: conditions.isEmpty ? null : args,
      orderBy: '${TasksTable.isPinned} DESC, ${TasksTable.dueDate} ASC',
    );
    return rows.map(TaskModel.fromMap).toList();
  }

  Future<int> update(TaskModel task) async {
    final Database db = await _appDatabase.database;
    return db.update(
      TasksTable.name,
      task.toMap(),
      where: '${TasksTable.id} = ?',
      whereArgs: [task.id],
    );
  }

  Future<int> delete(int id) async {
    final Database db = await _appDatabase.database;
    return db.delete(TasksTable.name, where: '${TasksTable.id} = ?', whereArgs: [id]);
  }

  /// Deletes the task and any recurrence rule it owns, atomically.
  ///
  /// Reminders and task_tags rows for this task are removed automatically
  /// by their ON DELETE CASCADE foreign keys. recurrence_rules is not: a
  /// task's FK to it is ON DELETE SET NULL, which only protects the
  /// reverse direction (deleting the rule first). So the rule is deleted
  /// explicitly here, in the same transaction as the task row, to avoid
  /// leaving an orphaned recurrence rule that nothing points to.
  Future<void> deleteCascading(int id) async {
    final Database db = await _appDatabase.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        TasksTable.name,
        columns: [TasksTable.recurrenceRuleId],
        where: '${TasksTable.id} = ?',
        whereArgs: [id],
        limit: 1,
      );
      final recurrenceRuleId = rows.isEmpty ? null : rows.first[TasksTable.recurrenceRuleId] as int?;

      await txn.delete(TasksTable.name, where: '${TasksTable.id} = ?', whereArgs: [id]);

      if (recurrenceRuleId != null) {
        await txn.delete(
          RecurrenceRulesTable.name,
          where: '${RecurrenceRulesTable.id} = ?',
          whereArgs: [recurrenceRuleId],
        );
      }
    });
  }
}
