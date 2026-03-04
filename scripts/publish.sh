#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Jot/App/Info.plist"

usage() {
  cat <<EOF
Usage: scripts/publish.sh <version> [--draft]

Bumps version in Info.plist, builds release artifacts, and creates a GitHub
release with all assets attached.

Arguments:
  <version>   Semantic version to release (e.g. 1.0.1)
  --draft     Create the GitHub release as a draft

Examples:
  ./scripts/publish.sh 1.0.1
  ./scripts/publish.sh 1.0.1 --draft
EOF
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

VERSION="$1"
shift

# Collect extra args (e.g. --draft) to pass through to gh release create.
GH_EXTRA_ARGS=("$@")

# ---------------------------------------------------------------------------
# 1. Bump CFBundleShortVersionString
# ---------------------------------------------------------------------------
echo "==> Bumping CFBundleShortVersionString to $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"

# ---------------------------------------------------------------------------
# 2. Auto-increment CFBundleVersion
# ---------------------------------------------------------------------------
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "==> Bumping CFBundleVersion from $CURRENT_BUILD to $NEW_BUILD"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

# ---------------------------------------------------------------------------
# 3. Run release.sh (builds app, DMG, zip, appcast)
# ---------------------------------------------------------------------------
echo "==> Running release.sh --version $VERSION --build $NEW_BUILD"
"$ROOT_DIR/scripts/release.sh" --version "$VERSION" --build "$NEW_BUILD"

# ---------------------------------------------------------------------------
# 4. Create GitHub release and upload assets
# ---------------------------------------------------------------------------
TAG="v$VERSION"
ASSETS=(
  "$ROOT_DIR/release-feed/Jot-$VERSION.zip"
  "$ROOT_DIR/release-feed/appcast.xml"
  "$ROOT_DIR/dist/Jot-$VERSION.dmg"
)

for asset in "${ASSETS[@]}"; do
  if [[ ! -f "$asset" ]]; then
    echo "error: expected asset not found: $asset"
    exit 1
  fi
done

echo "==> Creating GitHub release $TAG"
RELEASE_URL=$(gh release create "$TAG" \
  "${ASSETS[@]}" \
  --title "Jot $VERSION" \
  ${GH_EXTRA_ARGS[@]+"${GH_EXTRA_ARGS[@]}"} \
  2>&1 | tail -n 1)

echo
echo "Release created: $RELEASE_URL"
