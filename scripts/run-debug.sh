#!/usr/bin/env bash
#
# Build the Debug configuration for macOS and run it in the foreground so the
# app's stdout/stderr (print, NSLog, os_log to stderr) stream to this terminal.
# Press Ctrl-C to quit the app.
#
# Usage:
#   scripts/run-debug.sh                 # build + run
#   scripts/run-debug.sh path/to/file.md # build + run, then open a Markdown file
#   scripts/run-debug.sh --build-only    # build, don't launch
#
set -euo pipefail

SCHEME="MarkdownReader"
PROJECT="MarkdownReader.xcodeproj"
CONFIG="Debug"
DESTINATION="platform=macOS"

# Run from the repo root regardless of where the script is invoked from.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_ONLY=false
DOC=""
for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=true ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) DOC="$arg" ;;
  esac
done

echo "==> Building $SCHEME ($CONFIG) for macOS…"
xcodebuild \
  -scheme "$SCHEME" \
  -project "$PROJECT" \
  -configuration "$CONFIG" \
  -destination "$DESTINATION" \
  -quiet \
  build

# Resolve the built product path from the same build settings xcodebuild used.
settings="$(xcodebuild \
  -scheme "$SCHEME" \
  -project "$PROJECT" \
  -configuration "$CONFIG" \
  -destination "$DESTINATION" \
  -showBuildSettings 2>/dev/null)"

get() { printf '%s\n' "$settings" | sed -n "s/^[[:space:]]*$1 = //p" | head -1; }

TARGET_BUILD_DIR="$(get TARGET_BUILD_DIR)"
EXECUTABLE_PATH="$(get EXECUTABLE_PATH)"
FULL_PRODUCT_NAME="$(get FULL_PRODUCT_NAME)"
APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
BIN="$TARGET_BUILD_DIR/$EXECUTABLE_PATH"

echo "==> Built: $APP"

if [ "$BUILD_ONLY" = true ]; then
  exit 0
fi

if [ -n "$DOC" ]; then
  # Document-based apps receive files through LaunchServices, not argv, so use
  # `open` to hand the file to the app. Logs won't stream in this mode; tail
  # them with: log stream --predicate 'process == "MarkdownReader"' --level debug
  echo "==> Opening $DOC in $FULL_PRODUCT_NAME…"
  exec open -a "$APP" "$DOC"
fi

echo "==> Running (Ctrl-C to quit). App logs stream below:"
echo
exec "$BIN"
