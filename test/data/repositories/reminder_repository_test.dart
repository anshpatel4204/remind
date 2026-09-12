import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/reminder_data_source.dart';
import 'package:remind/data/datasources/task_data_source.dart';
import 'package:remind/data/datasources/task_tag_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/reminder_repository.dart';
import 'package:remind/data/repositories/task_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late ReminderRepository reminderRepository;
  late TaskRepository taskRepository;

  setUp(() {
    testDb = TestAppDatabase.create();
    reminderRepository = ReminderRepository(ReminderDataSource(testDb.appDatabase));
    taskRepository = TaskRepository(
      TaskDataSource(testDb.appDatabase),
      TaskTagDataSource(testDb.appDatabase),
    );
  });

  tearDown(() => testDb.tearDown());

  test('a fresh database has no reminders', () async {
    expect(await reminderRepository.getAllEnabledReminders(), isEmpty);
  });

  test('create, read, update, and delete a reminder', () async {
    final task = await taskRepository.createTask(title: 'Task with reminder');
    final reminderTime = DateTime(2026, 6, 1, 9);

    final created = await reminderRepository.createReminder(
      taskId: task.id!,
      reminderTime: reminderTime,
      reminderType: ReminderType.alarm,
    );
    expect(created.id, isNotNull);

    final fetched = await reminderRepository.getReminder(created.id!);
    expect(fetched?.taskId, task.id);
    expect(fetched?.reminderType, ReminderType.alarm);

    await reminderRepository.updateReminder(fetched!.copyWith(isEnabled: false));
    final updated = await reminderRepository.getReminder(created.id!);
    expect(updated?.isEnabled, isFalse);

    await reminderRepository.deleteReminder(created.id!);
    expect(await reminderRepository.getReminder(created.id!), isNull);
  });

  test('snoozing a reminder sets snoozeMinutes and snoozedUntil', () async {
    final task = await taskRepository.createTask(title: 'Snoozable task');
    final created = await reminderRepository.createReminder(
      taskId: task.id!,
      reminderTime: DateTime.now(),
    );

    await reminderRepository.snoozeReminder(created.id!, snoozeMinutes: 10);
    final snoozed = await reminderRepository.getReminder(created.id!);

    expect(snoozed?.snoozeMinutes, 10);
    expect(snoozed?.snoozedUntil, isNotNull);
  });

  test('deleting a task cascades to its reminders', () async {
    final task = await taskRepository.createTask(title: 'Task to delete');
    await reminderRepository.createReminder(taskId: task.id!, reminderTime: DateTime.now());

    await taskRepository.deleteTask(task.id!);

    expect(await reminderRepository.getRemindersForTask(task.id!), isEmpty);
  });
}
