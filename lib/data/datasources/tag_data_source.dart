import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/tag_model.dart';

/// Owns the raw SQLite access for the tags table.
class TagDataSource {
  TagDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<int> insert(TagModel tag) async {
    final Database db = await _appDatabase.database;
    return db.insert(TagsTable.name, tag.toMap());
  }

  Future<TagModel?> getById(int id) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      TagsTable.name,
      where: '${TagsTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TagModel.fromMap(rows.first);
  }

  Future<List<TagModel>> getAll() async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(TagsTable.name, orderBy: TagsTable.tagName);
    return rows.map(TagModel.fromMap).toList();
  }

  Future<int> update(TagModel tag) async {
    final Database db = await _appDatabase.database;
    return db.update(
      TagsTable.name,
      tag.toMap(),
      where: '${TagsTable.id} = ?',
      whereArgs: [tag.id],
    );
  }

  Future<int> delete(int id) async {
    final Database db = await _appDatabase.database;
    return db.delete(TagsTable.name, where: '${TagsTable.id} = ?', whereArgs: [id]);
  }
}
