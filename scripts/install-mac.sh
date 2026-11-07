#!/bin/bash
# Builds the Mac app and puts it in your Applications folder, replacing the old copy.
# Run it after making changes, so the app you open from the Dock is up to date:
#
#   ./scripts/install-mac.sh
#
# If PaycheckApp is open with a sheet or dialog showing, it won't quit. Close it, or add
# --force to quit it anyway (your budget is saved after every change, so only what's typed
# into an open sheet is lost):
#
#   ./scripts/install-mac.sh --force
#
# Your budget isn't touched: it's saved separately from the app.

set -euo pipefail

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

DEST="/Applications/PaycheckApp.app"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"                    # ignored by git
BUILT="$BUILD/Build/Products/Release/PaycheckApp.app"

echo "Building the Mac app..."
LOG="$BUILD/build.log"
mkdir -p "$BUILD"
if ! xcodebuild -project "$ROOT/PaycheckApp.xcodeproj" -scheme PaycheckApp -configuration Release \
        -destination 'platform=macOS' -derivedDataPath "$BUILD" build > "$LOG" 2>&1; then
    echo "The build failed. Errors:"
    grep -E "error:" "$LOG" | sort -u || tail -20 "$LOG"
    echo "Full log: $LOG"
    exit 1
fi

# The app's ID, read from the build (it comes from BUNDLE_ID_PREFIX in the project).
APP_ID="$(defaults read "$BUILT/Contents/Info" CFBundleIdentifier)"

# Quit the app if it's open, so it can be replaced.
if pgrep -f "$DEST/Contents/MacOS/" > /dev/null; then
    echo "Quitting PaycheckApp..."
    osascript -e "tell application id \"$APP_ID\" to quit" > /dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -f "$DEST/Contents/MacOS/" > /dev/null || break
        sleep 0.5
    done
    if pgrep -f "$DEST/Contents/MacOS/" > /dev/null && [ "$FORCE" = 1 ]; then
        pkill -TERM -f "$DEST/Contents/MacOS/" || true
        for _ in $(seq 1 10); do
            pgrep -f "$DEST/Contents/MacOS/" > /dev/null || break
            sleep 0.5
        done
    fi
    if pgrep -f "$DEST/Contents/MacOS/" > /dev/null; then
        echo "PaycheckApp didn't quit. It usually means a sheet or dialog is open in it."
        echo "Close it and run this again, or run it with --force to quit the app anyway:"
        echo "  $0 --force"
        exit 1
    fi
fi

# Move the old copy to the Trash (not deleted, so you can get it back).
if [ -e "$DEST" ]; then
    osascript -e "tell application \"Finder\" to delete POSIX file \"$DEST\"" > /dev/null
fi

ditto "$BUILT" "$DEST"
echo "Installed $DEST"
open "$DEST"
