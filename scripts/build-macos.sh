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
cp "$ROOT/VERSION" "$APP/Contents/Resources/VERSION"
mkdir -p "$APP/Contents/Resources/assets/brand"
cp "$ROOT/assets/brand/menu-template.tiff" "$APP/Contents/Resources/assets/brand/"
cp "$ROOT/assets/brand/ChatBar.icns" "$APP/Contents/Resources/"
cp "$ROOT/assets/brand/R004_LICENSE.txt" "$APP/Contents/Resources/assets/brand/"
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

echo "Smoke test: packaged native menu, one round"
FIX="$(mktemp -d)"
cleanup_fix() { rm -rf "$FIX"; }
trap cleanup_fix EXIT
REAL_HOME="$FIX/real-home"
LINK_HOME="$FIX/handoff-link"
REPO_FIX="$FIX/agents-bar"
PROJ="$FIX/proj"
CLI="$APP/Contents/Resources/cli/chatbar"
NATIVE="$APP/Contents/MacOS/ChatBar"
export CHATBAR_HOME="$LINK_HOME"
export CHATBAR_DOWNLOADS="$FIX/Downloads 临时"
export CHATBAR_NO_NOTIFY=1 CHATBAR_NO_OPEN=1 CHATBAR_NO_CLIPBOARD=1 CHATBAR_NO_REWRITE=1 CHATBAR_SWEEP_SETTLE=0
export CHATBAR_BIN=
mkdir -p "$REAL_HOME" "$REPO_FIX" "$CHATBAR_DOWNLOADS"
ln -s "$REAL_HOME" "$LINK_HOME"
git init -q "$REPO_FIX"
git -C "$REPO_FIX" -c user.email=chatbar@example.com -c user.name=ChatBar commit --allow-empty -qm init

show_step() {
  local step="$1" title="$2" label="$3" project="$4" round="$5" file_suffix="${6:-}"
  local dump
  dump="$("$NATIVE" --self-test --dump-state)"
  grep -Fxq "project: $project" <<< "$dump"
  grep -Fxq "round: $round" <<< "$dump"
  grep -Fxq "step: $step" <<< "$dump"
  grep -Fxq "title_short: $title" <<< "$dump"
  grep -Fxq "action_label: $label" <<< "$dump"
  if [[ -n "$file_suffix" ]]; then
    local file
    file="$(sed -n 's/^file: //p' <<< "$dump")"
    [[ "$file" == /*"$file_suffix" ]]
  fi
  printf '%s | %s | %s\n' "$step" "$title" "$label"
}

show_step no_project 添加项目 还没有项目 "" 0
"$CLI" project add --name agents-bar --repo "$REPO_FIX" --handoff "$PROJ" >/dev/null
show_step need_pack 待打包 等待本地助手打包 agents-bar 1
printf '2\n' > "$PROJ/round"
"$CLI" pack --quiet
show_step copy 新任务 '复制给 g 的话' agents-bar 2 /to_chatgpt_R002.md
"$CLI" step advance agents-bar 2 copy
show_step paste 粘贴 我已粘贴 agents-bar 2 /to_chatgpt_R002.md
"$CLI" step back agents-bar 2 paste
show_step copy 复制 '复制给 g 的话' agents-bar 2 /to_chatgpt_R002.md
"$CLI" step advance agents-bar 2 copy
"$CLI" step advance agents-bar 2 paste
show_step drag 拖文件 '拖文件 · to_chatgpt_R002.md' agents-bar 2 /to_chatgpt_R002.md
"$CLI" step advance agents-bar 2 drag >/dev/null
show_step send 拖文件 我已拖入并发送 agents-bar 2 /to_chatgpt_R002.md
"$CLI" step advance agents-bar 2 send
show_step wait '等 g' 打开下载文件夹 agents-bar 2 /agents-bar_round2_reply.zip

"$CLI" auto on >/dev/null
"$CLI" auto on --project agents-bar >/dev/null
printf 'Native smoke-test reply\n' > "$FIX/reply.md"
zip -q -j "$CHATBAR_DOWNLOADS/agents-bar_round2_reply.zip" "$FIX/reply.md"
"$CLI" sweep --auto >/dev/null
show_step received 新任务 收好了 agents-bar 2 /inbox/NEW.json
"$CLI" step advance agents-bar 2 received >/dev/null
show_step received 收好了 收好了 agents-bar 2 /inbox/NEW.json
printf '{"result":"native smoke-test result"}\n' > "$PROJ/agent-result.json"
show_step result 新任务 查看结果 agents-bar 3 /agent-result.json
"$CLI" step advance agents-bar 3 result >/dev/null
show_step received 收好了 收好了 agents-bar 2 /inbox/NEW.json
echo "native one-round smoke test ok"

rm -f "$ROOT/dist/ChatBar-macos-unsigned.zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/ChatBar-macos-unsigned.zip"
echo "Built $APP"
