import '../datasources/recurrence_rule_data_source.dart';
import '../models/enums.dart';
import '../models/recurrence_rule_model.dart';

/// Application-facing operations for recurrence rules.
///
/// This is the single gate a [RecurrenceRuleModel] passes through on its
/// way to SQLite, in both directions (create and update) - see
/// [_validate]. Nothing downstream (the data source, [RecurrenceCalculator])
/// has to defend against a malformed rule, because one can never be
/// persisted in the first place.
class RecurrenceRepository {
  RecurrenceRepository(this._dataSource);

  final RecurrenceRuleDataSource _dataSource;

  Future<RecurrenceRuleModel> createRule({
    required RecurrenceFrequency frequency,
    int intervalValue = 1,
    List<int>? daysOfWeek,
    RecurrenceCustomUnit? customUnit,
    RecurrenceMonthlyMode monthlyMode = RecurrenceMonthlyMode.dayOfMonth,
    int? weekOrdinal,
    required DateTime startDate,
    DateTime? endDate,
    int? occurrencesCount,
  }) async {
    _validate(
      frequency: frequency,
      intervalValue: intervalValue,
      daysOfWeek: daysOfWeek,
      customUnit: customUnit,
      monthlyMode: monthlyMode,
      weekOrdinal: weekOrdinal,
      startDate: startDate,
      endDate: endDate,
      occurrencesCount: occurrencesCount,
    );
    final rule = RecurrenceRuleModel(
      frequency: frequency,
      intervalValue: intervalValue,
      daysOfWeek: daysOfWeek,
      customUnit: customUnit,
      monthlyMode: monthlyMode,
      weekOrdinal: weekOrdinal,
      startDate: startDate,
      endDate: endDate,
      occurrencesCount: occurrencesCount,
      createdAt: DateTime.now(),
    );
    final id = await _dataSource.insert(rule);
    return rule.copyWith(id: id);
  }

  Future<RecurrenceRuleModel?> getRule(int id) => _dataSource.getById(id);

  Future<void> updateRule(RecurrenceRuleModel rule) async {
    if (rule.id == null) {
      throw ArgumentError('Cannot update a recurrence rule with no id');
    }
    _validate(
      frequency: rule.frequency,
      intervalValue: rule.intervalValue,
      daysOfWeek: rule.daysOfWeek,
      customUnit: rule.customUnit,
      monthlyMode: rule.monthlyMode,
      weekOrdinal: rule.weekOrdinal,
      startDate: rule.startDate,
      endDate: rule.endDate,
      occurrencesCount: rule.occurrencesCount,
    );
    await _dataSource.update(rule);
  }

  Future<void> deleteRule(int id) => _dataSource.delete(id);

  /// Valid values for [RecurrenceRuleModel.weekOrdinal]: 1st-4th, or -1
  /// for "last". See [WeekOrdinal].
  static const List<int> _validWeekOrdinals = [1, 2, 3, 4, -1];

  /// Rejects any recurrence rule shape that [RecurrenceCalculator] could
  /// not correctly (or safely) compute occurrences for. Shared by
  /// [createRule] and [updateRule] so both paths are equally protected.
  void _validate({
    required RecurrenceFrequency frequency,
    required int intervalValue,
    List<int>? daysOfWeek,
    RecurrenceCustomUnit? customUnit,
    required RecurrenceMonthlyMode monthlyMode,
    int? weekOrdinal,
    required DateTime startDate,
    DateTime? endDate,
    int? occurrencesCount,
  }) {
    if (intervalValue < 1) {
      throw ArgumentError(
          'intervalValue must be at least 1, got $intervalValue');
    }
    if (frequency == RecurrenceFrequency.weekly) {
      if (daysOfWeek == null || daysOfWeek.isEmpty) {
        throw ArgumentError(
            'A weekly recurrence rule requires at least one day of week');
      }
      if (daysOfWeek.any((day) => day < 1 || day > 7)) {
        throw ArgumentError(
          'daysOfWeek values must be ISO weekday numbers 1 (Monday) to 7 '
          '(Sunday), got $daysOfWeek',
        );
      }
    }
    if (frequency == RecurrenceFrequency.monthly &&
        monthlyMode == RecurrenceMonthlyMode.weekdayPosition) {
      if (daysOfWeek == null || daysOfWeek.length != 1) {
        throw ArgumentError(
          'A weekday-position monthly recurrence rule requires exactly '
          'one target weekday in daysOfWeek, got $daysOfWeek',
        );
      }
      if (daysOfWeek.first < 1 || daysOfWeek.first > 7) {
        throw ArgumentError(
          'daysOfWeek value must be an ISO weekday number 1 (Monday) to 7 '
          '(Sunday), got ${daysOfWeek.first}',
        );
      }
      if (weekOrdinal == null || !_validWeekOrdinals.contains(weekOrdinal)) {
        throw ArgumentError(
          'A weekday-position monthly recurrence rule requires weekOrdinal '
          'to be one of $_validWeekOrdinals (1st-4th, or -1 for "last"), '
          'got $weekOrdinal',
        );
      }
    }
    if (frequency == RecurrenceFrequency.custom && customUnit == null) {
      throw ArgumentError(
          'A custom recurrence rule requires customUnit to be set');
    }
    if (endDate != null && endDate.isBefore(startDate)) {
      throw ArgumentError(
          'endDate ($endDate) cannot be before startDate ($startDate)');
    }
    if (occurrencesCount != null && occurrencesCount < 1) {
      throw ArgumentError(
          'occurrencesCount must be at least 1, got $occurrencesCount');
    }
  }
}
