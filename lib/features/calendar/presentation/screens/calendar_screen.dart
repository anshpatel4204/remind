import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/reminder_model.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_model.dart';
import '../../../../presentation/widgets/remind_empty_state.dart';
import '../../../../presentation/widgets/remind_error_state.dart';
import '../../../../presentation/widgets/remind_loading_state.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../../../tasks/presentation/screens/task_details_screen.dart';
import '../../../tasks/presentation/screens/task_form_screen.dart';
import '../../../tasks/presentation/widgets/task_list_tile.dart';

final DateFormat _monthFormat = DateFormat('MMMM yyyy');
final DateFormat _dayHeaderFormat = DateFormat('EEEE, MMM d');
final DateFormat _weekEndpointFormat = DateFormat('MMM d');
final DateFormat _weekEndpointFormatWithYear = DateFormat('MMM d, yyyy');
final DateFormat _timeFormat = DateFormat('h:mm a');
const List<String> _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Which range the Calendar tab is currently showing.
enum _CalendarViewMode { day, week, month }

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The Monday that starts the week containing [d].
DateTime _startOfWeek(DateTime d) {
  final day = _dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// The Calendar tab: Day/Week/Month views (no calendar package - the
/// project avoids adding dependencies where a small amount of date math
/// does the job) with a dot under any day that has tasks due, a list of
/// that day's tasks and reminders below, and a FAB that creates a new task
/// already due on the selected day.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  _CalendarViewMode _viewMode = _CalendarViewMode.month;
  late DateTime _visibleMonth;
  late DateTime _visibleWeekStart;
  DateTime? _selectedDay;
  late Future<_CalendarData> _future;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _visibleWeekStart = _startOfWeek(now);
    _selectedDay = _dateOnly(now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  /// The due-date range currently visible, per [_viewMode] - always
  /// resolved to a concrete `[from, to]` window so [TaskRepository.getAllTasks]
  /// can filter it in SQL rather than the screen loading every task and
  /// filtering client-side.
  (DateTime, DateTime) _visibleRange() {
    switch (_viewMode) {
      case _CalendarViewMode.month:
        final from = _visibleMonth;
        final to = DateTime(_visibleMonth.year, _visibleMonth.month + 1)
            .subtract(const Duration(milliseconds: 1));
        return (from, to);
      case _CalendarViewMode.week:
        final from = _visibleWeekStart;
        final to = _visibleWeekStart.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
        return (from, to);
      case _CalendarViewMode.day:
        final day = _selectedDay ?? _dateOnly(DateTime.now());
        final from = day;
        final to = day.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        return (from, to);
    }
  }

  Future<_CalendarData> _load() async {
    final repos = RepositoryScope.of(context);
    final (from, to) = _visibleRange();
    final tasks = await repos.taskRepository.getAllTasks(dueDateFrom: from, dueDateTo: to);
    final categories = await repos.categoryRepository.getAllCategories();
    final categoryById = {for (final c in categories) if (c.id != null) c.id!: c};

    final now = DateTime.now();
    final tagsByTaskId = <int, List<TagModel>>{};
    final activeSnoozeTaskIds = <int>{};
    final remindersByTaskId = <int, List<ReminderModel>>{};
    final tasksByDay = <DateTime, List<TaskModel>>{};
    for (final task in tasks) {
      final id = task.id!;
      tagsByTaskId[id] = await repos.taskRepository.getTagsForTask(id);
      final reminders = await repos.reminderRepository.getRemindersForTask(id);
      remindersByTaskId[id] = reminders;
      final hasActiveSnooze = reminders.any(
        (r) => r.isEnabled && r.snoozedUntil != null && r.snoozedUntil!.isAfter(now),
      );
      if (hasActiveSnooze) activeSnoozeTaskIds.add(id);
      final day = _dateOnly(task.dueDate!);
      tasksByDay.putIfAbsent(day, () => []).add(task);
    }

    return _CalendarData(
      tasksByDay: tasksByDay,
      categoryById: categoryById,
      tagsByTaskId: tagsByTaskId,
      activeSnoozeTaskIds: activeSnoozeTaskIds,
      remindersByTaskId: remindersByTaskId,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _setViewMode(_CalendarViewMode mode) {
    setState(() {
      _viewMode = mode;
      final anchor = _selectedDay ?? _dateOnly(DateTime.now());
      switch (mode) {
        case _CalendarViewMode.month:
          _visibleMonth = DateTime(anchor.year, anchor.month);
        case _CalendarViewMode.week:
          _visibleWeekStart = _startOfWeek(anchor);
        case _CalendarViewMode.day:
          _selectedDay = anchor;
      }
      _future = _load();
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      if (_selectedDay == null ||
          _selectedDay!.year != _visibleMonth.year ||
          _selectedDay!.month != _visibleMonth.month) {
        _selectedDay = null;
      }
      _future = _load();
    });
  }

  void _changeWeek(int delta) {
    setState(() {
      _visibleWeekStart = _visibleWeekStart.add(Duration(days: 7 * delta));
      final weekEnd = _visibleWeekStart.add(const Duration(days: 6));
      if (_selectedDay == null || _selectedDay!.isBefore(_visibleWeekStart) || _selectedDay!.isAfter(weekEnd)) {
        _selectedDay = null;
      }
      _future = _load();
    });
  }

  void _changeDay(int delta) {
    setState(() {
      _selectedDay = (_selectedDay ?? _dateOnly(DateTime.now())).add(Duration(days: delta));
      _future = _load();
    });
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _visibleWeekStart = _startOfWeek(now);
      _selectedDay = _dateOnly(now);
      _future = _load();
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = day;
    });
  }

  Future<void> _openAddTask() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskFormScreen(initialDueDate: _selectedDay)),
    );
    _reload();
  }

  Future<void> _openDetails(TaskModel task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: task.id!)),
    );
    _reload();
  }

  Future<void> _openEdit(TaskModel task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskFormScreen(existingTask: task)),
    );
    _reload();
  }

  Future<void> _toggleComplete(TaskModel task) async {
    final repos = RepositoryScope.of(context);
    if (task.status == TaskStatus.completed) {
      await repos.taskRepository.reopenTask(task.id!);
    } else {
      await repos.notificationScheduler.completeTask(task.id!);
    }
    _reload();
  }

  Future<void> _togglePin(TaskModel task) async {
    await RepositoryScope.of(context).taskRepository.setPinned(task.id!, !task.isPinned);
    _reload();
  }

  Future<void> _confirmDelete(TaskModel task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${task.title}" will be permanently deleted, along with its reminder.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final repos = RepositoryScope.of(context);
    await repos.notificationScheduler.cancelNotificationsForTask(task.id!);
    await repos.taskRepository.deleteTask(task.id!);
    if (!mounted) return;
    _reload();
  }

  String _headerLabel() {
    switch (_viewMode) {
      case _CalendarViewMode.month:
        return _monthFormat.format(_visibleMonth);
      case _CalendarViewMode.week:
        final weekEnd = _visibleWeekStart.add(const Duration(days: 6));
        final startLabel = _visibleWeekStart.year == weekEnd.year
            ? _weekEndpointFormat.format(_visibleWeekStart)
            : _weekEndpointFormatWithYear.format(_visibleWeekStart);
        final endLabel = _weekEndpointFormatWithYear.format(weekEnd);
        return '$startLabel – $endLabel';
      case _CalendarViewMode.day:
        return _dayHeaderFormat.format(_selectedDay ?? DateTime.now());
    }
  }

  void _changeHeader(int delta) {
    switch (_viewMode) {
      case _CalendarViewMode.month:
        _changeMonth(delta);
      case _CalendarViewMode.week:
        _changeWeek(delta);
      case _CalendarViewMode.day:
        _changeDay(delta);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Jump to today',
            onPressed: _jumpToToday,
          ),
        ],
      ),
      body: FutureBuilder<_CalendarData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return REmindErrorState(
              message: 'Something went wrong loading the calendar.',
              onRetry: _reload,
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const REmindLoadingState();
          }
          final data = snapshot.data!;
          final selectedTasks =
              _selectedDay == null ? const <TaskModel>[] : (data.tasksByDay[_selectedDay!] ?? const []);

          // Enabled reminders for the selected day's tasks, earliest first -
          // real reminder data (not fabricated), reusing what _load() has
          // already fetched rather than issuing a new query.
          final dayReminders = <(TaskModel, ReminderModel)>[];
          for (final task in selectedTasks) {
            final reminders = data.remindersByTaskId[task.id] ?? const [];
            for (final reminder in reminders) {
              if (reminder.isEnabled) dayReminders.add((task, reminder));
            }
          }
          dayReminders.sort((a, b) => a.$2.reminderTime.compareTo(b.$2.reminderTime));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SegmentedButton<_CalendarViewMode>(
                  segments: const [
                    ButtonSegment(value: _CalendarViewMode.day, label: Text('Day')),
                    ButtonSegment(value: _CalendarViewMode.week, label: Text('Week')),
                    ButtonSegment(value: _CalendarViewMode.month, label: Text('Month')),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (selection) => _setViewMode(selection.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous',
                      onPressed: () => _changeHeader(-1),
                    ),
                    Expanded(
                      child: Text(
                        _headerLabel(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next',
                      onPressed: () => _changeHeader(1),
                    ),
                  ],
                ),
              ),
              if (_viewMode != _CalendarViewMode.day) ...[
                const _WeekdayHeader(),
                if (_viewMode == _CalendarViewMode.month)
                  _MonthGrid(
                    visibleMonth: _visibleMonth,
                    selectedDay: _selectedDay,
                    tasksByDay: data.tasksByDay,
                    onSelectDay: _selectDay,
                  )
                else
                  _WeekStrip(
                    weekStart: _visibleWeekStart,
                    selectedDay: _selectedDay,
                    tasksByDay: data.tasksByDay,
                    onSelectDay: _selectDay,
                  ),
                const Divider(height: 1),
              ],
              Expanded(
                child: _selectedDay == null
                    ? const Center(child: Text('Select a day to see its tasks'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        children: [
                          // The day's date is already shown in the header
                          // row above (for all three view modes) - no need
                          // to repeat it here too.
                          if (dayReminders.isNotEmpty) ...[
                            Text('Reminders', style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 6),
                            for (final (task, reminder) in dayReminders)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.notifications_outlined),
                                  title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Text(_timeFormat.format(reminder.reminderTime)),
                                  onTap: () => _openDetails(task),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          Text('Tasks', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 6),
                          if (selectedTasks.isEmpty)
                            const REmindEmptyState(
                              compact: true,
                              title: 'No tasks for this day 🎉',
                              message: 'Your schedule is clear.',
                            )
                          else
                            for (final task in selectedTasks)
                              TaskListTile(
                                task: task,
                                category:
                                    task.categoryId == null ? null : data.categoryById[task.categoryId],
                                tags: data.tagsByTaskId[task.id] ?? const [],
                                hasActiveSnooze: data.activeSnoozeTaskIds.contains(task.id),
                                onTap: () => _openDetails(task),
                                onToggleComplete: () => _toggleComplete(task),
                                onTogglePin: () => _togglePin(task),
                                onEdit: () => _openEdit(task),
                                onDelete: () => _confirmDelete(task),
                              ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar-add-task-fab',
        onPressed: _openAddTask,
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CalendarData {
  const _CalendarData({
    required this.tasksByDay,
    required this.categoryById,
    required this.tagsByTaskId,
    required this.activeSnoozeTaskIds,
    required this.remindersByTaskId,
  });

  final Map<DateTime, List<TaskModel>> tasksByDay;
  final Map<int, CategoryModel> categoryById;
  final Map<int, List<TagModel>> tagsByTaskId;
  final Set<int> activeSnoozeTaskIds;
  final Map<int, List<ReminderModel>> remindersByTaskId;
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          for (final label in _weekdayLabels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One day cell shared by the month grid and the week strip - the day
/// number, today/selected highlighting, and a task-count dot.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.label,
    required this.isToday,
    required this.isSelected,
    required this.taskCount,
    required this.onTap,
  });

  final DateTime date;
  final String label;
  final bool isToday;
  final bool isSelected;
  final int taskCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : isToday
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 6,
                child: taskCount == 0
                    ? null
                    : Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDay,
    required this.tasksByDay,
    required this.onSelectDay,
  });

  final DateTime visibleMonth;
  final DateTime? selectedDay;
  final Map<DateTime, List<TaskModel>> tasksByDay;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingBlanks = visibleMonth.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final trailingBlanks = (7 - totalCells % 7) % 7;
    final cellCount = totalCells + trailingBlanks;
    final today = _dateOnly(DateTime.now());

    // A plain `childAspectRatio: 1` would make every cell as tall as it is
    // wide, so on a wide-but-short viewport (a tablet, a landscape phone,
    // even the default test surface) a 5-6 row month grid can easily be
    // taller than the whole screen. Deriving the aspect ratio from the
    // available width instead caps each row at a fixed, comfortable height
    // regardless of how wide the grid is.
    const horizontalGridPadding = 8.0; // matches the GridView's own padding below
    const desiredCellHeight = 44.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - horizontalGridPadding) / 7;
        final aspectRatio = cellWidth > 0 ? cellWidth / desiredCellHeight : 1.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: aspectRatio,
          ),
          itemCount: cellCount,
          itemBuilder: (context, index) {
            final day = index - leadingBlanks + 1;
            if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

            final cellDate = DateTime(visibleMonth.year, visibleMonth.month, day);
            return _DayCell(
              date: cellDate,
              label: '$day',
              isToday: cellDate == today,
              isSelected: selectedDay != null && selectedDay! == cellDate,
              taskCount: tasksByDay[cellDate]?.length ?? 0,
              onTap: () => onSelectDay(cellDate),
            );
          },
        );
      },
    );
  }
}

/// A single Mon-Sun row of [_DayCell]s for Week view - the same visual
/// language as [_MonthGrid], just one week wide instead of a full month.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.weekStart,
    required this.selectedDay,
    required this.tasksByDay,
    required this.onSelectDay,
  });

  final DateTime weekStart;
  final DateTime? selectedDay;
  final Map<DateTime, List<TaskModel>> tasksByDay;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(builder: (context) {
                final date = weekStart.add(Duration(days: i));
                return _DayCell(
                  date: date,
                  label: '${date.day}',
                  isToday: date == today,
                  isSelected: selectedDay != null && selectedDay! == date,
                  taskCount: tasksByDay[date]?.length ?? 0,
                  onTap: () => onSelectDay(date),
                );
              }),
            ),
        ],
      ),
    );
  }
}
