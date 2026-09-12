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
    return AppRepositories._(
      taskRepository: TaskRepository(TaskDataSource(db), taskTagDataSource),
      reminderRepository: ReminderRepository(ReminderDataSource(db)),
      categoryRepository: CategoryRepository(CategoryDataSource(db)),
      tagRepository: TagRepository(TagDataSource(db), taskTagDataSource),
      settingsRepository: SettingsRepository(SettingsDataSource(db)),
      recurrenceRepository: RecurrenceRepository(RecurrenceRuleDataSource(db)),
    );
  }

  AppRepositories._({
    required this.taskRepository,
    required this.reminderRepository,
    required this.categoryRepository,
    required this.tagRepository,
    required this.settingsRepository,
    required this.recurrenceRepository,
  });

  final TaskRepository taskRepository;
  final ReminderRepository reminderRepository;
  final CategoryRepository categoryRepository;
  final TagRepository tagRepository;
  final SettingsRepository settingsRepository;
  final RecurrenceRepository recurrenceRepository;
}
