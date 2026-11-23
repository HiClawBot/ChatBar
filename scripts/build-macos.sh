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
BIN_PATH="$(swift build -c release --arch arm64 --package-path "$BIN_DIR" --show-bin-path)"
BUILT="${BIN_PATH}/ChatBar"
RESOURCE_BUNDLE="${BIN_PATH}/ChatBar_ChatBarApp.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  RESOURCE_BUNDLE="$(find "$BIN_PATH" -maxdepth 2 -type d -name 'ChatBar_ChatBarApp.bundle' -print -quit)"
fi
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "missing ChatBar_ChatBarApp.bundle next to ${BUILT}" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILT" "$APP/Contents/MacOS/ChatBar"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/ChatBar_ChatBarApp.bundle"
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

if [[ ! -d "$APP/Contents/Resources/ChatBar_ChatBarApp.bundle" ]]; then
  echo "ChatBar.app is missing Contents/Resources/ChatBar_ChatBarApp.bundle" >&2
  exit 1
fi

codesign --force --sign - --identifier bot.hiclaw.chatbar "$APP"
codesign --verify --verbose=2 "$APP"

echo "Smoke test: load localized strings"
"$APP/Contents/MacOS/ChatBar" --self-test

rm -f "$ROOT/dist/ChatBar-macos-unsigned.zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/ChatBar-macos-unsigned.zip"
echo "Built $APP"
