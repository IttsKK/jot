# Jot Phase 1 Implementation Plan

## Purpose
This document is the single source of truth for implementing Jot Phase 1 without feature overlap or sequencing chaos.  
Work proceeds in strict gates. No gate starts until the previous gate passes its acceptance checks.

## Inputs and Priority
1. User clarifications in chat (highest priority)
2. `Jot — Phase 1 Task Breakdown` (task-level acceptance)
3. `Jot — Product Spec v1` (product behavior and UX intent)

## Locked Decisions
- Platform: macOS 14+, Swift + SwiftUI + AppKit interop.
- App model: menu bar utility (`LSUIElement = YES`), no Dock icon.
- Database: SQLite via GRDB only.
- Queues: exactly two in v1: `work`, `reach_out`.
- Parser type model:
  - `type = follow_up` or `task` (default).
  - Type phrase stays in `title`.
  - `dueDate` and `note` are extracted and removed from `title`.
  - Mapping: `follow_up -> reach_out`, `task -> work`.
  - Overrides: `/r` and `/w` always win.
- Database naming convention: `snake_case` columns (`raw_input`, `due_date`, `done_at`, etc.).
- Settings Data tab: keep `Reset all data` only.
- JSON import/export: removed from Phase 1 scope.
- Global hotkey implementation: use the most reliable AppKit/macOS approach for global shortcuts.
- Testing tooling: XCTest (simple, native, sufficient for required acceptance checks).

## Non-Goals (Phase 1)
- No additional queues, tags, priorities, projects, or cloud sync.
- No contacts table (Phase 2 only).
- No storyboard/XIB usage.
- No Core Data.

## Working Protocol
- One active gate at a time.
- No parallel feature development.
- Each gate includes:
  - Scope
  - Deliverables
  - Acceptance checks
  - Stop condition
- If acceptance fails, fix immediately before continuing.
- Keep a running checklist at the bottom of this file.

## Planned Repository Structure
```
Jot/
  App/
  Models/
  Database/
  Parser/
  Views/
  Overlay/
  MenuBar/
  Notifications/
  Utilities/
  Settings/
  Tests/
  plans/
```

## Gate 0: Foundation Alignment
### Scope
- Create the planning and tracking baseline before coding.
- Lock all cross-spec conflicts in writing.

### Deliverables
- This plan file.
- Decision lock-in list (above).

### Acceptance Checks
- No unresolved spec conflicts for Phase 1 behavior.
- Implementation order is frozen.

### Stop Condition
- Start Gate 1 only after plan is in repo and confirmed.

## Gate 1: Project Setup and Bootstrap
### Scope
- Create a fresh macOS SwiftUI app named `Jot`.
- Add GRDB package.
- Configure utility-app startup behavior.

### Deliverables
- Xcode project targeting macOS 14+.
- App delegate bootstrap.
- `LSUIElement = YES`.
- Folder/group layout matching planned structure.
- Launch path with no visible main window yet.

### Acceptance Checks
- Project builds and runs on macOS 14+.
- App launches with no Dock icon.
- No crash on startup.
- `import GRDB` compiles.

### Stop Condition
- All checks pass locally.

## Gate 2: Data Model and Database Layer
### Scope
- Implement task schema, migrations, and CRUD operations.
- Enforce valid queue/status through enums.

### Schema (v1)
```sql
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    raw_input TEXT NOT NULL,
    title TEXT NOT NULL,
    queue TEXT NOT NULL DEFAULT 'work',
    status TEXT NOT NULL DEFAULT 'active',
    person TEXT,
    due_date TEXT,
    note TEXT,
    done_at TEXT,
    created_at TEXT NOT NULL,
    position INTEGER NOT NULL
);
```

