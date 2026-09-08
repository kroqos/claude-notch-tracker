#!/usr/bin/env bash
# Rebuild "Claude Notch.app" from this checkout and install it into /Applications.
#
#   bash scripts/rebuild-local.sh
#
# Local-only companion to make-app.sh. Signs with an Apple Development identity when the login
# keychain has one (a stable identity, so Keychain's "Always Allow" grants survive rebuilds),
# else ad-hoc. Assembles in a temp dir: a checkout under iCloud Drive
# (or any File Provider volume) gets Finder xattrs re-stamped onto every directory as soon as
# they're stripped, and codesign rejects a bundle carrying them. Outside the synced tree the
# strip in make-app.sh sticks.
# Override the identity with SIGN_ID=… and the install path with TARGET=….
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Claude Notch"
TARGET="${TARGET:-/Applications/$APP_NAME.app}"

# Identity: an Apple-issued development certificate if the keychain has one (Apple's chain is
# what macOS trusts, so Keychain's "Always Allow" grants survive rebuilds), else ad-hoc. A
# self-signed certificate is no better than ad-hoc here: macOS treats an unknown chain as
# ad-hoc and pins keychain grants to the binary's hash.
if [ -z "${SIGN_ID:-}" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/{print $2; exit}')"
  SIGN_ID="${SIGN_ID:--}"
fi

DIST="$(mktemp -d)/dist"
if [ "$SIGN_ID" = "-" ]; then
  DIST="$DIST" ALLOW_ADHOC=1 bash "$ROOT/scripts/make-app.sh"
else
  DIST="$DIST" SIGN_ID="$SIGN_ID" bash "$ROOT/scripts/make-app.sh"
fi
APP="$DIST/$APP_NAME.app"

codesign --verify --strict "$APP"

echo "▸ Installing to ${TARGET}…"
pkill -x ClaudeNotch 2>/dev/null || true
[ -e "$TARGET" ] && trash "$TARGET"
ditto "$APP" "$TARGET"
codesign --verify --strict "$TARGET"
open "$TARGET"
echo "✓ Installed and launched: $TARGET"
