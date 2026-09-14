import 'package:flutter/material.dart';

import '../../../../core/utils/date_formatting.dart';
import '../../../../core/utils/recurrence_text.dart';
import '../../../../data/models/enums.dart';
import '../widgets/recurrence_draft.dart';

/// Which top-level repeat option is selected - "does not repeat" is
/// represented here (rather than as a nullable [RecurrenceFrequency])
/// purely so this screen has one clean enum to drive its dropdown with.
enum _RepeatOption { doesNotRepeat, daily, weekly, monthly, yearly, custom }

_RepeatOption _optionForFrequency(RecurrenceFrequency frequency) {
  switch (frequency) {
    case RecurrenceFrequency.daily:
      return _RepeatOption.daily;
    case RecurrenceFrequency.weekly:
      return _RepeatOption.weekly;
    case RecurrenceFrequency.monthly:
      return _RepeatOption.monthly;
    case RecurrenceFrequency.yearly:
      return _RepeatOption.yearly;
    case RecurrenceFrequency.custom:
      return _RepeatOption.custom;
  }
}

/// The Add/Edit Task screen's "Repeat" control opens this screen to
/// configure how a task recurs. Pass [initialDraft] (from an existing
/// recurring task's rule, via [RecurrenceDraft.fromRule]) to edit; omit it
/// to start from "Does not repeat". [seriesStartDateTime] is the task's
/// own due date/time, which doubles as the recurrence's start date/time -
/// REmind deliberately does not ask for a separate "recurrence start
/// date": the first occurrence of any repeating task is simply the due
/// date/time the user already set, which keeps this screen focused on
/// just the *pattern* of repetition instead of duplicating a field the
/// user already filled in above it.
///
/// Backing out (the app bar's back button, or the system back
/// gesture/button) pops `null` directly, with no [RecurrenceConfigResult]
/// wrapper - the caller should leave whatever recurrence state it already
/// had. Tapping the checkmark always pops a [RecurrenceConfigResult],
/// whose `draft` is null for "Does not repeat" (meaning "remove any
/// recurrence") or a populated [RecurrenceDraft] otherwise - wrapping it
/// is what lets a caller tell "the user confirmed no recurrence" apart
/// from "the user backed out and changed nothing", which a bare nullable
/// return value could not.
class RecurrenceConfigScreen extends StatefulWidget {
  const RecurrenceConfigScreen({
    super.key,
    required this.seriesStartDateTime,
    this.initialDraft,
  });

  final DateTime seriesStartDateTime;
  final RecurrenceDraft? initialDraft;

  @override
  State<RecurrenceConfigScreen> createState() => _RecurrenceConfigScreenState();
}

/// Wraps the two distinct "screen was closed" outcomes a caller needs to
/// tell apart: the user explicitly chose "Does not repeat" and confirmed
/// (=> stop repeating, if it was previously recurring) vs. the user
/// backed out of the screen entirely (=> leave the existing choice alone).
class RecurrenceConfigResult {
  const RecurrenceConfigResult(this.draft);

  /// Null means "does not repeat".
  final RecurrenceDraft? draft;
}

