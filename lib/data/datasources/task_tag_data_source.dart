import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/tag_model.dart';

/// Owns the raw SQLite access for the task_tags many-to-many join table.
class TaskTagDataSource {
  TaskTagDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<void> addTag(int taskId, int tagId) async {
    final Database db = await _appDatabase.database;
    await db.insert(
      TaskTagsTable.name,
      {TaskTagsTable.taskId: taskId, TaskTagsTable.tagId: tagId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeTag(int taskId, int tagId) async {
    final Database db = await _appDatabase.database;
    await db.delete(
      TaskTagsTable.name,
      where: '${TaskTagsTable.taskId} = ? AND ${TaskTagsTable.tagId} = ?',
      whereArgs: [taskId, tagId],
    );
  }

  /// Replaces the full set of tags assigned to [taskId] with [tagIds], in a
  /// single transaction so partial updates are never visible.
  Future<void> replaceTagsForTask(int taskId, List<int> tagIds) async {
    final Database db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.delete(
        TaskTagsTable.name,
        where: '${TaskTagsTable.taskId} = ?',
        whereArgs: [taskId],
      );
      for (final tagId in tagIds) {
        await txn.insert(
          TaskTagsTable.name,
          {TaskTagsTable.taskId: taskId, TaskTagsTable.tagId: tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<TagModel>> getTagsForTask(int taskId) async {
    final Database db = await _appDatabase.database;
    final rows = await db.rawQuery('''
SELECT t.* FROM ${TagsTable.name} t
INNER JOIN ${TaskTagsTable.name} tt ON tt.${TaskTagsTable.tagId} = t.${TagsTable.id}
WHERE tt.${TaskTagsTable.taskId} = ?
ORDER BY t.${TagsTable.tagName}
''', [taskId]);
    return rows.map(TagModel.fromMap).toList();
  }

  Future<List<int>> getTaskIdsForTag(int tagId) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      TaskTagsTable.name,
      columns: [TaskTagsTable.taskId],
      where: '${TaskTagsTable.tagId} = ?',
      whereArgs: [tagId],
    );
    return rows.map((r) => r[TaskTagsTable.taskId] as int).toList();
  }
}
