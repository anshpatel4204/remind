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
    this.customUnit,
    this.monthlyMode = RecurrenceMonthlyMode.dayOfMonth,
    this.weekOrdinal,
    required this.startDate,
    this.endDate,
    this.occurrencesCount,
    required this.createdAt,
  });

  final int? id;
  final RecurrenceFrequency frequency;

  /// Repeat every [intervalValue] units of [frequency] (e.g. every 2 weeks).
  final int intervalValue;

  /// ISO weekday numbers (1 = Monday .. 7 = Sunday).
  ///
  /// For [RecurrenceFrequency.weekly]: every weekday the rule fires on.
  ///
  /// For [RecurrenceFrequency.monthly] with [monthlyMode]
  /// [RecurrenceMonthlyMode.weekdayPosition]: exactly one weekday - the
  /// target of [weekOrdinal] (e.g. `[2]` + `weekOrdinal: 1` means "the
  /// first Tuesday of every month").
  ///
  /// Null/unused for every other frequency/mode combination.
  final List<int>? daysOfWeek;

  /// The unit [intervalValue] counts in when [frequency] is
  /// [RecurrenceFrequency.custom] (e.g. "every 3 _months_"). Null for
  /// every other frequency.
  final RecurrenceCustomUnit? customUnit;

  /// Only meaningful when [frequency] is [RecurrenceFrequency.monthly].
  /// Defaults to [RecurrenceMonthlyMode.dayOfMonth], REmind's original
  /// monthly behavior, so every rule created before this field existed
  /// keeps behaving exactly as it did.
  final RecurrenceMonthlyMode monthlyMode;

  /// Only meaningful when [frequency] is [RecurrenceFrequency.monthly]
  /// and [monthlyMode] is [RecurrenceMonthlyMode.weekdayPosition]: 1-4 for
  /// "first" through "fourth", or -1 for "last" (see [WeekOrdinal]). Null
  /// otherwise.
  final int? weekOrdinal;

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
    // Absent (rather than merely null) on a pre-v4 backup restored onto a
    // v4+ install - `containsKey` (not just null-checking the value) so a
    // genuinely-null v4+ column still reads as day-of-month, not crash.
    final rawMonthlyMode = map[RecurrenceRulesTable.monthlyMode];
    return RecurrenceRuleModel(
      id: map[RecurrenceRulesTable.id] as int?,
      frequency: RecurrenceFrequency.fromDbValue(
          map[RecurrenceRulesTable.frequency] as int),
      intervalValue: map[RecurrenceRulesTable.intervalValue] as int,
      daysOfWeek: (rawDays == null || rawDays.isEmpty)
          ? null
          : rawDays.split(',').map(int.parse).toList(),
      customUnit: map[RecurrenceRulesTable.customUnit] == null
          ? null
          : RecurrenceCustomUnit.fromDbValue(
              map[RecurrenceRulesTable.customUnit] as int),
      monthlyMode: rawMonthlyMode == null
          ? RecurrenceMonthlyMode.dayOfMonth
          : RecurrenceMonthlyMode.fromDbValue(rawMonthlyMode as int),
      weekOrdinal: map[RecurrenceRulesTable.weekOrdinal] as int?,
      startDate: DateTime.fromMillisecondsSinceEpoch(
          map[RecurrenceRulesTable.startDate] as int),
      endDate: map[RecurrenceRulesTable.endDate] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map[RecurrenceRulesTable.endDate] as int),
      occurrencesCount: map[RecurrenceRulesTable.occurrencesCount] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          map[RecurrenceRulesTable.createdAt] as int),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    final map = <String, Object?>{
      RecurrenceRulesTable.frequency: frequency.dbValue,
      RecurrenceRulesTable.intervalValue: intervalValue,
      RecurrenceRulesTable.daysOfWeek: daysOfWeek?.join(','),
      RecurrenceRulesTable.customUnit: customUnit?.dbValue,
      RecurrenceRulesTable.monthlyMode: monthlyMode.dbValue,
      RecurrenceRulesTable.weekOrdinal: weekOrdinal,
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
    bool clearDaysOfWeek = false,
    RecurrenceCustomUnit? customUnit,
    bool clearCustomUnit = false,
    RecurrenceMonthlyMode? monthlyMode,
    int? weekOrdinal,
    bool clearWeekOrdinal = false,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    int? occurrencesCount,
    bool clearOccurrencesCount = false,
    DateTime? createdAt,
  }) {
    return RecurrenceRuleModel(
      id: id ?? this.id,
      frequency: frequency ?? this.frequency,
      intervalValue: intervalValue ?? this.intervalValue,
      daysOfWeek: clearDaysOfWeek ? null : (daysOfWeek ?? this.daysOfWeek),
      customUnit: clearCustomUnit ? null : (customUnit ?? this.customUnit),
      monthlyMode: monthlyMode ?? this.monthlyMode,
      weekOrdinal: clearWeekOrdinal ? null : (weekOrdinal ?? this.weekOrdinal),
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      occurrencesCount: clearOccurrencesCount
          ? null
          : (occurrencesCount ?? this.occurrencesCount),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
