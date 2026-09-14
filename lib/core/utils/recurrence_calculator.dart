import '../../data/models/enums.dart';
import '../../data/models/recurrence_rule_model.dart';

/// Which calendar unit a stepping pass advances by. Years are expressed in
/// terms of months (`12 * n`) rather than getting their own case, since
/// "N years" and "12*N months" are the same calculation once day-of-month
/// clamping is applied - see [RecurrenceCalculator._addMonths].
enum _StepKind { days, months }

/// Pure, deterministic calculation of recurrence occurrences.
///
/// Every method here takes explicit [DateTime] values as input and returns
/// explicit [DateTime] values as output. Nothing in this class calls
/// `DateTime.now()`, touches SQLite, or depends on any other I/O - so
/// every code path can be unit tested directly, with no database and no
/// dependence on "now", which is exactly what makes it possible to test
/// things like "a device with its clock changed" or "a reminder that is
/// already in the past" deterministically (the caller simply passes
/// whatever `after`/`now` value the test wants).
///
/// All calendar-based stepping (monthly/yearly/custom-months/custom-years/
/// custom-weeks) reconstructs the target date component-wise via
/// `DateTime(year, month, day, hour, minute, ...)` rather than using
/// `.add(Duration(...))`. A [Duration] is a fixed number of microseconds -
/// it has no notion of "a calendar month" or "the 15th" - and adding a
/// 24-hour Duration across a daylight-saving transition can even land on
/// the wrong wall-clock hour. Reconstructing the date from its year/month/
/// day components instead lets Dart's own [DateTime] constructor do the
/// normalizing (rolling January 32nd into February 1st, etc.), which is
/// well-defined, DST-safe, and leap-year-aware.
///
/// ### Monthly recurrence's two modes
///
/// A [RecurrenceFrequency.monthly] rule fires in one of two ways (see
/// [RecurrenceRuleModel.monthlyMode]):
///  - Day-of-month (the original, default behavior): the same calendar
///    day every month (e.g. "the 15th"), taken from `startDate.day`. When
///    a target month is too short to have that day (e.g. "the 31st" in
///    April), REmind's chosen, consistent, documented behavior is to
///    **clamp to the target month's last day** - "the 31st" becomes "the
///    30th" in a 30-day month and "the 28th/29th" in February - never
///    silently overflowing into the following month. This is exactly
///    what [_addMonths] already did before Part 12.5 and remains
///    unchanged.
///  - Weekday-position (new in Part 12.5): "the first Monday of every
///    month", "the last Friday of every month", etc. This mode has no
///    such edge case to document in the first place - every month has at
///    least four of every weekday, and always has exactly one "last"
///    occurrence of any weekday, so every ordinal this app exposes
///    (first/second/third/fourth/last) always resolves to a real date.
class RecurrenceCalculator {
  RecurrenceCalculator._();

  /// Safety cap on forward iteration for a single lookup. A well-formed
  /// rule (see `RecurrenceRepository`'s validation) never comes close to
  /// this; it exists purely so a malformed rule fails loudly with a
  /// [StateError] instead of looping forever.
  static const int _maxIterations = 100000;

  /// The very first occurrence of [rule] - normally its `startDate`
  /// itself, except for a weekly (or monthly weekday-position) rule whose
  /// `startDate` does not itself fall on a qualifying date, in which case
  /// it is the first matching date at/after `startDate`.
  static DateTime? firstOccurrence(RecurrenceRuleModel rule) {
    return nextOccurrence(rule, after: rule.startDate, inclusive: true);
  }

  /// The next time [rule] fires strictly after [after] - or at-or-after
  /// [after], when [inclusive] is true (used by [firstOccurrence] to
  /// include `startDate` itself).
  ///
  /// Returns null once the rule's end condition (`endDate` or
  /// `occurrencesCount`) has been reached before a qualifying occurrence
  /// is found - callers use this to detect "this recurrence has ended"
  /// (e.g. when deciding whether to roll a completed recurring task
  /// forward to another occurrence, or leave it completed for good).
  static DateTime? nextOccurrence(
    RecurrenceRuleModel rule, {
    required DateTime after,
    bool inclusive = false,
  }) {
    for (final occurrence in _occurrences(rule)) {
      final qualifies =
          inclusive ? !occurrence.isBefore(after) : occurrence.isAfter(after);
      if (qualifies) return occurrence;
    }
    return null;
  }

