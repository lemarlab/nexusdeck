#!/bin/zsh
# Builds NexusDeck (Release, Apple Silicon) and packages it as dist/NexusDeck-<version>.dmg
#   ./scripts/make-dmg.sh
set -e
cd "$(dirname "$0")/.."

xcodebuild -project NexusDeck.xcodeproj -scheme NexusDeck -configuration Release \
  -derivedDataPath build ARCHS=arm64 ONLY_ACTIVE_ARCH=NO clean build | grep -E "error:|BUILD (SUCC|FAIL)" || true

APP=build/Build/Products/Release/NexusDeck.app
[[ -d "$APP" ]] || { echo "Build fallita"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/NexusDeck.app"
ln -s /Applications "$STAGE/Applications"
xattr -cr "$STAGE/NexusDeck.app"

mkdir -p dist
DMG=dist/NexusDeck-$VERSION.dmg
rm -f "$DMG"
hdiutil create -volname "NexusDeck $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
rm -rf "$STAGE"
shasum -a 256 "$DMG"
echo "Creato $DMG"
