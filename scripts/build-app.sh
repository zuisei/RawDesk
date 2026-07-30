#!/usr/bin/env bash
set -euo pipefail

# Build a real macOS .app bundle from the SwiftPM target.
# Output: build/RAWDesk.app

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
EXE="$BIN_PATH/RAWDesk"
if [ ! -x "$EXE" ]; then
    echo "Executable not found at $EXE" >&2
    exit 1
fi

APP="$ROOT/build/RAWDesk.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$EXE" "$APP/Contents/MacOS/RAWDesk"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Generate the icon if missing.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "==> generating AppIcon.icns"
    swift "$ROOT/scripts/make-icon.swift" "$ROOT/Resources" >/dev/null
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc codesign so Gatekeeper does not block local launches.
echo "==> codesign --sign -"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# Refresh Launch Services so Finder/Dock pick up the new bundle.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" >/dev/null 2>&1 || true

echo "==> done: $APP"
echo "    open \"$APP\""
