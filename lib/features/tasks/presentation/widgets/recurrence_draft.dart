import '../../../../data/models/enums.dart';
import '../../../../data/models/recurrence_rule_model.dart';

/// In-memory, not-yet-persisted description of how a task should repeat -
/// built up by `RecurrenceConfigScreen` and turned into (or reconciled
/// with) a real [RecurrenceRuleModel] only when the Add/Edit Task form is
/// actually saved. Keeping this separate from [RecurrenceRuleModel] lets
/// the picker be cancelled without ever touching the database, and lets
/// "does not repeat" exist as a simple `null` `RecurrenceDraft?` on the
/// form's state rather than needing a whole extra enum value on
/// [RecurrenceFrequency] just to represent "no recurrence".
class RecurrenceDraft {
  const RecurrenceDraft({
    required this.frequency,
    this.intervalValue = 1,
    this.daysOfWeek,
    this.customUnit,
    this.monthlyMode = RecurrenceMonthlyMode.dayOfMonth,
    this.weekOrdinal,
    this.endDate,
  });

  final RecurrenceFrequency frequency;
  final int intervalValue;
  final List<int>? daysOfWeek;
  final RecurrenceCustomUnit? customUnit;
  final RecurrenceMonthlyMode monthlyMode;
  final int? weekOrdinal;

  /// Null means "never ends". REmind's Repeat picker deliberately only
  /// offers "Never" or "On a specific date" - not a count-based end
  /// condition - to keep the control approachable; [RecurrenceRuleModel]
  /// and `RecurrenceCalculator` still support `occurrencesCount` for
  /// whatever might use it programmatically later.
  final DateTime? endDate;

  factory RecurrenceDraft.fromRule(RecurrenceRuleModel rule) {
    return RecurrenceDraft(
      frequency: rule.frequency,
      intervalValue: rule.intervalValue,
      daysOfWeek: rule.daysOfWeek,
      customUnit: rule.customUnit,
      monthlyMode: rule.monthlyMode,
      weekOrdinal: rule.weekOrdinal,
      endDate: rule.endDate,
    );
  }

  /// Builds a throwaway [RecurrenceRuleModel] purely for preview/summary
  /// purposes (e.g. [recurrenceSummary]) or validation - never itself
  /// persisted; the Add/Edit Task form always goes through
  /// `RecurrenceRepository.createRule`/`updateRule` for the real thing.
  RecurrenceRuleModel toPreviewRule(DateTime startDate) {
    return RecurrenceRuleModel(
      frequency: frequency,
      intervalValue: intervalValue,
      daysOfWeek: daysOfWeek,
      customUnit: customUnit,
      monthlyMode: monthlyMode,
      weekOrdinal: weekOrdinal,
      startDate: startDate,
      endDate: endDate,
      createdAt: startDate,
    );
  }

  RecurrenceDraft copyWith({
    RecurrenceFrequency? frequency,
    int? intervalValue,
    List<int>? daysOfWeek,
    bool clearDaysOfWeek = false,
    RecurrenceCustomUnit? customUnit,
    RecurrenceMonthlyMode? monthlyMode,
    int? weekOrdinal,
    bool clearWeekOrdinal = false,
    DateTime? endDate,
    bool clearEndDate = false,
  }) {
    return RecurrenceDraft(
      frequency: frequency ?? this.frequency,
      intervalValue: intervalValue ?? this.intervalValue,
      daysOfWeek: clearDaysOfWeek ? null : (daysOfWeek ?? this.daysOfWeek),
      customUnit: customUnit ?? this.customUnit,
      monthlyMode: monthlyMode ?? this.monthlyMode,
      weekOrdinal: clearWeekOrdinal ? null : (weekOrdinal ?? this.weekOrdinal),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
    );
  }
}
