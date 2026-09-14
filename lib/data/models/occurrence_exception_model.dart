import '../database/db_constants.dart';
import 'enums.dart';

/// A recorded per-occurrence override for one dated occurrence of a
/// recurring task - "skip this one", "cancel future occurrences from
/// here", or "reschedule just this one" - without ever touching the
/// recurrence rule or creating a row for every future occurrence.
///
/// [recurrenceRuleId] + [occurrenceDate] together are this occurrence's
/// deterministic identity (see [OccurrenceExceptionsTable]); the database
/// enforces that pair as unique, so the same occurrence can never be
/// recorded twice.
class OccurrenceExceptionModel {
  const OccurrenceExceptionModel({
    this.id,
    required this.recurrenceRuleId,
    required this.occurrenceDate,
    required this.status,
    this.rescheduledTo,
    required this.createdAt,
  });

  final int? id;
  final int recurrenceRuleId;

  /// The occurrence's own canonical, un-rescheduled date/time - as
  /// `RecurrenceCalculator` would compute it directly from the rule.
  final DateTime occurrenceDate;
  final OccurrenceExceptionStatus status;

  /// Set only when [status] is [OccurrenceExceptionStatus.rescheduled].
  final DateTime? rescheduledTo;
  final DateTime createdAt;

  factory OccurrenceExceptionModel.fromMap(Map<String, Object?> map) {
    return OccurrenceExceptionModel(
      id: map[OccurrenceExceptionsTable.id] as int?,
      recurrenceRuleId: map[OccurrenceExceptionsTable.recurrenceRuleId] as int,
      occurrenceDate: DateTime.fromMillisecondsSinceEpoch(
          map[OccurrenceExceptionsTable.occurrenceDate] as int),
      status: OccurrenceExceptionStatus.fromDbValue(
          map[OccurrenceExceptionsTable.status] as int),
      rescheduledTo: map[OccurrenceExceptionsTable.rescheduledTo] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map[OccurrenceExceptionsTable.rescheduledTo] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          map[OccurrenceExceptionsTable.createdAt] as int),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    final map = <String, Object?>{
      OccurrenceExceptionsTable.recurrenceRuleId: recurrenceRuleId,
      OccurrenceExceptionsTable.occurrenceDate:
          occurrenceDate.millisecondsSinceEpoch,
      OccurrenceExceptionsTable.status: status.dbValue,
      OccurrenceExceptionsTable.rescheduledTo:
          rescheduledTo?.millisecondsSinceEpoch,
      OccurrenceExceptionsTable.createdAt: createdAt.millisecondsSinceEpoch,
    };
    if (includeId && id != null) {
      map[OccurrenceExceptionsTable.id] = id;
    }
    return map;
  }

  OccurrenceExceptionModel copyWith({
    int? id,
    int? recurrenceRuleId,
    DateTime? occurrenceDate,
    OccurrenceExceptionStatus? status,
    DateTime? rescheduledTo,
    bool clearRescheduledTo = false,
    DateTime? createdAt,
  }) {
    return OccurrenceExceptionModel(
      id: id ?? this.id,
      recurrenceRuleId: recurrenceRuleId ?? this.recurrenceRuleId,
      occurrenceDate: occurrenceDate ?? this.occurrenceDate,
      status: status ?? this.status,
      rescheduledTo:
          clearRescheduledTo ? null : (rescheduledTo ?? this.rescheduledTo),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'OccurrenceExceptionModel(id: $id, recurrenceRuleId: $recurrenceRuleId, '
      'occurrenceDate: $occurrenceDate, status: $status)';
}
