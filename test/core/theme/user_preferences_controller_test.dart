import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remind/core/theme/user_preferences_controller.dart';
import 'package:remind/data/datasources/settings_data_source.dart';
import 'package:remind/data/models/enums.dart';
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

  test('starts at safe defaults before load() runs', () {
    final controller = UserPreferencesController(settingsRepository);
    expect(controller.displayName, isNull);
    expect(controller.timeFormat, TimeFormatPreference.system);
    expect(controller.firstDayOfWeek, FirstDayOfWeekPreference.system);
    expect(controller.textScale, TextScalePreference.standard);
  });

  test('load() picks up previously saved values', () async {
    await settingsRepository.setDisplayName('Ansh');
    await settingsRepository.setTimeFormatPreference(TimeFormatPreference.h24);
    await settingsRepository
        .setFirstDayOfWeekPreference(FirstDayOfWeekPreference.sunday);
    await settingsRepository.setTextScalePreference(TextScalePreference.large);

    final controller = UserPreferencesController(settingsRepository);
    await controller.load();

    expect(controller.displayName, 'Ansh');
    expect(controller.timeFormat, TimeFormatPreference.h24);
    expect(controller.firstDayOfWeek, FirstDayOfWeekPreference.sunday);
    expect(controller.textScale, TextScalePreference.large);
  });

  test('each setter updates in-memory state immediately and persists it',
      () async {
    final controller = UserPreferencesController(settingsRepository);

    await controller.setDisplayName('Ansh Patel');
    expect(controller.displayName, 'Ansh Patel');
    expect(await settingsRepository.getDisplayName(), 'Ansh Patel');

    await controller.setTimeFormat(TimeFormatPreference.h12);
    expect(controller.timeFormat, TimeFormatPreference.h12);
    expect(await settingsRepository.getTimeFormatPreference(),
        TimeFormatPreference.h12);

    await controller.setFirstDayOfWeek(FirstDayOfWeekPreference.monday);
    expect(controller.firstDayOfWeek, FirstDayOfWeekPreference.monday);
    expect(await settingsRepository.getFirstDayOfWeekPreference(),
        FirstDayOfWeekPreference.monday);

    await controller.setTextScale(TextScalePreference.small);
    expect(controller.textScale, TextScalePreference.small);
    expect(await settingsRepository.getTextScalePreference(),
        TextScalePreference.small);
  });

  test('setDisplayName trims and treats blank input as clearing the name',
      () async {
    final controller = UserPreferencesController(settingsRepository);

    await controller.setDisplayName('  Ansh  ');
    expect(controller.displayName, 'Ansh');

    await controller.setDisplayName('   ');
    expect(controller.displayName, isNull);
    expect(await settingsRepository.getDisplayName(), isNull);
  });

  test('setters notify listeners exactly once per actual change', () async {
    final controller = UserPreferencesController(settingsRepository);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setTimeFormat(TimeFormatPreference.h24);
    expect(notifications, 1);

    // Setting the same value again is a no-op.
    await controller.setTimeFormat(TimeFormatPreference.h24);
    expect(notifications, 1);

    await controller.setTextScale(TextScalePreference.extraLarge);
    expect(notifications, 2);
  });

  group('resolveFirstDayOfWeek (pure)', () {
    test('sunday resolves to DateTime.sunday', () async {
      final controller = UserPreferencesController(settingsRepository);
      await controller.setFirstDayOfWeek(FirstDayOfWeekPreference.sunday);
      expect(controller.resolveFirstDayOfWeek(), DateTime.sunday);
    });

    test('monday resolves to DateTime.monday', () async {
      final controller = UserPreferencesController(settingsRepository);
      await controller.setFirstDayOfWeek(FirstDayOfWeekPreference.monday);
      expect(controller.resolveFirstDayOfWeek(), DateTime.monday);
    });

    test('system currently resolves to DateTime.monday (no per-locale '
        'first-day table yet)', () {
      final controller = UserPreferencesController(settingsRepository);
      expect(controller.resolveFirstDayOfWeek(), DateTime.monday);
    });
  });

  group('resolveUse24Hour (needs a BuildContext for the "system" case)', () {
    testWidgets('h12 always resolves to false, h24 always resolves to true, '
        'regardless of the device MediaQuery', (tester) async {
      final controller = UserPreferencesController(settingsRepository);
      late BuildContext capturedContext;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          capturedContext = context;
          return const SizedBox();
        }),
      ));

      await controller.setTimeFormat(TimeFormatPreference.h12);
      expect(controller.resolveUse24Hour(capturedContext), isFalse);

      await controller.setTimeFormat(TimeFormatPreference.h24);
      expect(controller.resolveUse24Hour(capturedContext), isTrue);
    });

    testWidgets(
        'system defers to MediaQuery.alwaysUse24HourFormat', (tester) async {
      final controller = UserPreferencesController(settingsRepository);
      late BuildContext capturedContext;

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(alwaysUse24HourFormat: true),
        child: MaterialApp(
          home: Builder(builder: (context) {
            capturedContext = context;
            return const SizedBox();
          }),
        ),
      ));

      expect(controller.timeFormat, TimeFormatPreference.system);
      expect(controller.resolveUse24Hour(capturedContext), isTrue);
    });
  });
}
