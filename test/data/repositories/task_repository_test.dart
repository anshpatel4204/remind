import 'package:flutter_test/flutter_test.dart';

import 'package:remind/core/utils/task_status_calculator.dart';
import 'package:remind/data/datasources/category_data_source.dart';
import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/datasources/tag_data_source.dart';
import 'package:remind/data/datasources/task_data_source.dart';
import 'package:remind/data/datasources/task_tag_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/models/task_filter.dart';
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
    taskRepository =
        TaskRepository(TaskDataSource(testDb.appDatabase), taskTagDataSource);
    tagRepository =
        TagRepository(TagDataSource(testDb.appDatabase), taskTagDataSource);
    categoryRepository =
        CategoryRepository(CategoryDataSource(testDb.appDatabase));
    recurrenceRepository =
        RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
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

    await taskRepository
        .updateTask(fetched!.copyWith(title: 'Finish REmind data layer (v2)'));
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

    final t1 = await taskRepository.createTask(
        title: 'Work task', categoryId: work.id);
    await taskRepository.createTask(
        title: 'Personal task', categoryId: personal.id);
    await taskRepository.createTask(
      title: 'Pinned work task',
      categoryId: work.id,
      isPinned: true,
    );
    await taskRepository.completeTask(t1.id!);

    expect(await taskRepository.getAllTasks(categoryId: work.id), hasLength(2));
    expect(await taskRepository.getAllTasks(status: TaskStatus.completed),
        hasLength(1));
    expect(await taskRepository.getAllTasks(pinnedOnly: true), hasLength(1));
  });

  test('deleting a task cascades to its tag associations', () async {
    final tag = await tagRepository.createTag(name: 'urgent');
    final task = await taskRepository
        .createTask(title: 'Tagged task', tagIds: [tag.id!]);

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
      final taskOne =
          await taskRepository.createTask(title: 'One', tagIds: [tag.id!]);
      final taskTwo =
          await taskRepository.createTask(title: 'Two', tagIds: [tag.id!]);

      final taskIds = await tagRepository.getTaskIdsForTag(tag.id!);
      expect(taskIds.toSet(), {taskOne.id, taskTwo.id});
    });
  });

  group('reopen', () {
    test(
        'reopening a completed task sets it back to pending and clears completedAt',
        () async {
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
    test(
        'every priority level, including the new Urgent level, round-trips through SQLite',
        () async {
      for (final priority in TaskPriority.values) {
        final task = await taskRepository.createTask(
            title: 'Priority $priority', priority: priority);
        final fetched = await taskRepository.getTask(task.id!);
        expect(fetched?.priority, priority);
      }
    });
  });

  group('due date and due time', () {
    test(
        'due date and due time-of-day both survive a full save/reload round trip',
        () async {
      final dueDate = DateTime(2026, 3, 17, 14, 30);
      final created = await taskRepository.createTask(
          title: 'Precise due moment', dueDate: dueDate);

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

  group('filtering', () {
    test('getAllTasks filters by priority', () async {
      await taskRepository.createTask(
          title: 'Low one', priority: TaskPriority.low);
      await taskRepository.createTask(
          title: 'Urgent one', priority: TaskPriority.urgent);
      await taskRepository.createTask(
          title: 'Urgent two', priority: TaskPriority.urgent);

      final urgentTasks =
          await taskRepository.getAllTasks(priority: TaskPriority.urgent);
      expect(urgentTasks, hasLength(2));
      expect(
          urgentTasks.every((t) => t.priority == TaskPriority.urgent), isTrue);
    });

    test('getAllTasks filters by tag', () async {
      final work = await tagRepository.createTag(name: 'work');
      final home = await tagRepository.createTag(name: 'home');

      await taskRepository.createTask(title: 'Work task', tagIds: [work.id!]);
      await taskRepository.createTask(title: 'Home task', tagIds: [home.id!]);
      await taskRepository
          .createTask(title: 'Both', tagIds: [work.id!, home.id!]);

      final workTasks = await taskRepository.getAllTasks(tagId: work.id);
      expect(workTasks.map((t) => t.title).toSet(), {'Work task', 'Both'});
    });

    test('getAllTasks with noDueDateOnly returns only tasks without a due date',
        () async {
      await taskRepository.createTask(title: 'No date');
      await taskRepository.createTask(
          title: 'Has date', dueDate: DateTime(2026, 1, 1));

      final noDate = await taskRepository.getAllTasks(noDueDateOnly: true);
      expect(noDate, hasLength(1));
      expect(noDate.single.title, 'No date');
    });

    test(
        'getAllTasks with a due date range returns only tasks due in that window',
        () async {
      await taskRepository.createTask(
          title: 'Before', dueDate: DateTime(2026, 6, 1));
      await taskRepository.createTask(
          title: 'Inside', dueDate: DateTime(2026, 6, 15));
      await taskRepository.createTask(
          title: 'After', dueDate: DateTime(2026, 7, 1));

      final inRange = await taskRepository.getAllTasks(
        dueDateFrom: DateTime(2026, 6, 10),
        dueDateTo: DateTime(2026, 6, 20),
      );
      expect(inRange, hasLength(1));
      expect(inRange.single.title, 'Inside');
    });

    group('getFilteredTasks (display-status and date-preset aware)', () {
      final now = DateTime(2026, 6, 15, 12, 0);

      test('status filter matches computed display status, including Overdue',
          () async {
        final overdue = await taskRepository.createTask(
          title: 'Overdue task',
          dueDate: now.subtract(const Duration(days: 1)),
        );
        await taskRepository.createTask(
            title: 'Pending task', dueDate: now.add(const Duration(days: 1)));
        final completed =
            await taskRepository.createTask(title: 'Completed task');
        await taskRepository.completeTask(completed.id!);

        final overdueResults = await taskRepository.getFilteredTasks(
          const TaskFilter(status: TaskDisplayStatus.overdue),
          now: now,
        );
        expect(overdueResults.map((t) => t.id), [overdue.id]);

        final completedResults = await taskRepository.getFilteredTasks(
          const TaskFilter(status: TaskDisplayStatus.completed),
          now: now,
        );
        expect(completedResults.map((t) => t.id), [completed.id]);
      });

      test('date filter "today" only returns tasks due that calendar day',
          () async {
        await taskRepository.createTask(
            title: 'Earlier today', dueDate: DateTime(2026, 6, 15, 8));
        await taskRepository.createTask(
            title: 'Later today', dueDate: DateTime(2026, 6, 15, 20));
        await taskRepository.createTask(
            title: 'Tomorrow', dueDate: DateTime(2026, 6, 16, 8));
        await taskRepository.createTask(title: 'No date');

        final today = await taskRepository.getFilteredTasks(
          const TaskFilter(dueDateFilter: DueDateFilter.today),
          now: now,
        );
        expect(today.map((t) => t.title).toSet(),
            {'Earlier today', 'Later today'});
      });

      test('date filter "this week" spans Monday through Sunday', () async {
        // 2026-06-15 is a Monday.
        await taskRepository.createTask(
            title: 'Monday', dueDate: DateTime(2026, 6, 15));
        await taskRepository.createTask(
            title: 'Sunday', dueDate: DateTime(2026, 6, 21, 23, 59));
        await taskRepository.createTask(
            title: 'Next Monday', dueDate: DateTime(2026, 6, 22));

        final thisWeek = await taskRepository.getFilteredTasks(
          const TaskFilter(dueDateFilter: DueDateFilter.thisWeek),
          now: now,
        );
        expect(thisWeek.map((t) => t.title).toSet(), {'Monday', 'Sunday'});
      });

      test('date filter "no due date" matches only tasks with no due date',
          () async {
        await taskRepository.createTask(title: 'Has a date', dueDate: now);
        await taskRepository.createTask(title: 'No date at all');

        final noDate = await taskRepository.getFilteredTasks(
          const TaskFilter(dueDateFilter: DueDateFilter.noDueDate),
          now: now,
        );
        expect(noDate, hasLength(1));
        expect(noDate.single.title, 'No date at all');
      });

      test('combining category, priority, and tag filters ANDs them together',
          () async {
        final categories = await categoryRepository.getAllCategories();
        final work = categories.firstWhere((c) => c.name == 'Work');
        final urgentTag = await tagRepository.createTag(name: 'urgent-tag');

        final match = await taskRepository.createTask(
          title: 'Matches everything',
          categoryId: work.id,
          priority: TaskPriority.high,
          tagIds: [urgentTag.id!],
        );
        await taskRepository.createTask(
          title: 'Wrong priority',
          categoryId: work.id,
          priority: TaskPriority.low,
          tagIds: [urgentTag.id!],
        );
        await taskRepository.createTask(
          title: 'Wrong category',
          priority: TaskPriority.high,
          tagIds: [urgentTag.id!],
        );

        final results = await taskRepository.getFilteredTasks(
          TaskFilter(
              categoryId: work.id,
              priority: TaskPriority.high,
              tagId: urgentTag.id),
          now: now,
        );
        expect(results.map((t) => t.id), [match.id]);
      });

      test(
          'combining status, category, priority, and tag filters ANDs all four together',
          () async {
        final categories = await categoryRepository.getAllCategories();
        final work = categories.firstWhere((c) => c.name == 'Work');
        final tag = await tagRepository.createTag(name: 'combo-tag');

        final match = await taskRepository.createTask(
          title: 'Matches all four',
          categoryId: work.id,
          priority: TaskPriority.urgent,
          tagIds: [tag.id!],
          dueDate: now.add(const Duration(days: 1)),
        );
        // Same category/priority/tag, but not Pending (it's Completed) -
        // must be excluded once status: pending is also required.
        final wrongStatus = await taskRepository.createTask(
          title: 'Same everything but completed',
          categoryId: work.id,
          priority: TaskPriority.urgent,
          tagIds: [tag.id!],
        );
        await taskRepository.completeTask(wrongStatus.id!);

        final results = await taskRepository.getFilteredTasks(
          TaskFilter(
            status: TaskDisplayStatus.pending,
            categoryId: work.id,
            priority: TaskPriority.urgent,
            tagId: tag.id,
          ),
          now: now,
        );
        expect(results.map((t) => t.id), [match.id]);
      });

      test(
          'date filter "tomorrow" only returns tasks due the next calendar day',
          () async {
        await taskRepository.createTask(
            title: 'Today', dueDate: DateTime(2026, 6, 15, 9));
        await taskRepository.createTask(
            title: 'Tomorrow morning', dueDate: DateTime(2026, 6, 16, 8));
        await taskRepository.createTask(
            title: 'Tomorrow night', dueDate: DateTime(2026, 6, 16, 23));
        await taskRepository.createTask(
            title: 'Day after', dueDate: DateTime(2026, 6, 17, 8));

        final tomorrow = await taskRepository.getFilteredTasks(
          const TaskFilter(dueDateFilter: DueDateFilter.tomorrow),
          now: now,
        );
        expect(tomorrow.map((t) => t.title).toSet(),
            {'Tomorrow morning', 'Tomorrow night'});
      });

      test('date filter "this month" spans the whole calendar month', () async {
        await taskRepository.createTask(
            title: 'Last day of May', dueDate: DateTime(2026, 5, 31, 23));
        await taskRepository.createTask(
            title: 'Start of June', dueDate: DateTime(2026, 6, 1));
        await taskRepository.createTask(
            title: 'Mid June', dueDate: DateTime(2026, 6, 15));
        await taskRepository.createTask(
            title: 'End of June', dueDate: DateTime(2026, 6, 30, 23, 59));
        await taskRepository.createTask(
            title: 'Start of July', dueDate: DateTime(2026, 7, 1));

        final thisMonth = await taskRepository.getFilteredTasks(
          const TaskFilter(dueDateFilter: DueDateFilter.thisMonth),
          now: now,
        );
        expect(
          thisMonth.map((t) => t.title).toSet(),
          {'Start of June', 'Mid June', 'End of June'},
        );
      });

      test('date filter "upcoming" is open-ended from tomorrow onward',
          () async {
        await taskRepository.createTask(
            title: 'Today', dueDate: DateTime(2026, 6, 15, 9));
        await taskRepository.createTask(
            title: 'Tomorrow', dueDate: DateTime(2026, 6, 16));
        await taskRepository.createTask(
            title: 'Next year', dueDate: DateTime(2027, 1, 1));

        final upcoming = await taskRepository.getFilteredTasks(
          const TaskFilter(dueDateFilter: DueDateFilter.upcoming),
          now: now,
        );
        expect(upcoming.map((t) => t.title).toSet(), {'Tomorrow', 'Next year'});
      });

      test(
        'DueDateFilter.overdue excludes completed/cancelled tasks even with a past due date',
        () async {
          final stillOverdue = await taskRepository.createTask(
            title: 'Still overdue',
            dueDate: now.subtract(const Duration(days: 1)),
          );
          final completedLate = await taskRepository.createTask(
            title: 'Completed after its due date',
            dueDate: now.subtract(const Duration(days: 2)),
          );
          await taskRepository.completeTask(completedLate.id!);
          final cancelledLate = await taskRepository.createTask(
            title: 'Cancelled, was overdue',
            dueDate: now.subtract(const Duration(days: 3)),
          );
          await taskRepository
              .updateTask(cancelledLate.copyWith(status: TaskStatus.cancelled));

          final results = await taskRepository.getFilteredTasks(
            const TaskFilter(dueDateFilter: DueDateFilter.overdue),
            now: now,
          );
          expect(results.map((t) => t.id), [stillOverdue.id]);

          // TaskFilterPresets.overdue (status-based) must agree.
          final viaPreset = await taskRepository.getFilteredTasks(
            const TaskFilter(status: TaskDisplayStatus.overdue),
            now: now,
          );
          expect(viaPreset.map((t) => t.id), [stillOverdue.id]);
        },
      );
    });
  });

  group('searchTasks (SQL LIKE across title/description/tags)', () {
    test('empty or whitespace-only query returns no results without querying',
        () async {
      await taskRepository.createTask(title: 'Anything');
      expect(await taskRepository.searchTasks(''), isEmpty);
      expect(await taskRepository.searchTasks('   '), isEmpty);
    });

    test('matches by title, case-insensitively', () async {
      final match =
          await taskRepository.createTask(title: 'Submit Project Report');
      await taskRepository.createTask(title: 'Unrelated task');

      final results = await taskRepository.searchTasks('project report');
      expect(results.map((t) => t.id), [match.id]);
    });

    test('matches by description', () async {
      final match = await taskRepository.createTask(
        title: 'Untitled',
        description: 'Remember to water the plants',
      );
      await taskRepository.createTask(
          title: 'Other', description: 'Nothing relevant here');

      final results = await taskRepository.searchTasks('water the plants');
      expect(results.map((t) => t.id), [match.id]);
    });

    test('matches by tag name', () async {
      final tag = await tagRepository.createTag(name: 'urgent');
      final match = await taskRepository
          .createTask(title: 'Tagged task', tagIds: [tag.id!]);
      await taskRepository.createTask(title: 'Untagged task');

      final results = await taskRepository.searchTasks('urgent');
      expect(results.map((t) => t.id), [match.id]);
    });

    test('a task matching via two tags is only returned once', () async {
      final tagA = await tagRepository.createTag(name: 'work-urgent');
      final tagB = await tagRepository.createTag(name: 'work-important');
      final match = await taskRepository.createTask(
        title: 'Double tagged',
        tagIds: [tagA.id!, tagB.id!],
      );

      final results = await taskRepository.searchTasks('work-');
      expect(results.map((t) => t.id).toList(), [match.id]);
    });

    test('a query matching nothing returns an empty list, not an error',
        () async {
      await taskRepository.createTask(title: 'Completely unrelated');
      expect(await taskRepository.searchTasks('xyzzy-no-match'), isEmpty);
    });

    test('LIKE wildcard characters in the query are matched literally',
        () async {
      await taskRepository.createTask(title: 'Discount: 50% off widgets');
      await taskRepository.createTask(title: 'Totally different title');

      // A literal "%" in the query must not act as a SQL LIKE wildcard
      // that would match every task.
      final results = await taskRepository.searchTasks('50%');
      expect(results, hasLength(1));
      expect(results.single.title, contains('50%'));
    });
  });

  group('sorting', () {
    test('sorting alphabetically respects ascending/descending direction',
        () async {
      await taskRepository.createTask(title: 'Banana');
      await taskRepository.createTask(title: 'apple');
      await taskRepository.createTask(title: 'Cherry');

      final ascending =
          await taskRepository.getAllTasks(sortBy: TaskSortOption.alphabetical);
      expect(ascending.map((t) => t.title).toList(),
          ['apple', 'Banana', 'Cherry']);

      final descending = await taskRepository.getAllTasks(
        sortBy: TaskSortOption.alphabetical,
        ascending: false,
      );
      expect(descending.map((t) => t.title).toList(),
          ['Cherry', 'Banana', 'apple']);
    });

    test('sorting by priority respects ascending/descending direction',
        () async {
      await taskRepository.createTask(title: 'Low', priority: TaskPriority.low);
      await taskRepository.createTask(
          title: 'Urgent', priority: TaskPriority.urgent);
      await taskRepository.createTask(
          title: 'Medium', priority: TaskPriority.medium);

      final ascending =
          await taskRepository.getAllTasks(sortBy: TaskSortOption.priority);
      expect(
          ascending.map((t) => t.title).toList(), ['Low', 'Medium', 'Urgent']);

      final descending = await taskRepository.getAllTasks(
        sortBy: TaskSortOption.priority,
        ascending: false,
      );
      expect(
          descending.map((t) => t.title).toList(), ['Urgent', 'Medium', 'Low']);
    });

    test(
        'sorting by due date puts tasks with no due date last, regardless of direction',
        () async {
      await taskRepository.createTask(title: 'No date');
      await taskRepository.createTask(
          title: 'Later', dueDate: DateTime(2026, 6, 20));
      await taskRepository.createTask(
          title: 'Earlier', dueDate: DateTime(2026, 6, 10));

      final ascending =
          await taskRepository.getAllTasks(sortBy: TaskSortOption.dueDate);
      expect(ascending.map((t) => t.title).toList(),
          ['Earlier', 'Later', 'No date']);

      final descending = await taskRepository.getAllTasks(
        sortBy: TaskSortOption.dueDate,
        ascending: false,
      );
      expect(descending.map((t) => t.title).toList(),
          ['Later', 'Earlier', 'No date']);
    });

    test('pinned tasks always sort first regardless of the chosen sort option',
        () async {
      await taskRepository.createTask(
          title: 'Zebra', priority: TaskPriority.urgent);
      await taskRepository.createTask(
        title: 'Aardvark, but pinned',
        priority: TaskPriority.low,
        isPinned: true,
      );

      final byPriority = await taskRepository.getAllTasks(
        sortBy: TaskSortOption.priority,
        ascending: false,
      );
      expect(byPriority.first.title, 'Aardvark, but pinned');
    });
  });

  group('large dataset (correctness at scale)', () {
    test(
        'creating, filtering, sorting, and searching hold up across ~500 tasks',
        () async {
      final categories = await categoryRepository.getAllCategories();
      final work = categories.firstWhere((c) => c.name == 'Work');
      final personal = categories.firstWhere((c) => c.name == 'Personal');
      final tag = await tagRepository.createTag(name: 'bulk');

      const total = 500;
      for (var i = 0; i < total; i++) {
        final isWork = i.isEven;
        await taskRepository.createTask(
          title: 'Bulk task #$i',
          categoryId: isWork ? work.id : personal.id,
          priority: TaskPriority.values[i % TaskPriority.values.length],
          dueDate: DateTime(2026, 1, 1).add(Duration(days: i % 30)),
          tagIds: i % 10 == 0 ? [tag.id!] : const [],
        );
      }
      // One easy-to-find needle for the search assertion below.
      await taskRepository.createTask(title: 'Findable Needle Task');

      final all = await taskRepository.getAllTasks();
      expect(all, hasLength(total + 1));

      final workOnly = await taskRepository.getAllTasks(categoryId: work.id);
      expect(workOnly, hasLength(total ~/ 2));

      final filtered = await taskRepository.getFilteredTasks(
        const TaskFilter(sortBy: TaskSortOption.priority, ascending: false),
      );
      expect(filtered, hasLength(total + 1));

      final tagged = await taskRepository.getAllTasks(tagId: tag.id);
      expect(tagged, hasLength(total ~/ 10));

      final found = await taskRepository.searchTasks('Findable Needle');
      expect(found, hasLength(1));
      expect(found.single.title, 'Findable Needle Task');

      final sorted = await taskRepository.getAllTasks(
        sortBy: TaskSortOption.alphabetical,
        ascending: true,
      );
      expect(sorted, hasLength(total + 1));
      for (var i = 1; i < sorted.length; i++) {
        expect(
          sorted[i - 1]
                  .title
                  .toLowerCase()
                  .compareTo(sorted[i].title.toLowerCase()) <=
              0,
          isTrue,
        );
      }
    });
  });
}
