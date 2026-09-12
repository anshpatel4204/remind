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
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[TasksTable.createdAt] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map[TasksTable.updatedAt] as int),
      completedAt: map[TasksTable.completedAt] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map[TasksTable.completedAt] as int),
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
      recurrenceRuleId: clearRecurrenceRuleId ? null : (recurrenceRuleId ?? this.recurrenceRuleId),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      isPinned: isPinned ?? this.isPinned,
    );
  }

  @override
  String toString() => 'TaskModel(id: $id, title: $title, status: $status)';
}
