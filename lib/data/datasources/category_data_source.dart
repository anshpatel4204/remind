import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/category_model.dart';

/// Owns the raw SQLite access for the categories table. Nothing above this
/// layer (repositories, and definitely not the UI) should build SQL for
/// categories directly.
class CategoryDataSource {
  CategoryDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<int> insert(CategoryModel category) async {
    final Database db = await _appDatabase.database;
    return db.insert(CategoriesTable.name, category.toMap());
  }

  Future<CategoryModel?> getById(int id) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      CategoriesTable.name,
      where: '${CategoriesTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CategoryModel.fromMap(rows.first);
  }

  Future<List<CategoryModel>> getAll() async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(CategoriesTable.name,
        orderBy: CategoriesTable.categoryName);
    return rows.map(CategoryModel.fromMap).toList();
  }

  Future<int> update(CategoryModel category) async {
    final Database db = await _appDatabase.database;
    return db.update(
      CategoriesTable.name,
      category.toMap(),
      where: '${CategoriesTable.id} = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> delete(int id) async {
    final Database db = await _appDatabase.database;
    return db.delete(
      CategoriesTable.name,
      where: '${CategoriesTable.id} = ?',
      whereArgs: [id],
    );
  }
}
