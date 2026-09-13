# REmind — Part 12: QA, Optimization & Release Build

## What's already done (code-level, completed this session)

**1. Security / Privacy audit — clean, no issues found**
- No `INTERNET`/`ACCESS_NETWORK_STATE` permission anywhere in the manifest → confirmed no backend/network dependency exists in the app at all.
- Zero `print()` / `debugPrint()` / `dart:developer` `log()` calls anywhere in `lib/` → no task content (or anything else) can leak into production logs.
- Every SQL statement in `lib/data/datasources/` uses parameterized `?` placeholders for all user/runtime values; the only string-interpolated pieces are static table/column name constants the app itself controls, never user input. `TaskDataSource.search()` explicitly escapes `%`, `_`, `\` in the user's search text before building the `LIKE` clause. Zero raw `rawInsert`/`rawUpdate`/`rawDelete` calls exist anywhere — everything goes through sqflite's safe helper methods.
- Only 4 permissions declared: `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `USE_EXACT_ALARM` — all directly justified by the reminder/notification feature, nothing extraneous.
- The background notification entry point (`notificationBackgroundEntryPoint`) already carries `@pragma('vm:entry-point')`, so Dart's release-mode tree-shaking can't strip it.

**2. Release build configuration — done**
- Bumped version: `pubspec.yaml` is now `1.0.0+1` (was `0.1.0+1`); `AppConstants.appVersion` (shown in Settings → Data and the About dialog) bumped to match — these two were not linked automatically and would otherwise have shown a stale `0.1.0` in a real release build.
- Generated a real Android upload keystore (`android/app/upload-keystore.jks`, alias `remind_upload`, RSA 2048, 10000-day validity) and wired it into `android/app/build.gradle.kts`'s `signingConfigs.release`, replacing the old `// TODO: Add your own signing config` / debug-signing placeholder. Credentials live in `android/key.properties`, which (along with the `.jks` file) is already covered by `.gitignore` — confirmed neither is tracked by git.
  - **Important**: since your existing installs on your phone were signed with the debug key, and this release build is now signed with the new real key, Android will refuse to install-over/update those — you'll need to **uninstall the existing REmind app from your phone first**, then install the new release build fresh.
  - **Please back up `android/app/upload-keystore.jks` and `android/key.properties` somewhere safe outside the git repo** (e.g. a password manager or an encrypted drive). If this keystore is ever lost, no future build can be signed as an update to this one.
- **Deliberately left off**: `minifyEnabled` / `shrinkResources` (R8/ProGuard + resource shrinking) are both `false`. Reasoning: I can't install or run a release build myself to verify R8 didn't silently break anything (the background notification isolate entry point and any plugin reflection are the specific risk areas), and Part 12's instructions emphasize reliability over optimization. Shipping an unminified-but-correctly-signed release build is the safer, defensible choice here. Worth revisiting once you've confirmed a release build installs and works correctly end-to-end — I can enable it as a small follow-up.

**3. Automated test coverage — reviewed for gaps, two added**
Reviewed the full existing suite against Part 12's database/backup testing requirements. Already well covered: schema migration v1→v2 and v2→v3, empty database, delete-task-with-reminders cascade, delete-task-with-recurrence-rule cascade, delete-category-used-by-tasks (categoryId → null, task preserved), delete-tag-used-by-tasks, full backup export/restore round trip, and a long list of invalid-backup-file rejections (bad JSON, wrong shape, missing section, too-new version, duplicate ids, missing id, corrupted field, orphaned references).

Two genuine gaps found and filled:
- **Large dataset**: new test creates ~500 tasks (mixed categories/priorities/due dates/tags) and verifies `getAllTasks`, `getFilteredTasks`, tag filtering, search, and alphabetical sorting all stay correct at that scale (`test/data/repositories/task_repository_test.dart`).
- **Database restart**: new test opens a database, inserts a task, fully closes the connection, then reopens a fresh `AppDatabase` against the same on-disk file — simulating the app being killed and relaunched — and verifies the task and the seeded categories are still there and weren't re-created (`test/data/database/app_database_test.dart`).

Note on "thousands of tasks": the automated test above uses 500 rows, which is enough to catch real correctness bugs (wrong SQL, N+1 patterns, broken sort) without making the test suite slow or flaky. Actual performance *timing* at real scale needs to be checked on your physical device (see Performance section below) — a desktop test-runner's timing wouldn't tell you anything meaningful about how it feels on the phone anyway.

