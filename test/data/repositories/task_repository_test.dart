import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/category_data_source.dart';
import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/datasources/tag_data_source.dart';
import 'package:remind/data/datasources/task_data_source.dart';
import 'package:remind/data/datasources/task_tag_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/category_repository.dart';
import 'package:remind/data/repositories/recurrence_repository.dart';
import 'package:remind/data/repositories/tag_repository.dart';
import 'package:remind/data/repositories/task_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late TaskRepository taskRepository;
  late TagRepository tagRepository;
  late CategoryRepository categoryRepository;
  late RecurrenceRepository recurrenceRepository;

  setUp(() {
    testDb = TestAppDatabase.create();
    final taskTagDataSource = TaskTagDataSource(testDb.appDatabase);
    taskRepository = TaskRepository(TaskDataSource(testDb.appDatabase), taskTagDataSource);
    tagRepository = TagRepository(TagDataSource(testDb.appDatabase), taskTagDataSource);
    categoryRepository = CategoryRepository(CategoryDataSource(testDb.appDatabase));
    recurrenceRepository = RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
  });

  tearDown(() => testDb.tearDown());

  test('a fresh database has no tasks', () async {
    expect(await taskRepository.getAllTasks(), isEmpty);
  });

  test('create, read, update, and delete a task', () async {
    final categories = await categoryRepository.getAllCategories();
    final work = categories.firstWhere((c) => c.name == 'Work');

    final created = await taskRepository.createTask(
      title: 'Finish REmind data layer',
      description: 'Part 2',
      priority: TaskPriority.high,
      categoryId: work.id,
      dueDate: DateTime(2026, 1, 1),
    );
    expect(created.id, isNotNull);
    expect(created.status, TaskStatus.pending);

    final fetched = await taskRepository.getTask(created.id!);
    expect(fetched?.title, 'Finish REmind data layer');
    expect(fetched?.categoryId, work.id);

    await taskRepository.updateTask(fetched!.copyWith(title: 'Finish REmind data layer (v2)'));
    final updated = await taskRepository.getTask(created.id!);
    expect(updated?.title, 'Finish REmind data layer (v2)');

    await taskRepository.completeTask(created.id!);
    final completed = await taskRepository.getTask(created.id!);
    expect(completed?.status, TaskStatus.completed);
    expect(completed?.completedAt, isNotNull);

    await taskRepository.deleteTask(created.id!);
    expect(await taskRepository.getTask(created.id!), isNull);
  });

  test('getAllTasks filters by status, category, and pinned', () async {
    final categories = await categoryRepository.getAllCategories();
    final work = categories.firstWhere((c) => c.name == 'Work');
    final personal = categories.firstWhere((c) => c.name == 'Personal');

    final t1 = await taskRepository.createTask(title: 'Work task', categoryId: work.id);
    await taskRepository.createTask(title: 'Personal task', categoryId: personal.id);
    await taskRepository.createTask(
      title: 'Pinned work task',
      categoryId: work.id,
      isPinned: true,
    );
    await taskRepository.completeTask(t1.id!);

    expect(await taskRepository.getAllTasks(categoryId: work.id), hasLength(2));
    expect(await taskRepository.getAllTasks(status: TaskStatus.completed), hasLength(1));
    expect(await taskRepository.getAllTasks(pinnedOnly: true), hasLength(1));
  });

  test('deleting a task cascades to its tag associations', () async {
    final tag = await tagRepository.createTag(name: 'urgent');
    final task = await taskRepository.createTask(title: 'Tagged task', tagIds: [tag.id!]);

    expect(await taskRepository.getTagsForTask(task.id!), hasLength(1));

    await taskRepository.deleteTask(task.id!);

    // The task_tags row should be gone (ON DELETE CASCADE), not orphaned.
    expect(await tagRepository.getTaskIdsForTag(tag.id!), isEmpty);
  });

  group('task/tag relationships', () {
    test('assigning and replacing tags for a task', () async {
      final tagA = await tagRepository.createTag(name: 'A');
      final tagB = await tagRepository.createTag(name: 'B');
      final tagC = await tagRepository.createTag(name: 'C');

      final task = await taskRepository.createTask(
        title: 'Multi-tag task',
        tagIds: [tagA.id!, tagB.id!],
      );

      var tags = await taskRepository.getTagsForTask(task.id!);
      expect(tags.map((t) => t.name).toSet(), {'A', 'B'});

      await taskRepository.setTagsForTask(task.id!, [tagB.id!, tagC.id!]);
      tags = await taskRepository.getTagsForTask(task.id!);
      expect(tags.map((t) => t.name).toSet(), {'B', 'C'});
    });

    test('a tag can be attached to multiple tasks', () async {
      final tag = await tagRepository.createTag(name: 'shared');
      final taskOne = await taskRepository.createTask(title: 'One', tagIds: [tag.id!]);
      final taskTwo = await taskRepository.createTask(title: 'Two', tagIds: [tag.id!]);

      final taskIds = await tagRepository.getTaskIdsForTag(tag.id!);
      expect(taskIds.toSet(), {taskOne.id, taskTwo.id});
    });
  });

  group('reopen', () {
    test('reopening a completed task sets it back to pending and clears completedAt', () async {
      final task = await taskRepository.createTask(title: 'Reopen me');
      await taskRepository.completeTask(task.id!);
      final completed = await taskRepository.getTask(task.id!);
      expect(completed?.status, TaskStatus.completed);
      expect(completed?.completedAt, isNotNull);

      await taskRepository.reopenTask(task.id!);
      final reopened = await taskRepository.getTask(task.id!);
      expect(reopened?.status, TaskStatus.pending);
      expect(reopened?.completedAt, isNull);
    });
  });

  group('pin/unpin', () {
    test('setPinned toggles isPinned and affects the pinned filter', () async {
      final task = await taskRepository.createTask(title: 'Pin me');
      expect(task.isPinned, isFalse);

      await taskRepository.setPinned(task.id!, true);
      var fetched = await taskRepository.getTask(task.id!);
      expect(fetched?.isPinned, isTrue);
      expect(await taskRepository.getAllTasks(pinnedOnly: true), hasLength(1));

      await taskRepository.setPinned(task.id!, false);
      fetched = await taskRepository.getTask(task.id!);
      expect(fetched?.isPinned, isFalse);
      expect(await taskRepository.getAllTasks(pinnedOnly: true), isEmpty);
    });
  });

  group('priority', () {
    test('every priority level, including the new Urgent level, round-trips through SQLite', () async {
      for (final priority in TaskPriority.values) {
        final task = await taskRepository.createTask(title: 'Priority $priority', priority: priority);
        final fetched = await taskRepository.getTask(task.id!);
        expect(fetched?.priority, priority);
      }
    });
  });

  group('due date and due time', () {
    test('due date and due time-of-day both survive a full save/reload round trip', () async {
      final dueDate = DateTime(2026, 3, 17, 14, 30);
      final created = await taskRepository.createTask(title: 'Precise due moment', dueDate: dueDate);

      final fetched = await taskRepository.getTask(created.id!);
      expect(fetched?.dueDate, dueDate);
      expect(fetched?.dueDate?.hour, 14);
      expect(fetched?.dueDate?.minute, 30);
    });

    test('editing a task can clear its due date back to null', () async {
      final created = await taskRepository.createTask(
        title: 'Has a due date',
        dueDate: DateTime(2026, 1, 1),
      );

      await taskRepository.updateTask(created.copyWith(clearDueDate: true));
      final fetched = await taskRepository.getTask(created.id!);
      expect(fetched?.dueDate, isNull);
    });
  });

  group('delete cascades', () {
    test('deleting a task also deletes the recurrence rule it owns', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1),
      );
      final task = await taskRepository.createTask(
        title: 'Recurring task',
        recurrenceRuleId: rule.id,
      );

      await taskRepository.deleteTask(task.id!);

      expect(await taskRepository.getTask(task.id!), isNull);
      expect(await recurrenceRepository.getRule(rule.id!), isNull);
    });

    test('deleting a task with no recurrence rule does not error', () async {
      final task = await taskRepository.createTask(title: 'No recurrence');
      await taskRepository.deleteTask(task.id!);
      expect(await taskRepository.getTask(task.id!), isNull);
    });
  });
}
