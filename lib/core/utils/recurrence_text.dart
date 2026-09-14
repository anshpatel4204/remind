import 'package:intl/intl.dart';

import '../../data/models/enums.dart';
import '../../data/models/recurrence_rule_model.dart';

final DateFormat _monthDayFormat = DateFormat('MMM d');

const List<String> _shortWeekdayLabels = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _fullWeekdayLabels = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// A short, plain-language summary of how often [rule] repeats, e.g.
/// "Every day", "Every Mon, Wed, Fri", "Every 2 weeks", "Monthly on the
/// 15th", "First Monday of every month", "Every year on Sep 15". Shared
/// between the Add/Edit Task screen's Repeat control (its collapsed
/// summary) and the recurrence indicator shown on task list rows and the
/// task details screen, so the same rule always reads identically
/// everywhere in the app.
String recurrenceSummary(RecurrenceRuleModel rule) {
  final n = rule.intervalValue;
  switch (rule.frequency) {
    case RecurrenceFrequency.daily:
      return n == 1 ? 'Every day' : 'Every $n days';

    case RecurrenceFrequency.weekly:
      final days = <int>{...?rule.daysOfWeek}.toList()..sort();
      final dayLabels = days.map((d) => _shortWeekdayLabels[d - 1]).join(', ');
      final base = dayLabels.isEmpty ? 'Every week' : 'Every $dayLabels';
      return n == 1 ? base : '$base, every $n weeks';

    case RecurrenceFrequency.monthly:
      if (rule.monthlyMode == RecurrenceMonthlyMode.weekdayPosition &&
          rule.weekOrdinal != null &&
          (rule.daysOfWeek?.isNotEmpty ?? false)) {
        final ordinalLabel = _ordinalWordLabel(rule.weekOrdinal!);
        final weekdayLabel = _fullWeekdayLabels[rule.daysOfWeek!.first - 1];
        return n == 1
            ? '$ordinalLabel $weekdayLabel of every month'
            : '$ordinalLabel $weekdayLabel, every $n months';
      }
      final dayLabel = _ordinalNumberLabel(rule.startDate.day);
      return n == 1
          ? 'Monthly on the $dayLabel'
          : 'On the $dayLabel, every $n months';

    case RecurrenceFrequency.yearly:
      final label = _monthDayFormat.format(rule.startDate);
      return n == 1 ? 'Every year on $label' : 'On $label, every $n years';

    case RecurrenceFrequency.custom:
      final unit = rule.customUnit;
      final unitWord = switch (unit) {
        RecurrenceCustomUnit.days => n == 1 ? 'day' : 'days',
        RecurrenceCustomUnit.weeks => n == 1 ? 'week' : 'weeks',
        RecurrenceCustomUnit.months => n == 1 ? 'month' : 'months',
        RecurrenceCustomUnit.years => n == 1 ? 'year' : 'years',
        null => n == 1 ? 'time' : 'times',
      };
      return 'Every $n $unitWord';
  }
}

/// "First", "Second", "Third", "Fourth", or "Last" for a
/// [RecurrenceRuleModel.weekOrdinal] value (1-4, or -1).
String _ordinalWordLabel(int weekOrdinal) {
  switch (weekOrdinal) {
    case 1:
      return 'First';
    case 2:
      return 'Second';
    case 3:
      return 'Third';
    case 4:
      return 'Fourth';
    case -1:
      return 'Last';
    default:
      return 'The';
  }
}

/// "1st", "2nd", "3rd", "15th", etc.
String _ordinalNumberLabel(int day) {
  if (day % 100 >= 11 && day % 100 <= 13) return '${day}th';
  switch (day % 10) {
    case 1:
      return '${day}st';
    case 2:
      return '${day}nd';
    case 3:
      return '${day}rd';
    default:
      return '${day}th';
  }
}

/// Display label for a [WeekOrdinal.value] as used in the recurrence
/// picker UI (e.g. dropdown items) - "First", "Second", ..., "Last".
String weekOrdinalLabel(WeekOrdinal ordinal) =>
    _ordinalWordLabel(ordinal.value);

/// Full weekday name for an ISO weekday number (1 = Monday .. 7 = Sunday).
String fullWeekdayLabel(int isoWeekday) => _fullWeekdayLabels[isoWeekday - 1];

/// Short (3-letter) weekday name for an ISO weekday number.
String shortWeekdayLabel(int isoWeekday) => _shortWeekdayLabels[isoWeekday - 1];
