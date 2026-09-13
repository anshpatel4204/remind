import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'db_constants.dart';
import 'legacy_schema_v1.dart';
import 'schema.dart';

/// Owns the single [Database] connection for the app and is the only place
/// that knows about opening, creating, and upgrading the SQLite file.
///
/// Data sources depend on this (never on `sqflite` directly for opening a
/// connection) so there is exactly one connection, one migration path, and
/// one place that configures pragmas such as foreign keys.
class AppDatabase {
  /// [testDatabasePath], when provided, opens the database at this exact
  /// file path instead of the app's normal on-device databases directory.
  /// Used by tests to get an isolated, disposable database per test case.
  AppDatabase({String? testDatabasePath})
      : _testDatabasePath = testDatabasePath;

  /// App-wide singleton used by production code.
  static final AppDatabase instance = AppDatabase();

  final String? _testDatabasePath;
  Database? _database;

  Future<Database> get database async {
    return _database ??= await _open();
  }

  Future<Database> _open() async {
    final path = _testDatabasePath ??
        join(await getDatabasesPath(), DbConfig.databaseName);
    return openDatabase(
      path,
      version: DbConfig.databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // SQLite defaults this off per-connection; every task/reminder/tag
    // relationship in this schema relies on foreign keys being enforced.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    for (final statement in SchemaV3.createAllTables) {
      await db.execute(statement);
    }
    for (final statement in SchemaV3.createIndexes) {
      await db.execute(statement);
    }
    await _seedDefaultCategories(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _upgradeV1ToV2(db);
    }
    if (oldVersion < 3) {
      await _upgradeV2ToV3(db);
    }
    // Future schema changes append another `if (oldVersion < N)` step here.
    // Each step is additive and migrates data before dropping anything, so
    // upgrading the app never requires deleting the user's database.
  }

  Future<void> _upgradeV1ToV2(Database db) async {
    await db.execute(
        'ALTER TABLE ${LegacySchemaV1.tableName} RENAME TO tasks_old_v1');

    for (final statement in SchemaV2.createAllTables) {
      await db.execute(statement);
    }
    for (final statement in SchemaV2.createIndexes) {
      await db.execute(statement);
    }

    // Preserve every v1 task, mapping its fields onto the richer v2 shape:
    // priority defaults to medium (1), status derives from the old
    // is_done flag (done -> completed, not done -> pending), and every new
    // column that had no v1 equivalent defaults to null/unset.
    await db.execute('''
INSERT INTO ${TasksTable.name} (
  ${TasksTable.id}, ${TasksTable.title}, ${TasksTable.description},
  ${TasksTable.priority}, ${TasksTable.status}, ${TasksTable.categoryId},
  ${TasksTable.recurrenceRuleId}, ${TasksTable.dueDate},
  ${TasksTable.createdAt}, ${TasksTable.updatedAt}, ${TasksTable.completedAt},
  ${TasksTable.isPinned}
)
SELECT
  id, title, NULL,
  1, CASE WHEN is_done = 1 THEN 2 ELSE 0 END, NULL,
  NULL, NULL,
  created_at, created_at, NULL,
  0
FROM tasks_old_v1
''');

    await db.execute('DROP TABLE tasks_old_v1');
    await _seedDefaultCategories(db);
  }

  /// Adds the `custom_unit` column introduced in schema v3. Deliberately
  /// only touches `recurrence_rules` - every other v2 table is unchanged
  /// in v3, so nothing else needs migrating. Existing rows get `NULL`
  /// (SQLite's default for a newly added column with no explicit
  /// default), which is exactly correct: no pre-v3 rule can have been a
  /// "custom" rule with a unit selected, since that concept didn't exist
  /// yet, and `NULL` is what [RecurrenceRuleModel.fromMap] already
  /// expects for "no custom unit".
  Future<void> _upgradeV2ToV3(Database db) async {
    await db.execute(
      'ALTER TABLE ${RecurrenceRulesTable.name} ADD COLUMN ${RecurrenceRulesTable.customUnit} INTEGER',
    );
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final name in kDefaultCategoryNames) {
      batch.insert(CategoriesTable.name, {
        CategoriesTable.categoryName: name,
        CategoriesTable.isDefault: 1,
        CategoriesTable.createdAt: now,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Deletes every row from every table this app owns, then inserts the
  /// rows supplied for each - all inside a single transaction, so a
  /// restore either fully replaces the database or (on any failure, e.g.
  /// a constraint violation in a corrupted-but-somehow-still-parsed
  /// backup) leaves it completely untouched rather than half-wiped.
  ///
  /// Insert order matters: children are inserted after the parents their
  /// foreign keys point at (categories/tags/recurrence_rules, then tasks,
  /// then task_tags/reminders), matching dependency order in the schema
  /// (see [SchemaV3]) so `PRAGMA foreign_keys = ON` never rejects a row.
  /// Deletion runs in the opposite order for the same reason.
  Future<void> replaceAllData({
    required List<Map<String, Object?>> categories,
    required List<Map<String, Object?>> tags,
    required List<Map<String, Object?>> recurrenceRules,
    required List<Map<String, Object?>> tasks,
    required List<Map<String, Object?>> taskTags,
    required List<Map<String, Object?>> reminders,
    required List<Map<String, Object?>> settings,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(RemindersTable.name);
      await txn.delete(TaskTagsTable.name);
      await txn.delete(TasksTable.name);
      await txn.delete(RecurrenceRulesTable.name);
      await txn.delete(CategoriesTable.name);
      await txn.delete(TagsTable.name);
      await txn.delete(SettingsTable.name);

      for (final row in categories) {
        await txn.insert(CategoriesTable.name, row);
      }
      for (final row in tags) {
        await txn.insert(TagsTable.name, row);
      }
      for (final row in recurrenceRules) {
        await txn.insert(RecurrenceRulesTable.name, row);
      }
      for (final row in tasks) {
        await txn.insert(TasksTable.name, row);
      }
      for (final row in taskTags) {
        await txn.insert(TaskTagsTable.name, row,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final row in reminders) {
        await txn.insert(RemindersTable.name, row);
      }
      for (final row in settings) {
        await txn.insert(SettingsTable.name, row);
      }
    });
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
