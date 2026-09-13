import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:remind/data/database/app_database.dart';
import 'package:remind/data/database/db_constants.dart';
import 'package:remind/data/database/legacy_schema_v1.dart';
import 'package:remind/data/database/schema.dart';

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

  group('schema migration v2 -> v3', () {
    test('adds custom_unit to recurrence_rules and preserves existing rows', () async {
      final dir = Directory.systemTemp.createTempSync('remind_migration_v2_v3_test_');
      final path = p.join(dir.path, 'migration_v2_v3_test.db');

      // Simulate a device that already has a "version 2" database on disk
      // (the schema shipped before this part), with one pre-existing
      // recurrence rule that of course predates the custom_unit column.
      final legacyDb = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            for (final statement in SchemaV2.createAllTables) {
              await db.execute(statement);
            }
            for (final statement in SchemaV2.createIndexes) {
              await db.execute(statement);
            }
          },
        ),
      );
      final preExistingRuleId = await legacyDb.insert(RecurrenceRulesTable.name, {
        RecurrenceRulesTable.frequency: 1, // weekly
        RecurrenceRulesTable.intervalValue: 1,
        RecurrenceRulesTable.daysOfWeek: '1,3,5',
        RecurrenceRulesTable.startDate: DateTime(2026, 1, 1).millisecondsSinceEpoch,
        RecurrenceRulesTable.createdAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      });
      await legacyDb.close();

      // Now open the same file through AppDatabase (version 3). This must
      // trigger onUpgrade's v2 -> v3 step rather than onCreate, and must
      // not lose the pre-existing rule.
      final appDatabase = AppDatabase(testDatabasePath: path);
      final db = await appDatabase.database;

      final columns = await db.rawQuery(
        "PRAGMA table_info(${RecurrenceRulesTable.name})",
      );
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      expect(columnNames.contains(RecurrenceRulesTable.customUnit), isTrue);

      final rules = await db.query(RecurrenceRulesTable.name);
      expect(rules, hasLength(1));
      expect(rules.first[RecurrenceRulesTable.id], preExistingRuleId);
      expect(rules.first[RecurrenceRulesTable.daysOfWeek], '1,3,5');
      // A column added by ALTER TABLE has no historical value to backfill
      // for a pre-existing row - it must come back null, which is exactly
      // what RecurrenceRuleModel.fromMap already treats as "no custom
      // unit".
      expect(rules.first[RecurrenceRulesTable.customUnit], isNull);

      await appDatabase.close();
      dir.deleteSync(recursive: true);
    });

    test('a fresh install at the current version already has custom_unit', () async {
      final testDb = TestAppDatabase.create();
      final db = await testDb.appDatabase.database;

      final columns = await db.rawQuery(
        "PRAGMA table_info(${RecurrenceRulesTable.name})",
      );
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      expect(columnNames.contains(RecurrenceRulesTable.customUnit), isTrue);

      await testDb.tearDown();
    });
  });

  group('database restart (close and reopen the same file)', () {
    test('data survives closing the database and reopening the same file', () async {
      final dir = Directory.systemTemp.createTempSync('remind_restart_test_');
      final path = p.join(dir.path, 'restart_test.db');

      var appDatabase = AppDatabase(testDatabasePath: path);
      var db = await appDatabase.database;

      final category = await db.query(CategoriesTable.name, limit: 1);
      final categoryId = category.first[CategoriesTable.id];
      final taskId = await db.insert(TasksTable.name, {
        TasksTable.title: 'Task that must survive a restart',
        TasksTable.status: 0,
        TasksTable.priority: 1,
        TasksTable.categoryId: categoryId,
        TasksTable.createdAt: 1000,
        TasksTable.updatedAt: 1000,
      });

      // Simulate the app being killed and relaunched: close the database
      // connection entirely, then open a fresh AppDatabase against the same
      // on-disk file, exactly as would happen on the next app launch.
      await appDatabase.close();
      appDatabase = AppDatabase(testDatabasePath: path);
      db = await appDatabase.database;

      final tasks = await db.query(TasksTable.name);
      expect(tasks, hasLength(1));
      expect(tasks.first[TasksTable.id], taskId);
      expect(tasks.first[TasksTable.title], 'Task that must survive a restart');

      // The default categories must not be re-seeded a second time (that
      // would indicate the reopen ran onCreate again instead of recognizing
      // the existing database).
      final categories = await db.query(CategoriesTable.name);
      expect(categories, hasLength(7));

      await appDatabase.close();
      dir.deleteSync(recursive: true);
    });
  });
}
