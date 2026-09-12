import '../datasources/task_data_source.dart';
import '../datasources/task_tag_data_source.dart';
import '../models/enums.dart';
import '../models/tag_model.dart';
import '../models/task_model.dart';

/// Application-facing operations for tasks, including their tag
/// associations. The UI never touches [TaskDataSource] or
/// [TaskTagDataSource] directly.
class TaskRepository {
  TaskRepository(this._taskDataSource, this._taskTagDataSource);

  final TaskDataSource _taskDataSource;
  final TaskTagDataSource _taskTagDataSource;

  Future<TaskModel> createTask({
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.medium,
    int? categoryId,
    int? recurrenceRuleId,
    DateTime? dueDate,
    bool isPinned = false,
    List<int> tagIds = const [],
  }) async {
    final now = DateTime.now();
    final task = TaskModel(
      title: title,
      description: description,
      priority: priority,
      categoryId: categoryId,
      recurrenceRuleId: recurrenceRuleId,
      dueDate: dueDate,
      createdAt: now,
      updatedAt: now,
      isPinned: isPinned,
    );
    final id = await _taskDataSource.insert(task);
    if (tagIds.isNotEmpty) {
      await _taskTagDataSource.replaceTagsForTask(id, tagIds);
    }
    return task.copyWith(id: id);
  }

  Future<TaskModel?> getTask(int id) => _taskDataSource.getById(id);

  Future<List<TaskModel>> getAllTasks({
    TaskStatus? status,
    int? categoryId,
    bool? pinnedOnly,
  }) {
    return _taskDataSource.getAll(status: status, categoryId: categoryId, pinnedOnly: pinnedOnly);
  }

  /// Updates [task] as given, after normalizing it so status and
  /// completedAt can never disagree (see [_withConsistentCompletion]):
  /// setting status to completed always stamps completedAt, and setting it
  /// to anything else always clears completedAt. This is the single path
  /// every status change (including from the edit form's status field)
  /// goes through, so an inconsistent completed/completedAt combination
  /// can never reach the database.
  Future<void> updateTask(TaskModel task) async {
    if (task.id == null) {
      throw ArgumentError('Cannot update a task with no id');
    }
    final normalized = _withConsistentCompletion(task.copyWith(updatedAt: DateTime.now()));
    await _taskDataSource.update(normalized);
  }

  Future<void> completeTask(int id) async {
    final task = await _taskDataSource.getById(id);
    if (task == null) return;
    final now = DateTime.now();
    await _taskDataSource.update(
      task.copyWith(status: TaskStatus.completed, updatedAt: now, completedAt: now),
    );
  }

  /// Reopens a completed (or cancelled) task back to Pending, clearing
  /// completedAt. Always lands on Pending rather than whatever status
  /// preceded completion, since REmind does not track that history.
  Future<void> reopenTask(int id) async {
    final task = await _taskDataSource.getById(id);
    if (task == null) return;
    await _taskDataSource.update(
      task.copyWith(
        status: TaskStatus.pending,
        updatedAt: DateTime.now(),
        clearCompletedAt: true,
      ),
    );
  }

  Future<void> setPinned(int id, bool isPinned) async {
    final task = await _taskDataSource.getById(id);
    if (task == null) return;
    await _taskDataSource.update(
      task.copyWith(isPinned: isPinned, updatedAt: DateTime.now()),
    );
  }

  /// Deletes a task along with everything that only exists because of it:
  /// its reminders and task_tags rows (cascaded by foreign keys) and its
  /// recurrence rule, if any (deleted explicitly - see
  /// [TaskDataSource.deleteCascading]). Tags themselves are untouched,
  /// since they are independent, reusable entities.
  Future<void> deleteTask(int id) => _taskDataSource.deleteCascading(id);

  Future<List<TagModel>> getTagsForTask(int taskId) => _taskTagDataSource.getTagsForTask(taskId);

  Future<void> setTagsForTask(int taskId, List<int> tagIds) =>
      _taskTagDataSource.replaceTagsForTask(taskId, tagIds);

  TaskModel _withConsistentCompletion(TaskModel task) {
    if (task.status == TaskStatus.completed) {
      return task.completedAt == null ? task.copyWith(completedAt: DateTime.now()) : task;
    }
    return task.completedAt == null ? task : task.copyWith(clearCompletedAt: true);
  }
}
