import '../database/db_constants.dart';
import 'enums.dart';

/// Describes how a recurring task/reminder repeats. Standalone rather than
/// inlined onto tasks so a single rule shape can later be reused (e.g. by
/// reminders that repeat independently of their task).
class RecurrenceRuleModel {
  const RecurrenceRuleModel({
    this.id,
    required this.frequency,
    this.intervalValue = 1,
    this.daysOfWeek,
    required this.startDate,
    this.endDate,
    this.occurrencesCount,
    required this.createdAt,
  });

  final int? id;
  final RecurrenceFrequency frequency;

  /// Repeat every [intervalValue] units of [frequency] (e.g. every 2 weeks).
  final int intervalValue;

  /// ISO weekday numbers (1 = Monday .. 7 = Sunday), only meaningful for
  /// [RecurrenceFrequency.weekly] and [RecurrenceFrequency.custom].
  final List<int>? daysOfWeek;
  final DateTime startDate;

  /// Null means the recurrence has no end date.
  final DateTime? endDate;

  /// An alternative, count-based end condition (e.g. "10 times"). Null
  /// means unused; a rule may specify [endDate], [occurrencesCount], both,
  /// or neither (never-ending).
  final int? occurrencesCount;
  final DateTime createdAt;

  factory RecurrenceRuleModel.fromMap(Map<String, Object?> map) {
    final rawDays = map[RecurrenceRulesTable.daysOfWeek] as String?;
    return RecurrenceRuleModel(
      id: map[RecurrenceRulesTable.id] as int?,
      frequency: RecurrenceFrequency.fromDbValue(map[RecurrenceRulesTable.frequency] as int),
      intervalValue: map[RecurrenceRulesTable.intervalValue] as int,
      daysOfWeek: (rawDays == null || rawDays.isEmpty)
          ? null
          : rawDays.split(',').map(int.parse).toList(),
      startDate: DateTime.fromMillisecondsSinceEpoch(map[RecurrenceRulesTable.startDate] as int),
      endDate: map[RecurrenceRulesTable.endDate] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map[RecurrenceRulesTable.endDate] as int),
      occurrencesCount: map[RecurrenceRulesTable.occurrencesCount] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[RecurrenceRulesTable.createdAt] as int),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    final map = <String, Object?>{
      RecurrenceRulesTable.frequency: frequency.dbValue,
      RecurrenceRulesTable.intervalValue: intervalValue,
      RecurrenceRulesTable.daysOfWeek: daysOfWeek?.join(','),
      RecurrenceRulesTable.startDate: startDate.millisecondsSinceEpoch,
      RecurrenceRulesTable.endDate: endDate?.millisecondsSinceEpoch,
      RecurrenceRulesTable.occurrencesCount: occurrencesCount,
      RecurrenceRulesTable.createdAt: createdAt.millisecondsSinceEpoch,
    };
    if (includeId && id != null) {
      map[RecurrenceRulesTable.id] = id;
    }
    return map;
  }

  RecurrenceRuleModel copyWith({
    int? id,
    RecurrenceFrequency? frequency,
    int? intervalValue,
    List<int>? daysOfWeek,
    DateTime? startDate,
    DateTime? endDate,
    int? occurrencesCount,
    DateTime? createdAt,
  }) {
    return RecurrenceRuleModel(
      id: id ?? this.id,
      frequency: frequency ?? this.frequency,
      intervalValue: intervalValue ?? this.intervalValue,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      occurrencesCount: occurrencesCount ?? this.occurrencesCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
