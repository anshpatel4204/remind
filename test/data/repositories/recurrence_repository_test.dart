import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/recurrence_repository.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late RecurrenceRepository repository;

  setUp(() {
    testDb = TestAppDatabase.create();
    repository = RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
  });

  tearDown(() => testDb.tearDown());

  test('create, read, update, and delete a recurrence rule', () async {
    final created = await repository.createRule(
      frequency: RecurrenceFrequency.weekly,
      daysOfWeek: [1, 3, 5],
      startDate: DateTime(2026, 1, 1),
    );
    expect(created.id, isNotNull);

    final fetched = await repository.getRule(created.id!);
    expect(fetched?.frequency, RecurrenceFrequency.weekly);
    expect(fetched?.daysOfWeek, [1, 3, 5]);

    await repository.updateRule(fetched!.copyWith(intervalValue: 2));
    final updated = await repository.getRule(created.id!);
    expect(updated?.intervalValue, 2);

    await repository.deleteRule(created.id!);
    expect(await repository.getRule(created.id!), isNull);
  });
}
