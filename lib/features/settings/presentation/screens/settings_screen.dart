import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';

/// Placeholder Settings screen. Only the About entry is wired up (it shows
/// REmind's branding via [showAboutDialog]) — no other settings
/// functionality is implemented yet.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
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
      ),
    );
  }
}
