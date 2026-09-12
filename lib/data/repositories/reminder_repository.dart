import '../datasources/reminder_data_source.dart';
import '../models/enums.dart';
import '../models/reminder_model.dart';

/// Application-facing operations for reminders.
class ReminderRepository {
  ReminderRepository(this._dataSource);

  final ReminderDataSource _dataSource;

  Future<ReminderModel> createReminder({
    required int taskId,
    required DateTime reminderTime,
    ReminderType reminderType = ReminderType.notification,
    bool isEnabled = true,
  }) async {
    final reminder = ReminderModel(
      taskId: taskId,
      reminderTime: reminderTime,
      reminderType: reminderType,
      isEnabled: isEnabled,
      createdAt: DateTime.now(),
    );
    final id = await _dataSource.insert(reminder);
    return reminder.copyWith(id: id);
  }

  Future<ReminderModel?> getReminder(int id) => _dataSource.getById(id);

  Future<List<ReminderModel>> getRemindersForTask(int taskId) => _dataSource.getForTask(taskId);

  Future<List<ReminderModel>> getAllEnabledReminders() => _dataSource.getAllEnabled();

  Future<void> updateReminder(ReminderModel reminder) async {
    if (reminder.id == null) {
      throw ArgumentError('Cannot update a reminder with no id');
    }
    await _dataSource.update(reminder);
  }

  Future<void> snoozeReminder(int id, {required int snoozeMinutes}) async {
    final reminder = await _dataSource.getById(id);
    if (reminder == null) return;
    final snoozedUntil = DateTime.now().add(Duration(minutes: snoozeMinutes));
    await _dataSource.update(
      reminder.copyWith(snoozeMinutes: snoozeMinutes, snoozedUntil: snoozedUntil),
    );
  }

  Future<void> deleteReminder(int id) => _dataSource.delete(id);
}
