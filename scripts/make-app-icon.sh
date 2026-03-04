#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIGHT_SRC_PNG="${1:-}"
DARK_SRC_PNG="${2:-}"
TINTED_SRC_PNG="${3:-}"
RESOURCES_DIR="$ROOT_DIR/Jot/Resources"
OUT_LIGHT_ICNS="$RESOURCES_DIR/AppIconLight.icns"
OUT_DARK_ICNS="$RESOURCES_DIR/AppIconDark.icns"
OUT_FALLBACK_ICNS="$RESOURCES_DIR/AppIcon.icns"
ASSETS_APPICONSET_DIR="$RESOURCES_DIR/Assets.xcassets/AppIcon.appiconset"

if [[ -z "$LIGHT_SRC_PNG" ]]; then
  cat <<EOF
Usage:
  scripts/make-app-icon.sh <light-1024.png> [dark-1024.png] [tinted-1024.png]

Output:
  Jot/Resources/AppIcon.icns        (fallback)
  Jot/Resources/AppIconLight.icns   (always generated)
  Jot/Resources/AppIconDark.icns    (always generated; falls back to light)
  Jot/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png (all sizes)
  Jot/Resources/Assets.car          (compiled asset catalog; requires Xcode)
EOF
  exit 1
fi

if [[ ! -f "$LIGHT_SRC_PNG" ]]; then
  echo "error: light source image not found: $LIGHT_SRC_PNG"
  exit 1
fi
if [[ -n "$DARK_SRC_PNG" && ! -f "$DARK_SRC_PNG" ]]; then
  echo "error: dark source image not found: $DARK_SRC_PNG"
  exit 1
fi
if [[ -n "$TINTED_SRC_PNG" && ! -f "$TINTED_SRC_PNG" ]]; then
  echo "error: tinted source image not found: $TINTED_SRC_PNG"
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "error: sips not found"
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "error: iconutil not found"
  exit 1
fi

build_icns() {
  local src_png="$1"
  local out_icns="$2"
  local tmp_dir
  local iconset_dir

  tmp_dir="$(mktemp -d /tmp/jot-iconset.XXXXXX)"
  iconset_dir="$tmp_dir/AppIcon.iconset"
  mkdir -p "$iconset_dir"

  render_size() {
    local size="$1"
    local name="$2"
    sips -z "$size" "$size" "$src_png" --out "$iconset_dir/$name" >/dev/null
  }

  render_size 16   "icon_16x16.png"
  render_size 32   "icon_16x16@2x.png"
  render_size 32   "icon_32x32.png"
  render_size 64   "icon_32x32@2x.png"
  render_size 128  "icon_128x128.png"
  render_size 256  "icon_128x128@2x.png"
  render_size 256  "icon_256x256.png"
  render_size 512  "icon_256x256@2x.png"
  render_size 512  "icon_512x512.png"
  render_size 1024 "icon_512x512@2x.png"

  iconutil -c icns "$iconset_dir" -o "$out_icns"
  rm -rf "$tmp_dir"
  echo "Wrote icon: $out_icns"
}

mkdir -p "$RESOURCES_DIR"
build_icns "$LIGHT_SRC_PNG" "$OUT_LIGHT_ICNS"
cp "$OUT_LIGHT_ICNS" "$OUT_FALLBACK_ICNS"
echo "Wrote fallback icon: $OUT_FALLBACK_ICNS"

DARK_SOURCE="${DARK_SRC_PNG:-$LIGHT_SRC_PNG}"
TINTED_SOURCE="${TINTED_SRC_PNG:-$LIGHT_SRC_PNG}"

build_icns "$DARK_SOURCE" "$OUT_DARK_ICNS"

mkdir -p "$ASSETS_APPICONSET_DIR"

# Generate all required sizes for each appearance variant.
render_iconset_sizes() {
  local src="$1"
  local prefix="$2"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$src" --out "$ASSETS_APPICONSET_DIR/${prefix}${size}x${size}.png" >/dev/null
    size2=$((size * 2))
    sips -z "$size2" "$size2" "$src" --out "$ASSETS_APPICONSET_DIR/${prefix}${size}x${size}@2x.png" >/dev/null
  done
}

render_iconset_sizes "$LIGHT_SRC_PNG" "icon_"
render_iconset_sizes "$DARK_SOURCE" "icon_dark_"
render_iconset_sizes "$TINTED_SOURCE" "icon_tinted_"
echo "Wrote themed appiconset PNGs in: $ASSETS_APPICONSET_DIR"

# Compile Assets.car so release.sh doesn't need Xcode/actool at build time.
ACTOOL_PATH=""
if command -v xcrun >/dev/null 2>&1; then
  ACTOOL_PATH="$(xcrun --find actool 2>/dev/null || true)"
fi
if [[ -n "$ACTOOL_PATH" ]]; then
  ASSETS_CATALOG="$RESOURCES_DIR/Assets.xcassets"
  ASSETS_CAR="$RESOURCES_DIR/Assets.car"
  echo "==> Compiling Assets.car for themed app icons"
  ACTOOL_TMP="$(mktemp -d /tmp/jot-actool.XXXXXX)"
  "$ACTOOL_PATH" "$ASSETS_CATALOG" \
    --compile "$ACTOOL_TMP" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --include-all-app-icons \
    --output-partial-info-plist "$ACTOOL_TMP/partial-info.plist"
  cp "$ACTOOL_TMP/Assets.car" "$ASSETS_CAR"
  rm -rf "$ACTOOL_TMP"
  echo "Wrote compiled asset catalog: $ASSETS_CAR"
else
  echo "warning: actool not available; skipping Assets.car compilation"
  echo "hint: install Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi
