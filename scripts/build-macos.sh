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

echo "Smoke test: ready R002 project through the real refresh pipeline"
FIX="$(mktemp -d)"
cleanup_fix() { rm -rf "$FIX"; }
trap cleanup_fix EXIT
REAL_HOME="$FIX/real-home"
LINK_HOME="$FIX/handoff-link"
REPO_FIX="$FIX/agents-bar"
PROJ="$FIX/proj"
mkdir -p "$REAL_HOME" "$REPO_FIX"
ln -s "$REAL_HOME" "$LINK_HOME"
git init -q "$REPO_FIX"
git -C "$REPO_FIX" config user.email "chatbar@example.com"
git -C "$REPO_FIX" config user.name "ChatBar"
printf 'print(1)\n' > "$REPO_FIX/main.py"
git -C "$REPO_FIX" add main.py
git -C "$REPO_FIX" commit -q -m init
CHATBAR_HOME="$LINK_HOME" CHATBAR_NO_NOTIFY=1 CHATBAR_NO_OPEN=1 CHATBAR_NO_REWRITE=1 \
  "$ROOT/cli/chatbar" project add --name agents-bar --repo "$REPO_FIX" --handoff "$PROJ" >/dev/null
printf '2\n' > "$PROJ/round"
printf 'none\n' > "$PROJ/pack-state"
printf '0\n' > "$PROJ/pack-round"
printf 'none\n' > "$PROJ/inbox-state"
printf '0\n' > "$PROJ/inbox-round"
OUT_DIR="$(CHATBAR_HOME="$LINK_HOME" CHATBAR_NO_NOTIFY=1 CHATBAR_NO_OPEN=1 CHATBAR_NO_REWRITE=1 \
  "$ROOT/cli/chatbar" folders | sed -n 's/^outbox_dir=//p')"
if [[ -z "$OUT_DIR" || ! -d "$OUT_DIR" ]]; then
  echo "fixture outbox missing: ${OUT_DIR}" >&2
  exit 1
fi
printf 'ready round\n' > "$OUT_DIR/to_chatgpt_R002.md"
if [[ ! -f "$OUT_DIR/给GPT的话.txt" && ! -f "$OUT_DIR/opener.txt" && ! -f "$OUT_DIR/opener.md" ]]; then
  printf 'opener\n' > "$OUT_DIR/给GPT的话.txt"
fi
DUMP_OUT="$FIX/dump.txt"
DUMP_ERR="$FIX/dump.err"
CHATBAR_HOME="$LINK_HOME" "$APP/Contents/MacOS/ChatBar" --self-test --dump-state >"$DUMP_OUT" 2>"$DUMP_ERR" &
DUMP_PID=$!
DUMP_CODE=1
DUMP_DONE=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$DUMP_PID" 2>/dev/null; then
    set +e
    wait "$DUMP_PID"
    DUMP_CODE=$?
    set -e
    DUMP_DONE=1
    break
  fi
  sleep 0.5
done
if [[ "$DUMP_DONE" -ne 1 ]]; then
  kill "$DUMP_PID" 2>/dev/null || true
  wait "$DUMP_PID" 2>/dev/null || true
  echo "dump-state did not finish within 5s" >&2
  cat "$DUMP_ERR" >&2 || true
  exit 1
fi
if [[ "$DUMP_CODE" -ne 0 ]]; then
  echo "dump-state failed ($DUMP_CODE)" >&2
  cat "$DUMP_OUT" "$DUMP_ERR" >&2 || true
  exit 1
fi
grep -F 'project: agents-bar' "$DUMP_OUT"
grep -F '现在：①' "$DUMP_OUT"
grep -F 'to_chatgpt_R002.md' "$DUMP_OUT"
echo "dump-state ok"

rm -f "$ROOT/dist/ChatBar-macos-unsigned.zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/ChatBar-macos-unsigned.zip"
echo "Built $APP"