class _RecurrenceConfigScreenState extends State<RecurrenceConfigScreen> {
  late _RepeatOption _option;
  late int _intervalValue;
  late Set<int> _daysOfWeek;
  late RecurrenceCustomUnit _customUnit;
  late RecurrenceMonthlyMode _monthlyMode;
  late int _weekOrdinal;
  DateTime? _endDate;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _option = draft == null
        ? _RepeatOption.doesNotRepeat
        : _optionForFrequency(draft.frequency);
    _intervalValue = draft?.intervalValue ?? 1;
    _daysOfWeek = {
      ...?draft?.daysOfWeek,
      if (draft == null || (draft.daysOfWeek?.isEmpty ?? true))
        widget.seriesStartDateTime.weekday,
    };
    _customUnit = draft?.customUnit ?? RecurrenceCustomUnit.days;
    _monthlyMode = draft?.monthlyMode ?? RecurrenceMonthlyMode.dayOfMonth;
    _weekOrdinal = draft?.weekOrdinal ??
        _ordinalForDayOfMonth(widget.seriesStartDateTime.day);
    _endDate = draft?.endDate;
  }

  /// A reasonable default ordinal for a task whose due date is, say, the
  /// 22nd - "the fourth <weekday>" - so switching into weekday-position
  /// mode starts from something plausible instead of always "First".
  static int _ordinalForDayOfMonth(int day) {
    final ordinal = ((day - 1) ~/ 7) + 1;
    return ordinal > 4 ? 4 : ordinal;
  }

  RecurrenceDraft? get _currentDraft {
    if (_option == _RepeatOption.doesNotRepeat) return null;
    switch (_option) {
      case _RepeatOption.doesNotRepeat:
        return null;
      case _RepeatOption.daily:
        return RecurrenceDraft(
          frequency: RecurrenceFrequency.daily,
          intervalValue: _intervalValue,
          endDate: _endDate,
        );
      case _RepeatOption.weekly:
        return RecurrenceDraft(
          frequency: RecurrenceFrequency.weekly,
          intervalValue: _intervalValue,
          daysOfWeek: _daysOfWeek.toList()..sort(),
          endDate: _endDate,
        );
      case _RepeatOption.monthly:
        return RecurrenceDraft(
          frequency: RecurrenceFrequency.monthly,
          intervalValue: _intervalValue,
          monthlyMode: _monthlyMode,
          daysOfWeek: _monthlyMode == RecurrenceMonthlyMode.weekdayPosition
              ? [widget.seriesStartDateTime.weekday]
              : null,
          weekOrdinal: _monthlyMode == RecurrenceMonthlyMode.weekdayPosition
              ? _weekOrdinal
              : null,
          endDate: _endDate,
        );
      case _RepeatOption.yearly:
        return RecurrenceDraft(
          frequency: RecurrenceFrequency.yearly,
          intervalValue: _intervalValue,
          endDate: _endDate,
        );
      case _RepeatOption.custom:
        return RecurrenceDraft(
          frequency: RecurrenceFrequency.custom,
          intervalValue: _intervalValue,
          customUnit: _customUnit,
          endDate: _endDate,
        );
    }
  }

  String? _validate(RecurrenceDraft? draft) {
    if (draft == null) return null;
    if (_intervalValue < 1) return 'Enter a number of 1 or more.';
    if (draft.frequency == RecurrenceFrequency.weekly &&
        (draft.daysOfWeek == null || draft.daysOfWeek!.isEmpty)) {
      return 'Pick at least one day of the week.';
    }
    if (_endDate != null && _endDate!.isBefore(widget.seriesStartDateTime)) {
      return 'The end date can\'t be before the due date.';
    }
    return null;
  }

  void _save() {
    final draft = _currentDraft;
    final error = _validate(draft);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.of(context).pop(RecurrenceConfigResult(draft));
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? widget.seriesStartDateTime,
      firstDate: widget.seriesStartDateTime,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _currentDraft?.toPreviewRule(widget.seriesStartDateTime);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repeat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (preview != null) ...[
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.repeat,
                        color:
                            Theme.of(context).colorScheme.onSecondaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        recurrenceSummary(preview),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<_RepeatOption>(
            initialValue: _option,
            decoration: const InputDecoration(labelText: 'Repeats'),
            items: const [
              DropdownMenuItem(
                  value: _RepeatOption.doesNotRepeat,
                  child: Text('Does not repeat')),
              DropdownMenuItem(
                  value: _RepeatOption.daily, child: Text('Every day')),
              DropdownMenuItem(
                  value: _RepeatOption.weekly, child: Text('Every week')),
              DropdownMenuItem(
                  value: _RepeatOption.monthly, child: Text('Every month')),
              DropdownMenuItem(
                  value: _RepeatOption.yearly, child: Text('Every year')),
              DropdownMenuItem(
                  value: _RepeatOption.custom, child: Text('Custom')),
            ],
            onChanged: (value) => setState(() {
              _option = value ?? _RepeatOption.doesNotRepeat;
              _errorText = null;
            }),
          ),
          if (_option != _RepeatOption.doesNotRepeat) ...[
            const SizedBox(height: 20),
            if (_option != _RepeatOption.custom) _buildIntervalRow(),
            if (_option == _RepeatOption.weekly) ...[
              const SizedBox(height: 16),
              _buildWeekdayChips(),
            ],
            if (_option == _RepeatOption.monthly) ...[
              const SizedBox(height: 16),
              _buildMonthlyModePicker(),
            ],
            if (_option == _RepeatOption.custom) ...[
              _buildCustomIntervalRow(),
            ],
            const SizedBox(height: 20),
            _buildEndSection(),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIntervalRow() {
    final unitWord = switch (_option) {
      _RepeatOption.daily => _intervalValue == 1 ? 'day' : 'days',
      _RepeatOption.weekly => _intervalValue == 1 ? 'week' : 'weeks',
      _RepeatOption.monthly => _intervalValue == 1 ? 'month' : 'months',
      _RepeatOption.yearly => _intervalValue == 1 ? 'year' : 'years',
      _ => '',
    };
    return Row(
      children: [
        const Text('Every'),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          child: TextFormField(
            key: ValueKey('interval-$_option'),
            initialValue: '$_intervalValue',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              setState(() {
                _intervalValue = (parsed == null || parsed < 1) ? 1 : parsed;
                _errorText = null;
              });
            },
          ),
        ),
        const SizedBox(width: 12),
        Text(unitWord),
      ],
    );
  }

  Widget _buildCustomIntervalRow() {
    return Row(
      children: [
        const Text('Every'),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          child: TextFormField(
            initialValue: '$_intervalValue',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              setState(() {
                _intervalValue = (parsed == null || parsed < 1) ? 1 : parsed;
                _errorText = null;
              });
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<RecurrenceCustomUnit>(
            initialValue: _customUnit,
            decoration: const InputDecoration(isDense: true),
            items: RecurrenceCustomUnit.values
                .map((u) => DropdownMenuItem(
                    value: u, child: Text(_customUnitLabel(u))))
                .toList(),
            onChanged: (value) => setState(() {
              _customUnit = value ?? _customUnit;
              _errorText = null;
            }),
          ),
        ),
      ],
    );
  }

  String _customUnitLabel(RecurrenceCustomUnit unit) {
    switch (unit) {
      case RecurrenceCustomUnit.days:
        return _intervalValue == 1 ? 'day' : 'days';
      case RecurrenceCustomUnit.weeks:
        return _intervalValue == 1 ? 'week' : 'weeks';
      case RecurrenceCustomUnit.months:
        return _intervalValue == 1 ? 'month' : 'months';
      case RecurrenceCustomUnit.years:
        return _intervalValue == 1 ? 'year' : 'years';
    }
  }

  Widget _buildWeekdayChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var day = 1; day <= 7; day++)
          FilterChip(
            label: Text(shortWeekdayLabel(day)),
            selected: _daysOfWeek.contains(day),
            onSelected: (selected) => setState(() {
              if (selected) {
                _daysOfWeek.add(day);
              } else {
                _daysOfWeek.remove(day);
              }
              _errorText = null;
            }),
          ),
      ],
    );
  }

  Widget _buildMonthlyModePicker() {
    final dayOfMonthLabel =
        'Monthly on the ${_dayOrdinal(widget.seriesStartDateTime.day)}';
    final ordinal = WeekOrdinal.fromValue(_weekOrdinal);
    final weekdayLabel = fullWeekdayLabel(widget.seriesStartDateTime.weekday);
    final weekdayPositionLabel =
        '${weekOrdinalLabel(ordinal)} $weekdayLabel of every month';
    return RadioGroup<RecurrenceMonthlyMode>(
      groupValue: _monthlyMode,
      onChanged: (value) => setState(() {
        _monthlyMode = value ?? _monthlyMode;
        _errorText = null;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioListTile<RecurrenceMonthlyMode>(
            contentPadding: EdgeInsets.zero,
            title: Text(dayOfMonthLabel),
            value: RecurrenceMonthlyMode.dayOfMonth,
          ),
          RadioListTile<RecurrenceMonthlyMode>(
            contentPadding: EdgeInsets.zero,
            title: Text(weekdayPositionLabel),
            value: RecurrenceMonthlyMode.weekdayPosition,
          ),
          if (_monthlyMode == RecurrenceMonthlyMode.weekdayPosition) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _weekOrdinal,
              decoration: InputDecoration(
                labelText: 'Which $weekdayLabel',
                isDense: true,
              ),
              items: WeekOrdinal.values
                  .map((o) => DropdownMenuItem(
                      value: o.value, child: Text(weekOrdinalLabel(o))))
                  .toList(),
              onChanged: (value) => setState(() {
                _weekOrdinal = value ?? _weekOrdinal;
                _errorText = null;
              }),
            ),
          ],
        ],
      ),
    );
  }

  String _dayOrdinal(int day) {
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

  Widget _buildEndSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ends', style: Theme.of(context).textTheme.labelLarge),
        RadioGroup<bool>(
          groupValue: _endDate != null,
          onChanged: (value) async {
            if (value == null) return;
            if (value == false) {
              setState(() {
                _endDate = null;
                _errorText = null;
              });
              return;
            }
            setState(() => _errorText = null);
            await _pickEndDate();
            if (_endDate == null && mounted) {
              setState(() => _endDate =
                  widget.seriesStartDateTime.add(const Duration(days: 30)));
            }
          },
          child: const Column(
            children: [
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                title: Text('Never'),
                value: false,
              ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                title: Text('On a date'),
                value: true,
              ),
            ],
          ),
        ),
        if (_endDate != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(formatDate(_endDate!)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickEndDate,
            ),
          ),
      ],
    );
  }
}
