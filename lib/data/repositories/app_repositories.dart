import '../../services/notification/notification_scheduler.dart';
import '../../services/notification/notification_transport.dart';
import '../../services/reminder/reminder_engine.dart';
import '../database/app_database.dart';
import '../datasources/category_data_source.dart';
import '../datasources/recurrence_rule_data_source.dart';
import '../datasources/reminder_data_source.dart';
import '../datasources/settings_data_source.dart';
import '../datasources/tag_data_source.dart';
import '../datasources/task_data_source.dart';
import '../datasources/task_tag_data_source.dart';
import 'backup_repository.dart';
import 'category_repository.dart';
import 'recurrence_repository.dart';
import 'reminder_repository.dart';
import 'settings_repository.dart';
import 'tag_repository.dart';
import 'task_repository.dart';

/// Constructs and holds one instance of every repository, all wired to a
/// single [AppDatabase] connection. Built once (see `RepositoryScope`) and
/// shared across the widget tree so every screen talks to the same
/// underlying SQLite connection through the same repository objects.
class AppRepositories {
  /// [notificationTransport] must always be passed explicitly - there is
  /// deliberately no default here. Production code passes a real
  /// [NotificationService][1]; anything else (tests, or a screen that has
  /// no interest in real notifications) passes [NoopNotificationTransport]
  /// or a test fake. That keeps it impossible to *accidentally* end up
  /// talking to a real platform channel from a test, or a no-op from
  /// production.
  ///
  /// [1]: ../../services/notification/notification_service.dart
  factory AppRepositories({
    AppDatabase? appDatabase,
    required NotificationTransport notificationTransport,
  }) {
    final db = appDatabase ?? AppDatabase.instance;
    final taskTagDataSource = TaskTagDataSource(db);
    final taskRepository = TaskRepository(TaskDataSource(db), taskTagDataSource);
    final reminderRepository = ReminderRepository(ReminderDataSource(db));
    final recurrenceRepository = RecurrenceRepository(RecurrenceRuleDataSource(db));
    final reminderEngine = ReminderEngine(
      taskRepository: taskRepository,
      reminderRepository: reminderRepository,
      recurrenceRepository: recurrenceRepository,
    );
    return AppRepositories._(
      taskRepository: taskRepository,
      reminderRepository: reminderRepository,
      categoryRepository: CategoryRepository(CategoryDataSource(db)),
      tagRepository: TagRepository(TagDataSource(db), taskTagDataSource),
      settingsRepository: SettingsRepository(SettingsDataSource(db)),
      recurrenceRepository: recurrenceRepository,
      reminderEngine: reminderEngine,
      notificationScheduler: NotificationScheduler(
        transport: notificationTransport,
        taskRepository: taskRepository,
        reminderRepository: reminderRepository,
        reminderEngine: reminderEngine,
      ),
      backupRepository: BackupRepository(db),
    );
  }

  AppRepositories._({
    required this.taskRepository,
    required this.reminderRepository,
    required this.categoryRepository,
    required this.tagRepository,
    required this.settingsRepository,
    required this.recurrenceRepository,
    required this.reminderEngine,
    required this.notificationScheduler,
    required this.backupRepository,
  });

  final TaskRepository taskRepository;
  final ReminderRepository reminderRepository;
  final CategoryRepository categoryRepository;
  final TagRepository tagRepository;
  final SettingsRepository settingsRepository;
  final RecurrenceRepository recurrenceRepository;

  /// Dedicated recurrence/reminder scheduling logic (see [ReminderEngine]
  /// itself for what it does and doesn't do). Screens should call this
  /// rather than re-implementing any scheduling decision themselves.
  final ReminderEngine reminderEngine;

  /// Connects [reminderEngine]'s decisions to an actual platform
  /// notification (see [NotificationScheduler] itself for the full
  /// architecture). Screens should call this - never
  /// [NotificationTransport] or `reminderRepository` - for anything that
  /// creates, changes, or removes a reminder, so a reminder row is never
  /// left without a matching scheduled notification, or vice versa.
  final NotificationScheduler notificationScheduler;

  /// Local JSON export/import for the whole database (Part 10's Backup
  /// and Restore) - see [BackupRepository] itself for the full format and
  /// validation rules.
  final BackupRepository backupRepository;
}
