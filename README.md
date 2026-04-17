# ChronoTick

ChronoTick is a local-first macOS time management app built with SwiftUI and SwiftData.
It focuses on a usable weekly timeline, fast natural-text task entry, checklist workflows,
habit tracking, local notifications, CSV import/export, menu bar access, and theme/background customization.

The current app target is macOS 14+.

## Highlights

- Weekly timeline with draggable timed tasks
- Daily checklist view with incomplete/completed sections
- Project-style task lists with optional deadlines
- Natural text parsing for quick task creation
- Local notification rules for daily checklist tasks
- Built-in habit: `完成每日任务`
- CSV import/export for tasks and habit check-ins
- Menu bar quick panel
- Theme color and background image customization

## Run Locally

### Xcode

1. Open `/Users/wenhant2/software/ChronoTick/ChronoTick.xcodeproj`
2. Select the `ChronoTick` scheme
3. Build and run on macOS

### Swift Package Manager

The repository also includes `Package.swift` for lightweight source/test access:

```bash
swift build
swift test
```

Note: the main production app flow is maintained through the Xcode project.

## Project Structure

- `ChronoTick/Models`
  SwiftData models for checklist tasks, project tasks, habits, reminder rules, and theme settings.
- `ChronoTick/ViewModels`
  Shared app navigation state and mutation coordination.
- `ChronoTick/Views`
  SwiftUI screens and reusable components.
- `ChronoTick/Services`
  Notifications, CSV processing, habit synchronization, seed/setup helpers.
- `ChronoTick/Utilities`
  Date helpers, parser logic, reminder-rule parsing, CSV document helpers.
- `ChronoTickTests`
  Unit tests for parser, CSV behavior, reminder matching, and checklist ownership draft logic.
- `Samples`
  Example CSV files for import/export testing.

## Architecture

- UI: SwiftUI
- Persistence: SwiftData
- Pattern: MVVM with a centralized task mutation coordinator
- Notifications: `UserNotifications`
- Import/Export: CSV using ISO 8601 date-time strings

### Why the mutation coordinator exists

ChronoTick now routes task mutations through one coordinator so that:

- persistence
- notification rescheduling
- checklist completion side effects
- built-in habit synchronization

stay consistent no matter whether a task is changed from quick add, the editor sheet,
the day list, or the weekly timeline.

## Data Semantics

### Daily Checklist Tasks (`TaskItem`)

ChronoTick distinguishes between:

- **Owning checklist date**: `TaskItem.date`
- **Actual scheduled datetime**: `TaskItem.startDateTime` / `TaskItem.endDateTime`

This matters for inputs like `25:30` or `-03:00`.

Example:

- You create a task inside the `04/17/26` daily checklist
- Input: `25:30 Complete things`
- The task still belongs to the `04/17/26` checklist
- But its actual scheduled time is `04/18/26 01:30`
- The weekly timeline and reminders use the actual scheduled time
- Daily checklist completion and the built-in completion habit use the owning checklist date

This ownership model is intentional and should remain stable unless the app explicitly adds
"move to another checklist" as a separate feature.

### Project Tasks

Project tasks belong to named project lists instead of daily checklists.

- They may have an optional deadline
- A deadline may be date-only or date+time
- Date-only deadlines render at a default visual time in the week view, but they do not gain a real time component in storage

## Natural Text Parsing

Supported examples:

- `23:30 ~ 23:50 read book`
- `23:30~23:50 read book`
- `09:00-10:30 Review paper`
- `9:00 Review paper`
- `18:30 dinner`
- `25:30 late work`
- `-03:00 early prep`
- `Complete things`

Supported punctuation:

- English and Chinese colon variants
- English and Chinese range separators
- Arbitrary spaces around separators

Parsing rules:

- `start + end + title` -> ranged task
- `time + title` -> point task
- no time -> untimed task
- invalid ranges still show a friendly Chinese error

## Notifications

ChronoTick supports two reminder systems:

### 1. Per-task reminders

Daily checklist tasks can enable their own reminder.
When enabled, that task uses its explicit reminder setting and does **not** stack unified rule reminders.

### 2. Unified reminder rules

In Settings, daily checklist reminder rules can match task titles via regular expression and expand to multiple reminder moments.

Examples:

- `-1d`
- `-3m`
- `-30s`
- `0m`
- `30s`
- `1.5m`

Project task reminder preferences are configured globally for date-only deadlines.

## CSV Import / Export

### Task CSV columns

`id,date,title,start_datetime,end_datetime,has_time,is_completed,reminder_enabled,reminder_offset_minutes,notes,created_at,updated_at`

### Habit CSV columns

`id,name,date,is_checked_in`

### Import modes

- **Merge import**
  Keeps existing data and merges imported content with de-duplication.
- **Replace import**
  Replaces the current dataset after explicit confirmation.

Example files:

- `/Users/wenhant2/software/ChronoTick/Samples/tasks_sample.csv`
- `/Users/wenhant2/software/ChronoTick/Samples/habits_sample.csv`

## Theme Settings

ChronoTick supports:

- Theme Color 1: accent / control emphasis color
- Theme Color 2: sidebar base surface color
- Optional background image

Background image and theme colors are intentionally independent:

- background image = visual page background
- theme colors = foreground/surface accents

## Known Limitations

- The Xcode scheme currently is not configured for `xcodebuild test` action, even though unit test files are present in the repository.
- Complex overlapping weekly timeline cards can still be refined further.
- Daily checklist editor currently exposes actual scheduled date/time, while checklist ownership remains fixed after creation.
- No cloud sync, account system, repeated tasks, or multi-device sync in V1.

## Recommended Future Extensions

### Repeating Tasks

- Add a dedicated recurrence model instead of overloading `TaskItem`
- Separate source task rules from generated occurrences

### iCloud / Cloud Sync

- Introduce repository abstractions above SwiftData
- Add a sync layer separately from the local mutation coordinator

### Multi-device Sync

- Preserve stable UUIDs
- Track change versions and conflict resolution strategy
- Keep notification scheduling device-local

## License

MIT. See `/Users/wenhant2/software/ChronoTick/LICENSE`.
