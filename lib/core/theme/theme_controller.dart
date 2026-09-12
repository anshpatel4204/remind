import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';

/// Persists and broadcasts the user's chosen [ThemeMode], backed by the
/// existing generic key/value [SettingsRepository] (no schema change
/// needed - that repository exists exactly for settings like this one).
///
/// Starts at [ThemeMode.system] and calls [load] once at app startup to
/// pick up any previously-saved choice; [setMode] both updates the app
/// immediately (via [notifyListeners]) and persists the new choice.
class ThemeController extends ChangeNotifier {
  ThemeController(this._settingsRepository);

  static const String _settingKey = 'theme_mode';

  final SettingsRepository _settingsRepository;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final stored = await _settingsRepository.getValue(_settingKey);
    final parsed = _parse(stored);
    if (parsed != null && parsed != _mode) {
      _mode = parsed;
      notifyListeners();
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _settingsRepository.setValue(_settingKey, _serialize(mode));
  }

  static ThemeMode? _parse(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  static String _serialize(ThemeMode mode) => mode.name;
}

/// Makes a shared [ThemeController] available to the widget tree via
/// [ThemeControllerScope.of], and rebuilds every dependent automatically
/// whenever it changes (an [InheritedNotifier] listens to the controller
/// itself, so callers never need their own [AnimatedBuilder]/[ListenableBuilder]).
class ThemeControllerScope extends InheritedNotifier<ThemeController> {
  const ThemeControllerScope({super.key, required ThemeController controller, required super.child})
      : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeControllerScope>();
    assert(scope != null, 'No ThemeControllerScope found in context');
    return scope!.notifier!;
  }
}
