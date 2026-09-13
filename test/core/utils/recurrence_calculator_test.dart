import 'package:flutter_test/flutter_test.dart';

import 'package:remind/core/utils/recurrence_calculator.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/models/recurrence_rule_model.dart';

/// Builds a rule for a test with sensible defaults, so each test only
/// spells out the fields it actually cares about.
RecurrenceRuleModel _rule({
  required RecurrenceFrequency frequency,
  int intervalValue = 1,
  List<int>? daysOfWeek,
  RecurrenceCustomUnit? customUnit,
  required DateTime startDate,
  DateTime? endDate,
  int? occurrencesCount,
}) {
  return RecurrenceRuleModel(
    frequency: frequency,
    intervalValue: intervalValue,
    daysOfWeek: daysOfWeek,
    customUnit: customUnit,
    startDate: startDate,
    endDate: endDate,
    occurrencesCount: occurrencesCount,
    createdAt: startDate,
  );
}

void main() {
  group('daily', () {
    test('every day at a fixed time', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );

      expect(RecurrenceCalculator.firstOccurrence(rule),
          DateTime(2026, 1, 1, 8, 0));
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 1, 8, 0)),
        DateTime(2026, 1, 2, 8, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 5, 8, 0)),
        DateTime(2026, 1, 6, 8, 0),
      );
    });

    test('every N days (interval)', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.daily,
        intervalValue: 3,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 1, 8, 0)),
        DateTime(2026, 1, 4, 8, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 4, 8, 0)),
        DateTime(2026, 1, 7, 8, 0),
      );
    });
  });

  group('weekly', () {
    test('every Monday', () {
      // 2026-06-15 is a Monday.
      final rule = _rule(
        frequency: RecurrenceFrequency.weekly,
        daysOfWeek: [DateTime.monday],
        startDate: DateTime(2026, 6, 15, 10, 0),
      );

      expect(RecurrenceCalculator.firstOccurrence(rule),
          DateTime(2026, 6, 15, 10, 0));
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 6, 15, 10, 0)),
        DateTime(2026, 6, 22, 10, 0),
      );
    });

    test('multiple weekdays in one week, in chronological order', () {
      // Monday + Wednesday + Friday, starting on the Monday itself.
      final rule = _rule(
        frequency: RecurrenceFrequency.weekly,
        daysOfWeek: [DateTime.monday, DateTime.wednesday, DateTime.friday],
        startDate: DateTime(2026, 6, 15, 10, 0),
      );

      expect(RecurrenceCalculator.firstOccurrence(rule),
          DateTime(2026, 6, 15, 10, 0));
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 6, 15, 10, 0)),
        DateTime(2026, 6, 17, 10, 0), // Wednesday
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 6, 17, 10, 0)),
        DateTime(2026, 6, 19, 10, 0), // Friday
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 6, 19, 10, 0)),
        DateTime(2026, 6, 22, 10, 0), // following Monday
      );
    });

    test('unsorted daysOfWeek input is still walked in chronological order',
        () {
      final rule = _rule(
        frequency: RecurrenceFrequency.weekly,
        daysOfWeek: [DateTime.friday, DateTime.monday, DateTime.wednesday],
        startDate: DateTime(2026, 6, 15, 10, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 6, 15, 10, 0)),
        DateTime(2026, 6, 17, 10, 0),
      );
    });

    test(
        'start date not on a selected weekday skips forward to the first match',
        () {
      // 2026-06-17 is a Wednesday; only Monday and Friday are selected.
      final rule = _rule(
        frequency: RecurrenceFrequency.weekly,
        daysOfWeek: [DateTime.monday, DateTime.friday],
        startDate: DateTime(2026, 6, 17, 9, 0),
      );

      // The Monday of that same week (Jun 15) is before startDate, so it
      // must not be treated as an occurrence - the first one is Friday.
      expect(RecurrenceCalculator.firstOccurrence(rule),
          DateTime(2026, 6, 19, 9, 0));
    });

    test('every N weeks (interval) with multiple weekdays', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.weekly,
        intervalValue: 2,
        daysOfWeek: [DateTime.monday],
        startDate: DateTime(2026, 6, 15, 10, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 6, 15, 10, 0)),
        DateTime(2026, 6, 29, 10, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 6, 29, 10, 0)),
        DateTime(2026, 7, 13, 10, 0),
      );
    });
  });

  group('monthly', () {
    test('every month on the 15th', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.monthly,
        startDate: DateTime(2026, 1, 15, 9, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 15, 9, 0)),
        DateTime(2026, 2, 15, 9, 0),
      );
    });

    test('a month that does not contain the selected day clamps, not overflows',
        () {
      // Jan 31 -> Feb 28 (2026 is not a leap year) -> Mar 31, never
      // spilling into March 3rd the way naive Duration-based addition
      // would.
      final rule = _rule(
        frequency: RecurrenceFrequency.monthly,
        startDate: DateTime(2026, 1, 31, 8, 0),
      );

      expect(RecurrenceCalculator.firstOccurrence(rule),
          DateTime(2026, 1, 31, 8, 0));
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 31, 8, 0)),
        DateTime(2026, 2, 28, 8, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 2, 28, 8, 0)),
        DateTime(2026, 3, 31, 8, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 3, 31, 8, 0)),
        DateTime(2026, 4, 30, 8, 0),
      );
    });

    test('every N months (interval)', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.monthly,
        intervalValue: 3,
        startDate: DateTime(2026, 1, 15, 9, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 15, 9, 0)),
        DateTime(2026, 4, 15, 9, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 4, 15, 9, 0)),
        DateTime(2026, 7, 15, 9, 0),
      );
    });
  });

  group('yearly', () {
    test('every year on September 15', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.yearly,
        startDate: DateTime(2026, 9, 15, 18, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 9, 15, 18, 0)),
        DateTime(2027, 9, 15, 18, 0),
      );
    });

    test(
        'leap-year Feb 29 clamps in non-leap years and recovers on the next leap year',
        () {
      final rule = _rule(
        frequency: RecurrenceFrequency.yearly,
        startDate: DateTime(2024, 2, 29, 7, 0), // 2024 is a leap year
      );

      expect(RecurrenceCalculator.firstOccurrence(rule),
          DateTime(2024, 2, 29, 7, 0));
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2024, 2, 29, 7, 0)),
        DateTime(2025, 2, 28, 7, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2025, 2, 28, 7, 0)),
        DateTime(2026, 2, 28, 7, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 2, 28, 7, 0)),
        DateTime(2027, 2, 28, 7, 0),
      );
      // 2028 is the next leap year: the 29th becomes reachable again
      // rather than staying permanently clamped to the 28th.
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2027, 12, 31)),
        DateTime(2028, 2, 29, 7, 0),
      );
    });

    test('every N years (interval)', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.yearly,
        intervalValue: 2,
        startDate: DateTime(2026, 9, 15, 18, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 9, 15, 18, 0)),
        DateTime(2028, 9, 15, 18, 0),
      );
    });
  });

  group('custom', () {
    test('every N days', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.custom,
        intervalValue: 5,
        customUnit: RecurrenceCustomUnit.days,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 1, 8, 0)),
        DateTime(2026, 1, 6, 8, 0),
      );
    });

    test(
        'every N weeks collapses onto day-stepping (no weekday selection needed)',
        () {
      final rule = _rule(
        frequency: RecurrenceFrequency.custom,
        intervalValue: 2,
        customUnit: RecurrenceCustomUnit.weeks,
        startDate: DateTime(2026, 1, 1, 8, 0), // a Thursday
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 1, 8, 0)),
        DateTime(2026, 1, 15, 8, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 15, 8, 0)),
        DateTime(2026, 1, 29, 8, 0),
      );
    });

    test('every N months', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.custom,
        intervalValue: 1,
        customUnit: RecurrenceCustomUnit.months,
        startDate: DateTime(2026, 1, 31, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 31, 8, 0)),
        DateTime(2026, 2, 28, 8, 0),
      );
    });

    test('every N years', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.custom,
        intervalValue: 1,
        customUnit: RecurrenceCustomUnit.years,
        startDate: DateTime(2024, 2, 29, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2024, 2, 29, 8, 0)),
        DateTime(2025, 2, 28, 8, 0),
      );
    });
  });

  group('end dates', () {
    test('the last occurrence on the end date itself is included', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
        endDate: DateTime(2026, 1, 5, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 4, 8, 0)),
        DateTime(2026, 1, 5, 8, 0),
      );
    });

    test('nothing occurs once the end date has passed', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
        endDate: DateTime(2026, 1, 5, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 5, 8, 0)),
        isNull,
      );
    });
  });

  group('occurrence count', () {
    test('stops after exactly occurrencesCount occurrences', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
        occurrencesCount: 3,
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 1, 8, 0)),
        DateTime(2026, 1, 2, 8, 0),
      );
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 2, 8, 0)),
        DateTime(2026, 1, 3, 8, 0),
      );
      // The 3rd occurrence (Jan 3) was the last one allowed; nothing
      // follows it.
      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 3, 8, 0)),
        isNull,
      );
    });
  });

  group('past dates', () {
    test(
        'a lookup far in the past still returns the rule\'s own first occurrence',
        () {
      final rule = _rule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule, after: DateTime(2000, 1, 1)),
        DateTime(2026, 1, 1, 8, 0),
      );
    });
  });

  group('invalid recurrence', () {
    test('a weekly rule with no days of week produces no occurrences', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.weekly,
        daysOfWeek: const [],
        startDate: DateTime(2026, 1, 1, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 1, 8, 0)),
        isNull,
      );
    });

    test('a custom rule with no customUnit produces no occurrences', () {
      final rule = _rule(
        frequency: RecurrenceFrequency.custom,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );

      expect(
        RecurrenceCalculator.nextOccurrence(rule,
            after: DateTime(2026, 1, 1, 8, 0)),
        isNull,
      );
    });
  });
}
