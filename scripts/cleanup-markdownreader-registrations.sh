#!/usr/bin/env bash
#
# Find duplicate MarkdownReader registrations and optionally remove them from
# Launch Services and PlugInKit without deleting any app bundles.
#
# Usage:
#   scripts/cleanup-markdownreader-registrations.sh
#   scripts/cleanup-markdownreader-registrations.sh --apply
#   scripts/cleanup-markdownreader-registrations.sh --apply --keep /path/to/MarkdownReader.app
#
set -euo pipefail

APP_BUNDLE_IDENTIFIER="com.taojiachun.MarkdownReader"
QUICK_LOOK_BUNDLE_IDENTIFIER="com.taojiachun.MarkdownReader.QuickLookPreview"
QUICK_LOOK_RELATIVE_PATH="Contents/PlugIns/MarkdownReaderQuickLook.appex"
LAUNCH_SERVICES_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PLUGINKIT="/usr/bin/pluginkit"
KEEP_APP="/Applications/MarkdownReader.app"
APPLY=false

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      APPLY=true
      shift
      ;;
    --keep)
      if [ "$#" -lt 2 ]; then
        echo "--keep requires a MarkdownReader app path." >&2
        exit 2
      fi
      KEEP_APP="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run scripts/cleanup-markdownreader-registrations.sh --help for usage." >&2
      exit 2
      ;;
  esac
done

if [ ! -x "$LAUNCH_SERVICES_REGISTER" ]; then
  echo "Launch Services registration tool not found: $LAUNCH_SERVICES_REGISTER" >&2
  exit 1
fi

if [ ! -x "$PLUGINKIT" ]; then
  echo "PlugInKit registration tool not found: $PLUGINKIT" >&2
  exit 1
fi

if [ ! -d "$KEEP_APP" ]; then
  echo "The app to preserve does not exist: $KEEP_APP" >&2
  echo "Use --keep /path/to/MarkdownReader.app to select another copy." >&2
  exit 1
fi

KEEP_APP="$(cd "$KEEP_APP" && pwd -P)"
KEEP_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleIdentifier' \
  "$KEEP_APP/Contents/Info.plist" 2>/dev/null || true)"

if [ "$KEEP_APP_IDENTIFIER" != "$APP_BUNDLE_IDENTIFIER" ]; then
  echo "The app selected by --keep has an unexpected bundle identifier:" >&2
  echo "  $KEEP_APP" >&2
  echo "Expected $APP_BUNDLE_IDENTIFIER, found ${KEEP_APP_IDENTIFIER:-none}." >&2
  exit 1
fi

if ! REGISTERED_APPS="$(/usr/bin/osascript -l JavaScript - <<'JXA'
ObjC.import('AppKit')

function run() {
    const urls = $.NSWorkspace.sharedWorkspace.URLsForApplicationsWithBundleIdentifier(
        'com.taojiachun.MarkdownReader'
    )
    return urls.js.map(function (url) {
        return ObjC.unwrap(url.path)
    }).join('\n')
}
JXA
)"; then
  echo "Unable to query registered MarkdownReader applications." >&2
  exit 1
fi

if ! REGISTERED_PROVIDERS="$("$PLUGINKIT" \
  -m \
  -A \
  -D \
  -vvv \
  -p com.apple.quicklook.preview \
  -i "$QUICK_LOOK_BUNDLE_IDENTIFIER")"; then
  echo "Unable to query registered MarkdownReader Quick Look providers." >&2
  exit 1
fi

DUPLICATE_APPS=()
while IFS= read -r APP_PATH; do
  [ -n "$APP_PATH" ] || continue
  if [ -d "$APP_PATH" ]; then
    APP_PATH="$(cd "$APP_PATH" && pwd -P)"
  fi
  [ "$APP_PATH" != "$KEEP_APP" ] || continue
  DUPLICATE_APPS+=("$APP_PATH")
done <<< "$REGISTERED_APPS"

KEEP_PROVIDER="$KEEP_APP/$QUICK_LOOK_RELATIVE_PATH"
DUPLICATE_PROVIDERS=()
while IFS= read -r PROVIDER_PATH; do
  [ -n "$PROVIDER_PATH" ] || continue
  if [ -d "$PROVIDER_PATH" ]; then
    PROVIDER_PATH="$(cd "$PROVIDER_PATH" && pwd -P)"
  fi
  [ "$PROVIDER_PATH" != "$KEEP_PROVIDER" ] || continue
  DUPLICATE_PROVIDERS+=("$PROVIDER_PATH")
done < <(printf '%s\n' "$REGISTERED_PROVIDERS" \
  | sed -n 's/^[[:space:]]*Path = //p')

echo "Keeping:"
echo "  $KEEP_APP"
echo
echo "Duplicate Launch Services app registrations: ${#DUPLICATE_APPS[@]}"
if [ "${#DUPLICATE_APPS[@]}" -gt 0 ]; then
  for APP_PATH in "${DUPLICATE_APPS[@]}"; do
    echo "  $APP_PATH"
  done
fi

echo
echo "Duplicate Quick Look provider registrations: ${#DUPLICATE_PROVIDERS[@]}"
if [ "${#DUPLICATE_PROVIDERS[@]}" -gt 0 ]; then
  for PROVIDER_PATH in "${DUPLICATE_PROVIDERS[@]}"; do
    echo "  $PROVIDER_PATH"
  done
fi

if [ "${#DUPLICATE_APPS[@]}" -eq 0 ] \
  && [ "${#DUPLICATE_PROVIDERS[@]}" -eq 0 ]; then
  echo
  echo "No duplicate MarkdownReader registrations were found."
  exit 0
fi

if [ "$APPLY" = false ]; then
  echo
  echo "Dry run only; no registrations were changed."
  echo "Run scripts/cleanup-markdownreader-registrations.sh --apply to unregister these duplicates."
  exit 0
fi

echo
for PROVIDER_PATH in "${DUPLICATE_PROVIDERS[@]}"; do
  echo "Unregistering Quick Look provider: $PROVIDER_PATH"
  "$PLUGINKIT" -r "$PROVIDER_PATH"
done

for APP_PATH in "${DUPLICATE_APPS[@]}"; do
  echo "Unregistering app: $APP_PATH"
  "$LAUNCH_SERVICES_REGISTER" -u "$APP_PATH"
done

echo "Refreshing the preserved app registration."
"$LAUNCH_SERVICES_REGISTER" -f "$KEEP_APP"
if [ -d "$KEEP_PROVIDER" ]; then
  "$PLUGINKIT" -a "$KEEP_PROVIDER"
fi

/usr/bin/qlmanage -r cache >/dev/null 2>&1 || true

echo
echo "Cleanup complete. No app bundles were deleted."
echo "Finder may retain its old Open With menu until Finder is relaunched or you log out."
