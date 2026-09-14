import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/database/db_constants.dart';
import 'package:remind/data/datasources/category_data_source.dart';
import 'package:remind/data/datasources/occurrence_exception_data_source.dart';
import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/datasources/reminder_data_source.dart';
import 'package:remind/data/datasources/tag_data_source.dart';
import 'package:remind/data/datasources/task_data_source.dart';
import 'package:remind/data/datasources/task_tag_data_source.dart';
import 'package:remind/data/backup/backup_constants.dart';
import 'package:remind/data/backup/backup_exception.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/backup_repository.dart';
import 'package:remind/data/repositories/category_repository.dart';
import 'package:remind/data/repositories/occurrence_exception_repository.dart';
import 'package:remind/data/repositories/recurrence_repository.dart';
import 'package:remind/data/repositories/reminder_repository.dart';
import 'package:remind/data/repositories/tag_repository.dart';
import 'package:remind/data/repositories/task_repository.dart';

import '../../test_helpers/test_database_factory.dart';

/// A minimal, otherwise-valid backup JSON map - every test that wants to
/// exercise one specific validation rule starts from this and overrides
/// just the section it cares about, instead of restating the whole shape
/// each time.
Map<String, Object?> _emptyBackupJson({
  int schemaVersion = 1,
  int appDatabaseVersion = 3,
  List<Object?>? categories,
  List<Object?>? tags,
  List<Object?>? recurrenceRules,
  List<Object?>? tasks,
  List<Object?>? taskTags,
  List<Object?>? reminders,
  List<Object?>? settings,
  // Null (the default) omits the key entirely, simulating a pre-Part-12.5
  // (backup schema v1) backup that predates this section - see
  // BackupJsonKeys.occurrenceExceptions. Pass a list (even an empty one)
  // to include the key, as a schema v2 backup always does.
  List<Object?>? occurrenceExceptions,
}) {
  return {
    'schemaVersion': schemaVersion,
    'appDatabaseVersion': appDatabaseVersion,
    'exportedAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
    'data': {
      'categories': categories ?? [],
      'tags': tags ?? [],
      'recurrenceRules': recurrenceRules ?? [],
      'tasks': tasks ?? [],
      'taskTags': taskTags ?? [],
      'reminders': reminders ?? [],
      'settings': settings ?? [],
      if (occurrenceExceptions != null)
        'occurrenceExceptions': occurrenceExceptions,
    },
  };
}

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late BackupRepository backupRepository;
  late TaskRepository taskRepository;
  late CategoryRepository categoryRepository;
  late TagRepository tagRepository;
  late RecurrenceRepository recurrenceRepository;
  late ReminderRepository reminderRepository;
  late OccurrenceExceptionRepository occurrenceExceptionRepository;

  setUp(() {
    testDb = TestAppDatabase.create();
    backupRepository = BackupRepository(testDb.appDatabase);
    final taskTagDataSource = TaskTagDataSource(testDb.appDatabase);
    taskRepository =
        TaskRepository(TaskDataSource(testDb.appDatabase), taskTagDataSource);
    categoryRepository =
        CategoryRepository(CategoryDataSource(testDb.appDatabase));
    tagRepository =
        TagRepository(TagDataSource(testDb.appDatabase), taskTagDataSource);
    recurrenceRepository =
        RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
    reminderRepository =
        ReminderRepository(ReminderDataSource(testDb.appDatabase));
    occurrenceExceptionRepository = OccurrenceExceptionRepository(
        OccurrenceExceptionDataSource(testDb.appDatabase));
  });

  tearDown(() => testDb.tearDown());

  group('export', () {
    test('produces the current schema/database version and every section',
        () async {
      final json = await backupRepository.exportToJson();
      final decoded = jsonDecode(json) as Map<String, Object?>;

      expect(decoded['schemaVersion'], kBackupSchemaVersion);
      expect(decoded['appDatabaseVersion'], DbConfig.databaseVersion);
      expect(decoded['exportedAt'], isA<int>());

      final data = decoded['data'] as Map<String, Object?>;
      // A fresh database already has the 7 seeded default categories.
      expect((data['categories'] as List).length, 7);
      expect(data['tags'], isEmpty);
      expect(data['recurrenceRules'], isEmpty);
      expect(data['tasks'], isEmpty);
      expect(data['taskTags'], isEmpty);
      expect(data['reminders'], isEmpty);
      expect(data['settings'], isEmpty);
      expect(data['occurrenceExceptions'], isEmpty);
    });
  });

  group('import (parseAndValidate)', () {
    test('rejects a file that is not valid JSON', () {
      expect(
        () => backupRepository.parseAndValidate('this is not json {'),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects JSON that is not a REmind backup at all', () {
      expect(
        () => backupRepository.parseAndValidate(jsonEncode([1, 2, 3])),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects a backup missing its data section', () {
      final broken = {
        'schemaVersion': 1,
        'appDatabaseVersion': 3,
        'exportedAt': 0
      };
      expect(
        () => backupRepository.parseAndValidate(jsonEncode(broken)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects a backup made by a newer, unsupported format version', () {
      final tooNew = _emptyBackupJson(schemaVersion: 999);
      expect(
        () => backupRepository.parseAndValidate(jsonEncode(tooNew)),
        throwsA(
          isA<BackupValidationException>()
              .having((e) => e.message, 'message', contains('newer version')),
        ),
      );
    });

    test('accepts an empty backup (every section present but empty)', () {
      final data =
          backupRepository.parseAndValidate(jsonEncode(_emptyBackupJson()));
      expect(data.totalRows, 0);
    });

    test('rejects duplicate ids within the same table', () {
      final duplicateCategories = _emptyBackupJson(
        categories: [
          {
            CategoriesTable.id: 1,
            CategoriesTable.categoryName: 'Work',
            CategoriesTable.isDefault: 0,
            CategoriesTable.createdAt: 0,
          },
          {
            CategoriesTable.id: 1,
            CategoriesTable.categoryName: 'Duplicate',
            CategoriesTable.isDefault: 0,
            CategoriesTable.createdAt: 0,
          },
        ],
      );
      expect(
        () =>
            backupRepository.parseAndValidate(jsonEncode(duplicateCategories)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects a row that is missing its id', () {
      final noId = _emptyBackupJson(
        categories: [
          {
            CategoriesTable.categoryName: 'Work',
            CategoriesTable.isDefault: 0,
            CategoriesTable.createdAt: 0
          },
        ],
      );
      expect(
        () => backupRepository.parseAndValidate(jsonEncode(noId)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test(
        'rejects a row with a corrupted/out-of-range field (e.g. an invalid enum value)',
        () {
      final badStatus = _emptyBackupJson(
        tasks: [
          {
            TasksTable.id: 1,
            TasksTable.title: 'Bad task',
            TasksTable.priority: 1,
            // TaskStatus only has 4 values (0-3); 99 is corrupted data.
            TasksTable.status: 99,
            TasksTable.createdAt: 0,
            TasksTable.updatedAt: 0,
            TasksTable.isPinned: 0,
          },
        ],
      );
      expect(
        () => backupRepository.parseAndValidate(jsonEncode(badStatus)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects a task that refers to a category not present in the backup',
        () {
      final orphanCategory = _emptyBackupJson(
        tasks: [
          {
            TasksTable.id: 1,
            TasksTable.title: 'Orphan',
            TasksTable.priority: 1,
            TasksTable.status: 0,
            TasksTable.categoryId: 42,
            TasksTable.createdAt: 0,
            TasksTable.updatedAt: 0,
            TasksTable.isPinned: 0,
          },
        ],
      );
      expect(
        () => backupRepository.parseAndValidate(jsonEncode(orphanCategory)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects a reminder that refers to a task not present in the backup',
        () {
      final orphanReminder = _emptyBackupJson(
        reminders: [
          {
            RemindersTable.id: 1,
            RemindersTable.taskId: 42,
            RemindersTable.reminderTime: 0,
            RemindersTable.reminderType: 0,
            RemindersTable.isEnabled: 1,
            RemindersTable.createdAt: 0,
          },
        ],
      );
      expect(
        () => backupRepository.parseAndValidate(jsonEncode(orphanReminder)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects a task/tag relationship referring to a missing task or tag',
        () {
      final orphanLink = _emptyBackupJson(
        taskTags: [
          {TaskTagsTable.taskId: 1, TaskTagsTable.tagId: 1},
        ],
      );
      expect(
        () => backupRepository.parseAndValidate(jsonEncode(orphanLink)),
        throwsA(isA<BackupValidationException>()),
      );
    });
  });

  group('restore', () {
    test('an empty backup wipes the database, including the default categories',
        () async {
      final data =
          backupRepository.parseAndValidate(jsonEncode(_emptyBackupJson()));
      await backupRepository.restore(data);

      expect(await categoryRepository.getAllCategories(), isEmpty);
      expect(await taskRepository.getAllTasks(), isEmpty);
    });

    test('restoring replaces existing data rather than merging with it',
        () async {
      await taskRepository.createTask(title: 'Will be wiped');
      final data =
          backupRepository.parseAndValidate(jsonEncode(_emptyBackupJson()));

      await backupRepository.restore(data);

      final remaining = await taskRepository.getAllTasks();
      expect(remaining, isEmpty);
    });

    test(
        'a full export/import round trip preserves every table and relationship',
        () async {
      final category = await categoryRepository.createCategory(
          name: 'Fitness', color: '#112233');
      final tag = await tagRepository.createTag(name: 'urgent-tag');
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.weekly,
        daysOfWeek: [1, 3, 5],
        startDate: DateTime(2026, 1, 1),
      );
      final task = await taskRepository.createTask(
        title: 'Round trip task',
        categoryId: category.id,
        recurrenceRuleId: rule.id,
        tagIds: [tag.id!],
      );
      await reminderRepository.createReminder(
          taskId: task.id!, reminderTime: DateTime(2026, 1, 2, 9));

      final exported = await backupRepository.exportToJson();

      // Restore into a second, independent database - proves the backup
      // is self-contained and doesn't depend on anything already in the
      // target database.
      final targetDb = TestAppDatabase.create();
      addTearDown(() => targetDb.tearDown());
      final targetBackupRepository = BackupRepository(targetDb.appDatabase);
      final targetCategoryRepository =
          CategoryRepository(CategoryDataSource(targetDb.appDatabase));
      final targetTagRepository = TagRepository(
        TagDataSource(targetDb.appDatabase),
        TaskTagDataSource(targetDb.appDatabase),
      );
      final targetTaskRepository = TaskRepository(
        TaskDataSource(targetDb.appDatabase),
        TaskTagDataSource(targetDb.appDatabase),
      );
      final targetReminderRepository =
          ReminderRepository(ReminderDataSource(targetDb.appDatabase));
      final targetRecurrenceRepository =
          RecurrenceRepository(RecurrenceRuleDataSource(targetDb.appDatabase));

      final parsed = targetBackupRepository.parseAndValidate(exported);
      await targetBackupRepository.restore(parsed);

      final restoredCategory =
          await targetCategoryRepository.getCategory(category.id!);
      expect(restoredCategory?.name, 'Fitness');

      final restoredTask = await targetTaskRepository.getTask(task.id!);
      expect(restoredTask?.title, 'Round trip task');
      expect(restoredTask?.categoryId, category.id);
      expect(restoredTask?.recurrenceRuleId, rule.id);

      final restoredTags = await targetTagRepository.getAllTags();
      expect(restoredTags.map((t) => t.name), contains('urgent-tag'));
      expect(await targetTagRepository.getTaskIdsForTag(tag.id!), [task.id]);

      final restoredRule = await targetRecurrenceRepository.getRule(rule.id!);
      expect(restoredRule?.daysOfWeek, [1, 3, 5]);

      final restoredReminders =
          await targetReminderRepository.getRemindersForTask(task.id!);
      expect(restoredReminders, hasLength(1));
    });
  });

  group('backup schema v2 (occurrenceExceptions)', () {
    test(
        'accepts a v1-schema backup that has no occurrenceExceptions '
        'section at all', () {
      final v1Backup = _emptyBackupJson(
        schemaVersion: 1,
        // occurrenceExceptions deliberately omitted (null) - this is
        // exactly what a real backup made before Part 12.5 looks like.
      );
      final data = backupRepository.parseAndValidate(jsonEncode(v1Backup));
      expect(data.occurrenceExceptions, isEmpty);
      expect(data.totalRows, 0);
    });

    test('a v1-schema backup restores cleanly with no exceptions table data',
        () async {
      final v1Backup = _emptyBackupJson(schemaVersion: 1);
      final data = backupRepository.parseAndValidate(jsonEncode(v1Backup));

      await backupRepository.restore(data);

      expect(await taskRepository.getAllTasks(), isEmpty);
    });

    test(
        'rejects an occurrence exception referring to a recurrence rule '
        'not present in the backup', () {
      final orphanException = _emptyBackupJson(
        occurrenceExceptions: [
          {
            OccurrenceExceptionsTable.id: 1,
            OccurrenceExceptionsTable.recurrenceRuleId: 42,
            OccurrenceExceptionsTable.occurrenceDate: 0,
            OccurrenceExceptionsTable.status: 0,
            OccurrenceExceptionsTable.createdAt: 0,
          },
        ],
      );
      expect(
        () => backupRepository.parseAndValidate(jsonEncode(orphanException)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test(
        'a full export/import round trip preserves occurrence exceptions '
        'and their link to the recurrence rule', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      await occurrenceExceptionRepository.recordSkipped(
        recurrenceRuleId: rule.id!,
        occurrenceDate: DateTime(2026, 1, 1, 8, 0),
        now: DateTime(2026, 1, 1, 8, 5),
      );

      final exported = await backupRepository.exportToJson();

      final targetDb = TestAppDatabase.create();
      addTearDown(() => targetDb.tearDown());
      final targetBackupRepository = BackupRepository(targetDb.appDatabase);
      final targetRecurrenceRepository =
          RecurrenceRepository(RecurrenceRuleDataSource(targetDb.appDatabase));
      final targetOccurrenceExceptionRepository = OccurrenceExceptionRepository(
          OccurrenceExceptionDataSource(targetDb.appDatabase));

      final parsed = targetBackupRepository.parseAndValidate(exported);
      await targetBackupRepository.restore(parsed);

      final restoredRule = await targetRecurrenceRepository.getRule(rule.id!);
      expect(restoredRule, isNotNull);

      final restoredException =
          await targetOccurrenceExceptionRepository.getForOccurrence(
        rule.id!,
        DateTime(2026, 1, 1, 8, 0),
      );
      expect(restoredException, isNotNull);
      expect(restoredException?.status, OccurrenceExceptionStatus.skipped);
    });
  });
}