### Deliverables
- `Task` model conforming to GRDB record protocols.
- `TaskQueue` enum: `work`, `reach_out`.
- `TaskStatus` enum: `active`, `done`, `archived`.
- `DatabaseManager` with:
  - `createTask`
  - `fetchTasks(queue:status:)`
  - `updateTask`
  - `deleteTask`
  - `toggleDone`
  - `reorderTask`
  - `archiveOldTasks`
- DB path: `~/Library/Application Support/Jot/tasks.db`.

### Acceptance Checks
- XCTest coverage for CRUD and behavior rules.
- Invalid queue/status creation is prevented by type system.
- `toggleDone` sets/clears `done_at` correctly.
- `archiveOldTasks` archives done tasks older than 24h.
- Database file created at expected location.

### Stop Condition
- All database tests green.

## Gate 3: Parsing Engine
### Scope
- Implement pure, side-effect-free parser callable on every keystroke.

### Parser Output (v1)
- `rawInput`
- `title`
- `type` (`follow_up` or `task`)
- `queue` (`reach_out` or `work`, derived from type or overrides)
- `person` (optional)
- `dueDate` (optional)
- `note` (optional)

### Parsing Order
1. Queue override (`/w`, `/r`) and strip override token.
2. Type detection from trigger phrases (reach-out phrases imply `follow_up`; otherwise `task`).
3. Date extraction and removal (with surrounding prepositions).
4. Description extraction (`about`, `regarding`, `re:`) and removal.
5. Person extraction for reach-out queue only.
6. Title cleanup.

### Date Handling Rules
- Relative tokens: `today`, `tonight`, `tomorrow`, `tmrw`, day names, `next week`, `next month`, `in X days/weeks/months`, `end of week`, `end of month`.
- Absolute tokens: `march 5`, `mar 5`, `3/5`, `3/5/26`, `the 15th`.
- All date parsing is relative to injected `now` value.

### Deliverables
- Parser module in `Parser/`.
- `ParsedTask` value type.
- Unit tests covering required examples and edge handling.
- Micro-benchmark style test/assertion for fast parse runtime on short input.

### Acceptance Checks
- All required parser fixtures pass.
- Parser remains pure function API.
- Performance target (<1ms average for typical short inputs) verified locally.

### Stop Condition
- Parser tests all green.

## Gate 4: Quick Capture Overlay
### Scope
- Build Alfred-style floating capture UI with live parse preview.

### Deliverables
- `NSPanel` subclass in `Overlay/`.
- Panel traits:
  - non-activating, borderless, full-size content
  - floating level
  - blur/vibrancy background
  - rounded corners (~16pt)
  - upper-third placement on active screen
  - dismiss on deactivate
- SwiftUI capture view with:
  - focused input field
  - live parse chips (queue/date/person/note)
  - subtle chip animation
  - Enter to save + dismiss
  - Escape to dismiss without save
  - clear input on dismiss
- Global hotkey manager:
  - default shortcut
  - toggle show/hide
  - persisted shortcut setting

### Acceptance Checks
- Hotkey opens overlay from any app.
- Live parse chips update while typing.
- Enter persists task to DB.
- Escape cancels without DB write.
- Overlay appears on active display and hides on blur.

### Stop Condition
- Manual functional checks pass end-to-end.

## Gate 5: Main Window Task List
### Scope
- Build browsable and editable task workspace with custom styling.

### Deliverables
- Main app window with warm custom styling (light/dark aware).
- Top tabs: `All`, `Work`, `Reach Out` with keyboard shortcuts.
- Reactive task list via GRDB observation.
- Sections:
  - Active tasks
  - Completed (done <24h, dimmed/strikethrough, undo capable)
  - Archive (collapsed by default)
- Row features:
  - custom checkbox
  - title
  - person chip (reach_out)
  - relative due text with color states
  - drag handle
- Interactions:
  - toggle done
  - inline edit panel
  - drag reorder persistence
  - context menu (edit/delete/snooze)
  - core keyboard navigation/actions

