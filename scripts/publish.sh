#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Jot/App/Info.plist"
DOCS_APPCAST="$ROOT_DIR/docs/appcast.xml"

usage() {
  cat <<EOF
Usage: scripts/publish.sh <version> [--draft] [--notes-file <path>]

Bumps version in Info.plist, builds release artifacts, and creates a GitHub
release with all assets attached. Also refreshes docs/appcast.xml for GitHub
Pages.

Arguments:
  <version>   Semantic version to release (e.g. 1.0.1)
  --draft     Create the GitHub release as a draft
  --notes-file  Path to the release notes markdown file to publish

Examples:
  ./scripts/publish.sh 1.0.1
  ./scripts/publish.sh 1.0.1 --draft
  ./scripts/publish.sh 1.0.1 --notes-file release-notes/1.0.1.md
EOF
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

VERSION="$1"
shift

RELEASE_NOTES_FILE=""
GH_EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes-file)
      if [[ $# -lt 2 ]]; then
        echo "error: --notes-file requires a path"
        exit 1
      fi
      RELEASE_NOTES_FILE="$2"
      shift 2
      ;;
    *)
      GH_EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$RELEASE_NOTES_FILE" ]]; then
  RELEASE_NOTES_FILE="$ROOT_DIR/release-notes/$VERSION.md"
fi

if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
  echo "error: release notes file not found: $RELEASE_NOTES_FILE"
  echo "hint: create release-notes/$VERSION.md or pass --notes-file <path>"
  exit 1
fi

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
# 4. Refresh GitHub Pages appcast
# ---------------------------------------------------------------------------
echo "==> Updating docs/appcast.xml"
cp "$ROOT_DIR/release-feed/appcast.xml" "$DOCS_APPCAST"

# ---------------------------------------------------------------------------
# 5. Create GitHub release and upload assets
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
  --notes-file "$RELEASE_NOTES_FILE" \
  ${GH_EXTRA_ARGS[@]+"${GH_EXTRA_ARGS[@]}"} \
  2>&1 | tail -n 1)

echo
echo "Release created: $RELEASE_URL"
echo
echo "Next steps:"
echo "  1) Commit and push the updated docs/appcast.xml and version changes on main"
echo "  2) Verify https://ittskk.github.io/jot/appcast.xml after Pages rebuilds"
