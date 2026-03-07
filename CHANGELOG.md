# Changelog

All notable user-facing changes are tracked here. Detailed release bodies remain in [`release-notes/`](release-notes).

## 1.0.0 - 2026-03-03

### Highlights

- Initial repository bootstrap for Jot.
- Established the `v1.0.0` baseline tag used by later release automation and changelog history.

### Notes

- The `v1.0.0` tag points to the initial commit.
- The website, richer packaging flow, and versioned checked-in release notes were added later.

## 1.1.2 - 2026-03-07

### Highlights

- Fixed the menu bar Settings action so it reliably opens the Settings window from the accessory app state.
- Added clear in-app warnings when a global hotkey cannot be registered because the shortcut is already in use.
- Improved the shortcut settings flow so registration failures are surfaced instead of silently leaving a broken shortcut behind.

### Improvements

- Tightened release publishing so releases are cut from a clean `main` branch, commit their metadata first, and publish from the pushed commit SHA.
- Declared macOS 14 as the app minimum in the app bundle metadata to match the actual app requirements.

## 1.1.1 - 2026-03-07

### Highlights

- Reworked hotkey editing so shortcuts are recorded directly from the keyboard instead of being assembled from separate key and modifier controls.
- Fixed the menu bar shortcut labels so the Today Focus entry reflects the configured hotkey instead of a hardcoded key.
- Improved shortcut display formatting across the app with cleaner symbol-based labels for keys and modifiers.

### Improvements

- Switched Sparkle appcast publishing to `docs/appcast.xml`, which matches the existing GitHub Pages setup and restores update delivery for installed clients.
- Added explicit versioned release notes support to the release flow so GitHub releases use the intended notes body.

## 1.1.0 - 2026-03-07

### Highlights

- Added a dedicated Notes inbox for quick ideas, with `/n`, `/note`, and `//` shortcuts.
- Added meeting-aware capture with `/meeting`, `/summary`, and `/end`, plus grouped meeting views for notes, tasks, and follow-ups.
- Added a Today list window with its own hotkey so you can pull a focused set of tasks into your day.
- Improved quick capture so slash-command modes lock after a space and metadata updates live while you type.

### Improvements

- Follow-ups created during a meeting now inherit the active attendee when possible.
- Expanded the main app with better editing flows for notes, meetings, and task details.
- Added parser, command, and database coverage for the new capture flows.
