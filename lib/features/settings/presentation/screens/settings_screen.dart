import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../presentation/widgets/remind_section_header.dart';
import '../../../../presentation/widgets/repository_scope.dart';

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

