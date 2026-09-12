import '../../core/utils/task_status_calculator.dart';
import 'enums.dart';

/// How the task list should be sorted. Each option sorts by one underlying
/// column; [TaskFilter.ascending] controls the direction. Pinned tasks
/// always surface first regardless of the chosen sort, matching the Part 3
/// task list's existing pinned-first behavior.
enum TaskSortOption { dueDate, priority, createdDate, alphabetical }

/// A quick shortcut for the task list's Date filter. [custom] uses the
/// caller-supplied [TaskFilter.customDueDateFrom]/[TaskFilter.customDueDateTo]
/// instead of a fixed range.
enum DueDateFilter { any, today, thisWeek, overdue, noDueDate, custom }

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
}
