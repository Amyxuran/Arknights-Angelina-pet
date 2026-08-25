#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/酸橙信使.app"
CONTENTS="$APP_DIR/Contents"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

cd "$ROOT"
swift build -c release --scratch-path "$BUILD_DIR"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$CONTENTS/Resources/UI素材"
cp "$BUILD_DIR/release/LimeCourier" "$CONTENTS/MacOS/LimeCourier"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/App/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp -R "$ROOT/GIF" "$CONTENTS/Resources/GIF"
cp "$ROOT/UI素材/22.png" "$CONTENTS/Resources/UI素材/22.png"
cp "$ROOT/UI素材/23.png" "$CONTENTS/Resources/UI素材/23.png"
cp "$ROOT/UI素材/7.png" "$CONTENTS/Resources/UI素材/7.png"

if [[ -n "$VERSION" ]]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
fi

chmod +x "$CONTENTS/MacOS/LimeCourier"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_DIR"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"
