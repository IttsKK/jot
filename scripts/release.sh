#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Jot"
INFO_PLIST="$ROOT_DIR/Jot/App/Info.plist"
DIST_DIR="$ROOT_DIR/dist"
FEED_DIR="$ROOT_DIR/release-feed"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"
SPARKLE_ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
DMG_BACKGROUND="${DMG_BACKGROUND:-}"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-128}"
APP_ICON_ICNS="${APP_ICON_ICNS:-$ROOT_DIR/Jot/Resources/AppIcon.icns}"
APP_ICON_LIGHT_ICNS="${APP_ICON_LIGHT_ICNS:-$ROOT_DIR/Jot/Resources/AppIconLight.icns}"
APP_ICON_DARK_ICNS="${APP_ICON_DARK_ICNS:-$ROOT_DIR/Jot/Resources/AppIconDark.icns}"
DMG_VOLUME_ICON_ICNS="${DMG_VOLUME_ICON_ICNS:-$APP_ICON_ICNS}"
ASSETS_CATALOG="${ASSETS_CATALOG:-$ROOT_DIR/Jot/Resources/Assets.xcassets}"
ACTOOL_PATH="${ACTOOL_PATH:-}"

if [[ -f "$ROOT_DIR/scripts/release.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/scripts/release.env"
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift not found"
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "error: hdiutil not found"
  exit 1
fi

if ! command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  echo "error: /usr/libexec/PlistBuddy not found"
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "error: codesign not found"
  exit 1
fi

if [[ -z "$ACTOOL_PATH" ]] && command -v xcrun >/dev/null 2>&1; then
  ACTOOL_PATH="$(xcrun --find actool 2>/dev/null || true)"
fi

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")}"
REPO_OWNER="${REPO_OWNER:-}"
REPO_NAME="${REPO_NAME:-}"
RELEASE_TAG="${RELEASE_TAG:-v$VERSION}"

usage() {
  cat <<EOF
Usage: scripts/release.sh [options]

Options:
  --version <x.y.z>      Override CFBundleShortVersionString for this release.
  --build <n>            Override CFBundleVersion for this release.
  --tag <vX.Y.Z>         GitHub release tag used in download URL (default: v<version>).
  --owner <name>         GitHub owner (eg IttsKK).
  --repo <name>          GitHub repo name (eg jot).
  --skip-dmg             Skip DMG generation.
  --skip-appcast         Skip appcast generation.
  -h, --help             Show this help.

You can also set defaults in scripts/release.env.
Advanced env vars:
  SIGN_IDENTITY         codesign identity (default: - for ad-hoc)
  SPARKLE_KEY_ACCOUNT   keychain account for Sparkle keys (default: ed25519)
  SPARKLE_ED_KEY_FILE   path to private Sparkle EdDSA key file (overrides keychain account)
  SPARKLE_PRIVATE_KEY   private Sparkle EdDSA key string from env (highest priority)
  DMG_BACKGROUND        path to PNG/JPG background image for DMG window
  DMG_ICON_SIZE         icon size in DMG Finder view (default: 128)
  APP_ICON_ICNS         fallback app icon .icns path (default: Jot/Resources/AppIcon.icns)
  APP_ICON_LIGHT_ICNS   light mode app icon .icns path (default: Jot/Resources/AppIconLight.icns)
  APP_ICON_DARK_ICNS    dark mode app icon .icns path (default: Jot/Resources/AppIconDark.icns)
  DMG_VOLUME_ICON_ICNS  dmg volume icon .icns path (default: APP_ICON_ICNS)
  ASSETS_CATALOG        path to icon asset catalog (default: Jot/Resources/Assets.xcassets)
  ACTOOL_PATH           optional explicit path to actool binary
EOF
}

SKIP_DMG=0
SKIP_APPCAST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --tag)
      RELEASE_TAG="$2"
      shift 2
      ;;
    --owner)
      REPO_OWNER="$2"
      shift 2
      ;;
    --repo)
      REPO_NAME="$2"
      shift 2
      ;;
    --skip-dmg)
      SKIP_DMG=1
      shift
      ;;
    --skip-appcast)
      SKIP_APPCAST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option '$1'"
      usage
      exit 1
      ;;
  esac
