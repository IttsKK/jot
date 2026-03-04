#!/usr/bin/env bash
set -euo pipefail

# Augment PATH with common pip/Python user-install bin dirs so tools like
# dmgbuild are discoverable even in non-login shells that lack a full PATH.
for _py_ver in 3.13 3.12 3.11 3.10 3.9; do
  _py_bin="$HOME/Library/Python/$_py_ver/bin"
  if [[ -d "$_py_bin" && ":$PATH:" != *":$_py_bin:"* ]]; then
    PATH="$_py_bin:$PATH"
  fi
done
unset _py_ver _py_bin

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
DMG_TOOL="${DMG_TOOL:-auto}"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-128}"
APP_ICON_ICNS="${APP_ICON_ICNS:-$ROOT_DIR/Jot/Resources/AppIcon.icns}"
APP_ICON_LIGHT_ICNS="${APP_ICON_LIGHT_ICNS:-$ROOT_DIR/Jot/Resources/AppIconLight.icns}"
APP_ICON_DARK_ICNS="${APP_ICON_DARK_ICNS:-$ROOT_DIR/Jot/Resources/AppIconDark.icns}"
DMG_ICON_PNG="${DMG_ICON_PNG:-$ROOT_DIR/Jot/Resources/dmg.png}"
DMG_VOLUME_ICON_ICNS="${DMG_VOLUME_ICON_ICNS:-}"
DMG_APPLICATIONS_ALIAS="${DMG_APPLICATIONS_ALIAS:-$ROOT_DIR/Jot/Resources/Applications}"
ASSETS_CAR="${ASSETS_CAR:-$ROOT_DIR/Jot/Resources/Assets.car}"

