# Jot Release Setup

This repo uses a local-first release flow:

- **Local:** `release.sh` builds the app, DMG, ZIP, and signed appcast
- **GitHub Actions:** publishes `appcast.xml` to GitHub Pages when a release is created

## One-time GitHub setup

1. Enable GitHub Pages:
   - Repository Settings -> Pages
   - Source: `GitHub Actions`

2. Confirm feed URL in app:
   - `Jot/App/Info.plist` should contain:
   - `SUFeedURL = https://ittskk.github.io/jot/appcast.xml`

## Day-to-day flow

1. Merge into `main`
   - CI runs automatically (build + tests)

2. Ship a release

```bash
# Build artifacts locally
./scripts/release.sh --version 1.0.1 --owner IttsKK --repo jot

# Create GitHub release with artifacts
gh release create v1.0.1 \
  release-feed/Jot-1.0.1.zip \
  dist/Jot-1.0.1.dmg \
  release-feed/appcast.xml \
  --title "Jot 1.0.1"
```

GitHub Actions will automatically deploy `appcast.xml` to Pages.

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
