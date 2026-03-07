# Jot

A lightweight macOS menu bar app for quick task capture. Type a task in natural language, hit Enter, and get back to work.

## Features

- **Quick capture overlay** — global hotkey opens an Alfred-style input panel; parses dates, people, queues, and notes from plain text
- **Two queues** — Work and Reach Out, with smart defaults (`/w`, `/r` shortcuts)
- **Menu bar first** — lives in the status bar with a summary of today's tasks; no Dock icon
- **Gentle notifications** — morning summary and due-date reminders with snooze
- **Auto-updates** — built-in update checking via Sparkle

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+

## Build

```bash
swift build
swift test
```

## Release

```bash
# One command: bumps version, builds, signs, refreshes docs/appcast.xml,
# commits the release metadata, pushes main, and creates the GitHub release
./scripts/publish.sh 1.0.1

# Or as a draft
./scripts/publish.sh 1.0.1 --draft
```

Run it from a clean `main` worktree with a matching `release-notes/<version>.md` file.

See [docs/releases.md](docs/releases.md) for full setup details (signing keys, GitHub Pages, etc.).

## License

All rights reserved.
