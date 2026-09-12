import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/settings_data_source.dart';
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
}
