import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_model.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../../../tasks/presentation/screens/task_details_screen.dart';
import '../../../tasks/presentation/screens/task_form_screen.dart';
import '../../../tasks/presentation/widgets/task_list_tile.dart';

final DateFormat _monthFormat = DateFormat('MMMM yyyy');
final DateFormat _dayHeaderFormat = DateFormat('EEEE, MMM d');
const List<String> _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The Calendar tab: a hand-rolled month grid (no calendar package - the
/// project avoids adding dependencies where a small amount of date math
/// does the job) with a dot under any day that has tasks due, and a list of
/// that day's tasks below the grid when a day is selected.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _visibleMonth;
  DateTime? _selectedDay;
  late Future<_CalendarData> _future;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  Future<_CalendarData> _load() async {
    final repos = RepositoryScope.of(context);
    final from = _visibleMonth;
    final to = DateTime(_visibleMonth.year, _visibleMonth.month + 1)
        .subtract(const Duration(milliseconds: 1));
    final tasks = await repos.taskRepository.getAllTasks(dueDateFrom: from, dueDateTo: to);
    final categories = await repos.categoryRepository.getAllCategories();
    final categoryById = {for (final c in categories) if (c.id != null) c.id!: c};

    final now = DateTime.now();
    final tagsByTaskId = <int, List<TagModel>>{};
    final activeSnoozeTaskIds = <int>{};
    final tasksByDay = <int, List<TaskModel>>{};
    for (final task in tasks) {
      final id = task.id!;
      tagsByTaskId[id] = await repos.taskRepository.getTagsForTask(id);
      final reminders = await repos.reminderRepository.getRemindersForTask(id);
      final hasActiveSnooze = reminders.any(
        (r) => r.isEnabled && r.snoozedUntil != null && r.snoozedUntil!.isAfter(now),
      );
      if (hasActiveSnooze) activeSnoozeTaskIds.add(id);
      final day = task.dueDate!.day;
      tasksByDay.putIfAbsent(day, () => []).add(task);
    }

    return _CalendarData(
      tasksByDay: tasksByDay,
      categoryById: categoryById,
      tagsByTaskId: tagsByTaskId,
      activeSnoozeTaskIds: activeSnoozeTaskIds,
    );
  }

  void _reload() {
    setState(() {
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

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
      _future = _load();
    });
  }

  void _selectDay(int day) {
    setState(() {
      _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month, day);
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
            return _CalendarErrorView(onRetry: _reload);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final selectedTasks =
              _selectedDay == null ? const <TaskModel>[] : (data.tasksByDay[_selectedDay!.day] ?? const []);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeMonth(-1),
                    ),
                    Expanded(
                      child: Text(
                        _monthFormat.format(_visibleMonth),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeMonth(1),
                    ),
                  ],
                ),
              ),
              const _WeekdayHeader(),
              _MonthGrid(
                visibleMonth: _visibleMonth,
                selectedDay: _selectedDay,
                tasksByDay: data.tasksByDay,
                onSelectDay: _selectDay,
              ),
              const Divider(height: 1),
              Expanded(
                child: _selectedDay == null
                    ? const Center(child: Text('Select a day to see its tasks'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        children: [
                          Text(
                            _dayHeaderFormat.format(_selectedDay!),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          if (selectedTasks.isEmpty)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    Text(
                                      'No tasks for this day 🎉',
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Your schedule is clear.',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
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
  });

  final Map<int, List<TaskModel>> tasksByDay;
  final Map<int, CategoryModel> categoryById;
  final Map<int, List<TagModel>> tagsByTaskId;
  final Set<int> activeSnoozeTaskIds;
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

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDay,
    required this.tasksByDay,
    required this.onSelectDay,
  });

  final DateTime visibleMonth;
  final DateTime? selectedDay;
  final Map<int, List<TaskModel>> tasksByDay;
  final ValueChanged<int> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingBlanks = visibleMonth.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final trailingBlanks = (7 - totalCells % 7) % 7;
    final cellCount = totalCells + trailingBlanks;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
      itemCount: cellCount,
      itemBuilder: (context, index) {
        final day = index - leadingBlanks + 1;
        if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

        final cellDate = DateTime(visibleMonth.year, visibleMonth.month, day);
        final isToday = cellDate == today;
        final isSelected = selectedDay != null &&
            selectedDay!.year == cellDate.year &&
            selectedDay!.month == cellDate.month &&
            selectedDay!.day == cellDate.day;
        final taskCount = tasksByDay[day]?.length ?? 0;

        return Padding(
          padding: const EdgeInsets.all(2),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelectDay(day),
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
                    '$day',
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
      },
    );
  }
}

class _CalendarErrorView extends StatelessWidget {
  const _CalendarErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            const Text('Something went wrong loading the calendar.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