if [[ -f "$ROOT_DIR/scripts/release.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/scripts/release.env"
fi

_DEFAULT_BG="$ROOT_DIR/Jot/Resources/DMG/background.png"
if [[ -z "$DMG_BACKGROUND" && -f "$_DEFAULT_BG" ]]; then
  DMG_BACKGROUND="$_DEFAULT_BG"
fi
unset _DEFAULT_BG

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

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")}"
REPO_OWNER="${REPO_OWNER:-}"
REPO_NAME="${REPO_NAME:-}"
RELEASE_TAG="${RELEASE_TAG:-}"

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
  DMG_TOOL              dmg builder: auto|dmgbuild|create-dmg|finder (default: auto)
  DMG_VOLUME_NAME       mounted DMG volume name (default: "<App> <version>")
  DMG_ICON_SIZE         icon size in DMG Finder view (default: 128)
  APP_ICON_ICNS         fallback app icon .icns path (default: Jot/Resources/AppIcon.icns)
  APP_ICON_LIGHT_ICNS   light mode app icon .icns path (default: Jot/Resources/AppIconLight.icns)
  APP_ICON_DARK_ICNS    dark mode app icon .icns path (default: Jot/Resources/AppIconDark.icns)
  DMG_VOLUME_ICON_ICNS  dmg volume icon .icns path (default: APP_ICON_ICNS)
  ASSETS_CAR            path to pre-compiled Assets.car (default: Jot/Resources/Assets.car)
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

DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-$APP_NAME $VERSION}"
if [[ -z "$RELEASE_TAG" ]]; then
  RELEASE_TAG="v$VERSION"
fi

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

# Copy pre-compiled asset catalog for modern icon theming (light/dark/tinted/clear).
if [[ -f "$ASSETS_CAR" ]]; then
  echo "==> Copying pre-compiled Assets.car for themed app icons"
  cp "$ASSETS_CAR" "$DIST_DIR/$APP_NAME.app/Contents/Resources/Assets.car"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist" \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
else
  echo "warning: Assets.car not found at $ASSETS_CAR; themed icons will not be available"
  echo "hint: run scripts/make-app-icon.sh on a machine with Xcode to regenerate it"
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
  # Convert DMG icon PNG to .icns if no explicit .icns was provided.
  if [[ -z "$DMG_VOLUME_ICON_ICNS" && -f "$DMG_ICON_PNG" ]]; then
    _iconset="$DIST_DIR/dmg_icon.iconset"
    rm -rf "$_iconset"
    mkdir -p "$_iconset"
    for _sz in 16 32 128 256 512; do
      sips -z $_sz $_sz "$DMG_ICON_PNG" --out "$_iconset/icon_${_sz}x${_sz}.png" >/dev/null
      _sz2=$((_sz * 2))
      sips -z $_sz2 $_sz2 "$DMG_ICON_PNG" --out "$_iconset/icon_${_sz}x${_sz}@2x.png" >/dev/null
    done
    iconutil -c icns "$_iconset" -o "$DIST_DIR/dmg_icon.icns"
    rm -rf "$_iconset"
    DMG_VOLUME_ICON_ICNS="$DIST_DIR/dmg_icon.icns"
  fi
  if [[ -z "$DMG_VOLUME_ICON_ICNS" ]]; then
    DMG_VOLUME_ICON_ICNS="$APP_ICON_ICNS"
  fi

  DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
  echo "==> Packaging drag-install DMG: $DMG_PATH"
  rm -f "$DMG_PATH"

  # Finder background aliases can break when the target volume is mounted as
  # "<name> 1" due to an existing mount. Detach matching mounted volumes first.
  shopt -s nullglob
  for _mounted in "/Volumes/$DMG_VOLUME_NAME"*; do
    if [[ -d "$_mounted" ]]; then
      hdiutil detach "$_mounted" -quiet >/dev/null 2>&1 || true
    fi
  done
  shopt -u nullglob
  unset _mounted

  if [[ -n "$DMG_BACKGROUND" && ! -f "$DMG_BACKGROUND" ]]; then
    echo "error: DMG background not found: $DMG_BACKGROUND"
    exit 1
  fi

  # Resolve dmgbuild binary — pip installs it under the user Python bin dir which
  # is often absent from PATH in non-login shells (e.g. when run from an IDE).
  DMGBUILD_BIN=""
  if command -v dmgbuild >/dev/null 2>&1; then
    DMGBUILD_BIN="$(command -v dmgbuild)"
  elif command -v python3 >/dev/null 2>&1; then
    _py_user_base="$(python3 -m site --user-base 2>/dev/null || true)"
    if [[ -n "$_py_user_base" && -x "$_py_user_base/bin/dmgbuild" ]]; then
      DMGBUILD_BIN="$_py_user_base/bin/dmgbuild"
    fi
    unset _py_user_base
  fi

  USE_DMGBUILD=0
  USE_CREATEDMG=0
  USE_FINDER=0
  case "$DMG_TOOL" in
    auto)
      if command -v create-dmg >/dev/null 2>&1; then
        USE_CREATEDMG=1
      elif [[ -n "$DMGBUILD_BIN" ]]; then
        USE_DMGBUILD=1
      else
        USE_FINDER=1
      fi
      ;;
    dmgbuild)
      if [[ -z "$DMGBUILD_BIN" ]]; then
        echo "error: dmgbuild not found; install with: pip install dmgbuild"
        exit 1
      fi
      USE_DMGBUILD=1
      ;;
    create-dmg)
      # create-dmg uses AppleScript/Finder and may require explicit Automation
      # permission (System Settings -> Privacy & Security -> Automation).
      USE_CREATEDMG=1
      ;;
    finder)
      USE_FINDER=1
      ;;
    *)
      echo "error: invalid DMG_TOOL '$DMG_TOOL' (expected auto|dmgbuild|create-dmg|finder)"
      exit 1
      ;;
  esac

  if [[ "$USE_DMGBUILD" -eq 1 ]]; then
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

    _volume_icon=""
    if [[ -f "$DMG_VOLUME_ICON_ICNS" ]]; then
      _volume_icon="$DMG_VOLUME_ICON_ICNS"
    elif [[ -f "$APP_ICON_ICNS" ]]; then
      _volume_icon="$APP_ICON_ICNS"
    elif [[ -f "$APP_ICON_LIGHT_ICNS" ]]; then
      _volume_icon="$APP_ICON_LIGHT_ICNS"
    elif [[ -f "$APP_ICON_DARK_ICNS" ]]; then
      _volume_icon="$APP_ICON_DARK_ICNS"
    fi
    if [[ -n "$_volume_icon" ]]; then
      dmgbuild_args+=(-D "volume_icon=$_volume_icon")
    fi
    unset _volume_icon

    if [[ -n "$DMG_BACKGROUND" ]]; then
      dmgbuild_args+=(-D "background=$DMG_BACKGROUND")
    fi
    if [[ -n "$DMG_APPLICATIONS_ALIAS" && -f "$DMG_APPLICATIONS_ALIAS" ]]; then
      dmgbuild_args+=(-D "applications_alias=$DMG_APPLICATIONS_ALIAS")
    fi
    "$DMGBUILD_BIN" "${dmgbuild_args[@]}" "$DMG_VOLUME_NAME" "$DMG_PATH"

  elif [[ "$USE_CREATEDMG" -eq 1 ]]; then
    echo "    (using create-dmg)"
    DMG_STAGING="$DIST_DIR/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$DIST_DIR/$APP_NAME.app" "$DMG_STAGING/"
    dmg_args=(
      --volname "$DMG_VOLUME_NAME"
      --window-pos 120 120
      --window-size 780 528
      --filesystem HFS+
      --icon-size "$DMG_ICON_SIZE"
      --icon "$APP_NAME.app" 260 240
      --hide-extension "$APP_NAME.app"
      --app-drop-link 520 240
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
    if [[ "$USE_FINDER" -eq 1 && "$DMG_TOOL" != "auto" ]]; then
      echo "    (using finder/hdiutil)"
    else
      echo "warning: neither dmgbuild nor create-dmg installed; using hdiutil fallback"
      echo "hint: pip install dmgbuild  (recommended) or  brew install create-dmg"
    fi
    DMG_STAGING="$DIST_DIR/dmg-staging"
    DMG_RW_PATH="$DIST_DIR/$APP_NAME-$VERSION-rw.dmg"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$DIST_DIR/$APP_NAME.app" "$DMG_STAGING/"
    rm -f "$DMG_RW_PATH"
    hdiutil create -volname "$DMG_VOLUME_NAME" -fs HFS+ -srcfolder "$DMG_STAGING" -ov -format UDRW "$DMG_RW_PATH" >/dev/null

    ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW_PATH")"
    MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUTPUT" | sed -nE 's#^.*(/Volumes/.*)$#\1#p' | head -n 1)"
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

    BG_POSIX_PATH=""
    if [[ -n "$DMG_BACKGROUND" ]]; then
      mkdir -p "$MOUNT_POINT/.background"
      BG_FILE="$(basename "$DMG_BACKGROUND")"
      cp "$DMG_BACKGROUND" "$MOUNT_POINT/.background/$BG_FILE"
      BG_POSIX_PATH="$MOUNT_POINT/.background/$BG_FILE"
    fi

    if command -v osascript >/dev/null 2>&1; then
      OSA_OUTPUT=""
      if ! OSA_OUTPUT="$(osascript 2>&1 <<EOF
tell application "Finder"
  tell disk "$MOUNT_VOLUME_NAME"
    open
    try
      if exists item "Applications" then delete item "Applications"
    end try
    try
      make new alias file to folder "Applications" of startup disk at disk "$MOUNT_VOLUME_NAME"
      if exists item "Applications alias" then set name of item "Applications alias" to "Applications"
    end try
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {120, 120, 900, 648}
      set opts to the icon view options
      try
        set icon size of opts to $DMG_ICON_SIZE
      end try
      try
        set text size of opts to 14
      end try
      try
        set shows item info of opts to false
      end try
      try
        set shows icon preview of opts to true
      end try
      try
        set arrangement of opts to not arranged
      end try
$(if [[ -n "${BG_POSIX_PATH:-}" ]]; then
  printf '      try\n'
  printf '        set bgAlias to (POSIX file "%s") as alias\n' "$BG_POSIX_PATH"
  printf '        set background picture of opts to bgAlias\n'
  printf '      end try\n'
fi)
    end tell
    try
      set position of item "$APP_NAME.app" to {260, 240}
      set position of item "Applications" to {520, 240}
    end try
    update without registering applications
    delay 2
    close
    open
    delay 1
  end tell
end tell
EOF
)"
      then
        echo "warning: Finder styling failed; continuing with default DMG layout"
        if [[ -n "$OSA_OUTPUT" ]]; then
          echo "Finder error:"
          echo "$OSA_OUTPUT"
        fi
      fi
    fi

    rm -rf "$MOUNT_POINT/.fseventsd" "$MOUNT_POINT/.Trashes"
    sync
    cleanup_mounted_dmg
    trap - EXIT
    hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH%.dmg}" >/dev/null
    rm -f "$DMG_RW_PATH"
    rm -rf "$DMG_STAGING"
  fi
  rm -f "$DIST_DIR/dmg_icon.icns"
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
