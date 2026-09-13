import '../../core/utils/task_status_calculator.dart';
import '../datasources/task_data_source.dart';
import '../datasources/task_tag_data_source.dart';
import '../models/enums.dart';
import '../models/tag_model.dart';
import '../models/task_filter.dart';
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
    TaskPriority? priority,
    int? tagId,
    bool? pinnedOnly,
    DateTime? dueDateFrom,
    DateTime? dueDateTo,
    bool noDueDateOnly = false,
    TaskSortOption sortBy = TaskSortOption.dueDate,
    bool ascending = true,
  }) {
    return _taskDataSource.getAll(
      status: status,
      categoryId: categoryId,
      priority: priority,
      tagId: tagId,
      pinnedOnly: pinnedOnly,
      dueDateFrom: dueDateFrom,
      dueDateTo: dueDateTo,
      noDueDateOnly: noDueDateOnly,
      sortBy: sortBy,
      ascending: ascending,
    );
  }

  /// Applies every criterion in [filter] - category, tag, priority, a due
  /// date shortcut, and a display status that includes the computed
  /// Overdue/Snoozed states - plus its chosen sort, and returns the
  /// matching tasks.
  ///
  /// The mechanical filters (category/tag/priority/due-date range) run in
  /// SQL via [getAllTasks]. [filter.status] cannot: it is a
  /// [TaskDisplayStatus], which only exists as a computed value (see
  /// [TaskStatusCalculator]), not a stored column - so it is applied as a
  /// second pass over the SQL results instead. [now] exists only so tests
  /// can pin "the current moment"; real callers should leave it as the
  /// current device time.
  Future<List<TaskModel>> getFilteredTasks(TaskFilter filter, {DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();
    final window = _resolveDueDateWindow(
      filter.dueDateFilter,
      filter.customDueDateFrom,
      filter.customDueDateTo,
      effectiveNow,
    );

    var tasks = await getAllTasks(
      categoryId: filter.categoryId,
      priority: filter.priority,
      tagId: filter.tagId,
      dueDateFrom: window.from,
      dueDateTo: window.to,
      noDueDateOnly: window.noDueDateOnly,
      sortBy: filter.sortBy,
      ascending: filter.ascending,
    );

    // "Overdue" is inherently about tasks that are still outstanding - a
    // completed or cancelled task with a past due date isn't meaningfully
    // "overdue", so this window always excludes terminal statuses
    // regardless of what filter.status separately asks for. (Preferring
    // TaskFilterPresets.overdue - which filters by computed display status
    // instead - already gets this right without relying on this
    // exclusion, but this keeps DueDateFilter.overdue correct too for any
    // caller that uses it directly, e.g. the filter sheet's Date chips.)
    if (filter.dueDateFilter == DueDateFilter.overdue) {
      tasks = tasks
          .where((t) => t.status != TaskStatus.completed && t.status != TaskStatus.cancelled)
          .toList();
    }

    if (filter.status == null) return tasks;
    return tasks
        .where((t) => TaskStatusCalculator.displayStatusFor(t, now: effectiveNow) == filter.status)
        .toList();
  }

  /// Searches tasks by title, description, or tag name - a real SQL query
  /// (see [TaskDataSource.search]), not an in-memory scan of every task, so
  /// it stays fast regardless of how large the task table grows. Returns at
  /// most [limit] matches, most-relevant-ish first (pinned, then by due
  /// date) - the same ordering [getAllTasks] uses by default.
  Future<List<TaskModel>> searchTasks(String query, {int limit = 100}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Future.value(const []);
    return _taskDataSource.search(trimmed, limit: limit);
  }

  /// Resolves a [DueDateFilter] shortcut into a concrete `[from, to]` due
  /// date window (or a "no due date only" flag) as of [now]. Weeks run
  /// Monday-Sunday.
  ({DateTime? from, DateTime? to, bool noDueDateOnly}) _resolveDueDateWindow(
    DueDateFilter dueDateFilter,
    DateTime? customFrom,
    DateTime? customTo,
    DateTime now,
  ) {
    switch (dueDateFilter) {
      case DueDateFilter.any:
        return (from: null, to: null, noDueDateOnly: false);
      case DueDateFilter.today:
        final startOfDay = DateTime(now.year, now.month, now.day);
        final endOfDay = startOfDay
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        return (from: startOfDay, to: endOfDay, noDueDateOnly: false);
      case DueDateFilter.tomorrow:
        final startOfTomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        final endOfTomorrow = startOfTomorrow
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        return (from: startOfTomorrow, to: endOfTomorrow, noDueDateOnly: false);
      case DueDateFilter.thisWeek:
        final startOfDay = DateTime(now.year, now.month, now.day);
        final startOfWeek = startOfDay.subtract(Duration(days: startOfDay.weekday - 1));
        final endOfWeek = startOfWeek
            .add(const Duration(days: 7))
            .subtract(const Duration(milliseconds: 1));
        return (from: startOfWeek, to: endOfWeek, noDueDateOnly: false);
      case DueDateFilter.thisMonth:
        final startOfMonth = DateTime(now.year, now.month);
        final endOfMonth = DateTime(now.year, now.month + 1).subtract(const Duration(milliseconds: 1));
        return (from: startOfMonth, to: endOfMonth, noDueDateOnly: false);
      case DueDateFilter.upcoming:
        final startOfTomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        return (from: startOfTomorrow, to: null, noDueDateOnly: false);
      case DueDateFilter.overdue:
        return (from: null, to: now, noDueDateOnly: false);
      case DueDateFilter.noDueDate:
        return (from: null, to: null, noDueDateOnly: true);
      case DueDateFilter.custom:
        return (from: customFrom, to: customTo, noDueDateOnly: false);
    }
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