done

echo "==> Using version $VERSION ($BUILD_NUMBER)"
echo "==> Building release binary"
swift build -c release --product "$APP_NAME"

BIN_PATH="$(find "$ROOT_DIR/.build" -type f -path "*/release/$APP_NAME" | head -n 1)"
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build" -type d -path "*/release/Sparkle.framework" | head -n 1)"

if [[ -z "$BIN_PATH" ]]; then
  echo "error: release binary not found"
  exit 1
fi

if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework not found (run swift build first and ensure Sparkle dependency resolves)"
  exit 1
fi

echo "==> Creating app bundle"
rm -rf "$DIST_DIR" "$FEED_DIR"
mkdir -p \
  "$DIST_DIR/$APP_NAME.app/Contents/MacOS" \
  "$DIST_DIR/$APP_NAME.app/Contents/Frameworks" \
  "$DIST_DIR/$APP_NAME.app/Contents/Resources" \
  "$FEED_DIR"

cp "$BIN_PATH" "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
cp -R "$SPARKLE_FRAMEWORK" "$DIST_DIR/$APP_NAME.app/Contents/Frameworks/"
chmod +x "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

icon_installed=0
if [[ -f "$APP_ICON_LIGHT_ICNS" ]]; then
  cp "$APP_ICON_LIGHT_ICNS" "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIconLight.icns"
  cp "$APP_ICON_LIGHT_ICNS" "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
  icon_installed=1
fi
if [[ -f "$APP_ICON_DARK_ICNS" ]]; then
  cp "$APP_ICON_DARK_ICNS" "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIconDark.icns"
  icon_installed=1
fi
if [[ "$icon_installed" -eq 0 && -f "$APP_ICON_ICNS" ]]; then
  cp "$APP_ICON_ICNS" "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
  icon_installed=1
