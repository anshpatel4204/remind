import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/recurrence_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late RecurrenceRepository repository;

  setUp(() {
    testDb = TestAppDatabase.create();
    repository =
        RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
  });

  tearDown(() => testDb.tearDown());

  test('create, read, update, and delete a recurrence rule', () async {
    final created = await repository.createRule(
      frequency: RecurrenceFrequency.weekly,
      daysOfWeek: [1, 3, 5],
      startDate: DateTime(2026, 1, 1),
    );
    expect(created.id, isNotNull);

    final fetched = await repository.getRule(created.id!);
    expect(fetched?.frequency, RecurrenceFrequency.weekly);
    expect(fetched?.daysOfWeek, [1, 3, 5]);

    await repository.updateRule(fetched!.copyWith(intervalValue: 2));
    final updated = await repository.getRule(created.id!);
    expect(updated?.intervalValue, 2);

    await repository.deleteRule(created.id!);
    expect(await repository.getRule(created.id!), isNull);
  });

  test('round-trips a custom rule and its customUnit', () async {
    final created = await repository.createRule(
      frequency: RecurrenceFrequency.custom,
      intervalValue: 3,
      customUnit: RecurrenceCustomUnit.weeks,
      startDate: DateTime(2026, 1, 1),
    );

    final fetched = await repository.getRule(created.id!);
    expect(fetched?.frequency, RecurrenceFrequency.custom);
    expect(fetched?.intervalValue, 3);
    expect(fetched?.customUnit, RecurrenceCustomUnit.weeks);

    // Round-trip through an update too, so a rewritten customUnit is
    // actually persisted and not silently dropped.
    await repository
        .updateRule(fetched!.copyWith(customUnit: RecurrenceCustomUnit.months));
    final updated = await repository.getRule(created.id!);
    expect(updated?.customUnit, RecurrenceCustomUnit.months);
  });

  test('round-trips a monthly weekday-position rule', () async {
    final created = await repository.createRule(
      frequency: RecurrenceFrequency.monthly,
      monthlyMode: RecurrenceMonthlyMode.weekdayPosition,
      daysOfWeek: [DateTime.monday],
      weekOrdinal: WeekOrdinal.first.value,
      startDate: DateTime(2026, 1, 5),
    );

    final fetched = await repository.getRule(created.id!);
    expect(fetched?.frequency, RecurrenceFrequency.monthly);
    expect(fetched?.monthlyMode, RecurrenceMonthlyMode.weekdayPosition);
    expect(fetched?.daysOfWeek, [DateTime.monday]);
    expect(fetched?.weekOrdinal, WeekOrdinal.first.value);

    // Round-trip through an update too (e.g. switching "first" to "last"
    // Monday), so weekOrdinal is actually persisted, not silently dropped.
    await repository.updateRule(
      fetched!.copyWith(weekOrdinal: WeekOrdinal.last.value),
    );
    final updated = await repository.getRule(created.id!);
    expect(updated?.weekOrdinal, WeekOrdinal.last.value);
  });

  test(
      'a monthly rule defaults to dayOfMonth mode when monthlyMode is not '
      'specified', () async {
    final created = await repository.createRule(
      frequency: RecurrenceFrequency.monthly,
      startDate: DateTime(2026, 1, 15),
    );

    expect(created.monthlyMode, RecurrenceMonthlyMode.dayOfMonth);
    final fetched = await repository.getRule(created.id!);
    expect(fetched?.monthlyMode, RecurrenceMonthlyMode.dayOfMonth);
  });

  group('invalid recurrence rejection', () {
    test('rejects a monthly weekday-position rule with no target weekday', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.monthly,
          monthlyMode: RecurrenceMonthlyMode.weekdayPosition,
          weekOrdinal: WeekOrdinal.first.value,
          startDate: DateTime(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });

    test(
        'rejects a monthly weekday-position rule with more than one '
        'weekday selected', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.monthly,
          monthlyMode: RecurrenceMonthlyMode.weekdayPosition,
          daysOfWeek: [DateTime.monday, DateTime.friday],
          weekOrdinal: WeekOrdinal.first.value,
          startDate: DateTime(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a monthly weekday-position rule with no weekOrdinal', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.monthly,
          monthlyMode: RecurrenceMonthlyMode.weekdayPosition,
          daysOfWeek: [DateTime.monday],
          startDate: DateTime(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });

    test(
        'rejects a monthly weekday-position rule with an out-of-range '
        'weekOrdinal', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.monthly,
          monthlyMode: RecurrenceMonthlyMode.weekdayPosition,
          daysOfWeek: [DateTime.monday],
          weekOrdinal: 5,
          startDate: DateTime(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });
    test('rejects an intervalValue below 1', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.daily,
          intervalValue: 0,
          startDate: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a weekly rule with no days of week selected', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.weekly,
          startDate: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a weekly rule with an out-of-range day of week', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [0, 8],
          startDate: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a custom rule with no customUnit', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.custom,
          startDate: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an endDate before startDate', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.daily,
          startDate: DateTime(2026, 1, 10),
          endDate: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an occurrencesCount below 1', () {
      expect(
        () => repository.createRule(
          frequency: RecurrenceFrequency.daily,
          startDate: DateTime(2026, 1, 1),
          occurrencesCount: 0,
        ),
        throwsArgumentError,
      );
    });

    test('also validates on updateRule, not just createRule', () async {
      final created = await repository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1),
      );
      expect(
        () => repository.updateRule(created.copyWith(intervalValue: -1)),
        throwsArgumentError,
      );
    });
  });
}
