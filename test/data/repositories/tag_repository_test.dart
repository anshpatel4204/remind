import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/tag_data_source.dart';
import 'package:remind/data/datasources/task_tag_data_source.dart';
import 'package:remind/data/repositories/tag_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late TagRepository repository;

  setUp(() {
    testDb = TestAppDatabase.create();
    repository = TagRepository(
      TagDataSource(testDb.appDatabase),
      TaskTagDataSource(testDb.appDatabase),
    );
  });

  tearDown(() => testDb.tearDown());

  test('a fresh database has no tags', () async {
    expect(await repository.getAllTags(), isEmpty);
  });

  test('create, read, update, and delete a tag', () async {
    final created = await repository.createTag(name: 'urgent', color: '#FF0000');
    expect(created.id, isNotNull);

    final fetched = await repository.getTag(created.id!);
    expect(fetched?.name, 'urgent');

    await repository.updateTag(fetched!.copyWith(name: 'very-urgent'));
    final updated = await repository.getTag(created.id!);
    expect(updated?.name, 'very-urgent');

    await repository.deleteTag(created.id!);
    expect(await repository.getTag(created.id!), isNull);
  });
}
