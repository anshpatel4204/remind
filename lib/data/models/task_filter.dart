import '../../core/utils/task_status_calculator.dart';
import 'enums.dart';

/// How the task list should be sorted. Each option sorts by one underlying
/// column; [TaskFilter.ascending] controls the direction. Pinned tasks
/// always surface first regardless of the chosen sort, matching the Part 3
/// task list's existing pinned-first behavior.
enum TaskSortOption { dueDate, priority, createdDate, alphabetical }

/// A quick shortcut for the task list's Date filter. [custom] uses the
/// caller-supplied [TaskFilter.customDueDateFrom]/[TaskFilter.customDueDateTo]
/// instead of a fixed range. [upcoming] is open-ended (tomorrow onward, no
/// end) rather than a fixed window.
enum DueDateFilter { any, today, tomorrow, thisWeek, thisMonth, upcoming, overdue, noDueDate, custom }

/// Bundles every criterion the Task List's filter bar can apply, plus the
/// chosen sort - one object so the UI has a single source of truth for
/// "what's currently filtering/sorting the list" instead of half a dozen
/// loose fields, and [TaskRepository.getFilteredTasks] doesn't need an
/// ever-longer parameter list.
///
/// [status] is a [TaskDisplayStatus] (the *computed* status shown on the
/// task list's badges - Pending/In Progress/Completed/Overdue/Snoozed/
/// Cancelled) rather than the smaller persisted [TaskStatus], so filtering
/// by "Overdue" or "Snoozed" actually works, matching what the user sees.
class TaskFilter {
  const TaskFilter({
    this.status,
    this.categoryId,
    this.priority,
    this.tagId,
    this.dueDateFilter = DueDateFilter.any,
    this.customDueDateFrom,
    this.customDueDateTo,
    this.sortBy = TaskSortOption.dueDate,
    this.ascending = true,
  });

  final TaskDisplayStatus? status;
  final int? categoryId;
  final TaskPriority? priority;
  final int? tagId;
  final DueDateFilter dueDateFilter;
  final DateTime? customDueDateFrom;
  final DateTime? customDueDateTo;
  final TaskSortOption sortBy;
  final bool ascending;

  bool get hasActiveFilters =>
      status != null ||
      categoryId != null ||
      priority != null ||
      tagId != null ||
      dueDateFilter != DueDateFilter.any;

  /// Returns a copy with the given fields replaced - used by the Tasks
  /// screen's quick-filter chips (see [TaskFilterPresets]) to change just
  /// the date/status axis without disturbing whatever else the full
  /// filter/sort sheet has already set.
  TaskFilter copyWith({
    TaskDisplayStatus? status,
    int? categoryId,
    TaskPriority? priority,
    int? tagId,
    DueDateFilter? dueDateFilter,
    DateTime? customDueDateFrom,
    DateTime? customDueDateTo,
    TaskSortOption? sortBy,
    bool? ascending,
  }) {
    return TaskFilter(
      status: status ?? this.status,
      categoryId: categoryId ?? this.categoryId,
      priority: priority ?? this.priority,
      tagId: tagId ?? this.tagId,
      dueDateFilter: dueDateFilter ?? this.dueDateFilter,
      customDueDateFrom: customDueDateFrom ?? this.customDueDateFrom,
      customDueDateTo: customDueDateTo ?? this.customDueDateTo,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
    );
  }
}

/// Canonical named filter presets - the one place "what does 'Overdue'
/// actually mean as a filter" (etc.) is decided, so every screen that
/// offers a quick preset (Home's stat cards, the Tasks tab's quick-filter
/// chips, ...) agrees with the others instead of each reimplementing its
/// own slightly-different [TaskFilter].
///
/// [overdue] and [completed] deliberately filter by [TaskFilter.status]
/// rather than a due-date window: "overdue" means *still outstanding* and
/// past its due date, so a completed task with a past due date must not
/// count (see [TaskRepository.getFilteredTasks], which also excludes
/// terminal statuses from [DueDateFilter.overdue] at the repository level
/// as a second safety net).
class TaskFilterPresets {
  TaskFilterPresets._();

  static const TaskFilter all = TaskFilter();
  static const TaskFilter today = TaskFilter(dueDateFilter: DueDateFilter.today);
  static const TaskFilter tomorrow = TaskFilter(dueDateFilter: DueDateFilter.tomorrow);
  static const TaskFilter thisWeek = TaskFilter(dueDateFilter: DueDateFilter.thisWeek);
  static const TaskFilter thisMonth = TaskFilter(dueDateFilter: DueDateFilter.thisMonth);
  static const TaskFilter upcoming = TaskFilter(dueDateFilter: DueDateFilter.upcoming);
  static const TaskFilter overdue = TaskFilter(status: TaskDisplayStatus.overdue);
  static const TaskFilter completed = TaskFilter(status: TaskDisplayStatus.completed);

  /// Label + preset pairs, in the order they should appear as quick-filter
  /// chips.
  static const List<(String, TaskFilter)> quickList = [
    ('All', all),
    ('Today', today),
    ('Tomorrow', tomorrow),
    ('This Week', thisWeek),
    ('This Month', thisMonth),
    ('Upcoming', upcoming),
    ('Overdue', overdue),
    ('Completed', completed),
  ];
}
