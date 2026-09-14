import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/settings_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/settings_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late SettingsRepository repository;

  setUp(() {
    testDb = TestAppDatabase.create();
    repository = SettingsRepository(SettingsDataSource(testDb.appDatabase));
  });

  tearDown(() => testDb.tearDown());

  test('a fresh database has no settings', () async {
    expect(await repository.getAllSettings(), isEmpty);
  });

  test('set and get a setting value', () async {
    await repository.setValue('theme_mode', 'dark');
    expect(await repository.getValue('theme_mode'), 'dark');
  });

  test('setting a value again overwrites it (upsert)', () async {
    await repository.setValue('theme_mode', 'dark');
    await repository.setValue('theme_mode', 'light');

    final all = await repository.getAllSettings();
    expect(all['theme_mode'], 'light');
    expect(all, hasLength(1));
  });

  test('deleting a setting removes it', () async {
    await repository.setValue('theme_mode', 'dark');
    await repository.deleteSetting('theme_mode');
    expect(await repository.getValue('theme_mode'), isNull);
  });

  group('default task priority', () {
    test('defaults to null (no default chosen) on a fresh database', () async {
      expect(await repository.getDefaultTaskPriority(), isNull);
    });

    test('set and get round-trips the priority', () async {
      await repository.setDefaultTaskPriority(TaskPriority.high);
      expect(await repository.getDefaultTaskPriority(), TaskPriority.high);
    });

    test('can be cleared back to null', () async {
      await repository.setDefaultTaskPriority(TaskPriority.urgent);
      await repository.setDefaultTaskPriority(null);
      expect(await repository.getDefaultTaskPriority(), isNull);
    });

    test(
        'a corrupted stored value is treated as no default rather than crashing',
        () async {
      await repository.setValue('default_task_priority', 'not-a-number');
      expect(await repository.getDefaultTaskPriority(), isNull);

      await repository.setValue('default_task_priority', '999');
      expect(await repository.getDefaultTaskPriority(), isNull);
    });
  });

  group('default category', () {
    test('defaults to null (uncategorized) on a fresh database', () async {
      expect(await repository.getDefaultCategoryId(), isNull);
    });

    test('set and get round-trips the category id', () async {
      await repository.setDefaultCategoryId(42);
      expect(await repository.getDefaultCategoryId(), 42);
    });

    test('can be cleared back to null', () async {
      await repository.setDefaultCategoryId(42);
      await repository.setDefaultCategoryId(null);
      expect(await repository.getDefaultCategoryId(), isNull);
    });
  });

  // Part 13: local profile & preferences. Each of these is stored in the
  // same generic settings table as the fields above - no schema change,
  // by design (see SettingsRepository's Part 13 doc comment).

  group('display name (profile)', () {
    test('defaults to null (no name set) on a fresh database', () async {
      expect(await repository.getDisplayName(), isNull);
    });

    test('set and get round-trips the name', () async {
      await repository.setDisplayName('Ansh');
      expect(await repository.getDisplayName(), 'Ansh');
    });

    test('trims surrounding whitespace', () async {
      await repository.setDisplayName('  Ansh Patel  ');
      expect(await repository.getDisplayName(), 'Ansh Patel');
    });

    test('an empty or whitespace-only name is stored as null', () async {
      await repository.setDisplayName('Ansh');
      await repository.setDisplayName('   ');
      expect(await repository.getDisplayName(), isNull);
    });
  });

  group('onboarding completed', () {
    test('defaults to false on a fresh database', () async {
      expect(await repository.getOnboardingCompleted(), isFalse);
    });

    test('set and get round-trips true', () async {
      await repository.setOnboardingCompleted(true);
      expect(await repository.getOnboardingCompleted(), isTrue);
    });

    test('can be set back to false', () async {
      await repository.setOnboardingCompleted(true);
      await repository.setOnboardingCompleted(false);
      expect(await repository.getOnboardingCompleted(), isFalse);
    });
  });

  group('time format preference', () {
    test('defaults to system on a fresh database', () async {
      expect(await repository.getTimeFormatPreference(),
          TimeFormatPreference.system);
    });

    test('set and get round-trips 12-hour and 24-hour', () async {
      await repository.setTimeFormatPreference(TimeFormatPreference.h12);
      expect(
          await repository.getTimeFormatPreference(), TimeFormatPreference.h12);

      await repository.setTimeFormatPreference(TimeFormatPreference.h24);
      expect(
          await repository.getTimeFormatPreference(), TimeFormatPreference.h24);
    });

    test('a corrupted stored value falls back to system rather than crashing',
        () async {
      await repository.setValue('time_format_preference', 'not-a-real-value');
      expect(await repository.getTimeFormatPreference(),
          TimeFormatPreference.system);
    });
  });

  group('first day of week preference', () {
    test('defaults to system on a fresh database', () async {
      expect(await repository.getFirstDayOfWeekPreference(),
          FirstDayOfWeekPreference.system);
    });

    test('set and get round-trips Monday and Sunday', () async {
      await repository
          .setFirstDayOfWeekPreference(FirstDayOfWeekPreference.sunday);
      expect(await repository.getFirstDayOfWeekPreference(),
          FirstDayOfWeekPreference.sunday);

      await repository
          .setFirstDayOfWeekPreference(FirstDayOfWeekPreference.monday);
      expect(await repository.getFirstDayOfWeekPreference(),
          FirstDayOfWeekPreference.monday);
    });

    test('a corrupted stored value falls back to system rather than crashing',
        () async {
      await repository.setValue('first_day_of_week_preference', 'bogus');
      expect(await repository.getFirstDayOfWeekPreference(),
          FirstDayOfWeekPreference.system);
    });
  });

  group('default reminder time minutes', () {
    test('defaults to 540 (9:00 AM) on a fresh database', () async {
      expect(await repository.getDefaultReminderTimeMinutes(), 540);
    });

    test('set and get round-trips a value', () async {
      await repository.setDefaultReminderTimeMinutes(6 * 60 + 30); // 6:30 AM
      expect(await repository.getDefaultReminderTimeMinutes(), 6 * 60 + 30);
    });

    test('an out-of-range or non-numeric stored value falls back to 540',
        () async {
      await repository.setValue('default_reminder_time_minutes', 'not-a-number');
      expect(await repository.getDefaultReminderTimeMinutes(), 540);

      await repository.setValue('default_reminder_time_minutes', '1440');
      expect(await repository.getDefaultReminderTimeMinutes(), 540);

      await repository.setValue('default_reminder_time_minutes', '-1');
      expect(await repository.getDefaultReminderTimeMinutes(), 540);
    });
  });

  group('text scale preference', () {
    test('defaults to standard on a fresh database', () async {
      expect(
          await repository.getTextScalePreference(), TextScalePreference.standard);
    });

    test('set and get round-trips every value', () async {
      for (final value in TextScalePreference.values) {
        await repository.setTextScalePreference(value);
        expect(await repository.getTextScalePreference(), value);
      }
    });

    test('a corrupted stored value falls back to standard rather than crashing',
        () async {
      await repository.setValue('text_scale_preference', 'huge');
      expect(
          await repository.getTextScalePreference(), TextScalePreference.standard);
    });
  });

  test(
      'Part 13 keys coexist with a pre-existing setting like theme_mode '
      '(migration compatibility: no schema change, same settings table)',
      () async {
    // Simulates a database that already has settings saved from before
    // Part 13 existed.
    await repository.setValue('theme_mode', 'dark');

    await repository.setDisplayName('Ansh');
    await repository.setOnboardingCompleted(true);
    await repository.setTimeFormatPreference(TimeFormatPreference.h24);
    await repository
        .setFirstDayOfWeekPreference(FirstDayOfWeekPreference.sunday);
    await repository.setDefaultReminderTimeMinutes(480);
    await repository.setTextScalePreference(TextScalePreference.large);

    // The old key is untouched by any of the new ones being written...
    expect(await repository.getValue('theme_mode'), 'dark');
    // ...and every new key round-trips correctly alongside it.
    expect(await repository.getDisplayName(), 'Ansh');
    expect(await repository.getOnboardingCompleted(), isTrue);
    expect(
        await repository.getTimeFormatPreference(), TimeFormatPreference.h24);
    expect(await repository.getFirstDayOfWeekPreference(),
        FirstDayOfWeekPreference.sunday);
    expect(await repository.getDefaultReminderTimeMinutes(), 480);
    expect(
        await repository.getTextScalePreference(), TextScalePreference.large);

    final all = await repository.getAllSettings();
    expect(all, hasLength(7));
  });
}
