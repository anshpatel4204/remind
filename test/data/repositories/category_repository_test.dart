import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/category_data_source.dart';
import 'package:remind/data/repositories/category_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late CategoryRepository repository;

  setUp(() {
    testDb = TestAppDatabase.create();
    repository = CategoryRepository(CategoryDataSource(testDb.appDatabase));
  });

  tearDown(() => testDb.tearDown());

  test('a fresh database already has the 7 default categories', () async {
    final categories = await repository.getAllCategories();
    expect(categories, hasLength(7));
    expect(categories.every((c) => c.isDefault), isTrue);
  });

  test('create, read, update, and delete a custom category', () async {
    final created = await repository.createCategory(name: 'Fitness', color: '#00FF00');
    expect(created.id, isNotNull);
    expect(created.isDefault, isFalse);

    final fetched = await repository.getCategory(created.id!);
    expect(fetched?.name, 'Fitness');

    await repository.updateCategory(fetched!.copyWith(name: 'Fitness & Health'));
    final updated = await repository.getCategory(created.id!);
    expect(updated?.name, 'Fitness & Health');

    await repository.deleteCategory(created.id!);
    expect(await repository.getCategory(created.id!), isNull);
  });

  test('default categories cannot be deleted', () async {
    final categories = await repository.getAllCategories();
    final work = categories.firstWhere((c) => c.name == 'Work');

    expect(() => repository.deleteCategory(work.id!), throwsStateError);

    final stillThere = await repository.getCategory(work.id!);
    expect(stillThere, isNotNull);
  });
}