  /// Yields every occurrence of [rule], in chronological order starting
  /// from its very first one, stopping once its end date or occurrence
  /// count is reached (or never, for a rule with neither). This is a
  /// lazy generator (`sync*`): [nextOccurrence] only ever pulls as many
  /// values from it as it needs to find one qualifying occurrence, so it
  /// never pays to compute occurrences beyond that.
  static Iterable<DateTime> _occurrences(RecurrenceRuleModel rule) sync* {
    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        yield* _unitStepOccurrences(rule,
            kind: _StepKind.days, amount: rule.intervalValue);
        return;
      case RecurrenceFrequency.weekly:
        yield* _weeklyOccurrences(rule);
        return;
      case RecurrenceFrequency.monthly:
        if (rule.monthlyMode == RecurrenceMonthlyMode.weekdayPosition) {
          yield* _monthlyWeekdayPositionOccurrences(rule);
        } else {
          yield* _unitStepOccurrences(rule,
              kind: _StepKind.months, amount: rule.intervalValue);
        }
        return;
      case RecurrenceFrequency.yearly:
        yield* _unitStepOccurrences(rule,
            kind: _StepKind.months, amount: rule.intervalValue * 12);
        return;
      case RecurrenceFrequency.custom:
        yield* _customOccurrences(rule);
        return;
    }
  }

  /// "Custom" collapses onto the same day/month stepping the other
  /// frequencies use, once `customUnit` picks which one: days and weeks
  /// both become day-stepping (a week is just 7 days), months and years
  /// both become month-stepping (a year is just 12 months).
  static Iterable<DateTime> _customOccurrences(RecurrenceRuleModel rule) sync* {
    final unit = rule.customUnit;
    final amount = rule.intervalValue;
    switch (unit) {
      case RecurrenceCustomUnit.days:
        yield* _unitStepOccurrences(rule, kind: _StepKind.days, amount: amount);
        return;
      case RecurrenceCustomUnit.weeks:
        yield* _unitStepOccurrences(rule,
            kind: _StepKind.days, amount: amount * 7);
        return;
      case RecurrenceCustomUnit.months:
        yield* _unitStepOccurrences(rule,
            kind: _StepKind.months, amount: amount);
        return;
      case RecurrenceCustomUnit.years:
        yield* _unitStepOccurrences(rule,
            kind: _StepKind.months, amount: amount * 12);
        return;
      case null:
        // RecurrenceRepository's validation never lets a custom rule
        // reach storage without a customUnit; a rule built by hand
        // (bypassing the repository, e.g. directly in a test) that
        // violates that contract simply produces no occurrences rather
        // than crashing arbitrarily deep inside date math.
        return;
    }
  }

  /// Simple calendar stepping used by daily/monthly(day-of-month)/yearly
  /// and every "custom" variant: occurrence index `i` is `startDate`
  /// advanced by `amount * i` of [kind] (days or months), clamping the
  /// day-of-month when a target month is shorter than `startDate`'s day
  /// (see [_addMonths]) - this is what correctly turns "the 31st" into
  /// "the 28th/29th/30th" in a shorter month instead of overflowing into
  /// the month after, and what correctly turns "yearly on Feb 29" into
  /// "Feb 28" on a non-leap year.
  static Iterable<DateTime> _unitStepOccurrences(
    RecurrenceRuleModel rule, {
    required _StepKind kind,
    required int amount,
  }) sync* {
    var index = 0;
    while (true) {
      if (index > _maxIterations) {
        throw StateError(
          'RecurrenceCalculator: exceeded $_maxIterations iterations '
          'computing occurrences for rule ${rule.id}',
        );
      }
      final occurrence = kind == _StepKind.days
          ? _addDays(rule.startDate, amount * index)
          : _addMonths(rule.startDate, amount * index);
      if (rule.endDate != null && occurrence.isAfter(rule.endDate!)) return;
      if (rule.occurrencesCount != null && index >= rule.occurrencesCount!) {
        return;
      }
      yield occurrence;
      index++;
    }
  }

  /// Weekly stepping with (possibly multiple) selected weekdays, e.g.
  /// "every Monday + Wednesday + Friday", repeated every `intervalValue`
  /// weeks.
  ///
  /// Occurrences are generated in Monday-anchored "blocks": block 0 is the
  /// week containing `startDate`, block `b` is `intervalValue * b` weeks
  /// after that. Within each block, every selected weekday is visited in
  /// chronological (ascending) order. A candidate that falls before
  /// `startDate` is only possible in block 0 (every later block is
  /// entirely after it) and is simply skipped, rather than counted as an
  /// occurrence.
  static Iterable<DateTime> _weeklyOccurrences(RecurrenceRuleModel rule) sync* {
    final days = <int>{...?rule.daysOfWeek}.toList()..sort();
    if (days.isEmpty) {
      // RecurrenceRepository's validation never lets a weekly rule reach
      // storage with no selected days; a hand-built rule that violates
      // that contract simply produces no occurrences.
      return;
    }

    final start = rule.startDate;
    final anchorMonday = _addDays(start, -(start.weekday - 1));

    var block = 0;
    var index = 0; // genuine occurrence count, for the occurrencesCount bound
    while (true) {
      if (block > _maxIterations) {
        throw StateError(
          'RecurrenceCalculator: exceeded $_maxIterations iterations '
          'computing weekly occurrences for rule ${rule.id}',
        );
      }
      final blockMonday =
          _addDays(anchorMonday, block * rule.intervalValue * 7);
      for (final weekday in days) {
        final candidate = _addDays(blockMonday, weekday - 1);
        if (candidate.isBefore(start)) continue;
        if (rule.endDate != null && candidate.isAfter(rule.endDate!)) return;
        if (rule.occurrencesCount != null && index >= rule.occurrencesCount!) {
          return;
        }
        yield candidate;
        index++;
      }
      block++;
    }
  }

  /// Monthly weekday-position stepping, e.g. "the first Monday of every
  /// month" or "the last Friday of every month", repeated every
  /// `intervalValue` months.
  ///
  /// Occurrence index `i` targets the month `intervalValue * i` months
  /// after `startDate`'s own month (the *month* advances the same way
  /// [_addMonths] does; only the day-of-month is computed differently -
  /// see [_nthWeekdayOfMonth] - since there is no "day of month" to clamp
  /// in this mode). A candidate before `startDate` (possible only for
  /// `i == 0`, if `startDate` itself isn't that month's qualifying
  /// weekday) is skipped rather than counted as an occurrence, exactly
  /// like [_weeklyOccurrences] does for its own `startDate` edge case.
  static Iterable<DateTime> _monthlyWeekdayPositionOccurrences(
      RecurrenceRuleModel rule) sync* {
    final weekdays = rule.daysOfWeek;
    final ordinal = rule.weekOrdinal;
    if (weekdays == null || weekdays.isEmpty || ordinal == null) {
      // RecurrenceRepository's validation never lets a weekday-position
      // monthly rule reach storage without exactly one target weekday
      // and an ordinal; a hand-built rule that violates that contract
      // simply produces no occurrences.
      return;
    }
    final weekday = weekdays.first;
    final start = rule.startDate;

    var index = 0;
    var occurrenceCount = 0;
    while (true) {
      if (index > _maxIterations) {
        throw StateError(
          'RecurrenceCalculator: exceeded $_maxIterations iterations '
          'computing monthly weekday-position occurrences for rule '
          '${rule.id}',
        );
      }
      final target =
          _shiftYearMonth(start.year, start.month, rule.intervalValue * index);
      final occurrence = _nthWeekdayOfMonth(
        target.year,
        target.month,
        weekday,
        ordinal,
        start,
      );
      if (occurrence != null && !occurrence.isBefore(start)) {
        if (rule.endDate != null && occurrence.isAfter(rule.endDate!)) return;
        if (rule.occurrencesCount != null &&
            occurrenceCount >= rule.occurrencesCount!) {
          return;
        }
        yield occurrence;
        occurrenceCount++;
      }
      index++;
    }
  }

  /// The date of the [ordinal]-th [isoWeekday] (1 = Monday .. 7 = Sunday)
  /// in [year]/[month] - or, for `ordinal == -1`, the *last* [isoWeekday]
  /// in that month - with [timeOf]'s time-of-day attached. `ordinal` 1-4
  /// always resolves (every month has at least four of every weekday) and
  /// -1 always resolves (every month has a last occurrence of any
  /// weekday); this only returns null for an out-of-range `ordinal` a
  /// hand-built rule might otherwise pass in (e.g. 5, or 0).
  static DateTime? _nthWeekdayOfMonth(
    int year,
    int month,
    int isoWeekday,
    int ordinal,
    DateTime timeOf,
  ) {
    final daysInMonth = _daysInMonth(year, month);
    if (ordinal == -1) {
      for (var day = daysInMonth; day >= 1; day--) {
        if (DateTime(year, month, day).weekday == isoWeekday) {
          return _atTimeOf(year, month, day, timeOf);
        }
      }
      return null;
    }
    if (ordinal < 1) return null;
    var count = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      if (DateTime(year, month, day).weekday == isoWeekday) {
        count++;
        if (count == ordinal) return _atTimeOf(year, month, day, timeOf);
      }
    }
    return null;
  }

  static DateTime _atTimeOf(int year, int month, int day, DateTime timeOf) {
    return DateTime(
      year,
      month,
      day,
      timeOf.hour,
      timeOf.minute,
      timeOf.second,
      timeOf.millisecond,
      timeOf.microsecond,
    );
  }

  /// [year]/[month] advanced by [monthsToAdd] whole calendar months (which
  /// may be 0), with the year rolling over correctly either direction is
  /// never needed here since `monthsToAdd` is always >= 0, but the modulo
  /// arithmetic is written to stay correct regardless.
  static ({int year, int month}) _shiftYearMonth(
      int year, int month, int monthsToAdd) {
    final totalMonths = (month - 1) + monthsToAdd;
    final targetYear = year + totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    return (year: targetYear, month: targetMonth);
  }

  /// Adds [days] calendar days to [start], preserving its time-of-day
  /// exactly. Deliberately date-component arithmetic rather than
  /// `start.add(Duration(days: days))`: a fixed-duration add can shift the
  /// wall-clock hour across a DST transition (a day that is only 23 or 25
  /// hours long), while reconstructing the target date from
  /// year/month/day and re-attaching the original hour/minute/second
  /// cannot - the result always reads the same time of day the rule was
  /// created with. [days] may be any non-negative amount; passing it as
  /// the `day` component and letting [DateTime] normalize the overflow is
  /// itself a safe, well-defined Dart idiom.
  static DateTime _addDays(DateTime start, int days) {
    final rolled = DateTime(start.year, start.month, start.day + days);
    return DateTime(
      rolled.year,
      rolled.month,
      rolled.day,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
  }

  /// Adds [months] calendar months to [start], clamping the day-of-month
  /// to the target month's actual length (so "Jan 31 + 1 month" becomes
  /// "Feb 28/29", never "Mar 3") and preserving [start]'s time-of-day.
  /// [months] is always >= 0 here (an occurrence index times a positive
  /// interval), so the plain non-negative modulo/division below is safe.
  static DateTime _addMonths(DateTime start, int months) {
    final shifted = _shiftYearMonth(start.year, start.month, months);
    final targetDay = _clampDay(start.day, shifted.year, shifted.month);
    return DateTime(
      shifted.year,
      shifted.month,
      targetDay,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
  }

  static int _clampDay(int day, int year, int month) {
    final maxDay = _daysInMonth(year, month);
    return day > maxDay ? maxDay : day;
  }

  /// Number of days in [month] of [year]. Passing day `0` for the month
  /// *after* the target month is a standard, leap-year-aware Dart idiom:
  /// [DateTime] normalizes "the 0th of month M+1" back to "the last day
  /// of month M".
  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;
}
