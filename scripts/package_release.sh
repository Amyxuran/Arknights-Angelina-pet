#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_DIR="$ROOT/dist/酸橙信使.app"
PLIST="$ROOT/App/Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")}"
RELEASE_DIR="$ROOT/dist/release"
ASSET_NAME="LimeCourier-${VERSION}-macos-arm64.zip"
ASSET_PATH="$RELEASE_DIR/$ASSET_NAME"

required_variables=(
  SIGN_IDENTITY
  APPLE_ID
  APPLE_TEAM_ID
  APPLE_APP_PASSWORD
)
for variable in $required_variables; do
  if [[ -z "${(P)variable:-}" ]]; then
    print -u2 "Missing required environment variable: $variable"
    exit 1
  fi
done

VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
SIGN_IDENTITY="$SIGN_IDENTITY" \
  "$ROOT/scripts/build_app.sh"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ASSET_PATH"
xcrun notarytool submit "$ASSET_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

rm -f "$ASSET_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ASSET_PATH"
print "$ASSET_PATH"
