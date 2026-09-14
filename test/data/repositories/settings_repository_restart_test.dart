import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:remind/data/database/app_database.dart';
import 'package:remind/data/datasources/settings_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/settings_repository.dart';

/// App-restart persistence (Part 13): unlike settings_repository_test.dart,
/// which gives every test a brand-new [AppDatabase] via
/// TestAppDatabase.create(), these tests deliberately reopen the *same*
/// on-disk database file with a second [AppDatabase]/[SettingsRepository]
/// pair after closing the first - simulating the app process actually
/// restarting, rather than just reusing an in-memory connection.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('remind_restart_test_');
    dbPath = p.join(tempDir.path, 'restart_test.db');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Best-effort only - see widget_test.dart's tearDown for why.
    }
  });

  test('profile and preferences survive closing and reopening the database',
      () async {
    final firstDb = AppDatabase(testDatabasePath: dbPath);
    final firstRepository =
        SettingsRepository(SettingsDataSource(firstDb));
    await firstRepository.setDisplayName('Ansh');
    await firstRepository.setOnboardingCompleted(true);
    await firstRepository.setTimeFormatPreference(TimeFormatPreference.h24);
    await firstRepository
        .setFirstDayOfWeekPreference(FirstDayOfWeekPreference.sunday);
    await firstRepository.setDefaultReminderTimeMinutes(420);
    await firstRepository.setTextScalePreference(TextScalePreference.large);
    await firstDb.close();

    // A fresh AppDatabase/SettingsRepository pointed at the exact same
    // file - nothing in memory is shared with the pair above, so this can
    // only pass if everything actually made it to disk.
    final secondDb = AppDatabase(testDatabasePath: dbPath);
    final secondRepository =
        SettingsRepository(SettingsDataSource(secondDb));

    expect(await secondRepository.getDisplayName(), 'Ansh');
    expect(await secondRepository.getOnboardingCompleted(), isTrue);
    expect(await secondRepository.getTimeFormatPreference(),
        TimeFormatPreference.h24);
    expect(await secondRepository.getFirstDayOfWeekPreference(),
        FirstDayOfWeekPreference.sunday);
    expect(await secondRepository.getDefaultReminderTimeMinutes(), 420);
    expect(await secondRepository.getTextScalePreference(),
        TextScalePreference.large);

    await secondDb.close();
  });
}
