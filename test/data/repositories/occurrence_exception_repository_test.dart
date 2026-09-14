import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/occurrence_exception_data_source.dart';
import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/occurrence_exception_repository.dart';
import 'package:remind/data/repositories/recurrence_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late OccurrenceExceptionRepository repository;
  late RecurrenceRepository recurrenceRepository;
  late int ruleId;

  setUp(() async {
    testDb = TestAppDatabase.create();
    repository = OccurrenceExceptionRepository(
        OccurrenceExceptionDataSource(testDb.appDatabase));
    recurrenceRepository =
        RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
    final rule = await recurrenceRepository.createRule(
      frequency: RecurrenceFrequency.daily,
      startDate: DateTime(2026, 1, 1, 8, 0),
    );
    ruleId = rule.id!;
  });

  tearDown(() => testDb.tearDown());

  test('a fresh rule has no recorded exceptions', () async {
    expect(await repository.getHistoryForRule(ruleId), isEmpty);
    expect(
      await repository.getForOccurrence(ruleId, DateTime(2026, 1, 1, 8, 0)),
      isNull,
    );
  });

  test('recordSkipped stores a skipped exception for the occurrence date',
      () async {
    await repository.recordSkipped(
      recurrenceRuleId: ruleId,
      occurrenceDate: DateTime(2026, 1, 1, 8, 0),
      now: DateTime(2026, 1, 1, 8, 5),
    );

    final exception =
        await repository.getForOccurrence(ruleId, DateTime(2026, 1, 1, 8, 0));
    expect(exception, isNotNull);
    expect(exception?.status, OccurrenceExceptionStatus.skipped);
    expect(exception?.rescheduledTo, isNull);
  });

  test('recordRescheduled stores the target time it was moved to', () async {
    await repository.recordRescheduled(
      recurrenceRuleId: ruleId,
      occurrenceDate: DateTime(2026, 1, 1, 8, 0),
      rescheduledTo: DateTime(2026, 1, 1, 14, 0),
      now: DateTime(2026, 1, 1, 8, 0),
    );

    final exception =
        await repository.getForOccurrence(ruleId, DateTime(2026, 1, 1, 8, 0));
    expect(exception?.status, OccurrenceExceptionStatus.rescheduled);
    expect(exception?.rescheduledTo, DateTime(2026, 1, 1, 14, 0));
  });

  test('recordCancelled stores a cancelled exception', () async {
    await repository.recordCancelled(
      recurrenceRuleId: ruleId,
      occurrenceDate: DateTime(2026, 1, 5, 8, 0),
      now: DateTime(2026, 1, 5, 8, 5),
    );

    final exception =
        await repository.getForOccurrence(ruleId, DateTime(2026, 1, 5, 8, 0));
    expect(exception?.status, OccurrenceExceptionStatus.cancelled);
  });

  group('duplicate-occurrence prevention (the same occurrence recorded twice)',
      () {
    test(
        'recording a second action against the same (rule, date) replaces '
        'the first, rather than creating a second row', () async {
      await repository.recordSkipped(
        recurrenceRuleId: ruleId,
        occurrenceDate: DateTime(2026, 1, 1, 8, 0),
        now: DateTime(2026, 1, 1, 8, 5),
      );
      // The same occurrence is later rescheduled instead (e.g. the user
      // changed their mind) - this must overwrite the skip, not add a
      // second, conflicting exception for the identical occurrence.
      await repository.recordRescheduled(
        recurrenceRuleId: ruleId,
        occurrenceDate: DateTime(2026, 1, 1, 8, 0),
        rescheduledTo: DateTime(2026, 1, 1, 18, 0),
        now: DateTime(2026, 1, 1, 8, 10),
      );

      final history = await repository.getHistoryForRule(ruleId);
      expect(history, hasLength(1));
      expect(history.single.status, OccurrenceExceptionStatus.rescheduled);
      expect(history.single.rescheduledTo, DateTime(2026, 1, 1, 18, 0));

      final exception =
          await repository.getForOccurrence(ruleId, DateTime(2026, 1, 1, 8, 0));
      expect(exception?.status, OccurrenceExceptionStatus.rescheduled);
    });

    test(
        'recording the identical action twice against the same occurrence '
        'still leaves exactly one row', () async {
      await repository.recordSkipped(
        recurrenceRuleId: ruleId,
        occurrenceDate: DateTime(2026, 1, 1, 8, 0),
        now: DateTime(2026, 1, 1, 8, 5),
      );
      await repository.recordSkipped(
        recurrenceRuleId: ruleId,
        occurrenceDate: DateTime(2026, 1, 1, 8, 0),
        now: DateTime(2026, 1, 1, 8, 6),
      );

      expect(await repository.getHistoryForRule(ruleId), hasLength(1));
    });

    test('different occurrence dates on the same rule are tracked separately',
        () async {
      await repository.recordSkipped(
        recurrenceRuleId: ruleId,
        occurrenceDate: DateTime(2026, 1, 1, 8, 0),
        now: DateTime(2026, 1, 1, 8, 5),
      );
      await repository.recordSkipped(
        recurrenceRuleId: ruleId,
        occurrenceDate: DateTime(2026, 1, 2, 8, 0),
        now: DateTime(2026, 1, 2, 8, 5),
      );

      expect(await repository.getHistoryForRule(ruleId), hasLength(2));
    });
  });

  test('getHistoryForRule returns exceptions most recent occurrence first',
      () async {
    await repository.recordSkipped(
      recurrenceRuleId: ruleId,
      occurrenceDate: DateTime(2026, 1, 1, 8, 0),
      now: DateTime(2026, 1, 1, 8, 5),
    );
    await repository.recordSkipped(
      recurrenceRuleId: ruleId,
      occurrenceDate: DateTime(2026, 1, 3, 8, 0),
      now: DateTime(2026, 1, 3, 8, 5),
    );
    await repository.recordSkipped(
      recurrenceRuleId: ruleId,
      occurrenceDate: DateTime(2026, 1, 2, 8, 0),
      now: DateTime(2026, 1, 2, 8, 5),
    );

    final history = await repository.getHistoryForRule(ruleId);
    expect(history.map((e) => e.occurrenceDate), [
      DateTime(2026, 1, 3, 8, 0),
      DateTime(2026, 1, 2, 8, 0),
      DateTime(2026, 1, 1, 8, 0),
    ]);
  });

  test('an exception for one rule is not returned for another rule', () async {
    final otherRule = await recurrenceRepository.createRule(
      frequency: RecurrenceFrequency.daily,
      startDate: DateTime(2026, 2, 1, 8, 0),
    );

    await repository.recordSkipped(
      recurrenceRuleId: ruleId,
      occurrenceDate: DateTime(2026, 1, 1, 8, 0),
      now: DateTime(2026, 1, 1, 8, 5),
    );

    expect(await repository.getHistoryForRule(otherRule.id!), isEmpty);
    expect(
      await repository.getForOccurrence(
          otherRule.id!, DateTime(2026, 1, 1, 8, 0)),
      isNull,
    );
  });
}
