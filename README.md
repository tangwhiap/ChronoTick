# ChronoTick

ChronoTick is a local-first macOS time-management app built with Swift, SwiftUI, and SwiftData.
It is designed around a daily checklist, a week timeline, project-style task lists, habit tracking,
local reminders, CSV import/export, menu-bar access, and customizable themes.

The current app target is **macOS 14+**.

## What It Does

- Daily checklist tasks with incomplete/completed sections.
- Weekly timeline with timed tasks, current-time indicator, week navigation, zoom commands, drag-to-move, and top/bottom resizing.
- Project task lists with optional date-only or date+time deadlines.
- Fast natural-language-ish task entry, including time ranges and cross-midnight time input.
- Local notifications for daily checklist tasks and project-task deadlines.
- Habit tracking with a built-in `完成每日任务` habit synchronized from daily checklist completion.
- CSV import/export for daily checklist tasks and habit check-ins.
- Menu bar panel for quick access.
- Theme customization with two theme colors, saved presets, background images, and fixed-ratio background crop editing.

## Data Model Semantics

### Daily Checklist Ownership

Daily checklist tasks have two separate time concepts:

- `TaskItem.date`: the owning daily checklist date.
- `TaskItem.startDateTime` / `TaskItem.endDateTime`: the actual scheduled time used by the week timeline and reminders.

For example, if the selected daily checklist is `2026-04-17` and the user enters:

```text
25:30 finish notes
```

the task still belongs to the `2026-04-17` checklist, but its actual scheduled time is
`2026-04-18 01:30`. This split is intentional. Checklist completion and the built-in completion
habit use the owning date, while timeline layout and notification scheduling use the actual time.

### Timed Task Kinds

Daily checklist tasks render as one of three timing kinds:

- Untimed: no actual start time.
- Point: actual start time only.
- Range: actual start and end time.

Range tasks can span midnight. The week timeline splits them into per-day display segments when
needed, while preserving the single underlying task.

### Project Tasks

Project tasks belong to `ProjectTaskList`, not to a daily checklist.

- Only incomplete project tasks with a deadline appear in the week timeline.
- Date-only deadlines are rendered visually at noon.
- Date+time deadlines use their concrete time.
- Completing a project task hides it from the week timeline.

## Natural Text Parsing

The quick-add parser supports:

```text
23:30 ~ 23:50 read book
23:30~23:50 read book
09:00-10:30 Review paper
9:00 Review paper
18:30 dinner
25:30 late work
-03:00 early prep
Complete things
```

Supported input details:

- English and Chinese colon variants.
- English and Chinese range separators.
- Optional spaces around time range separators.
- Hours from `-47` through `47`.
- Minute values from `00` through `59`.

Parsing outcomes:

- `start + end + title` becomes a ranged task.
- `time + title` becomes a point task.
- no time becomes an untimed task.
- invalid titles, times, and ranges produce localized Chinese validation messages.

## Week Timeline

The week timeline is the main calendar-style planning surface.

- Timed daily checklist tasks are rendered by actual scheduled time.
- Completed daily checklist tasks remain visible but use muted styling.
- Project-task deadlines render as deadline markers.
- Dragging a task body moves the whole task.
- Dragging the top handle changes the start time.
- Dragging the bottom handle changes the end time.
- Direct manipulation snaps to 5-minute increments.
- Drag previews use the same computed preview model for card position, card height, displayed time text, and final persistence, so the visual state should stay aligned with the saved result.
- The timeline supports zoom levels: compact, standard, comfortable, and spacious.

Zoom commands are available from the app's `视图` menu:

- `Command +`: zoom in.
- `Command -`: zoom out.
- `Command 0`: reset to standard size.

## Daily Checklist

The daily checklist shows tasks for the selected owning date, not necessarily the selected actual
scheduled date. This is important for cross-midnight inputs such as `25:30`.

Checklist interactions route through the shared mutation pipeline:

- mark complete/incomplete
- edit task
- delete task
- synchronize reminders
- update the built-in completion habit

The task editor shows both the owning checklist date and the actual scheduled date/time. Editing
actual time does not reassign checklist ownership.

## Habit Tracking

Habit tracking includes:

- custom habit creation
- rename/delete flows
- future-date protection
- monthly grid navigation
- streak, total completed days, and monthly completion rate
- built-in `完成每日任务` habit

The built-in habit is synchronized from daily checklist completion state and cannot be deleted.

## Notifications

ChronoTick uses macOS `UserNotifications`.

### Daily Checklist Task Reminders

Daily checklist tasks support two reminder paths:

- Per-task reminders.
- Shared reminder rules configured in Settings.

If a task has its own reminder enabled, it uses that explicit reminder and does not stack shared
regex-rule reminders.

Shared daily checklist reminder rules match task titles with regular expressions and accept offsets
such as:

```text
-1d
-3m
-30s
0m
30s
1.5m
```

Changing task titles, task times, reminder settings, or reminder rules triggers notification
rescheduling.

### Project Task Deadline Reminders

Project-task reminders apply to incomplete project tasks that have date-only deadlines.
The global project reminder preferences support:

- one day before
- one week before
- configurable reminder time

Project tasks with concrete date+time deadlines do not use these global date-only reminder offsets.

## CSV Import And Export

CSV tools live in Settings.

### Task CSV

Columns:

```text
id,date,title,start_datetime,end_datetime,has_time,is_completed,reminder_enabled,reminder_offset_minutes,notes,created_at,updated_at
```

### Habit CSV

Columns:

```text
id,name,date,is_checked_in
```

### Import Modes

- Merge import: keeps existing data and skips duplicate task fingerprints.
- Replace import: deletes the current dataset for that import kind after confirmation.

