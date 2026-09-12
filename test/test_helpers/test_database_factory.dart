import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:remind/data/database/app_database.dart';

/// Call once (e.g. in a `setUpAll`) before any test that touches
/// [AppDatabase]. Swaps sqflite's platform-channel implementation for the
/// FFI one so database tests can run on the host machine via `flutter
/// test`, instead of requiring an Android emulator.
void initTestSqfliteFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// A fresh [AppDatabase] backed by its own temp file, plus a teardown
/// callback that closes it and deletes the file. Each test should get its
/// own instance (call this in `setUp`) so tests never see another test's
/// data.
class TestAppDatabase {
  TestAppDatabase._(this.appDatabase, this._tempDir);

  factory TestAppDatabase.create() {
    final dir = Directory.systemTemp.createTempSync('remind_test_');
    final path = p.join(dir.path, 'test.db');
    return TestAppDatabase._(AppDatabase(testDatabasePath: path), dir);
  }

  final AppDatabase appDatabase;
  final Directory _tempDir;

  Future<void> tearDown() async {
    await appDatabase.close();
    if (_tempDir.existsSync()) {
      _tempDir.deleteSync(recursive: true);
    }
  }
}
