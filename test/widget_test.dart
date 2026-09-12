import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:remind/data/database/app_database.dart';
import 'package:remind/data/repositories/app_repositories.dart';
import 'package:remind/services/notification/notification_transport.dart';
import 'package:remind/main.dart';

void main() {
  late Directory tempDir;
  late AppDatabase appDatabase;
  late AppRepositories repositories;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('remind_widget_test_');
    final path = p.join(tempDir.path, 'widget_test.db');
    appDatabase = AppDatabase(testDatabasePath: path);
    repositories = AppRepositories(
      appDatabase: appDatabase,
      notificationTransport: const NoopNotificationTransport(),
    );
  });

  tearDown(() async {
    await appDatabase.close();
    // Best-effort cleanup only: on Windows the OS can hold the sqlite
    // file's handle open for a brief moment after close() returns, which
    // would make a strict deleteSync() here flaky and fail otherwise
    // passing tests over an irrelevant temp-file race. Leftover temp dirs
    // are harmless (OS temp cleanup handles them eventually).
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Ignore - see above.
    }
  });

  // The Tasks list and the Add/Edit task form each do a real database
  // read (via sqflite_common_ffi, which talks to a background isolate)
  // before their content renders, showing a CircularProgressIndicator
  // meanwhile. Two problems stack up here: that spinner is an
  // indeterminate animation pumpAndSettle() would wait on forever, and
  // testWidgets()'s fake-time zone does not reliably let a real
  // cross-isolate message round-trip complete on plain tester.pump()
  // calls alone. tester.runAsync() steps outside the fake-time zone to let
  // real async work (the actual database call) genuinely progress; a
  // plain pump() afterwards then lets the now-resolved Future's setState
  // rebuild the tree. Repeating this, bounded by maxAttempts, waits for
  // exactly the widget we need without hanging indefinitely on failure.
  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxAttempts = 30,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      if (finder.evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    // Let any in-flight route transition (push/pop slide+fade) finish so a
    // widget that merely EXISTS in the tree is also actually laid out at
    // its final on-screen position before the caller taps/interacts with
    // it. Without this, a widget found mid-transition can still be
    // positioned off-screen, which makes tester.tap()'s hit test miss.
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('REmind shell shows all five navigation destinations', (WidgetTester tester) async {
    await tester.pumpWidget(RemindApp(repositories: repositories));
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Tapping Tasks shows the task list with its empty state', (WidgetTester tester) async {
    await tester.pumpWidget(RemindApp(repositories: repositories));
    await tester.pump();

    await tester.tap(find.text('Tasks'));
    await pumpUntilFound(tester, find.text('No tasks yet'));

    expect(find.text('No tasks yet'), findsOneWidget);
  });

  testWidgets('Creating a task from the Tasks tab shows it in the list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(RemindApp(repositories: repositories));
    await tester.pump();

    await tester.tap(find.text('Tasks'));
    await pumpUntilFound(tester, find.text('No tasks yet'));

    await tester.tap(find.byTooltip('Add task'));
    await pumpUntilFound(tester, find.widgetWithText(TextFormField, 'Title'));

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Buy groceries');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await pumpUntilFound(tester, find.text('Buy groceries'));

    expect(find.text('Buy groceries'), findsOneWidget);
    expect(find.text('No tasks yet'), findsNothing);
  });
}
