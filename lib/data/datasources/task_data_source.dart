import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/enums.dart';
import '../models/task_filter.dart';
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

  /// Fetches tasks, optionally filtered by [status], [categoryId],
  /// [priority], [tagId], and/or [pinnedOnly]; all supplied filters are
  /// AND-ed together. The due date can additionally be narrowed to a range
  /// ([dueDateFrom]/[dueDateTo], either end optional) or to tasks with no
  /// due date at all ([noDueDateOnly] - which takes priority over the range
  /// when both are supplied, since "has no due date" and "due date in this
  /// range" are mutually exclusive). Results are always pinned-first; within
  /// that, ordered by [sortBy] in [ascending] or descending direction.
  Future<List<TaskModel>> getAll({
    TaskStatus? status,
    int? categoryId,
    TaskPriority? priority,
    int? tagId,
    bool? pinnedOnly,
    DateTime? dueDateFrom,
    DateTime? dueDateTo,
    bool noDueDateOnly = false,
    TaskSortOption sortBy = TaskSortOption.dueDate,
    bool ascending = true,
  }) async {
    final Database db = await _appDatabase.database;

    final whereConditions = <String>[];
    final whereArgs = <Object?>[];

    if (status != null) {
      whereConditions.add('t.${TasksTable.status} = ?');
      whereArgs.add(status.dbValue);
    }
    if (categoryId != null) {
      whereConditions.add('t.${TasksTable.categoryId} = ?');
      whereArgs.add(categoryId);
    }
    if (priority != null) {
      whereConditions.add('t.${TasksTable.priority} = ?');
      whereArgs.add(priority.dbValue);
    }
    if (pinnedOnly == true) {
      whereConditions.add('t.${TasksTable.isPinned} = 1');
    }
    if (noDueDateOnly) {
      whereConditions.add('t.${TasksTable.dueDate} IS NULL');
    } else {
      if (dueDateFrom != null) {
        whereConditions.add('t.${TasksTable.dueDate} >= ?');
        whereArgs.add(dueDateFrom.millisecondsSinceEpoch);
      }
      if (dueDateTo != null) {
        whereConditions.add('t.${TasksTable.dueDate} <= ?');
        whereArgs.add(dueDateTo.millisecondsSinceEpoch);
      }
    }

    // Filtering by tag requires a join against the many-to-many task_tags
    // table; only added to the query when a tagId filter is actually in
    // use, so the common no-tag-filter case stays a plain single-table
    // query.
    var joinClause = '';
    final joinArgs = <Object?>[];
    if (tagId != null) {
      joinClause =
          'INNER JOIN ${TaskTagsTable.name} tt ON tt.${TaskTagsTable.taskId} = t.${TasksTable.id} '
          'AND tt.${TaskTagsTable.tagId} = ?';
      joinArgs.add(tagId);
    }

    final whereClause = whereConditions.isEmpty ? '' : 'WHERE ${whereConditions.join(' AND ')}';
    final sql = '''
SELECT t.* FROM ${TasksTable.name} t
$joinClause
$whereClause
ORDER BY ${_orderByClause(sortBy, ascending)}
''';

    final rows = await db.rawQuery(sql, [...joinArgs, ...whereArgs]);
    return rows.map(TaskModel.fromMap).toList();
  }

  /// Builds the ORDER BY clause for [getAll]. Pinned tasks always come
  /// first. Tasks with no due date always sort after ones that have one,
  /// regardless of [ascending], since "no due date" isn't meaningfully
  /// earlier or later than any real date.
  String _orderByClause(TaskSortOption sortBy, bool ascending) {
    final direction = ascending ? 'ASC' : 'DESC';
    switch (sortBy) {
      case TaskSortOption.dueDate:
        return '${TasksTable.isPinned} DESC, '
            '${TasksTable.dueDate} IS NULL, '
            '${TasksTable.dueDate} $direction';
      case TaskSortOption.priority:
        return '${TasksTable.isPinned} DESC, ${TasksTable.priority} $direction';
      case TaskSortOption.createdDate:
        return '${TasksTable.isPinned} DESC, ${TasksTable.createdAt} $direction';
      case TaskSortOption.alphabetical:
        return '${TasksTable.isPinned} DESC, ${TasksTable.title} COLLATE NOCASE $direction';
    }
  }

  /// Searches by title, description, or an associated tag's name, all in
  /// one SQL query - no table is ever pulled fully into memory. Matching is
  /// case-insensitive and substring-based (`LIKE '%query%'`); `%`, `_`, and
  /// `\\` in the user's input are escaped first so they're matched
  /// literally rather than treated as SQL wildcards. Joins to
  /// task_tags/tags only to test for a match - `SELECT DISTINCT t.*` keeps
  /// a task that matches via more than one tag from appearing twice.
  Future<List<TaskModel>> search(String query, {int limit = 100}) async {
    final Database db = await _appDatabase.database;
    final escaped = query.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
    final likeArg = '%$escaped%';

    final sql = '''
SELECT DISTINCT t.* FROM ${TasksTable.name} t
LEFT JOIN ${TaskTagsTable.name} tt ON tt.${TaskTagsTable.taskId} = t.${TasksTable.id}
LEFT JOIN ${TagsTable.name} tg ON tg.${TagsTable.id} = tt.${TaskTagsTable.tagId}
WHERE t.${TasksTable.title} LIKE ? ESCAPE '\\'
   OR t.${TasksTable.description} LIKE ? ESCAPE '\\'
   OR tg.${TagsTable.tagName} LIKE ? ESCAPE '\\'
ORDER BY ${_orderByClause(TaskSortOption.dueDate, true)}
LIMIT ?
''';

    final rows = await db.rawQuery(sql, [likeArg, likeArg, likeArg, limit]);
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
