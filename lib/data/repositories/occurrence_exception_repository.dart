import '../datasources/occurrence_exception_data_source.dart';
import '../models/enums.dart';
import '../models/occurrence_exception_model.dart';

/// Application-facing operations for per-occurrence recurrence
/// exceptions - the additive, append-only log behind "skip this
/// occurrence", "cancel future occurrences", and "reschedule this
/// occurrence". See [OccurrenceExceptionModel] for the identity/uniqueness
/// guarantee this sits on top of.
///
/// `ReminderEngine` is the only caller in normal operation - screens
/// should go through it (for the same reason they go through it rather
/// than `RecurrenceRepository`/`ReminderRepository` directly), never
/// record an exception themselves.
class OccurrenceExceptionRepository {
  OccurrenceExceptionRepository(this._dataSource);

  final OccurrenceExceptionDataSource _dataSource;

  Future<OccurrenceExceptionModel> recordSkipped({
    required int recurrenceRuleId,
    required DateTime occurrenceDate,
    DateTime? now,
  }) {
    return _upsert(
      recurrenceRuleId: recurrenceRuleId,
      occurrenceDate: occurrenceDate,
      status: OccurrenceExceptionStatus.skipped,
      now: now,
    );
  }

  Future<OccurrenceExceptionModel> recordCancelled({
    required int recurrenceRuleId,
    required DateTime occurrenceDate,
    DateTime? now,
  }) {
    return _upsert(
      recurrenceRuleId: recurrenceRuleId,
      occurrenceDate: occurrenceDate,
      status: OccurrenceExceptionStatus.cancelled,
      now: now,
    );
  }

  Future<OccurrenceExceptionModel> recordRescheduled({
    required int recurrenceRuleId,
    required DateTime occurrenceDate,
    required DateTime rescheduledTo,
    DateTime? now,
  }) {
    return _upsert(
      recurrenceRuleId: recurrenceRuleId,
      occurrenceDate: occurrenceDate,
      status: OccurrenceExceptionStatus.rescheduled,
      rescheduledTo: rescheduledTo,
      now: now,
    );
  }

  Future<OccurrenceExceptionModel> recordCompleted({
    required int recurrenceRuleId,
    required DateTime occurrenceDate,
    DateTime? now,
  }) {
    return _upsert(
      recurrenceRuleId: recurrenceRuleId,
      occurrenceDate: occurrenceDate,
      status: OccurrenceExceptionStatus.completed,
      now: now,
    );
  }

  Future<OccurrenceExceptionModel?> getForOccurrence(
    int recurrenceRuleId,
    DateTime occurrenceDate,
  ) {
    return _dataSource.getForOccurrence(recurrenceRuleId, occurrenceDate);
  }

  /// Every exception recorded for [recurrenceRuleId], most recent first -
  /// this recurring task's occurrence history.
  Future<List<OccurrenceExceptionModel>> getHistoryForRule(
      int recurrenceRuleId) {
    return _dataSource.getForRule(recurrenceRuleId);
  }

  Future<OccurrenceExceptionModel> _upsert({
    required int recurrenceRuleId,
    required DateTime occurrenceDate,
    required OccurrenceExceptionStatus status,
    DateTime? rescheduledTo,
    DateTime? now,
  }) async {
    final exception = OccurrenceExceptionModel(
      recurrenceRuleId: recurrenceRuleId,
      occurrenceDate: occurrenceDate,
      status: status,
      rescheduledTo: rescheduledTo,
      createdAt: now ?? DateTime.now(),
    );
    final id = await _dataSource.upsert(exception);
    return exception.copyWith(id: id);
  }
}
