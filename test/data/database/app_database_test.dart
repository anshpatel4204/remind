import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:remind/data/database/app_database.dart';
import 'package:remind/data/database/db_constants.dart';
import 'package:remind/data/database/legacy_schema_v1.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  group('AppDatabase initialization (fresh install)', () {
    late TestAppDatabase testDb;

    setUp(() => testDb = TestAppDatabase.create());
    tearDown(() => testDb.tearDown());

    test('creates all expected tables on first open', () async {
      final db = await testDb.appDatabase.database;
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
      );
      final tableNames = rows.map((r) => r['name'] as String).toSet();

      expect(
        tableNames,
        containsAll(<String>{
          CategoriesTable.name,
          TagsTable.name,
          TasksTable.name,
          TaskTagsTable.name,
          RecurrenceRulesTable.name,
          RemindersTable.name,
          SettingsTable.name,
        }),
      );
    });

    test('enables foreign key enforcement', () async {
      final db = await testDb.appDatabase.database;
      final result = await db.rawQuery('PRAGMA foreign_keys');
      expect(result.first.values.first, 1);
    });

    test('seeds exactly the 7 default categories', () async {
      final db = await testDb.appDatabase.database;
      final rows = await db.query(CategoriesTable.name);
      final names = rows.map((r) => r[CategoriesTable.categoryName] as String).toSet();

      expect(rows, hasLength(7));
      expect(names, kDefaultCategoryNames.toSet());
      expect(rows.every((r) => r[CategoriesTable.isDefault] == 1), isTrue);
    });

    test('empty database has no tasks, tags, reminders, or recurrence rules', () async {
      final db = await testDb.appDatabase.database;
      expect(await db.query(TasksTable.name), isEmpty);
      expect(await db.query(TagsTable.name), isEmpty);
      expect(await db.query(RemindersTable.name), isEmpty);
      expect(await db.query(RecurrenceRulesTable.name), isEmpty);
    });

    test('rejects a reminder pointing at a non-existent task', () async {
      final db = await testDb.appDatabase.database;
      expect(
        () => db.insert(RemindersTable.name, {
          RemindersTable.taskId: 999,
          RemindersTable.reminderTime: DateTime.now().millisecondsSinceEpoch,
          RemindersTable.createdAt: DateTime.now().millisecondsSinceEpoch,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('schema migration v1 -> v2', () {
    test('preserves existing tasks and adds the new tables', () async {
      final dir = Directory.systemTemp.createTempSync('remind_migration_test_');
      final path = p.join(dir.path, 'migration_test.db');

      // Simulate a device that already has a "version 1" database on disk.
      final legacyDb = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(LegacySchemaV1.createTasks);
          },
        ),
      );
      await legacyDb.insert('tasks', {
        'title': 'Pre-existing task from v1',
        'is_done': 1,
        'created_at': 1000,
      });
      await legacyDb.insert('tasks', {
        'title': 'Another pre-existing task',
        'is_done': 0,
        'created_at': 2000,
      });
      await legacyDb.close();

      // Now open the same file through AppDatabase (version 2). This must
      // trigger onUpgrade rather than onCreate, and must not lose data.
      final appDatabase = AppDatabase(testDatabasePath: path);
      final db = await appDatabase.database;

      final tasks = await db.query(TasksTable.name, orderBy: TasksTable.createdAt);
      expect(tasks, hasLength(2));
      expect(tasks[0][TasksTable.title], 'Pre-existing task from v1');
      expect(tasks[0][TasksTable.status], 2); // is_done=1 -> completed
      expect(tasks[1][TasksTable.title], 'Another pre-existing task');
      expect(tasks[1][TasksTable.status], 0); // is_done=0 -> pending

      // New tables introduced in v2 must exist post-upgrade too, with
      // default categories seeded (v1 had none).
      final categories = await db.query(CategoriesTable.name);
      expect(categories, hasLength(7));

      final tableNames = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(tableNames.contains('tasks_old_v1'), isFalse);
      expect(tableNames.contains(TaskTagsTable.name), isTrue);
      expect(tableNames.contains(RemindersTable.name), isTrue);

      await appDatabase.close();
      dir.deleteSync(recursive: true);
    });
  });
}
