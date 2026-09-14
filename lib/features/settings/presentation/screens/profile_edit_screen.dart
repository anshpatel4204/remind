import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/user_preferences_controller.dart';
import '../../../../core/utils/avatar_utils.dart';

/// Lets the user set or change their optional local display name, with a
/// live preview of the generated-initials avatar it produces (see
/// `avatar_utils.dart`'s doc comment for why REmind doesn't offer a real
/// photo picker in V1: no `image_picker` dependency/native permission is
/// introduced just for a profile picture, and a name-derived avatar needs
/// nowhere to store image bytes at all).
///
/// Reached from Settings > Profile. Saves directly to the app's shared
/// [UserPreferencesController] (via [UserPreferencesScope]) on Save, so
/// every other screen showing the name/avatar - the About dialog, a
/// future onboarding re-visit - updates immediately, with no separate
/// reload step.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _nameController = TextEditingController();
  bool _loadedInitialName = false;

  @override
  void initState() {
    super.initState();
    // Repaints the avatar preview as the user types, without waiting for
    // Save - purely local UI state, nothing is persisted until Save.
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // UserPreferencesScope.of(context) depends on an InheritedWidget, so
    // it can only be read here (or later), never from initState - and
    // guarded to run once, so it never clobbers text the user already
    // typed if a dependency changes again later.
    if (!_loadedInitialName) {
      _loadedInitialName = true;
      _nameController.text = UserPreferencesScope.of(context).displayName ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await UserPreferencesScope.of(context).setDisplayName(_nameController.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: [
          Center(
            child: InitialsAvatar(name: _nameController.text, radius: 48),
          ),
          const SizedBox(height: AppSpacing.xxl),
          TextField(
            controller: _nameController,
            key: const Key('profileNameField'),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your name is stored only on this device and is never required. '
            'REmind generates your avatar from your initials - no photo is '
            'uploaded or stored.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
