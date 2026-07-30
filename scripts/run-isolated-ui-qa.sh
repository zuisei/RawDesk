#!/usr/bin/env bash
set -euo pipefail

# Launch a QA-only copy of the built RAWDesk app without using the user's
# normal catalog, Application Support, or RAWDesk preference domain.
#
# Use --reset before a clean first launch. Relaunch without --reset to test
# persistence. Use --cleanup after the QA app has exited.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${RAWDESK_APP_PATH:-$ROOT/build/RAWDesk.app}"
QA_ROOT="${RAWDESK_UI_QA_ROOT:-/tmp/rawdesk-isolated-ui-qa}"
QA_BUNDLE_ID="${RAWDESK_UI_QA_BUNDLE_ID:-local.rawdesk.app.uiqa}"
QA_APP="$QA_ROOT/RAWDesk-QA.app"
QA_HOME="$QA_ROOT/home"
QA_SUPPORT="$QA_ROOT/support"
SOURCE_EXECUTABLE="$APP/Contents/MacOS/RAWDesk"
EXECUTABLE="$QA_APP/Contents/MacOS/RAWDesk"

case "$QA_ROOT" in
    /tmp/rawdesk-*) ;;
    *)
        echo "RAWDESK_UI_QA_ROOT must match /tmp/rawdesk-*" >&2
        exit 2
        ;;
esac

case "$QA_BUNDLE_ID" in
    local.rawdesk.app.uiqa*) ;;
    *)
        echo "RAWDESK_UI_QA_BUNDLE_ID must start with local.rawdesk.app.uiqa" >&2
        exit 2
        ;;
esac

if [ ! -x "$SOURCE_EXECUTABLE" ]; then
    echo "RAWDesk executable not found at $SOURCE_EXECUTABLE" >&2
    echo "Build it first with CONFIG=release ./scripts/build-app.sh" >&2
    exit 1
fi

if [ "${1:-}" = "--cleanup" ]; then
    if pgrep -f "$EXECUTABLE" >/dev/null 2>&1; then
        echo "The isolated RAWDesk process is still running." >&2
        exit 1
    fi
    rm -rf "$QA_ROOT"
    defaults delete "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
    echo "==> removed isolated QA data and preference domain"
    exit 0
fi

if [ "${1:-}" = "--reset" ]; then
    if pgrep -f "$EXECUTABLE" >/dev/null 2>&1; then
        echo "The isolated RAWDesk process is still running." >&2
        exit 1
    fi
    rm -rf "$QA_ROOT"
    defaults delete "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
elif [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--reset|--cleanup]" >&2
    exit 2
fi

mkdir -p "$QA_HOME/Library/Preferences"
mkdir -p "$QA_HOME/Library/Saved Application State"
mkdir -p "$QA_SUPPORT"

rm -rf "$QA_APP"
ditto "$APP" "$QA_APP"
plutil -replace CFBundleIdentifier \
    -string "$QA_BUNDLE_ID" \
    "$QA_APP/Contents/Info.plist"
codesign --force --deep --sign - "$QA_APP" >/dev/null

export HOME="$QA_HOME"
export CFFIXED_USER_HOME="$QA_HOME"
export RAWDESK_SUPPORT_DIRECTORY_OVERRIDE="$QA_SUPPORT"

echo "==> source app: $APP"
echo "==> isolated app: $QA_APP"
echo "==> isolated bundle id: $QA_BUNDLE_ID"
echo "==> isolated home: $QA_HOME"
echo "==> isolated support: $QA_SUPPORT"

exec "$EXECUTABLE"
