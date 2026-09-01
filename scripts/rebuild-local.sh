#!/usr/bin/env bash
# Rebuild "Claude Notch.app" from this checkout and install it into /Applications.
#
#   bash scripts/rebuild-local.sh
#
# Local-only companion to make-app.sh: ad-hoc signed, not notarized. A checkout under iCloud
# Drive (or any File Provider volume) gets Finder xattrs stamped onto every directory, ditto
# carries them into the bundle, and codesign rejects that as "detritus". So: assemble in a temp
# dir, strip the xattrs there (nothing re-stamps them outside the synced tree), re-sign, install.
# Override the install path with TARGET=….
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Claude Notch"
TARGET="${TARGET:-/Applications/$APP_NAME.app}"

DIST="$(mktemp -d)/dist"
DIST="$DIST" ALLOW_ADHOC=1 bash "$ROOT/scripts/make-app.sh"
APP="$DIST/$APP_NAME.app"

echo "▸ Stripping xattrs and re-signing…"
xattr -cr "$APP"
find "$APP" -name '._*' -delete
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

echo "▸ Installing to ${TARGET}…"
pkill -x ClaudeNotch 2>/dev/null || true
[ -e "$TARGET" ] && trash "$TARGET"
ditto "$APP" "$TARGET"
codesign --verify --strict "$TARGET"
open "$TARGET"
echo "✓ Installed and launched: $TARGET"