Habit import normalizes records so a unique habit name maps to one habit and duplicate same-day
rows are coalesced. Checked-in rows win over unchecked rows because unchecked state is represented
by the absence of a stored check-in row.

Sample files:

- `Samples/tasks_sample.csv`
- `Samples/habits_sample.csv`

## Themes

ChronoTick supports:

- Theme Color 1: accent/control emphasis color.
- Theme Color 2: stable sidebar/surface color.
- Optional background image.
- Saved theme presets.
- Editing and deleting saved themes.
- Fixed-ratio background crop editing.

Background images are copied into ChronoTick's own Application Support directory. Moving or deleting
the original image does not break an already selected theme.

The crop editor stores crop position and zoom metadata while preserving the full original copied
image. The background image itself is not destructively cropped.

## Local Data

Runtime data is stored outside the repository.

The SwiftData store is created under:

```text
~/Library/Application Support/ChronoTick/ChronoTick.store
```

Theme image copies are stored under:

```text
~/Library/Application Support/ChronoTick/ThemeAssets
```

The repository does not contain user task data, habit data, reminder settings, or copied theme
images.

## Project Structure

```text
ChronoTick/
  ChronoTickApp.swift
  Models/
  Services/
  Utilities/
  ViewModels/
  Views/
  Resources/
ChronoTickTests/
Samples/
tools/
Package.swift
ChronoTick.xcodeproj/
build_and_install_app.sh
```

Important areas:

- `ChronoTick/Models`: SwiftData models for daily tasks, project tasks, habits, reminder rules, and themes.
- `ChronoTick/ViewModels/AppViewModel.swift`: app navigation state, week timeline zoom state, and task mutation entry points.
- `ChronoTick/Views/Week/WeekTimelineView.swift`: week timeline rendering and direct-manipulation interactions.
- `ChronoTick/Views/Settings/SettingsView.swift`: theme settings, reminders, CSV import/export, and theme crop editor.
- `ChronoTick/Services/NotificationScheduler.swift`: all local notification scheduling and cleanup.
- `ChronoTick/Services/CSVService.swift`: CSV parsing, export, merge, and habit normalization.
- `ChronoTick/Services/SystemHabitService.swift`: built-in habit setup and daily-completion synchronization.
- `ChronoTick/Utilities/TaskTimeTextParser.swift`: quick-add time parsing.

## Architecture Notes

- UI: SwiftUI.
- Persistence: SwiftData.
- App state: `AppViewModel`.
- Mutation path: `TaskMutationCoordinator`.
- Notifications: `NotificationScheduler`.
- CSV: `CSVService`.
- Date handling: `Calendar.chronoTick` and date helper extensions.

`TaskMutationCoordinator` exists so task changes from quick add, the editor sheet, the day list,
the project list, or the week timeline all perform the same follow-up work:

- persist model changes
- reschedule notifications
- update timestamps
- synchronize the built-in completion habit where needed

## Build And Install

### Build With Xcode

Open:

```text
ChronoTick.xcodeproj
```

Select the `ChronoTick` scheme and build for macOS.

### Build From Terminal

```bash
xcodebuild -project /Users/wenhant2/software/ChronoTick/ChronoTick.xcodeproj \
  -scheme ChronoTick \
  -configuration Debug \
  -derivedDataPath /Users/wenhant2/software/ChronoTick/.build-cache/DerivedData \
  -destination 'platform=macOS,arch=arm64' \
  build
```

### Install To `/Applications`

The repo includes:

```bash
./build_and_install_app.sh
```

The script:

- builds the Debug app
- closes any running ChronoTick process
- replaces `/Applications/ChronoTick.app`
- verifies the installed app signature
- leaves user data under `~/Library/Application Support/ChronoTick` untouched

Manual equivalent:

```bash
pkill -x ChronoTick
rm -rf /Applications/ChronoTick.app
ditto /Users/wenhant2/software/ChronoTick/.build-cache/DerivedData/Build/Products/Debug/ChronoTick.app /Applications/ChronoTick.app
codesign --verify --deep --strict /Applications/ChronoTick.app
open /Applications/ChronoTick.app
```

## Swift Package

The repository includes `Package.swift` for source indexing and lightweight command-line access:

```bash
swift build
```

The production app flow is maintained through the Xcode project.

## Tests

Unit test files exist under `ChronoTickTests`, including coverage for:

- task time parsing
- task draft validation
- CSV behavior
- reminder rule matching
- notification scheduling helper logic
- habit statistics

Current limitation: the Xcode scheme is not configured for `xcodebuild test`, so the command:

```bash
xcodebuild -project /Users/wenhant2/software/ChronoTick/ChronoTick.xcodeproj \
  -scheme ChronoTick \
  -configuration Debug \
  -derivedDataPath /Users/wenhant2/software/ChronoTick/.build-cache/DerivedData \
  -destination 'platform=macOS,arch=arm64' \
  test
```

currently fails with:

```text
Scheme ChronoTick is not currently configured for the test action.
```

## Current Limitations

- No cloud sync, account system, recurring tasks, or multi-device sync.
- Week timeline overlap handling is functional but can still be made smarter.
- Daily checklist ownership is intentionally stable; there is no dedicated "move to another checklist" feature yet.
- Tests are present, but the Xcode scheme needs a configured test action before `xcodebuild test` can run.

## Future Extension Ideas

### Repeating Tasks

- Add a recurrence model instead of overloading `TaskItem`.
- Separate recurrence rules from generated task occurrences.

### Sync

- Add a repository layer above SwiftData.
- Keep notification scheduling device-local.
- Preserve stable UUIDs and introduce conflict-resolution metadata.

### Timeline Refinement

- Improve overlap layout for dense schedules.
- Add keyboard nudging for selected timeline tasks.
- Consider explicit drag affordance states for accessibility.

## License

MIT. See `LICENSE`.
