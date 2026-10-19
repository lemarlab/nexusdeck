#!/bin/zsh
# Builds NexusDeckAudio.driver (universal) and optionally installs it.
#   ./build.sh            build only
#   ./build.sh install    build + install to /Library/Audio/Plug-Ins/HAL + restart coreaudiod (needs admin)
set -e
cd "$(dirname "$0")"
OUT=build/NexusDeckAudio.driver
rm -rf build
mkdir -p "$OUT/Contents/MacOS"
cp Info.plist "$OUT/Contents/Info.plist"
clang -bundle -O2 -Wall -Wextra -arch arm64 -mmacosx-version-min=12.0 \
  -framework CoreAudio -framework CoreFoundation \
  -o "$OUT/Contents/MacOS/NexusDeckAudio" NexusDeckAudio.c
codesign --force --sign "${SIGN_IDENTITY:--}" --timestamp=none "$OUT"
echo "Built $OUT"

if [[ "$1" == "install" ]]; then
  # Root cannot read ~/Desktop (privacy protection), so stage in /tmp first.
  STAGE=/tmp/NexusDeckAudio.driver
  rm -rf "$STAGE" && ditto "$OUT" "$STAGE"
  osascript -e "do shell script \"rm -rf /Library/Audio/Plug-Ins/HAL/NexusDeckAudio.driver && ditto '$STAGE' /Library/Audio/Plug-Ins/HAL/NexusDeckAudio.driver && chown -R root:wheel /Library/Audio/Plug-Ins/HAL/NexusDeckAudio.driver && killall coreaudiod\" with administrator privileges"
  rm -rf "$STAGE"
  echo "Installed"
fi
