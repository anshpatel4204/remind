import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remind/core/theme/theme_controller.dart';
import 'package:remind/data/datasources/settings_data_source.dart';
import 'package:remind/data/repositories/settings_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late SettingsRepository settingsRepository;

  setUp(() {
    testDb = TestAppDatabase.create();
    settingsRepository = SettingsRepository(SettingsDataSource(testDb.appDatabase));
  });

  tearDown(() => testDb.tearDown());

  test('starts at ThemeMode.system before load() runs', () {
    final controller = ThemeController(settingsRepository);
    expect(controller.mode, ThemeMode.system);
  });

  test('load() picks up a previously saved theme', () async {
    await settingsRepository.setValue('theme_mode', 'dark');

    final controller = ThemeController(settingsRepository);
    await controller.load();

    expect(controller.mode, ThemeMode.dark);
  });

  test('load() leaves the default when nothing was saved', () async {
    final controller = ThemeController(settingsRepository);
    await controller.load();

    expect(controller.mode, ThemeMode.system);
  });

  test('setMode() updates the in-memory mode immediately and persists it',
      () async {
    final controller = ThemeController(settingsRepository);

    await controller.setMode(ThemeMode.light);
    expect(controller.mode, ThemeMode.light);
    expect(await settingsRepository.getValue('theme_mode'), 'light');

    await controller.setMode(ThemeMode.dark);
    expect(controller.mode, ThemeMode.dark);
    expect(await settingsRepository.getValue('theme_mode'), 'dark');
  });

  test('setMode() notifies listeners exactly once per actual change',
      () async {
    final controller = ThemeController(settingsRepository);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setMode(ThemeMode.dark);
    expect(notifications, 1);

    // Setting the same mode again is a no-op - no redundant rebuild.
    await controller.setMode(ThemeMode.dark);
    expect(notifications, 1);

    await controller.setMode(ThemeMode.light);
    expect(notifications, 2);
  });

  test('a second controller sharing the same repository picks up a change '
      'made by the first after calling load() again', () async {
    final first = ThemeController(settingsRepository);
    final second = ThemeController(settingsRepository);

    await first.setMode(ThemeMode.dark);
    expect(second.mode, ThemeMode.system); // not yet reloaded

    await second.load();
    expect(second.mode, ThemeMode.dark);
  });
}
