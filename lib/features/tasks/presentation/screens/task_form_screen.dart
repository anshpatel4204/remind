import 'package:flutter/material.dart';

import '../../../../core/utils/date_formatting.dart';
import '../../../../core/utils/recurrence_text.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/recurrence_rule_model.dart';
import '../../../../data/models/reminder_model.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_model.dart';
import '../../../../data/repositories/app_repositories.dart';
import '../../../../presentation/widgets/remind_loading_state.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../widgets/recurrence_draft.dart';
import 'recurrence_config_screen.dart';

/// A single form used for both creating a new task and editing an existing
/// one. Pass [existingTask] to edit; omit it to create.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, this.existingTask, this.initialDueDate});

  final TaskModel? existingTask;

  /// Pre-fills the due date when creating a new task (ignored when
  /// [existingTask] is set) - used by the Calendar tab's Add Task FAB so
  /// adding a task for a selected day doesn't require re-picking the date.
  final DateTime? initialDueDate;

  bool get isEditing => existingTask != null;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  TaskPriority _priority = TaskPriority.medium;
  TaskStatus _status = TaskStatus.pending;
  int? _categoryId;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  Set<int> _selectedTagIds = {};

  bool _reminderEnabled = false;
  DateTime? _reminderDate;
  TimeOfDay? _reminderTime;
  ReminderModel? _existingReminder;

  /// The user's Settings > Tasks > Default reminder time (Part 13),
  /// applied whenever neither an existing reminder time nor the task's
  /// own due time is available. Starts at 9:00 AM - REmind's original
  /// hardcoded fallback - so nothing changes before [_loadFormData]'s
  /// real value loads.
  TimeOfDay _defaultReminderTime = const TimeOfDay(hour: 9, minute: 0);

  /// Null means "does not repeat". See [RecurrenceDraft] for why this is
  /// kept separate from a real [RecurrenceRuleModel] until the form is
  /// actually saved.
  RecurrenceDraft? _recurrenceDraft;

  /// The recurrence rule as it was when this form loaded (an existing
  /// recurring task only) - kept around purely so [_reconcileRecurrence]
  /// can tell whether the user actually changed the recurrence pattern
  /// (or the due date) in this edit session, as opposed to editing some
  /// unrelated field (title, priority, ...) and saving - see its own docs
  /// for why that distinction matters.
  RecurrenceRuleModel? _loadedRecurrenceRule;

  List<CategoryModel> _categories = [];
  List<TagModel> _tags = [];
  bool _loading = true;
  bool _saving = false;

  bool _dataLoadStarted = false;

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    if (task != null) {
      _titleController.text = task.title;
      _descriptionController.text = task.description ?? '';
      _priority = task.priority;
      _status = task.status;
      _categoryId = task.categoryId;
      if (task.dueDate != null) {
        _dueDate = DateTime(
            task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
        _dueTime =
            TimeOfDay(hour: task.dueDate!.hour, minute: task.dueDate!.minute);
      }
    } else if (widget.initialDueDate != null) {
      final initial = widget.initialDueDate!;
      _dueDate = DateTime(initial.year, initial.month, initial.day);
    }
  }

  // Loading categories/tags/the existing reminder depends on
  // RepositoryScope.of(context), which cannot be called from initState()
  // (it needs dependOnInheritedWidgetOfExactType) - it must wait until
  // didChangeDependencies().
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dataLoadStarted) {
      _dataLoadStarted = true;
      _loadFormData();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadFormData() async {
    final repos = RepositoryScope.of(context);
    final categories = await repos.categoryRepository.getAllCategories();
    final tags = await repos.tagRepository.getAllTags();

    Set<int> selectedTagIds = {};
    ReminderModel? existingReminder;
    RecurrenceDraft? recurrenceDraft;
    RecurrenceRuleModel? loadedRule;

    final task = widget.existingTask;
    if (task != null) {
      final taskTags = await repos.taskRepository.getTagsForTask(task.id!);
      selectedTagIds = {
        for (final t in taskTags)
          if (t.id != null) t.id!
      };

      final reminders =
          await repos.reminderRepository.getRemindersForTask(task.id!);
      existingReminder = reminders.isEmpty ? null : reminders.first;

      if (task.recurrenceRuleId != null) {
        loadedRule =
            await repos.recurrenceRepository.getRule(task.recurrenceRuleId!);
        recurrenceDraft =
            loadedRule == null ? null : RecurrenceDraft.fromRule(loadedRule);
      }
    }

    // Only a brand-new task picks up the Settings > Tasks defaults - an
    // existing task's own saved priority/category always wins, exactly
    // like initState() already treats initialDueDate as new-task-only.
    TaskPriority? defaultPriority;
    int? defaultCategoryId;
    if (task == null) {
      defaultPriority = await repos.settingsRepository.getDefaultTaskPriority();
      defaultCategoryId = await repos.settingsRepository.getDefaultCategoryId();
    }
    final defaultReminderMinutes =
        await repos.settingsRepository.getDefaultReminderTimeMinutes();

    if (!mounted) return;
    setState(() {
      _categories = categories;
      _tags = tags;
      _selectedTagIds = selectedTagIds;
      if (task == null) {
        if (defaultPriority != null) _priority = defaultPriority;
        if (defaultCategoryId != null &&
            categories.any((c) => c.id == defaultCategoryId)) {
          _categoryId = defaultCategoryId;
        }
      }
      // A category the task pointed to (or a stale default above) may
      // since have been deleted (the dropdown would otherwise crash
      // trying to show a value with no matching item).
      if (_categoryId != null && !categories.any((c) => c.id == _categoryId)) {
        _categoryId = null;
      }
      _defaultReminderTime = TimeOfDay(
        hour: defaultReminderMinutes ~/ 60,
        minute: defaultReminderMinutes % 60,
      );
      _existingReminder = existingReminder;
      _recurrenceDraft = recurrenceDraft;
      _loadedRecurrenceRule = loadedRule;
      if (existingReminder != null) {
        _reminderEnabled = existingReminder.isEnabled;
        _reminderDate = DateTime(
          existingReminder.reminderTime.year,
          existingReminder.reminderTime.month,
          existingReminder.reminderTime.day,
        );
        _reminderTime = TimeOfDay(
          hour: existingReminder.reminderTime.hour,
          minute: existingReminder.reminderTime.minute,
        );
      }
      _loading = false;
    });
  }

  DateTime? get _combinedDueDateTime {
    if (_dueDate == null) return null;
    final time = _dueTime ?? const TimeOfDay(hour: 0, minute: 0);
    return DateTime(
        _dueDate!.year, _dueDate!.month, _dueDate!.day, time.hour, time.minute);
  }

  DateTime? get _combinedReminderDateTime {
    if (_reminderDate == null) return null;
    final time = _reminderTime ?? _defaultReminderTime;
    return DateTime(
      _reminderDate!.year,
      _reminderDate!.month,
      _reminderDate!.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickDueTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: _dueTime ?? TimeOfDay.now());
    if (picked != null) setState(() => _dueTime = picked);
  }

  Future<void> _pickReminderDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _reminderDate ?? _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _reminderDate = picked);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? _dueTime ?? _defaultReminderTime,
    );
    if (picked != null) setState(() => _reminderTime = picked);
  }

  /// Opens the Repeat picker. Requires a due date to already be set - the
  /// recurrence's own start date/time is always the task's due date/time
  /// (see [RecurrenceConfigScreen]'s docs for why REmind doesn't ask for a
  /// separate one) - so the Repeat control itself is disabled until a due
  /// date exists (see its `enabled:` below).
  Future<void> _openRecurrencePicker() async {
    final startDateTime = _combinedDueDateTime;
    if (startDateTime == null) return;

    final result = await Navigator.of(context).push<RecurrenceConfigResult>(
      MaterialPageRoute(
        builder: (_) => RecurrenceConfigScreen(
          seriesStartDateTime: startDateTime,
          initialDraft: _recurrenceDraft,
        ),
      ),
    );
    // A null result means the user backed out of the picker entirely -
    // leave whatever recurrence choice was already there untouched. A
    // non-null result (even one whose own `.draft` is null, for "Does
    // not repeat") is an explicit, confirmed choice.
    if (result == null) return;
    setState(() => _recurrenceDraft = result.draft);
  }

  Future<void> _addNewTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final repos = RepositoryScope.of(context);
    final tag = await repos.tagRepository.createTag(name: trimmed);
    if (!mounted) return;
    setState(() {
      _tags = [..._tags, tag];
      _selectedTagIds = {..._selectedTagIds, tag.id!};
    });
  }

  Future<void> _showAddTagDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await _addNewTag(name);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_reminderEnabled && _reminderDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Pick a reminder date, or turn the reminder off.')),
      );
      return;
    }
    if (_recurrenceDraft != null && _combinedDueDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a due date, or turn Repeat off.')),
      );
      return;
    }

    setState(() => _saving = true);
    final repos = RepositoryScope.of(context);
    final trimmedDescription = _descriptionController.text.trim();

    try {
      TaskModel task;
      if (widget.isEditing) {
        task = widget.existingTask!.copyWith(
          title: _titleController.text.trim(),
          description: trimmedDescription.isEmpty ? null : trimmedDescription,
          clearDescription: trimmedDescription.isEmpty,
          priority: _priority,
          status: _status,
          categoryId: _categoryId,
          clearCategoryId: _categoryId == null,
          dueDate: _combinedDueDateTime,
          clearDueDate: _combinedDueDateTime == null,
        );
        await repos.taskRepository.updateTask(task);
      } else {
        task = await repos.taskRepository.createTask(
          title: _titleController.text.trim(),
          description: trimmedDescription.isEmpty ? null : trimmedDescription,
          priority: _priority,
          categoryId: _categoryId,
          dueDate: _combinedDueDateTime,
        );
      }

      await repos.taskRepository
          .setTagsForTask(task.id!, _selectedTagIds.toList());

      // Routed through notificationScheduler (never reminderRepository
      // directly) so setting/changing/removing a reminder here always
      // keeps its actual scheduled Android notification in sync - see
      // NotificationScheduler for why that matters (duplicate
      // prevention, cancel-before-reschedule, etc).
      final reminderTime = _combinedReminderDateTime;
      if (_reminderEnabled && reminderTime != null) {
        if (_existingReminder == null) {
          await repos.notificationScheduler.createAndScheduleReminder(
            taskId: task.id!,
            reminderTime: reminderTime,
          );
        } else {
          await repos.notificationScheduler.updateAndRescheduleReminder(
            _existingReminder!.id!,
            reminderTime,
          );
        }
      } else if (_existingReminder != null) {
        await repos.notificationScheduler
            .deleteReminder(_existingReminder!.id!);
      }

      await _reconcileRecurrence(repos, task);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Creates, updates, or removes [task]'s recurrence rule to match
  /// [_recurrenceDraft], after the task's own fields/tags/reminder have
  /// already been saved above.
  ///
  /// Editing an *existing* recurring task's pattern (or its due
  /// date/time) here restarts the series from the task's current due
  /// date/time (rather than its original creation date) - this is what
  /// makes "This and future occurrences" and "Entire series" the same
  /// operation in REmind's single-row-per-series architecture (see the
  /// Part 12.5 final report and `openRecurringAwareEdit`): there is no
  /// separate historical occurrence data for a "future-only" change to
  /// leave untouched, so the new pattern simply takes over from here on.
  ///
  /// If the user saved the form WITHOUT changing the Repeat pattern or
  /// the due date - e.g. they only edited the title or priority of a
  /// recurring task - this deliberately does nothing to the rule or to
  /// [TaskModel.occurrenceOriginalDate]. Otherwise an unrelated edit
  /// would silently discard a pending "Reschedule this occurrence only"
  /// (whose entire point is to move just one occurrence while the rest
  /// of the series keeps its original anchor - see
  /// `ReminderEngine.rescheduleCurrentOccurrence`), which would violate
  /// the "editing one occurrence must not affect the whole series" rule.
  Future<void> _reconcileRecurrence(
      AppRepositories repos, TaskModel task) async {
    final draft = _recurrenceDraft;
    final existingRuleId = task.recurrenceRuleId;

    if (draft == null) {
      if (existingRuleId == null) return;
      await repos.recurrenceRepository.deleteRule(existingRuleId);
      await repos.taskRepository.updateTask(
        task.copyWith(
          clearRecurrenceRuleId: true,
          clearOccurrenceOriginalDate: true,
        ),
      );
      return;
    }

    final startDate = _combinedDueDateTime!;

    if (existingRuleId != null) {
      final existingRule = _loadedRecurrenceRule ??
          await repos.recurrenceRepository.getRule(existingRuleId);

      // Nothing to reconcile against - leave the task/rule as they are
      // rather than guessing.
      if (existingRule == null) return;

      final dueDateChanged = task.dueDate != startDate;
      final patternChanged = _recurrencePatternChanged(existingRule, draft);

      // Neither the Repeat pattern nor the due date actually changed in
      // this edit session (e.g. the user only changed the title or
      // priority) - don't touch the rule's startDate or clear a pending
      // one-off occurrence reschedule.
      if (!patternChanged && !dueDateChanged) return;

      await repos.recurrenceRepository.updateRule(
        existingRule.copyWith(
          frequency: draft.frequency,
          intervalValue: draft.intervalValue,
          daysOfWeek: draft.daysOfWeek,
          clearDaysOfWeek: draft.daysOfWeek == null,
          customUnit: draft.customUnit,
          clearCustomUnit: draft.customUnit == null,
          monthlyMode: draft.monthlyMode,
          weekOrdinal: draft.weekOrdinal,
          clearWeekOrdinal: draft.weekOrdinal == null,
          startDate: startDate,
          endDate: draft.endDate,
          clearEndDate: draft.endDate == null,
        ),
      );
      if (task.occurrenceOriginalDate != null || task.dueDate != startDate) {
        await repos.taskRepository.updateTask(
          task.copyWith(dueDate: startDate, clearOccurrenceOriginalDate: true),
        );
      }
      return;
    }

    final newRule = await repos.recurrenceRepository.createRule(
      frequency: draft.frequency,
      intervalValue: draft.intervalValue,
      daysOfWeek: draft.daysOfWeek,
      customUnit: draft.customUnit,
      monthlyMode: draft.monthlyMode,
      weekOrdinal: draft.weekOrdinal,
      startDate: startDate,
      endDate: draft.endDate,
    );
    await repos.taskRepository.updateTask(
      task.copyWith(recurrenceRuleId: newRule.id, dueDate: startDate),
    );
  }

  /// Whether [draft] describes a genuinely different recurrence pattern
  /// than [existingRule] (the rule as it was when this form was opened,
  /// captured in [_loadedRecurrenceRule]).
  ///
  /// Used by [_reconcileRecurrence] to avoid resetting a recurring
  /// series' anchor date, and clearing a pending one-off occurrence
  /// reschedule, just because the user saved an edit that had nothing to
  /// do with its Repeat settings or due date - see that method's doc
  /// comment for why this matters.
  bool _recurrencePatternChanged(
    RecurrenceRuleModel existingRule,
    RecurrenceDraft draft,
  ) {
    if (existingRule.frequency != draft.frequency) return true;
    if (existingRule.intervalValue != draft.intervalValue) return true;
    if (!_sameDaysOfWeek(existingRule.daysOfWeek, draft.daysOfWeek)) {
      return true;
    }
    if (existingRule.customUnit != draft.customUnit) return true;
    if (existingRule.monthlyMode != draft.monthlyMode) return true;
    if (existingRule.weekOrdinal != draft.weekOrdinal) return true;
    if (existingRule.endDate != draft.endDate) return true;
    return false;
  }

  /// Order-independent equality for the `daysOfWeek` recurrence field
  /// (weekly recurrence stores the selected weekdays in any order; a
  /// re-sorted-but-otherwise-identical list should not count as a
  /// pattern change).
  bool _sameDaysOfWeek(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    final sortedA = [...a]..sort();
    final sortedB = [...b]..sort();
    for (var i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar:
            AppBar(title: Text(widget.isEditing ? 'Edit task' : 'Add task')),
        body: const REmindLoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit task' : 'Add task'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              textInputAction: TextInputAction.next,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Title is required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TaskPriority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: TaskPriority.values
                  .map((p) => DropdownMenuItem(
                      value: p, child: Text(_priorityLabel(p))))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _priority = value ?? _priority),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('None')),
                ..._categories.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            if (widget.isEditing) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<TaskStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  helperText:
                      'Overdue and Snoozed are calculated automatically, not set here.',
                ),
                items: TaskStatus.values
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(_statusLabel(s))))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _status = value ?? _status),
              ),
            ],
            const SizedBox(height: 20),
            Text('Tags', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _tags)
                  FilterChip(
                    label: Text(tag.name),
                    selected: _selectedTagIds.contains(tag.id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selectedTagIds.add(tag.id!);
                      } else {
                        _selectedTagIds.remove(tag.id);
                      }
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('New tag'),
                  onPressed: _showAddTagDialog,
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Due date'),
              subtitle:
                  Text(_dueDate == null ? 'Not set' : formatDate(_dueDate!)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDueDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Due time'),
              subtitle: Text(
                  _dueTime == null ? 'Not set' : _dueTime!.format(context)),
              trailing: const Icon(Icons.access_time_outlined),
              enabled: _dueDate != null,
              onTap: _dueDate == null ? null : _pickDueTime,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat'),
              subtitle: Text(_dueDate == null
                  ? 'Set a due date first'
                  : (_recurrenceDraft == null
                      ? 'Does not repeat'
                      : recurrenceSummary(_recurrenceDraft!
                          .toPreviewRule(_combinedDueDateTime!)))),
              trailing: const Icon(Icons.repeat),
              enabled: _dueDate != null,
              onTap: _dueDate == null ? null : _openRecurrencePicker,
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remind me'),
              subtitle:
                  const Text('Sends a notification at the reminder time.'),
              value: _reminderEnabled,
              onChanged: (value) => setState(() {
                _reminderEnabled = value;
                if (value) {
                  _reminderDate ??= _dueDate ?? DateTime.now();
                  _reminderTime ??= _dueTime ?? _defaultReminderTime;
                }
              }),
            ),
            if (_reminderEnabled) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reminder date'),
                subtitle: Text(_reminderDate == null
                    ? 'Not set'
                    : formatDate(_reminderDate!)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickReminderDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reminder time'),
                subtitle: Text(_reminderTime == null
                    ? 'Not set'
                    : _reminderTime!.format(context)),
                trailing: const Icon(Icons.access_time_outlined),
                enabled: _reminderDate != null,
                onTap: _reminderDate == null ? null : _pickReminderTime,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save task'),
            ),
          ],
        ),
      ),
    );
  }

  String _priorityLabel(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
      case TaskPriority.urgent:
        return 'Urgent';
    }
  }

  String _statusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return 'Pending';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.cancelled:
        return 'Cancelled';
    }
  }
}
