import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:remind/data/database/app_database.dart';
import 'package:remind/data/repositories/app_repositories.dart';
import 'package:intl/intl.dart';
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

    // The Settings tab stays mounted in the background the whole time
    // (see main_shell.dart's IndexedStack), and Part 11 gave it a much
    // longer chain of sequential database reads on startup than before.
    // This test finds its own "No tasks yet" fast enough that it would
    // otherwise finish - and tearDown() would close the database - while
    // Settings' load is still mid-flight, leaving one of
    // sqflite_common_ffi's internal lock-diagnostic Timers pending and
    // tripping flutter_test's "Timer still pending" assertion. Waiting
    // for a widget that only renders once Settings' own load finishes
    // (see _SettingsScreenState.build's `if (data == null)` guard) lets
    // that background chain settle first.
    await pumpUntilFound(tester, find.text('Appearance'));
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

    // See the Calendar-tab equivalent test for why: the title field we
    // just typed into still displays this exact text until the form
    // screen is actually popped, so waiting for the literal string alone
    // can match instantly, before the real save has finished. Wait for
    // the Tasks tab's own FAB to reappear first to know we've actually
    // navigated back.
    await pumpUntilFound(tester, find.byTooltip('Add task'));
    await pumpUntilFound(tester, find.text('Buy groceries'));

    expect(find.text('Buy groceries'), findsOneWidget);
    expect(find.text('No tasks yet'), findsNothing);
  });

  testWidgets('Calendar shows a Day/Week/Month switcher and navigates between them', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(RemindApp(repositories: repositories));
    await tester.pump();

    await tester.tap(find.text('Calendar'));
    await pumpUntilFound(tester, find.text('Month'));

    // Starts in Month view: the weekday header row is visible.
    expect(find.text('Mon'), findsOneWidget);

    final todayHeader = DateFormat('EEEE, MMM d').format(DateTime.now());
    await tester.tap(find.text('Day'));
    await pumpUntilFound(tester, find.text(todayHeader));

    // Day view has no weekday header/grid at all.
    expect(find.text('Mon'), findsNothing);
    expect(find.text(todayHeader), findsOneWidget);

    await tester.tap(find.text('Week'));
    await pumpUntilFound(tester, find.text('Mon'));

    // Week view brings the weekday header back.
    expect(find.text('Mon'), findsOneWidget);
  });

  testWidgets('Creating a task from the Calendar tab shows it in that day\'s list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(RemindApp(repositories: repositories));
    await tester.pump();

    await tester.tap(find.text('Calendar'));
    await pumpUntilFound(tester, find.text('Month'));

    await tester.tap(find.byTooltip('Add task').first);
    await pumpUntilFound(tester, find.widgetWithText(TextFormField, 'Title'));

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Water the plants');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));

    // Waiting for the literal text "Water the plants" alone is ambiguous:
    // the title field we just typed into displays that exact same string
    // right up until the form screen is actually popped, so this can match
    // instantly - before the real save/insert has even started - letting
    // the test (and its tearDown, which closes the database) race ahead of
    // the still in-flight write. Wait for the Calendar tab's own FAB to
    // reappear first, which only happens once we've actually navigated
    // back, i.e. the save has genuinely finished.
    await pumpUntilFound(tester, find.byTooltip('Add task').first);
    await pumpUntilFound(tester, find.text('Water the plants'));

    // sqflite_common starts an internal "warn if this lock is held for
    // 10s" diagnostic Timer around every write, purely as a debugging
    // aid - it is not a sign anything is actually stuck, and normally
    // fires (or gets cancelled) so quickly in real use that nobody
    // notices it exists. But every pump() elsewhere in this test only
    // ever nudges the fake test clock forward by tens or hundreds of
    // milliseconds, so that 10-second Timer never actually gets to
    // elapse - it just sits there "pending" until flutter_test's
    // end-of-test invariant check flags it as a leak. A single big jump
    // past 10 seconds fires it, but does so instantly from the fake
    // clock's point of view, without giving the real cross-isolate side
    // of that same operation any actual time to finish responding -
    // stepping forward gradually, interleaved with real delays like the
    // rest of this file's real-database waits, lets both happen the way
    // they would outside a test.
    for (var settle = 0; settle < 12; settle++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Water the plants'), findsOneWidget);
  });

  testWidgets('Search shows a prompt, then "no results" for a non-matching query', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(RemindApp(repositories: repositories));
    await tester.pump();

    await tester.tap(find.text('Tasks'));
    await pumpUntilFound(tester, find.text('No tasks yet'));

    await tester.tap(find.byType(TextField).first);
    await pumpUntilFound(tester, find.text('Search your tasks'));

    // The Tasks tab's own (read-only) search field is still technically
    // findable here alongside the Search screen's own field - the pushed
    // route covers it visually, but both remain matched by a plain
    // find.byType(TextField), which made ".first" pick whichever the
    // finder happened to order first rather than reliably the new
    // screen's field. Target it by key instead, since that field is the
    // only place a Key('searchScreenField') exists in the tree.
    await tester.enterText(find.byKey(const Key('searchScreenField')), 'nothing matches this');

    // The search box debounces via a real Timer(250ms) before it fires the
    // query, and that Timer runs on the fake test clock - pumpUntilFound's
    // shared loop deliberately pumps with a bare, zero-duration pump() (so
    // as not to perturb other tests' real cross-isolate database timing),
    // which never elapses that clock. So this test waits it out itself:
    // pump WITH a duration each iteration to let the debounce elapse and
    // fire, interleaved with a real-time delay so the resulting real
    // database query also gets a chance to actually complete.
    final noResultsFinder = find.textContaining('No results for');
    for (var attempt = 0; attempt < 30; attempt++) {
      if (noResultsFinder.evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.textContaining('No results for "nothing matches this"'), findsOneWidget);
  });
}
