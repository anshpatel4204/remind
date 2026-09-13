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
}
