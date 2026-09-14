import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import '../../data/repositories/settings_repository.dart';

/// Persists and broadcasts the user's local profile (display name) and
/// cross-cutting display preferences (time format, first day of week,
/// text scale), backed by the existing generic key/value
/// [SettingsRepository] - exactly the same pattern [ThemeController] (see
/// `theme_controller.dart`) already established for theme mode, kept as a
/// separate controller rather than folded into that one so a screen that
/// only cares about theme doesn't rebuild every time the display name
/// changes, and vice versa.
///
/// Starts at safe defaults (no name, every preference "system"/"standard")
/// and calls [load] once at app startup to pick up anything previously
/// saved - see [RemindApp]'s `initState` for where that happens, right
/// next to `ThemeController.load()`.
class UserPreferencesController extends ChangeNotifier {
  UserPreferencesController(this._settingsRepository);

  final SettingsRepository _settingsRepository;

  String? _displayName;
  TimeFormatPreference _timeFormat = TimeFormatPreference.system;
  FirstDayOfWeekPreference _firstDayOfWeek = FirstDayOfWeekPreference.system;
  TextScalePreference _textScale = TextScalePreference.standard;

  String? get displayName => _displayName;
  TimeFormatPreference get timeFormat => _timeFormat;
  FirstDayOfWeekPreference get firstDayOfWeek => _firstDayOfWeek;
  TextScalePreference get textScale => _textScale;

  Future<void> load() async {
    final name = await _settingsRepository.getDisplayName();
    final timeFormat = await _settingsRepository.getTimeFormatPreference();
    final firstDayOfWeek =
        await _settingsRepository.getFirstDayOfWeekPreference();
    final textScale = await _settingsRepository.getTextScalePreference();

    if (name == _displayName &&
        timeFormat == _timeFormat &&
        firstDayOfWeek == _firstDayOfWeek &&
        textScale == _textScale) {
      return;
    }
    _displayName = name;
    _timeFormat = timeFormat;
    _firstDayOfWeek = firstDayOfWeek;
    _textScale = textScale;
    notifyListeners();
  }

  Future<void> setDisplayName(String? name) async {
    final trimmed = name?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (normalized == _displayName) return;
    _displayName = normalized;
    notifyListeners();
    await _settingsRepository.setDisplayName(normalized);
  }

  Future<void> setTimeFormat(TimeFormatPreference preference) async {
    if (preference == _timeFormat) return;
    _timeFormat = preference;
    notifyListeners();
    await _settingsRepository.setTimeFormatPreference(preference);
  }

  Future<void> setFirstDayOfWeek(FirstDayOfWeekPreference preference) async {
    if (preference == _firstDayOfWeek) return;
    _firstDayOfWeek = preference;
    notifyListeners();
    await _settingsRepository.setFirstDayOfWeekPreference(preference);
  }

  Future<void> setTextScale(TextScalePreference preference) async {
    if (preference == _textScale) return;
    _textScale = preference;
    notifyListeners();
    await _settingsRepository.setTextScalePreference(preference);
  }

  /// Resolves [timeFormat] against the device's own 24-hour setting when
  /// the preference is [TimeFormatPreference.system], so every
  /// `formatTime`/`formatDateTime` call site has one place to ask "should
  /// this be 24-hour?" instead of repeating the same three-way switch.
  bool resolveUse24Hour(BuildContext context) {
    switch (_timeFormat) {
      case TimeFormatPreference.h24:
        return true;
      case TimeFormatPreference.h12:
        return false;
      case TimeFormatPreference.system:
        return MediaQuery.of(context).alwaysUse24HourFormat;
    }
  }

  /// The actual weekday [DateTime.monday]-[DateTime.sunday] REmind's
  /// Calendar week view should start on. "System" currently always
  /// resolves to Monday (see [FirstDayOfWeekPreference.system]'s doc
  /// comment) - REmind doesn't have a per-locale first-day table, so this
  /// is the one place that decision is made, rather than duplicating a
  /// fallback in every caller.
  int resolveFirstDayOfWeek() {
    switch (_firstDayOfWeek) {
      case FirstDayOfWeekPreference.sunday:
        return DateTime.sunday;
      case FirstDayOfWeekPreference.monday:
      case FirstDayOfWeekPreference.system:
        return DateTime.monday;
    }
  }
}

/// Makes a shared [UserPreferencesController] available to the widget
/// tree via [UserPreferencesScope.of], rebuilding every dependent
/// automatically when it changes - the same [InheritedNotifier] pattern
/// [ThemeControllerScope] uses.
class UserPreferencesScope extends InheritedNotifier<UserPreferencesController> {
  const UserPreferencesScope(
      {super.key,
      required UserPreferencesController controller,
      required super.child})
      : super(notifier: controller);

  static UserPreferencesController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<UserPreferencesScope>();
    assert(scope != null, 'No UserPreferencesScope found in context');
    return scope!.notifier!;
  }
}
