import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../data/backup/backup_constants.dart';
import '../../../../data/backup/backup_data.dart';
import '../../../../data/backup/backup_exception.dart';
import '../../../../data/database/db_constants.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../presentation/widgets/main_shell.dart';
import '../../../../presentation/widgets/remind_section_header.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../../../../services/backup/backup_file_service.dart';
import '../../../../services/notification/notification_scheduler.dart';

/// The Settings tab: appearance (theme mode), notification preferences,
/// task defaults, backup/restore, data info, and the About entry.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Map<SnoozeOption, String> _snoozeLabel = {
    SnoozeOption.fiveMinutes: '5 minutes',
    SnoozeOption.tenMinutes: '10 minutes',
    SnoozeOption.fifteenMinutes: '15 minutes',
    SnoozeOption.thirtyMinutes: '30 minutes',
    SnoozeOption.oneHour: '1 hour',
  };

  // Loaded state is kept directly in a nullable field, rather than a
  // Future handed to a FutureBuilder, so that toggling a switch or
  // picking an option doesn't flash a loading spinner over the whole
  // section while it reloads - only the very first load does that.
  _SettingsData? _data;
  bool _initialized = false;
  final _backupFileService = BackupFileService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _reload();
    }
  }

  Future<_SettingsData> _load() async {
    final repos = RepositoryScope.of(context);
    final scheduler = repos.notificationScheduler;
    final notificationsEnabled = await scheduler.notificationsEnabled();
    final exactAlarmsAllowed = await scheduler.canScheduleExactAlarms();
    final masterEnabled = await scheduler.notificationsMasterEnabled();
    final soundEnabled = await scheduler.soundEnabled();
    final vibrationEnabled = await scheduler.vibrationEnabled();
    final defaultSnooze = await scheduler.defaultSnoozeOption();
    final defaultPriority = await repos.settingsRepository.getDefaultTaskPriority();
    final defaultCategoryId = await repos.settingsRepository.getDefaultCategoryId();
    final categories = await repos.categoryRepository.getAllCategories();
    return _SettingsData(
      notificationsEnabled: notificationsEnabled,
      exactAlarmsAllowed: exactAlarmsAllowed,
      masterEnabled: masterEnabled,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
      defaultSnooze: defaultSnooze,
      defaultPriority: defaultPriority ?? TaskPriority.medium,
      defaultCategoryId: defaultCategoryId,
      categories: categories,
    );
  }

  /// Runs [_load] and applies the result, so a caller that just persisted
  /// a change (a toggle, a picker choice) can `await` this and know the
  /// on-screen state reflects it - not just that a rebuild was scheduled.
  Future<void> _reload() async {
    final data = await _load();
    if (!mounted) return;
    setState(() {
      _data = data;
    });
  }

  Future<void> _requestPermission() async {
    await RepositoryScope.of(context).notificationScheduler.ensureNotificationPermission();
    if (!mounted) return;
    await _reload();
  }

  /// Exports the whole database to a new local JSON file (Part 10
  /// "Backup"). The repository layer builds the JSON; this screen's only
  /// job is turning that string into a file and telling the user it's
  /// done.
  Future<void> _createBackup() async {
    final repos = RepositoryScope.of(context);
    try {
      final json = await repos.backupRepository.exportToJson();
      final file = await _backupFileService.writeBackup(json);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup saved as ${p.basename(file.path)}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create a backup.')),
      );
    }
  }

  /// Lists the backups already on disk and lets the user pick one to
  /// restore (Part 10 "Restore"). There's no dependency on a file-picker
  /// package here on purpose: every backup this app can restore was made
  /// by this app, in its own backups folder, so listing that folder is
  /// simpler and just as capable.
  Future<void> _showRestoreList() async {
    final List<BackupFileInfo> backups;
    try {
      backups = await _backupFileService.listBackups();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read your backups.')),
      );
      return;
    }

    if (!mounted) return;
    if (backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No backups yet - create one first.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<BackupFileInfo>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Select a backup to restore', style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final backup in backups)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(backup.name),
                  subtitle: Text(DateFormat.yMMMd().add_jm().format(backup.modifiedAt)),
                  onTap: () => Navigator.of(context).pop(backup),
                ),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    await _restoreFrom(selected);
  }

  /// Reads, validates, confirms, and restores [backup] - in that order.
  /// Nothing destructive happens until the user has seen exactly what's
  /// in the file and explicitly confirmed, and a safety backup of what's
  /// about to be overwritten is written right before it is.
  Future<void> _restoreFrom(BackupFileInfo backup) async {
    final repos = RepositoryScope.of(context);

    final BackupData data;
    try {
      final jsonContent = await _backupFileService.readBackup(backup.file);
      data = repos.backupRepository.parseAndValidate(jsonContent);
    } on BackupValidationException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot restore this backup'),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that backup file.')),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all data?'),
        content: Text(
          'This backup was made on ${DateFormat.yMMMd().add_jm().format(data.exportedAt)} and '
          'contains ${data.tasks.length} task(s), ${data.categories.length} categor${data.categories.length == 1 ? 'y' : 'ies'}, '
          'and ${data.tags.length} tag(s).\n\n'
          'Restoring it will permanently replace everything currently in REmind. '
          'A safety backup of your current data will be made first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final safetyJson = await repos.backupRepository.exportToJson();
      await _backupFileService.writeSafetyBackup(safetyJson);
      await repos.backupRepository.restore(data);
      await repos.notificationScheduler.reconcileAfterStartup();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore failed. Your data has not been changed.')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Restore complete'),
        content: const Text('Your data has been restored.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );

    if (!mounted) return;
    // Every screen's already-loaded state (Statistics' cached future, the
    // task list, etc.) still reflects the pre-restore data - rebuilding
    // the whole shell from scratch is the simplest way to guarantee every
    // screen re-reads the now-restored database instead of showing stale
    // in-memory state.
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  /// Opens a bottom sheet listing [options], with whichever one matches
  /// [selected] pre-checked, and runs [onSelected] (expected to persist
  /// the new value and reload this screen's state) when the user taps a
  /// different one.
  ///
  /// A callback is used here instead of relying on the sheet's return
  /// value on purpose: the Default category picker has a legitimate
  /// "None" choice, whose business value is `null` - the same value a
  /// dismissed-without-choosing sheet would otherwise return, which would
  /// make the two indistinguishable.
  Future<void> _showPicker<T>({
    required String title,
    required List<({T value, String label})> options,
    required T selected,
    required void Function(T value) onSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
              RadioGroup<T>(
                groupValue: selected,
                onChanged: (value) {
                  Navigator.of(context).pop();
                  // RadioGroup's callback type is always nullable (T
                  // flattens to itself when T is already nullable, as it
                  // is for the Default category picker's `int?`), but a
                  // tap always carries the tapped tile's own value, so
                  // this narrows straight back to T rather than meaning
                  // "nothing selected". That includes a literal `null`
                  // for the Default category picker's "None" option -
                  // this must NOT be treated as "no selection".
                  final chosen = value as T;
                  if (chosen == selected) return;
                  onSelected(chosen);
                },
                child: Column(
                  children: [
                    for (final option in options)
                      RadioListTile<T>(title: Text(option.label), value: option.value),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeControllerScope.of(context);
    final repos = RepositoryScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) {
          final data = _data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: REmindSectionHeader(title: 'Appearance', icon: Icons.palette_outlined),
              ),
              RadioGroup<ThemeMode>(
                groupValue: themeController.mode,
                onChanged: (mode) => mode == null ? null : themeController.setMode(mode),
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text('System default'),
                      value: ThemeMode.system,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Light'),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Dark'),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: REmindSectionHeader(title: 'Notifications', icon: Icons.notifications_outlined),
              ),
              ListTile(
                leading: Icon(
                  data.notificationsEnabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: data.notificationsEnabled ? AppColors.success : Theme.of(context).colorScheme.error,
                ),
                title: const Text('Notifications'),
                subtitle: Text(data.notificationsEnabled ? 'Allowed' : 'Not allowed'),
                trailing: data.notificationsEnabled
                    ? null
                    : TextButton(
                        onPressed: _requestPermission,
                        child: const Text('Allow'),
                      ),
              ),
              ListTile(
                leading: Icon(
                  data.exactAlarmsAllowed ? Icons.alarm_on_outlined : Icons.alarm_off_outlined,
                  color: data.exactAlarmsAllowed ? AppColors.success : Theme.of(context).colorScheme.error,
                ),
                title: const Text('Exact reminder timing'),
                subtitle: Text(
                  data.exactAlarmsAllowed
                      ? 'Reminders will fire at the precise time'
                      : 'Reminders may fire a little late (exact alarms are off '
                          'in system settings)',
                ),
              ),
              if (!data.notificationsEnabled || !data.exactAlarmsAllowed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'To fix this from your device, open Settings > Apps > REmind > '
                    'Notifications (and Alarms & reminders, for exact timing).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              SwitchListTile(
                title: const Text('Enable notifications'),
                subtitle: const Text('Turn off to stop all reminder notifications from REmind'),
                value: data.masterEnabled,
                onChanged: (value) async {
                  await repos.notificationScheduler.setNotificationsMasterEnabled(value);
                  await _reload();
                },
              ),
              SwitchListTile(
                title: const Text('Sound'),
                subtitle: const Text('Play a sound with reminder notifications'),
                value: data.soundEnabled,
                onChanged: !data.masterEnabled
                    ? null
                    : (value) async {
                        await repos.notificationScheduler.setSoundEnabled(value);
                        await _reload();
                      },
              ),
              SwitchListTile(
                title: const Text('Vibration'),
                subtitle: const Text('Vibrate with reminder notifications'),
                value: data.vibrationEnabled,
                onChanged: !data.masterEnabled
                    ? null
                    : (value) async {
                        await repos.notificationScheduler.setVibrationEnabled(value);
                        await _reload();
                      },
              ),
              ListTile(
                leading: const Icon(Icons.snooze_outlined),
                title: const Text('Default snooze duration'),
                subtitle: Text(_snoozeLabel[data.defaultSnooze] ?? '10 minutes'),
                onTap: () => _showPicker<SnoozeOption>(
                  title: 'Default snooze duration',
                  options: [
                    for (final option in NotificationScheduler.defaultableSnoozeOptions)
                      (value: option, label: _snoozeLabel[option]!),
                  ],
                  selected: data.defaultSnooze,
                  onSelected: (value) async {
                    await repos.notificationScheduler.setDefaultSnoozeOption(value);
                    await _reload();
                  },
                ),
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: REmindSectionHeader(title: 'Tasks', icon: Icons.checklist_outlined),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Default priority'),
                subtitle: Text(AppColors.priorityLabel[data.defaultPriority] ?? 'Medium'),
                onTap: () => _showPicker<TaskPriority>(
                  title: 'Default priority',
                  options: [
                    for (final priority in TaskPriority.values)
                      (value: priority, label: AppColors.priorityLabel[priority]!),
                  ],
                  selected: data.defaultPriority,
                  onSelected: (value) async {
                    await repos.settingsRepository.setDefaultTaskPriority(value);
                    await _reload();
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Default category'),
                subtitle: Text(_categoryLabel(data.categories, data.defaultCategoryId)),
                onTap: () => _showPicker<int?>(
                  title: 'Default category',
                  options: [
                    (value: null, label: 'None'),
                    for (final category in data.categories)
                      (value: category.id, label: category.name),
                  ],
                  selected: data.defaultCategoryId,
                  onSelected: (value) async {
                    await repos.settingsRepository.setDefaultCategoryId(value);
                    await _reload();
                  },
                ),
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: REmindSectionHeader(title: 'Backup', icon: Icons.backup_outlined),
              ),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Create backup'),
                subtitle: const Text('Save all your tasks, reminders, and settings to a local file'),
                onTap: _createBackup,
              ),
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Restore from backup'),
                subtitle: const Text('Replace all current data with a previous backup'),
                onTap: _showRestoreList,
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: REmindSectionHeader(title: 'Data', icon: Icons.storage_outlined),
              ),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('App version'),
                subtitle: Text(AppConstants.appVersion),
              ),
              const ListTile(
                leading: Icon(Icons.dns_outlined),
                title: Text('Database schema version'),
                subtitle: Text('${DbConfig.databaseVersion}'),
              ),
              const ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('Backup format version'),
                subtitle: Text('$kBackupSchemaVersion'),
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: REmindSectionHeader(title: 'About', icon: Icons.info_outline),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About REmind'),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: AppConstants.appVersion,
                  applicationIcon: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      AppConstants.brandLogoAsset,
                      width: 48,
                      height: 48,
                    ),
                  ),
                  children: const [
                    SizedBox(height: 8),
                    Text(AppConstants.appTagline),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _categoryLabel(List<CategoryModel> categories, int? categoryId) {
    if (categoryId == null) return 'None';
    for (final category in categories) {
      if (category.id == categoryId) return category.name;
    }
    return 'None';
  }
}

class _SettingsData {
  const _SettingsData({
    required this.notificationsEnabled,
    required this.exactAlarmsAllowed,
    required this.masterEnabled,
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.defaultSnooze,
    required this.defaultPriority,
    required this.defaultCategoryId,
    required this.categories,
  });

  final bool notificationsEnabled;
  final bool exactAlarmsAllowed;
  final bool masterEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final SnoozeOption defaultSnooze;
  final TaskPriority defaultPriority;
  final int? defaultCategoryId;
  final List<CategoryModel> categories;
}
