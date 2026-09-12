import '../../services/reminder/reminder_engine.dart';
import '../database/app_database.dart';
import '../datasources/category_data_source.dart';
import '../datasources/recurrence_rule_data_source.dart';
import '../datasources/reminder_data_source.dart';
import '../datasources/settings_data_source.dart';
import '../datasources/tag_data_source.dart';
import '../datasources/task_data_source.dart';
import '../datasources/task_tag_data_source.dart';
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
  factory AppRepositories({AppDatabase? appDatabase}) {
    final db = appDatabase ?? AppDatabase.instance;
    final taskTagDataSource = TaskTagDataSource(db);
    final taskRepository = TaskRepository(TaskDataSource(db), taskTagDataSource);
    final reminderRepository = ReminderRepository(ReminderDataSource(db));
    final recurrenceRepository = RecurrenceRepository(RecurrenceRuleDataSource(db));
    return AppRepositories._(
      taskRepository: taskRepository,
      reminderRepository: reminderRepository,
      categoryRepository: CategoryRepository(CategoryDataSource(db)),
      tagRepository: TagRepository(TagDataSource(db), taskTagDataSource),
      settingsRepository: SettingsRepository(SettingsDataSource(db)),
      recurrenceRepository: recurrenceRepository,
      reminderEngine: ReminderEngine(
        taskRepository: taskRepository,
        reminderRepository: reminderRepository,
        recurrenceRepository: recurrenceRepository,
      ),
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
}
