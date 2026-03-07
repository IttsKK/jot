# Jot Release Setup

This repo uses a local-first release flow:

- **Local:** `release.sh` builds the app, DMG, ZIP, and signed appcast
- **GitHub Pages:** serves the site and `docs/appcast.xml` directly from `main`

## One-time GitHub setup

1. Enable GitHub Pages:
   - Repository Settings -> Pages
   - Source: `Deploy from a branch`
   - Branch: `main`
   - Folder: `/docs`

2. Confirm feed URL in app:
   - `Jot/App/Info.plist` should contain:
   - `SUFeedURL = https://ittskk.github.io/jot/appcast.xml`

## Day-to-day flow

1. Merge into `main`
   - CI runs automatically (build + tests)

2. Ship a release

```bash
# One command: bumps version, builds, signs, and uploads to GitHub
./scripts/publish.sh 1.0.1

# Or create a draft release first
./scripts/publish.sh 1.0.1 --draft
```

This requires a clean tracked worktree on `main`, bumps `Info.plist` version fields, runs `release.sh` (build + sign + DMG + appcast), copies the generated feed to `docs/appcast.xml`, commits the release metadata, pushes `main`, and creates a GitHub release targeting the pushed commit.

## Local build prerequisites

- Xcode with Swift toolchain
- `dmgbuild` (`pip install dmgbuild`)
- Sparkle signing key (via `SPARKLE_PRIVATE_KEY`, `SPARKLE_ED_KEY_FILE`, or keychain `SPARKLE_KEY_ACCOUNT`)

## Icon and DMG asset sources

Release packaging pulls assets directly from this repo:

- App icons:
  - `Jot/Resources/AppIcon.icns`
  - `Jot/Resources/AppIconLight.icns`
  - `Jot/Resources/AppIconDark.icns`
  - `Jot/Resources/Assets.xcassets/AppIcon.appiconset/*` (for themed icons on newer macOS)
- DMG background:
  - `Jot/Resources/DMG/background.png`
