import '../datasources/recurrence_rule_data_source.dart';
import '../models/enums.dart';
import '../models/recurrence_rule_model.dart';

/// Application-facing operations for recurrence rules.
class RecurrenceRepository {
  RecurrenceRepository(this._dataSource);

  final RecurrenceRuleDataSource _dataSource;

  Future<RecurrenceRuleModel> createRule({
    required RecurrenceFrequency frequency,
    int intervalValue = 1,
    List<int>? daysOfWeek,
    required DateTime startDate,
    DateTime? endDate,
    int? occurrencesCount,
  }) async {
    final rule = RecurrenceRuleModel(
      frequency: frequency,
      intervalValue: intervalValue,
      daysOfWeek: daysOfWeek,
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
    await _dataSource.update(rule);
  }

  Future<void> deleteRule(int id) => _dataSource.delete(id);
}
