# REmind

**Remember. Organize. Achieve.**

REmind is an offline-first task and reminder management app for Android, built with Flutter. It's designed around a simple idea: your tasks and their due dates live entirely on your device, in a real relational database, with no account, no server, and no network dependency required to use the app.

## Features

- **Full task lifecycle** — create, view, edit, delete, complete, reopen, and pin/unpin tasks.
- **Rich task fields** — title, description, priority (Low / Medium / High / Urgent), category, multiple tags, due date, and due time.
- **Smart status tracking** — every task has a real, persisted status (Pending / In Progress / Completed / Cancelled), plus a live-computed display status that also detects **Overdue** and **Snoozed** states from the current time and due date, so a task can never incorrectly show as overdue after it's marked complete.
- **Safe deletion** — deleting a task requires confirmation and cleans up everything related to it (tags, reminders, recurrence rules) in a single database transaction, so nothing is ever left orphaned.
- **Categories & tags** — organize tasks with color-coded categories and free-form tags.
- **Reminder scaffolding** — tasks can have a reminder date/time attached (actual notification scheduling is not yet implemented — see [Roadmap](#roadmap)).
- **Material 3 design** — a clean five-tab layout (Home, Tasks, Calendar, Statistics, Settings) built entirely with Flutter's Material 3 components.
- **100% offline** — all data is stored locally in SQLite; the app never needs a network connection.

## Screenshots

_Add screenshots here once available (Task List, Add Task, Task Details)._

## Tech stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Material 3) |
| Language | Dart |
| Local database | SQLite via [`sqflite`](https://pub.dev/packages/sqflite) |
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

```
lib/
├── core/
│   ├── constants/     # app-wide constants (branding, category colors)
│   ├── theme/         # Material 3 theme definition
│   └── utils/         # pure helpers: date formatting, hex colors,
│                       # and the overdue/snoozed status calculator
├── data/
│   ├── database/      # schema, migrations, the AppDatabase singleton
│   ├── models/        # immutable data models + enums
│   ├── datasources/   # one class per table, raw sqflite queries only
│   └── repositories/  # one class per feature area, sits between UI and datasources
├── features/
│   ├── tasks/         # Task List, Add/Edit Task, Task Details screens
│   ├── home/, calendar/, statistics/, settings/   # placeholder/basic screens
└── presentation/
    └── widgets/       # shared shell widgets, RepositoryScope (DI)
```

### Database schema

SQLite database `remind.db`, currently at schema version 2:

| Table | Purpose |
|---|---|
| `tasks` | Core task records |
| `categories` | 7 seeded defaults (Work, Study, Personal, Finance, Shopping, Health, Other) |
| `tags` | Free-form tags |
| `task_tags` | Many-to-many join between tasks and tags |
| `recurrence_rules` | Recurrence configuration (not yet used by the UI) |
| `reminders` | Reminder date/time attached to a task (not yet wired to real notifications) |
| `settings` | Simple key/value app settings |

Foreign keys are enforced (`PRAGMA foreign_keys = ON`), with cascading deletes on task → reminders/tags and `SET NULL` on task → category/recurrence. Deleting a task additionally removes its recurrence rule via an explicit transaction, since `SET NULL` alone doesn't clean up the other side of that relationship.

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

> **Note:** if you run on an Android emulator and see a persistently black screen with no crash in the logs, this is a known graphics-driver issue with some experimental emulator system images (e.g. the "16k page size" preview images), not an app bug. Try `flutter run --no-enable-impeller`, or simply run on a physical device or a standard (non-experimental) emulator image instead.

### Test

```bash
flutter test
```

Runs the full suite (data layer, pure-function unit tests, and end-to-end widget tests) using an in-memory/temp-file SQLite database via `sqflite_common_ffi` — no emulator required.

### Analyze

```bash
flutter analyze
```

## Inspecting the local database

Since all data lives in on-device SQLite, the easiest way to inspect it during development is Android Studio's **Database Inspector** (View → Tool Windows → App Inspection → Database Inspector) while running a debug build — it lets you browse `remind.db`'s tables live, no root required.

To pull a copy for use in a desktop SQLite browser instead:

```bash
adb exec-out run-as com.remind.app cat databases/remind.db > remind.db
```

## Project status

| Part | Scope | Status |
|---|---|---|
| 1 | App shell, navigation, branding | ✅ Complete |
| 2 | SQLite schema, migrations, repositories | ✅ Complete |
| 3 | Full task management (CRUD, status, overdue logic) | ✅ Complete |
| 4+ | Notifications, recurrence, calendar/statistics views | 🔲 Planned |

## Roadmap

- [ ] Real reminder notifications (local push notifications tied to the existing `reminders` table)
- [ ] Recurring tasks using the existing `recurrence_rules` table
- [ ] Calendar view backed by real task data
- [ ] Statistics/insights screen backed by real task data
- [ ] Settings screen (theme, defaults, data export/import)

## Contributing

This is currently a personal/learning project and not yet open to external contributions, but suggestions and issue reports are welcome.

## License

_No license has been chosen yet. All rights reserved by default until one is added._
