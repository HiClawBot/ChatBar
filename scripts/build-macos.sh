#!/bin/bash
# Build an ad-hoc signed ChatBar.app for Apple silicon. No Apple Developer Program account.
# The app is not notarized. See README for the first-open steps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ChatBar.app"
BIN_DIR="$ROOT/macos/ChatBar"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "scripts/build-macos.sh runs on macOS." >&2
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This build targets Apple silicon (arm64), without Rosetta." >&2
  exit 1
fi

swift build -c release --arch arm64 --package-path "$BIN_DIR" --product ChatBar
BUILT="$(swift build -c release --arch arm64 --package-path "$BIN_DIR" --show-bin-path)/ChatBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILT" "$APP/Contents/MacOS/ChatBar"
cp "$BIN_DIR/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$BIN_DIR/Sources/ChatBarApp/Resources/zh-Hans.lproj" "$APP/Contents/Resources/"
cp -R "$BIN_DIR/Sources/ChatBarApp/Resources/en.lproj" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/cli" "$APP/Contents/Resources/templates"
cp -R "$ROOT/cli/." "$APP/Contents/Resources/cli/"
cp -R "$ROOT/templates/." "$APP/Contents/Resources/templates/"
if [[ -d "$ROOT/hooks" ]]; then
  mkdir -p "$APP/Contents/Resources/hooks"
  cp -R "$ROOT/hooks/." "$APP/Contents/Resources/hooks/"
fi
chmod +x "$APP/Contents/MacOS/ChatBar" "$APP/Contents/Resources/cli/chatbar"
find "$APP/Contents/Resources/cli" -name '*.sh' -exec chmod +x {} +

codesign --force --sign - --identifier bot.hiclaw.chatbar "$APP"
codesign --verify --verbose=2 "$APP"

rm -f "$ROOT/dist/ChatBar-macos-unsigned.zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/ChatBar-macos-unsigned.zip"
echo "Built $APP"
