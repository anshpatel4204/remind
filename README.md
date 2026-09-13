# REmind

**Remember. Organize. Achieve.**

REmind is an offline-first task and reminder management app for Android, built with Flutter. It's designed around a simple idea: your tasks and their due dates live entirely on your device, in a real relational database, with no account, no server, and no network dependency required to use the app.

## Features

- **Full task lifecycle** — create, view, edit, delete, complete, reopen, and pin/unpin tasks.
- **Rich task fields** — title, description, priority (Low / Medium / High / Urgent), category, multiple tags, due date, and due time.
- **Smart status tracking** — every task has a real, persisted status (Pending / In Progress / Completed / Cancelled), plus a live-computed display status that also detects **Overdue** and **Snoozed** states from the current time and due date, so a task can never incorrectly show as overdue after it's marked complete.
- **Safe deletion** — deleting a task requires confirmation and cleans up everything related to it (tags, reminders, recurrence rules) in a single database transaction, so nothing is ever left orphaned.
- **Categories & tags** — organize tasks with color-coded categories and free-form tags.
- **Real local notifications** — one-time and recurring reminders (daily/weekly/monthly/yearly/custom interval), multiple reminders per task, snooze presets and a custom snooze time, reschedule, cancel. Notifications are scheduled natively via Android's AlarmManager, so they still fire with the app backgrounded, killed, or after a device reboot.
- **Calendar** — Day/Week/Month views with a task-indicator per day and a day-detail task list.
- **Search & filters** — debounced full-text search across title/description/tags, plus filtering by status, category, priority, tag, and date presets (today/tomorrow/this week/this month/upcoming/overdue/no due date), with sorting by due date, priority, creation date, or alphabetically.
- **Statistics** — totals, completion rate, Today/This Week/This Month completed counts, an Overdue-vs-Missed breakdown, a rolling 7-day completed-tasks chart, and category/priority breakdowns.
- **Backup & restore** — export all data to a local JSON file and restore from it, with thorough validation of any backup file before it's applied (corrupted/incompatible files are rejected with a clear message, never silently applied).
- **Settings** — theme (System/Light/Dark), notification preferences (master toggle, sound, vibration, default snooze duration), default priority/category for new tasks, and read-only app/database/backup version info.
- **Material 3 design** — a five-tab layout (Home, Tasks, Calendar, Statistics, Settings) built entirely with Flutter's Material 3 components, matched to a full visual design reference across both light and dark mode.
- **100% offline** — all data is stored locally in SQLite; the app never needs a network connection, and requests no network permission.

## Screenshots

_Add screenshots here once available (Task List, Add Task, Task Details)._

