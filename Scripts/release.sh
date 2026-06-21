#!/usr/bin/env bash
#
# Build → sign (Developer ID, hardened runtime) → DMG → notarize → staple.
# Produces dist/OpenSuperWhisper-<VERSION>.dmg, ready to attach to a GitHub release.
#
# Required env:
#   DEVELOPER_ID    e.g. "Developer ID Application: Maxim Costa (TEAMID)"
#   NOTARY_PROFILE  notarytool keychain profile (see docs/DISTRIBUTION.md)
#   VERSION         e.g. 0.3.0
# Optional:
#   SCHEME (default OpenSuperWhisper), APP_NAME (default OpenSuperWhisper)
#
# NOTE: this is the starting-point pipeline. It must be validated once a real Developer ID
# certificate exists — in particular the bundled dylibs (libwhisper / libomp /
# libautocorrect_swift) must each be Developer-ID-signed for notarization to pass.
set -euo pipefail

: "${DEVELOPER_ID:?set DEVELOPER_ID (Developer ID Application identity)}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE (notarytool keychain profile)}"
: "${VERSION:?set VERSION}"
SCHEME="${SCHEME:-OpenSuperWhisper}"
APP_NAME="${APP_NAME:-OpenSuperWhisper}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DIST="$ROOT/dist"
BUILD="$ROOT/build-release"
rm -rf "$DIST" "$BUILD"
mkdir -p "$DIST"

echo "==> Building native dependencies (libwhisper, autocorrect, libomp)…"
./run.sh build

echo "==> Building Release with Xcode…"
xcodebuild -scheme "$SCHEME" -configuration Release -derivedDataPath "$BUILD" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  build

APP="$BUILD/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "App not found at $APP" >&2; exit 1; }

echo "==> Signing bundled dylibs + app (hardened runtime)…"
find "$APP/Contents" -name "*.dylib" -print0 | while IFS= read -r -d '' lib; do
  codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$lib"
done
codesign --force --deep --timestamp --options runtime --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Packaging DMG…"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

echo "==> Notarizing (uploads to Apple and waits)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Done."
shasum -a 256 "$DMG"