### Acceptance Checks
- New tasks from overlay appear instantly.
- Filters and tab switching behave correctly.
- Reorder persists via `position`.
- Completed/archive behavior follows 24h rule.
- Empty state message renders when list is empty.

### Stop Condition
- Functional and interaction checks pass.

## Gate 6: Menu Bar
### Scope
- Add menu bar status item and compact operational menu.

### Deliverables
- `NSStatusItem` icon.
- Dynamic menu:
  - due-today summary line
  - up to 5 due-today tasks
  - quick add
  - open app
  - settings
  - quit
- Hooks into DB state and app navigation.

### Acceptance Checks
- Menu bar icon appears on launch.
- Summary updates when task state changes.
- Quick Add and Open App actions work.
- Quit action exits app.

### Stop Condition
- Manual verification complete.

## Gate 7: Notifications
### Scope
- Implement local notifications with gentle, low-noise behavior.

### Deliverables
- Permission request flow on first launch.
- Morning summary scheduler (default 9:00 AM; configurable).
- Reach-out due notifications with actions:
  - `Done` (mark complete)
  - `Snooze` (push date by configured duration; default 1 week)
- Periodic due scan (~every 30 min while running).
- Gentle resurfacing: overdue active reach-outs moved forward by 7 days silently.
- Notification policy enforcement:
  - no badge
  - no sound
  - no spam bursts (batch where needed)

### Acceptance Checks
- Morning summary fires as configured.
- Due reach-out notification appears on due day.
- Action buttons perform expected DB updates.
- No badge count and no sound are set.

### Stop Condition
- End-to-end notification path validated.

## Gate 8: Settings
### Scope
- Native macOS settings with immediate effect.

### Deliverables
- `Settings` scene tabs:
  - General: launch at login, default queue fallback
  - Quick Capture: hotkey preset, overlay position
  - Notifications: toggles, summary time, snooze default
  - Appearance: light/dark/system
  - Data: reset all data (with confirmation)
- UserDefaults persistence and live application of changes.

### Acceptance Checks
- Settings window opens from menu bar.
- Changing settings applies without restart.
- Hotkey updates after preset change.
- Reset data clears DB only after confirmation.

### Stop Condition
- Final Phase 1 acceptance run passes.

## Test Strategy
### Automated
- XCTest unit tests for:
  - DB CRUD and lifecycle rules
  - Parser correctness and edge cases
  - Archive timing rules
  - Critical notification action handlers (where unit-testable)

### Manual
- Overlay behavior and global hotkey.
- Main list interactions and drag reorder.
- Menu bar workflows.
- Notification delivery and actions.
- Settings propagation.

## Quality Gates (Global)
- Build must remain green after each gate.
- No new warnings introduced without reason.
- No feature creep outside locked scope.
- No UI defaults where custom styling is required.

## Risks and Mitigations
- Global hotkey reliability:
  - Mitigation: use proven registration API and centralize handling.
- Date parsing ambiguity:
  - Mitigation: deterministic parsing order + fixture tests using fixed `now`.
- Reactive UI consistency:
  - Mitigation: GRDB observation from single DB manager boundary.
- Utility app lifecycle quirks (`LSUIElement`):
  - Mitigation: explicit AppDelegate/window/menu wiring tests in early gates.

## Progress Tracker
- [x] Gate 0: Foundation Alignment
- [x] Gate 1: Project Setup and Bootstrap
- [x] Gate 2: Data Model and Database Layer
- [x] Gate 3: Parsing Engine
- [x] Gate 4: Quick Capture Overlay
- [x] Gate 5: Main Window Task List
- [x] Gate 6: Menu Bar
- [x] Gate 7: Notifications
- [x] Gate 8: Settings

## Notes for Date-Sensitive Parser Tests
When validating relative date fixtures, pin `now` in tests to avoid ambiguity.  
Example baseline for expected fixtures: `2026-03-03` (Tuesday).
