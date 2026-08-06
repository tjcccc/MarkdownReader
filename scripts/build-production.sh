#!/usr/bin/env bash
#
# Create a verified Release build and a ZIP suitable for local distribution.
# This script does not notarize the app; public distribution still requires a
# Developer ID certificate and Apple's notarization service.
#
# Usage:
#   scripts/build-production.sh
#   scripts/build-production.sh --skip-tests
#
set -euo pipefail

SCHEME="MarkdownReader"
PROJECT="MarkdownReader.xcodeproj"
CONFIGURATION="Release"
BUILD_ARCHITECTURE="$(uname -m)"
DESTINATION="platform=macOS,arch=$BUILD_ARCHITECTURE"
DERIVED_DATA_PATH=".build"
DIST_DIRECTORY="dist"
QUICK_LOOK_BUNDLE="MarkdownReaderQuickLook.appex"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SKIP_TESTS=false
case "${1:-}" in
  "") ;;
  --skip-tests) SKIP_TESTS=true ;;
  -h|--help)
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Run scripts/build-production.sh --help for usage." >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "Only one option may be supplied." >&2
  exit 2
fi

if [ "$SKIP_TESTS" = false ]; then
  echo "==> Running unit tests…"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -only-testing:MarkdownReaderTests \
    -quiet \
    test
fi

echo "==> Building $SCHEME ($CONFIGURATION)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -quiet \
  clean build

settings="$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -showBuildSettings 2>/dev/null)"

get_build_setting() {
  printf '%s\n' "$settings" | sed -n "s/^[[:space:]]*$1 = //p" | head -1
}

TARGET_BUILD_DIR="$(get_build_setting TARGET_BUILD_DIR)"
FULL_PRODUCT_NAME="$(get_build_setting FULL_PRODUCT_NAME)"
APP_PATH="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
QUICK_LOOK_PATH="$APP_PATH/Contents/PlugIns/$QUICK_LOOK_BUNDLE"

if [ ! -d "$APP_PATH" ]; then
  echo "Expected app was not produced: $APP_PATH" >&2
  exit 1
fi

if [ ! -d "$QUICK_LOOK_PATH" ]; then
  echo "Quick Look extension is missing: $QUICK_LOOK_PATH" >&2
  exit 1
fi

APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
DOCUMENT_UTI="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleDocumentTypes:0:LSItemContentTypes:0' \
  "$APP_INFO_PLIST")"
SHORT_EXTENSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:0' \
  "$APP_INFO_PLIST")"
LONG_EXTENSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:1' \
  "$APP_INFO_PLIST")"

if [ "$DOCUMENT_UTI" != "net.daringfireball.markdown" ] \
  || [ "$SHORT_EXTENSION" != "md" ] \
  || [ "$LONG_EXTENSION" != "markdown" ]; then
  echo "The app has invalid Markdown Launch Services metadata." >&2
  exit 1
fi

echo "==> Verifying app and embedded extension signatures…"
codesign --verify --deep --strict "$APP_PATH"
codesign --verify --strict "$QUICK_LOOK_PATH"

VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$APP_INFO_PLIST")"
ARCHIVE_NAME="MarkdownReader-$VERSION-macOS-$BUILD_ARCHITECTURE.zip"
ARCHIVE_PATH="$DIST_DIRECTORY/$ARCHIVE_NAME"

mkdir -p "$DIST_DIRECTORY"
STAGING_DIRECTORY="$(mktemp -d "$DIST_DIRECTORY/.production.XXXXXX")"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT

echo "==> Packaging ${ARCHIVE_NAME}…"
ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$APP_PATH" \
  "$STAGING_DIRECTORY/$ARCHIVE_NAME"
mv -f "$STAGING_DIRECTORY/$ARCHIVE_NAME" "$ARCHIVE_PATH"
unzip -tq "$ARCHIVE_PATH"

CHECKSUM="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
SIGNATURE="$(codesign -d --verbose=2 "$APP_PATH" 2>&1 | sed -n 's/^Signature=//p')"

echo
echo "Production build complete."
echo "  App:     $APP_PATH"
echo "  Archive: $ARCHIVE_PATH"
echo "  SHA-256: $CHECKSUM"

if [ "$SIGNATURE" = "adhoc" ]; then
  echo
  echo "Note: this app has an ad-hoc signature. It is suitable for local testing,"
  echo "but public distribution requires Developer ID signing and notarization."
fi