fi
if [[ "$icon_installed" -eq 1 ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist" \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
fi

# Compile asset catalog for modern icon theming (light/dark/tinted/clear).
if [[ -d "$ASSETS_CATALOG" ]]; then
  ICONSET_DIR="$ASSETS_CATALOG/AppIcon.appiconset"
  required_iconset_files=("Contents.json" "1024-any.png" "1024-dark.png" "1024-tinted.png" "1024-clear.png")
  missing_files=()
  for file_name in "${required_iconset_files[@]}"; do
    if [[ ! -f "$ICONSET_DIR/$file_name" ]]; then
      missing_files+=("$file_name")
    fi
  done

  if [[ ${#missing_files[@]} -eq 0 ]]; then
    if [[ -n "$ACTOOL_PATH" ]]; then
      echo "==> Compiling asset catalog for themed app icons"
      "$ACTOOL_PATH" "$ASSETS_CATALOG" \
        --compile "$DIST_DIR/$APP_NAME.app/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --include-all-app-icons

      /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist" \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
    else
      echo "warning: actool not available; skipping themed asset-catalog icon compile"
      echo "hint: install full Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    fi
  else
    echo "warning: skipping asset-catalog icon compile; missing in $ICONSET_DIR:"
    printf '  - %s\n' "${missing_files[@]}"
  fi
fi

# Ensure executable can find embedded Sparkle.framework in packaged app.
if ! otool -l "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
fi

echo "==> Writing release metadata into bundled Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"

echo "==> Signing app bundle (identity: $SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" "$DIST_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$DIST_DIR/$APP_NAME.app"

ZIP_PATH="$FEED_DIR/$APP_NAME-$VERSION.zip"
echo "==> Packaging zip for Sparkle: $ZIP_PATH"
ditto -c -k --keepParent "$DIST_DIR/$APP_NAME.app" "$ZIP_PATH"

if [[ "$SKIP_DMG" -eq 0 ]]; then
  DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
  echo "==> Packaging drag-install DMG: $DMG_PATH"
  rm -f "$DMG_PATH"

  if [[ -n "$DMG_BACKGROUND" && ! -f "$DMG_BACKGROUND" ]]; then
    echo "error: DMG background not found: $DMG_BACKGROUND"
    exit 1
  fi

  if command -v dmgbuild >/dev/null 2>&1; then
    # dmgbuild constructs .DS_Store programmatically — no Finder/AppleScript
    # dependency — avoiding macOS Tahoe's symlink-icon rendering bugs.
    echo "    (using dmgbuild)"
    DMGBUILD_SETTINGS="$ROOT_DIR/scripts/dmgbuild-settings.py"
    if [[ ! -f "$DMGBUILD_SETTINGS" ]]; then
      echo "error: $DMGBUILD_SETTINGS not found"
      exit 1
    fi
    dmgbuild_args=(-s "$DMGBUILD_SETTINGS")
    dmgbuild_args+=(-D "app_path=$DIST_DIR/$APP_NAME.app")
    dmgbuild_args+=(-D "icon_size=$DMG_ICON_SIZE")
    if [[ -n "$DMG_BACKGROUND" ]]; then
      dmgbuild_args+=(-D "background=$DMG_BACKGROUND")
    fi
    dmgbuild "${dmgbuild_args[@]}" "$APP_NAME" "$DMG_PATH"

  elif command -v create-dmg >/dev/null 2>&1; then
    echo "    (using create-dmg)"
    DMG_STAGING="$DIST_DIR/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$DIST_DIR/$APP_NAME.app" "$DMG_STAGING/"
    dmg_args=(
      --volname "$APP_NAME"
      --window-pos 120 120
      --window-size 780 500
      --filesystem HFS+
      --icon-size "$DMG_ICON_SIZE"
      --icon "$APP_NAME.app" 180 230
      --hide-extension "$APP_NAME.app"
      --app-drop-link 500 230
      --no-internet-enable
    )
    if [[ ! -f "$DMG_VOLUME_ICON_ICNS" && -f "$APP_ICON_LIGHT_ICNS" ]]; then
      DMG_VOLUME_ICON_ICNS="$APP_ICON_LIGHT_ICNS"
    fi
    if [[ -f "$DMG_VOLUME_ICON_ICNS" ]]; then
      dmg_args+=(--volicon "$DMG_VOLUME_ICON_ICNS")
    fi
    if [[ -n "$DMG_BACKGROUND" ]]; then
      dmg_args+=(--background "$DMG_BACKGROUND")
    fi
    create-dmg "${dmg_args[@]}" "$DMG_PATH" "$DMG_STAGING"
    rm -rf "$DMG_STAGING"

  else
    echo "warning: neither dmgbuild nor create-dmg installed; using hdiutil fallback"
    echo "hint: pip install dmgbuild  (recommended) or  brew install create-dmg"
    DMG_STAGING="$DIST_DIR/dmg-staging"
    DMG_RW_PATH="$DIST_DIR/$APP_NAME-$VERSION-rw.dmg"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$DIST_DIR/$APP_NAME.app" "$DMG_STAGING/"
    ln -snf /Applications "$DMG_STAGING/Applications"
    rm -f "$DMG_RW_PATH"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW "$DMG_RW_PATH" >/dev/null

    ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW_PATH")"
    MOUNT_POINT="$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\// { for (i=1; i<=NF; i++) if ($i ~ /^\/Volumes\//) { print $i; exit } }')"
    if [[ -z "$MOUNT_POINT" ]]; then
      echo "error: failed to mount temporary DMG"
      echo "$ATTACH_OUTPUT"
      exit 1
    fi
    MOUNT_VOLUME_NAME="$(basename "$MOUNT_POINT")"

    cleanup_mounted_dmg() {
      if [[ -n "${MOUNT_POINT:-}" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
      fi
    }
    trap cleanup_mounted_dmg EXIT

    BG_NAME=""
    if [[ -n "$DMG_BACKGROUND" ]]; then
      mkdir -p "$MOUNT_POINT/.background"
      cp "$DMG_BACKGROUND" "$MOUNT_POINT/.background/$(basename "$DMG_BACKGROUND")"
      BG_NAME=".background/$(basename "$DMG_BACKGROUND")"
    fi

    if command -v osascript >/dev/null 2>&1; then
      if ! osascript >/dev/null 2>&1 <<EOF
tell application "Finder"
  tell disk "$MOUNT_VOLUME_NAME"
    open
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {120, 120, 780, 500}
      set opts to the icon view options
      set icon size of opts to $DMG_ICON_SIZE
      try
        set arrangement of opts to not arranged
      end try
$(if [[ -n "$BG_NAME" ]]; then
  printf '      set background picture of opts to file "%s"\n' "$BG_NAME"
fi)
    end tell
    try
      set position of item "$APP_NAME.app" to {180, 230}
      set position of item "Applications" to {500, 230}
    end try
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF
      then
        echo "warning: Finder styling failed; continuing with default DMG layout"
      fi
    fi

    sync
    cleanup_mounted_dmg
    trap - EXIT
    hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH%.dmg}" >/dev/null
    rm -f "$DMG_RW_PATH"
    rm -rf "$DMG_STAGING"
  fi
fi

if [[ "$SKIP_APPCAST" -eq 0 ]]; then
  if [[ -z "$REPO_OWNER" || -z "$REPO_NAME" ]]; then
    echo "error: appcast generation requires --owner and --repo (or scripts/release.env)"
    echo "hint: rerun with --skip-appcast if you only need local artifacts"
    exit 1
  fi
  if [[ ! -x "$SPARKLE_BIN" ]]; then
    echo "error: $SPARKLE_BIN not found (build once to fetch Sparkle tools)"
    exit 1
  fi

  DOWNLOAD_PREFIX="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/$RELEASE_TAG/"
  echo "==> Generating appcast.xml with download prefix:"
  echo "    $DOWNLOAD_PREFIX"

  if [[ -n "$SPARKLE_PRIVATE_KEY" ]]; then
    echo "    (signing mode: SPARKLE_PRIVATE_KEY via stdin)"
    printf '%s' "$SPARKLE_PRIVATE_KEY" \
      | "$SPARKLE_BIN" --ed-key-file - --download-url-prefix "$DOWNLOAD_PREFIX" "$FEED_DIR"
  elif [[ -n "$SPARKLE_ED_KEY_FILE" ]]; then
    if [[ ! -f "$SPARKLE_ED_KEY_FILE" ]]; then
      echo "error: SPARKLE_ED_KEY_FILE not found: $SPARKLE_ED_KEY_FILE"
      exit 1
    fi
    echo "    (signing mode: SPARKLE_ED_KEY_FILE)"
    "$SPARKLE_BIN" --ed-key-file "$SPARKLE_ED_KEY_FILE" --download-url-prefix "$DOWNLOAD_PREFIX" "$FEED_DIR"
  else
    echo "    (signing mode: keychain account '$SPARKLE_KEY_ACCOUNT')"
    "$SPARKLE_BIN" --account "$SPARKLE_KEY_ACCOUNT" --download-url-prefix "$DOWNLOAD_PREFIX" "$FEED_DIR"
  fi
fi

echo
echo "Release artifacts ready:"
echo "  App bundle:   $DIST_DIR/$APP_NAME.app"
echo "  Zip:          $ZIP_PATH"
if [[ "$SKIP_DMG" -eq 0 ]]; then
  echo "  DMG:          $DIST_DIR/$APP_NAME-$VERSION.dmg"
fi
if [[ "$SKIP_APPCAST" -eq 0 ]]; then
  echo "  Appcast:      $FEED_DIR/appcast.xml"
  echo
  echo "Next publish steps:"
  echo "  1) Create GitHub release $RELEASE_TAG"
  echo "  2) Upload $(basename "$ZIP_PATH") (and optionally DMG)"
  echo "  3) Publish appcast.xml to your SUFeedURL host"
fi
