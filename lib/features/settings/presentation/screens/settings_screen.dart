import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../data/backup/backup_data.dart';
import '../../../../data/backup/backup_exception.dart';
import '../../../../presentation/widgets/main_shell.dart';
import '../../../../presentation/widgets/remind_section_header.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../../../../services/backup/backup_file_service.dart';

/// The Settings tab: appearance (theme mode), a read-only notification
/// status panel, and the About entry.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<_NotificationStatus> _statusFuture;
  bool _initialized = false;
  final _backupFileService = BackupFileService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _statusFuture = _loadStatus();
    }
  }

  Future<_NotificationStatus> _loadStatus() async {
    final scheduler = RepositoryScope.of(context).notificationScheduler;
    final enabled = await scheduler.notificationsEnabled();
    final exact = await scheduler.canScheduleExactAlarms();
    return _NotificationStatus(notificationsEnabled: enabled, exactAlarmsAllowed: exact);
  }

  Future<void> _requestPermission() async {
    await RepositoryScope.of(context).notificationScheduler.ensureNotificationPermission();
    if (!mounted) return;
    setState(() {
      _statusFuture = _loadStatus();
    });
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
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Select a backup to restore', style: TextStyle(fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeControllerScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) {
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
              FutureBuilder<_NotificationStatus>(
                future: _statusFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return const ListTile(
                      leading: Icon(Icons.error_outline),
                      title: Text('Could not check notification status'),
                    );
                  }
                  final status = snapshot.data!;
                  return Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          status.notificationsEnabled
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_off_outlined,
                          color: status.notificationsEnabled
                              ? Colors.green
                              : Theme.of(context).colorScheme.error,
                        ),
                        title: const Text('Notifications'),
                        subtitle: Text(status.notificationsEnabled ? 'Allowed' : 'Not allowed'),
                        trailing: status.notificationsEnabled
                            ? null
                            : TextButton(
                                onPressed: _requestPermission,
                                child: const Text('Allow'),
                              ),
                      ),
                      ListTile(
                        leading: Icon(
                          status.exactAlarmsAllowed ? Icons.alarm_on_outlined : Icons.alarm_off_outlined,
                          color: status.exactAlarmsAllowed
                              ? Colors.green
                              : Theme.of(context).colorScheme.error,
                        ),
                        title: const Text('Exact reminder timing'),
                        subtitle: Text(
                          status.exactAlarmsAllowed
                              ? 'Reminders will fire at the precise time'
                              : 'Reminders may fire a little late (exact alarms are off '
                                  'in system settings)',
                        ),
                      ),
                      if (!status.notificationsEnabled || !status.exactAlarmsAllowed)
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
                    ],
                  );
                },
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: REmindSectionHeader(title: 'Data', icon: Icons.storage_outlined),
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
                child: REmindSectionHeader(title: 'About', icon: Icons.info_outline),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About REmind'),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: '0.1.0',
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
}

class _NotificationStatus {
  const _NotificationStatus({required this.notificationsEnabled, required this.exactAlarmsAllowed});

  final bool notificationsEnabled;
  final bool exactAlarmsAllowed;
}

