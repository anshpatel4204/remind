import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/db_constants.dart';
import '../models/occurrence_exception_model.dart';

/// Owns the raw SQLite access for the occurrence_exceptions table.
///
/// Every write goes through [upsert] rather than a plain insert: the
/// unique (rule, date) index means a second action recorded against the
/// same occurrence (e.g. rescheduling an occurrence that was already
/// rescheduled once) must replace the earlier row, never conflict or
/// duplicate it - this is the concrete mechanism behind "the system must
/// prevent duplicate occurrences".
class OccurrenceExceptionDataSource {
  OccurrenceExceptionDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<int> upsert(OccurrenceExceptionModel exception) async {
    final Database db = await _appDatabase.database;
    return db.insert(
      OccurrenceExceptionsTable.name,
      exception.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<OccurrenceExceptionModel?> getForOccurrence(
    int recurrenceRuleId,
    DateTime occurrenceDate,
  ) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      OccurrenceExceptionsTable.name,
      where: '${OccurrenceExceptionsTable.recurrenceRuleId} = ? AND '
          '${OccurrenceExceptionsTable.occurrenceDate} = ?',
      whereArgs: [recurrenceRuleId, occurrenceDate.millisecondsSinceEpoch],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OccurrenceExceptionModel.fromMap(rows.first);
  }

  /// Every exception recorded against [recurrenceRuleId], most recent
  /// first - used to render a recurring task's occurrence history (which
  /// dates were skipped/cancelled/rescheduled) without ever having to
  /// scan or materialize every occurrence date.
  Future<List<OccurrenceExceptionModel>> getForRule(
      int recurrenceRuleId) async {
    final Database db = await _appDatabase.database;
    final rows = await db.query(
      OccurrenceExceptionsTable.name,
      where: '${OccurrenceExceptionsTable.recurrenceRuleId} = ?',
      whereArgs: [recurrenceRuleId],
      orderBy: '${OccurrenceExceptionsTable.occurrenceDate} DESC',
    );
    return rows.map(OccurrenceExceptionModel.fromMap).toList();
  }

  Future<int> delete(int id) async {
    final Database db = await _appDatabase.database;
    return db.delete(
      OccurrenceExceptionsTable.name,
      where: '${OccurrenceExceptionsTable.id} = ?',
      whereArgs: [id],
    );
  }
}