## Tech stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Material 3) |
| Language | Dart |
| Local database | SQLite via [`sqflite`](https://pub.dev/packages/sqflite) |
| Local notifications | [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications), [`timezone`](https://pub.dev/packages/timezone), [`flutter_timezone`](https://pub.dev/packages/flutter_timezone) |
| Backup file storage | [`path_provider`](https://pub.dev/packages/path_provider) (app's own private documents directory) |
| Testing DB | [`sqflite_common_ffi`](https://pub.dev/packages/sqflite_common_ffi) (runs the full DB test suite on desktop, no emulator needed) |
| Date/time formatting | [`intl`](https://pub.dev/packages/intl) |
| Dependency injection | A minimal hand-rolled `InheritedWidget` (`RepositoryScope`) — no external state-management package |

No third-party backend, analytics, or ads SDKs are used anywhere in the app.

## Architecture

REmind follows a strict layered architecture — the UI never touches SQL directly:

```
UI (screens/widgets)
   ↓
Repository  (business rules, e.g. status consistency, cascading delete)
   ↓
DataSource  (raw SQL / sqflite calls)
   ↓
SQLite (on-device database)
```

Notification scheduling is a parallel, separately-layered concern: screens go through `NotificationScheduler` (the single choke-point for create/cancel/reschedule/snooze), which depends on a `NotificationTransport` interface rather than the notification plugin directly, with `NotificationService` as the real Android implementation and a fake transport used in tests.

```
lib/
├── core/
│   ├── constants/     # app-wide constants (branding, category colors/icons)
│   ├── theme/         # Material 3 theme + design tokens (colors, spacing, typography)
│   └── utils/         # pure helpers: date formatting, hex colors, recurrence
│                       # calculation, task status + statistics calculators
├── data/
│   ├── backup/        # backup file format model, schema versioning, validation errors
│   ├── database/      # schema, migrations, the AppDatabase singleton
│   ├── models/        # immutable data models + enums
│   ├── datasources/    # one class per table, raw sqflite queries only
│   └── repositories/  # one class per feature area, sits between UI and datasources
├── features/
│   ├── tasks/, home/, calendar/, statistics/, settings/
│   ├── search/, categories/, tags/    # each feature: presentation/screens (+ widgets)
├── presentation/
│   └── widgets/       # shared shell widgets (empty/error/loading states, charts,
│                       # stat cards), RepositoryScope (DI)
└── services/
    ├── notification/  # NotificationTransport/Service/Scheduler
    └── backup/        # BackupFileService (file I/O for export/import)
```

### Database schema

SQLite database `remind.db`, currently at schema version 3.

| Table | Purpose |
|---|---|
| `tasks` | Core task records |
| `categories` | 7 seeded defaults (Work, Study, Personal, Finance, Shopping, Health, Other) |
| `tags` | Free-form tags |
| `task_tags` | Many-to-many join between tasks and tags |
| `recurrence_rules` | Recurrence configuration (daily/weekly/monthly/yearly/custom interval) |
| `reminders` | One or more reminder date/times attached to a task, wired to real Android notifications |
| `settings` | Simple key/value app settings |

Foreign keys are enforced (`PRAGMA foreign_keys = ON`), with cascading deletes on task → reminders/tags and `SET NULL` on task → category/recurrence. Deleting a task additionally removes its recurrence rule via an explicit transaction, since `SET NULL` alone doesn't clean up the other side of that relationship. Schema migrations (v1→v2→v3) are additive and covered by tests that simulate upgrading a pre-existing database in place.

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (developed and tested against Flutter 3.44.x)
- Android Studio (or another IDE with Flutter/Dart plugins) and an Android device or emulator
- Dart SDK `>=3.4.0 <4.0.0` (bundled with the Flutter SDK above)

### Setup

```bash
git clone https://github.com/anshpatel4204/remind.git
cd remind
flutter pub get
```

### Run

```bash
flutter run
```

If you have multiple devices/emulators connected, list them and target one explicitly:

```bash
flutter devices
flutter run -d <device-id>
```

> **Note:** if you run on an Android emulator and see a persistently black screen with no crash in the logs, this is a known graphics-driver issue with some experimental emulator system images (e.g. the "16k page size" preview images), not an app bug. Try `flutter run --no-enable-impeller`, or simply run on a physical device or a standard (non-experimental) emulator image instead. Notification behavior (background/killed-app delivery, reboot restoration) can only be fully verified on a physical device.

### Test

```bash
flutter test
```

Runs the full suite (data layer, pure-function unit tests, and end-to-end widget tests) using an in-memory/temp-file SQLite database via `sqflite_common_ffi` — no emulator required.

### Analyze

```bash
flutter analyze
```

### Release build

A release build needs a signing keystore that isn't committed to this repo (`android/app/upload-keystore.jks` + `android/key.properties`, both gitignored). Without it, `buildTypes.release` falls back to debug signing so the build still succeeds locally; ask whoever holds the real keystore for a copy before shipping a real release artifact.

```bash
flutter build apk --release        # installable APK
flutter build appbundle --release  # .aab, e.g. for a Play Store submission
```

## Inspecting the local database

Since all data lives in on-device SQLite, the easiest way to inspect it during development is Android Studio's **Database Inspector** (View → Tool Windows → App Inspection → Database Inspector) while running a debug build — it lets you browse `remind.db`'s tables live, no root required.

To pull a copy for use in a desktop SQLite browser instead:

```bash
adb exec-out run-as com.remind.app cat databases/remind.db > remind.db
```

## Project status

Parts 1–12 of the development plan are complete: app shell, SQLite data layer, full task management, notifications/recurrence, the main UI (Home/Calendar/Statistics/Settings), search & filters, statistics enhancements, backup & restore, settings/theming/UI polish, and a full QA/cleanup/release-build-prep pass. See `PART12_CHECKLIST.md` for the outstanding manual device-testing checklist and exact release-build commands.

## Not yet implemented

- Splash and onboarding screens, and a dedicated profile/about screen (About currently lives inline in Settings).
- Statistics' Week/Month/Year range tabs and comparative "+X%" trend deltas (Today/Week/Month completed counts exist; a trend against a prior period does not).
- Importing/sharing a backup file from outside the app (restore currently only lists backups from the app's own private storage, by design — no `file_picker`/`share_plus` dependency yet).
- R8/ProGuard minification and resource shrinking for release builds (deliberately left off until a release build has been verified end-to-end on a physical device).
- Publishing to Google Play.

## Contributing

This is currently a personal/learning project and not yet open to external contributions, but suggestions and issue reports are welcome.

## License

_No license has been chosen yet. All rights reserved by default until one is added._