---

## What I can't do myself — needs you to run and report back

I have no Flutter/Android toolchain access (no way to run `flutter analyze`, `flutter test`, `flutter build`, or `adb`), and no physical Android device. Everything below needs you to run it and report the actual results — nothing in the Final Report will claim something works unless you've confirmed it.

### Commands to run (in order)

```powershell
cd D:\Ansh\MyProjects\remind

flutter pub get
flutter analyze
flutter test

# Debug build, quick sanity install if you want it
flutter build apk --debug

# Release build (uninstall any existing debug-signed REmind from your phone first!)
flutter build apk --release
flutter build appbundle --release
```

The `.aab` (the file needed for eventual Play Store submission — **not** something we're uploading now) will land at:
`build\app\outputs\bundle\release\app-release.aab`

The release `.apk` (useful for installing directly on your phone to test) will land at:
`build\app\outputs\flutter-apk\app-release.apk`

**Per the spec: do not publish or upload the app anywhere. These commands only produce local build artifacts on your machine.**

### Manual test checklist

Tick these off on your physical Android device. Report back anything that fails, looks wrong, or behaves unexpectedly — including exact repro steps.

**Task testing**
- [ ] Create a task (all fields: title, description, priority, category, tags, due date, due time)
- [ ] Edit a task
- [ ] Delete a task (with confirmation)
- [ ] Complete a task, then reopen it
- [ ] Pin / unpin a task
- [ ] Change priority, category, tags on an existing task
- [ ] Search for tasks by title / description / tag
- [ ] Apply and clear filters (status, category, priority, tag, date presets)

**Reminder testing**
- [ ] One-time reminder fires at the correct time
- [ ] Daily recurring reminder
- [ ] Weekly recurring reminder
- [ ] Monthly recurring reminder
- [ ] Yearly recurring reminder
- [ ] Custom recurrence interval
- [ ] A task with multiple reminders
- [ ] Snooze a reminder from the notification tray
- [ ] Reschedule a reminder
- [ ] Cancel a reminder

**Notification testing (physical device, this is the one that matters most)**
- [ ] Notification fires with app open
- [ ] Notification fires with app in background
- [ ] Notification fires with app fully killed
- [ ] Notification fires with screen locked
- [ ] Behavior with notification permission granted
- [ ] Behavior with notification permission denied (should degrade gracefully, no crash)
- [ ] Notification still fires correctly after a phone reboot
- [ ] A recurring reminder fires again on schedule after the first firing

**Database testing**
- [ ] Fresh install / empty database behaves correctly (no crashes, sensible empty states)
- [ ] App handles a large number of tasks smoothly (add a few hundred manually or via repeated use)
- [ ] Force-close and relaunch the app — data persists (this is now also covered by an automated test, but worth confirming on-device too)
- [ ] Delete a task that has reminders — reminders are gone, no orphaned notifications
- [ ] Delete a category that's used by tasks — those tasks survive with no category, don't get deleted
- [ ] Delete a tag that's used by tasks — tasks survive, tag removed from them

**Backup testing**
- [ ] Export a backup
- [ ] Change/delete some data
- [ ] Restore from the backup — verify data matches what was exported
- [ ] Try restoring an invalid/corrupted backup file — should show a clear error, not crash

**UI testing**
- [ ] Small phone screen
- [ ] Large phone screen / tablet if you have one
- [ ] Light mode, Dark mode, System mode
- [ ] Keyboard doesn't obscure input fields or break layout
- [ ] Screen rotation (if you support it — otherwise confirm it's locked as intended)
- [ ] Touch targets are comfortably tappable
- [ ] Scrolling is smooth on long lists
- [ ] Very long task titles / descriptions don't break layout

**Performance**
- [ ] App startup time feels acceptable
- [ ] Task list / search / calendar / statistics stay responsive with a realistic number of tasks
- [ ] If practical, try a few thousand tasks and see how it holds up — this is the one thing I genuinely can't approximate from here

---

## Final report

Once you've run the commands and been through the checklist, send me the results (analyzer output, test output, and which manual items passed/failed/weren't tested) and I'll put together the final Part 12 report in the exact structure you asked for — Application / Version / Technology / Features / Testing / Build / Remaining Issues. Nothing will be marked as working unless you've actually confirmed it, and I won't publish or upload anything — just preparing the local release build, as instructed.
