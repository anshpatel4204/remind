import '../database/db_constants.dart';
import 'enums.dart';

/// A single task/to-do item.
class TaskModel {
  const TaskModel({
    this.id,
    required this.title,
    this.description,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    this.categoryId,
    this.recurrenceRuleId,
    this.dueDate,
    this.occurrenceOriginalDate,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.isPinned = false,
  });

  final int? id;
  final String title;
  final String? description;
  final TaskPriority priority;
  final TaskStatus status;
  final int? categoryId;
  final int? recurrenceRuleId;
  final DateTime? dueDate;

  /// Only ever set on a recurring task (non-null [recurrenceRuleId]) whose
  /// *current* occurrence has been individually moved via "Reschedule
  /// this occurrence": the occurrence's original, canonical date/time -
  /// i.e. what [dueDate] would still be if it hadn't been rescheduled.
  ///
  /// `ReminderEngine` anchors recurrence math (computing the *next*
  /// occurrence on completion/skip/catch-up) on
  /// `occurrenceOriginalDate ?? dueDate` rather than on [dueDate] alone,
  /// so a one-off reschedule can never drift the rest of the series. Null
  /// for every non-recurring task and for a recurring task whose current
  /// occurrence sits exactly where the rule says it should.
  final DateTime? occurrenceOriginalDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final bool isPinned;

  factory TaskModel.fromMap(Map<String, Object?> map) {
    return TaskModel(
      id: map[TasksTable.id] as int?,
      title: map[TasksTable.title] as String,
      description: map[TasksTable.description] as String?,
      priority: TaskPriority.fromDbValue(map[TasksTable.priority] as int),
      status: TaskStatus.fromDbValue(map[TasksTable.status] as int),
      categoryId: map[TasksTable.categoryId] as int?,
      recurrenceRuleId: map[TasksTable.recurrenceRuleId] as int?,
      dueDate: map[TasksTable.dueDate] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map[TasksTable.dueDate] as int),
      occurrenceOriginalDate: map[TasksTable.occurrenceOriginalDate] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map[TasksTable.occurrenceOriginalDate] as int),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map[TasksTable.createdAt] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(map[TasksTable.updatedAt] as int),
      completedAt: map[TasksTable.completedAt] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map[TasksTable.completedAt] as int),
      isPinned: (map[TasksTable.isPinned] as int) == 1,
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    final map = <String, Object?>{
      TasksTable.title: title,
      TasksTable.description: description,
      TasksTable.priority: priority.dbValue,
      TasksTable.status: status.dbValue,
      TasksTable.categoryId: categoryId,
      TasksTable.recurrenceRuleId: recurrenceRuleId,
      TasksTable.dueDate: dueDate?.millisecondsSinceEpoch,
      TasksTable.occurrenceOriginalDate:
          occurrenceOriginalDate?.millisecondsSinceEpoch,
      TasksTable.createdAt: createdAt.millisecondsSinceEpoch,
      TasksTable.updatedAt: updatedAt.millisecondsSinceEpoch,
      TasksTable.completedAt: completedAt?.millisecondsSinceEpoch,
      TasksTable.isPinned: isPinned ? 1 : 0,
    };
    if (includeId && id != null) {
      map[TasksTable.id] = id;
    }
    return map;
  }

  TaskModel copyWith({
    int? id,
    String? title,
    String? description,
    bool clearDescription = false,
    TaskPriority? priority,
    TaskStatus? status,
    int? categoryId,
    bool clearCategoryId = false,
    int? recurrenceRuleId,
    bool clearRecurrenceRuleId = false,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? occurrenceOriginalDate,
    bool clearOccurrenceOriginalDate = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool? isPinned,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      priority: priority ?? this.priority,
      status: status ?? this.status,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      recurrenceRuleId: clearRecurrenceRuleId
          ? null
          : (recurrenceRuleId ?? this.recurrenceRuleId),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      occurrenceOriginalDate: clearOccurrenceOriginalDate
          ? null
          : (occurrenceOriginalDate ?? this.occurrenceOriginalDate),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      isPinned: isPinned ?? this.isPinned,
    );
  }

  @override
  String toString() => 'TaskModel(id: $id, title: $title, status: $status)';
}
