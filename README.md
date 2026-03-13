# Jot

Jot is a local-first macOS capture app for tasks, follow-ups, notes, and meetings. It lives in the menu bar, opens a fast global capture overlay, and keeps a fuller main window and Today list close by when you need them.

## What Jot Does

- **Quick capture from anywhere** with a global shortcut and natural-language parsing for dates, people, notes, and queue changes
- **Three queues** for Work, Follow Up, and Notes, plus a separate Today list for what matters right now
- **Meeting-aware capture** so you can start a meeting, jot notes and follow-ups during it, and keep everything attached to that meeting
- **Main app window** for browsing queues, editing tasks, reviewing meetings, and managing Today Focus
- **Customizable hotkeys** recorded directly from the keyboard in Settings
- **Local notifications** for the morning summary and due follow-ups with done and snooze actions
- **Sparkle updates** for packaged app installs via the published appcast

## Quick Capture Commands

Jot works with plain text, but it also supports slash commands for faster mode switching:

- `/w` for Work
- `/f` for Follow Up
- `/n` for Note
- `/meeting` to start a meeting from a single draft
- `/end` to end the current meeting with an optional summary
- `/summary` to update the current meeting summary
- `/t` to add the item to the Today list

Examples:

- `email Tyler tomorrow`
- `/f Bob wednesday`
- `/n pricing idea from support call`
- `/meeting Product roadmap with Tyler`
- `/t finish release notes`

## Current Release

`1.1.8` is the latest published release as of March 12, 2026.

- `1.1.8` separates closing the Jot frontend from fully terminating the app, so background capture can keep running without leaving the app UI stuck around.
- `1.1.7` fixes the lingering Dock/frontend state after closing Jot and adds `Check for Updates...` to the standard app menu.
- `1.1.6` fixes background mode so the Dock icon disappears once Jot returns to menu bar-only operation.

See [CHANGELOG.md](CHANGELOG.md) for the condensed history and [`release-notes/`](release-notes) for version-specific release bodies.

## Requirements

- macOS 14 or later
- Swift 5.10+
- A packaged `.app` build if you want notifications and Sparkle update checks to work

## Build

```bash
swift build
swift test
```

## Release

Create a matching release notes file first, then run:

```bash
./scripts/publish.sh 1.1.3
```

Or create the GitHub release as a draft:

```bash
./scripts/publish.sh 1.1.3 --draft
```

The publish script:

- bumps the app version and build number
- builds and signs the app, ZIP, DMG, and appcast
- refreshes [`docs/appcast.xml`](docs/appcast.xml)
- commits and pushes the release metadata to `main`
- creates the GitHub release from the pushed commit

Run it from a clean `main` worktree with a matching `release-notes/<version>.md` file.

See [docs/releases.md](docs/releases.md) for the full release setup and publishing details.

## License

All rights reserved.
