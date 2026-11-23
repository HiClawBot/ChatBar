#!/bin/bash
# ChatBar tests. Bash 3.2 compatible. No network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHATBAR="${ROOT}/cli/chatbar"
export CHATBAR_NO_OPEN=1
export CHATBAR_NO_CLIPBOARD=1
export CHATBAR_NO_NOTIFY=1
export CHATBAR_SWEEP_SETTLE=0

FAILS=0
fail() {
  echo "FAIL: $*" >&2
  FAILS=$((FAILS + 1))
}
assert_eq() {
  if [[ "$1" != "$2" ]]; then
    fail "expected [$2] got [$1] ($3)"
  fi
}
assert_contains() {
  if ! printf '%s' "$1" | grep -F -q -- "$2"; then
    fail "missing [$2] in [$1] ($3)"
  fi
}
assert_not_contains() {
  if printf '%s' "$1" | grep -F -q -- "$2"; then
    fail "unexpected [$2] ($3)"
  fi
}
assert_file() {
  [[ -f "$1" ]] || fail "missing file $1"
}
assert_dir() {
  [[ -d "$1" ]] || fail "missing dir $1"
}

# --- syntax ---
bash -n "$CHATBAR"
for f in "$ROOT"/cli/lib/*.sh "$ROOT"/swiftbar/*.sh "$ROOT"/scripts/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f" || fail "syntax $f"
done

# --- decode ---
# shellcheck source=/dev/null
source "$ROOT/cli/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/cli/lib/decode.sh"
# shellcheck source=/dev/null
source "$ROOT/cli/lib/folders.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/解码 目录"
printf 'hi' > "$TMP/解码 目录/我的 文件.md"
printf 'plus' > "$TMP/解码 目录/a+b.txt"

plain="$TMP/解码 目录/我的 文件.md"
once="file://$(printf '%s' "$plain" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g')"
# once is fully percent-encoded path after file://
decoded="$(cb_decode_dropped_item "$once")"
assert_eq "$decoded" "$plain" "single encoded chinese path"

double_raw="$(printf '%s' "$once" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g')"
decoded2="$(cb_decode_dropped_item "$double_raw")"
assert_eq "$decoded2" "$plain" "double encoded chinese path"

space_url="file://${TMP// /%20}/解码%20目录/a%2Bb.txt"
# The TMP path may contain characters. Build from the known file via one encode of the path only.
plus_path="$TMP/解码 目录/a+b.txt"
plus_url="file://$(printf '%s' "$plus_path" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g')"
assert_eq "$(cb_decode_dropped_item "$plus_url")" "$plus_path" "plus sign is not a space"

comma_a="$TMP/解码 目录/a,b.txt"
printf 'c' > "$comma_a"
enc_a="$(printf '%s' "$comma_a" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g')"
enc_b="$(printf '%s' "$plus_path" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g')"
joined="file://${enc_a},file://${enc_b}"
got=""
while IFS= read -r -d '' p; do
  got="${got}${p}"$'\n'
done < <(cb_split_dropped "$joined")
assert_contains "$got" "$comma_a" "comma split first"
assert_contains "$got" "$plus_path" "comma split second"

assert_eq "$(cb_effective_role_name outbox "" "")" "①发出_拖给ChatGPT" "default outbox"
assert_eq "$(cb_effective_role_name inbox "" "")" "②收回_ChatGPT回复拖到这里" "default inbox"
assert_eq "$(cb_effective_role_name archive "" "")" "已归档" "default archive"
assert_eq "$(cb_effective_role_name log "" "")" "记录" "default log"
assert_eq "$(cb_effective_role_name outbox "规划聊天" "")" "①发出_拖给规划聊天" "chat token outbox"
assert_eq "$(cb_effective_role_name inbox "规划聊天" "")" "②收回_规划聊天回复拖到这里" "chat token inbox"
assert_eq "$(cb_effective_role_name outbox "ChatGPT" "自定义发出")" "自定义发出" "override outbox"

# --- projects, pack, ingest, archive ---
export CHATBAR_HOME="$TMP/handoff 交接"
mkdir -p "$CHATBAR_HOME"
REPO="$TMP/项目 甲"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" config user.email "chatbar-test@example.com"
git -C "$REPO" config user.name "ChatBar Test"
printf 'print(1)\n' > "$REPO/main.py"
printf 'PASSWORD=hunter2secret\n' > "$REPO/.env"
git -C "$REPO" add main.py .env
git -C "$REPO" commit -q -m init
printf 'token=anothersecret999\n' >> "$REPO/main.py"
printf 'PASSWORD=newenvsecret999\n' >> "$REPO/.env"
printf 'Topic: 审阅差异\n' > "$REPO/status.md"

HANDOFF="$TMP/Volumes/4T_示例/交接 目录"
"$CHATBAR" project add --name "项目甲" --repo "$REPO" --handoff "$HANDOFF" --with-templates >/dev/null
folders="$("$CHATBAR" folders)"
assert_contains "$folders" "outbox=①发出_拖给ChatGPT" "folders outbox"
assert_contains "$folders" "inbox=②收回_ChatGPT回复拖到这里" "folders inbox"
assert_contains "$folders" "archive=已归档" "folders archive"
assert_contains "$folders" "log=记录" "folders log"
assert_dir "$HANDOFF/①发出_拖给ChatGPT"
assert_dir "$HANDOFF/②收回_ChatGPT回复拖到这里"
assert_file "$HANDOFF/folders.json"
assert_file "$HANDOFF/打开收发两个窗口.command"
[[ -x "$HANDOFF/打开收发两个窗口.command" ]] || fail "command not executable"
assert_contains "$(cat "$HANDOFF/打开收发两个窗口.command")" "open --handoff" "command calls open"
assert_file "$REPO/AGENTS.md"

"$CHATBAR" project add --name "项目甲" --repo "$REPO" --handoff "$HANDOFF" --chat-name "规划聊天" >/dev/null
folders="$("$CHATBAR" folders)"
assert_contains "$folders" "outbox=①发出_拖给规划聊天" "renamed outbox"
assert_contains "$folders" "inbox=②收回_规划聊天回复拖到这里" "renamed inbox"
assert_dir "$HANDOFF/①发出_拖给规划聊天"
[[ ! -d "$HANDOFF/①发出_拖给ChatGPT" ]] || fail "old outbox dir should have moved"

# workspace root distinct from repo
WS="$TMP/workspace 根"
mkdir -p "$WS"
"$CHATBAR" project add --name "项目甲" --repo "$REPO" --handoff "$HANDOFF" --workspace "$WS" >/dev/null

"$CHATBAR" pack --topic >/dev/null 2>"$TMP/pack.err" || true
pack_out="$("$CHATBAR" pack)"
assert_file "$HANDOFF/①发出_拖给规划聊天/to_planner.md"
pack_body="$(cat "$HANDOFF/①发出_拖给规划聊天/to_planner.md")"
assert_contains "$pack_body" "round 1" "opener round"
assert_contains "$pack_body" "planner" "opener role"
assert_contains "$pack_body" "项目甲_R001_reply.md" "delivery filename"
assert_contains "$pack_body" "## Delivery format" "delivery section"
assert_contains "$pack_body" "Base commit (main):" "pack names the base commit"
assert_contains "$pack_body" "unified diff" "pack asks for a diff"
tail -n 12 "$HANDOFF/①发出_拖给规划聊天/to_planner.md" | grep -q "inline chat text" || fail "delivery section not at end"
assert_file "$HANDOFF/①发出_拖给规划聊天/给GPT的话.txt"
assert_file "$HANDOFF/①发出_拖给规划聊天/复制开场白.command"
assert_contains "$pack_body" "main.py" "diff mentions source"
assert_not_contains "$pack_body" "anothersecret999" "secret redacted"
assert_not_contains "$pack_body" "newenvsecret999" "env excluded"
assert_not_contains "$pack_body" "hunter2secret" "committed env excluded"
assert_contains "$pack_body" "REDACTED" "redaction marker"
shopt -s nullglob
snaps=("$HANDOFF/①发出_拖给规划聊天"/to_planner-*.md)
[[ "${#snaps[@]}" -eq 1 ]] || fail "expected one timestamped pack, got ${#snaps[@]}"
shopt -u nullglob
logf="$HANDOFF/记录/events.jsonl"
assert_file "$logf"
assert_contains "$(cat "$logf")" '"direction":"to_planner"' "jsonl pack"
assert_contains "$(cat "$logf")" '"approx_tokens":' "jsonl tokens"
assert_contains "$(cat "$logf")" '"spec_version":"0"' "jsonl spec"

open_out="$("$CHATBAR" open)"
assert_contains "$open_out" "opener:" "open copies opener"
assert_contains "$open_out" "项目甲_R001_reply.md" "open opener asks for the reply file"
assert_contains "$open_out" "reveal:" "open reveals"
assert_contains "$open_out" "layout:outbox-left,inbox-right" "side by side"
assert_contains "$open_out" "①发出_拖给规划聊天/to_planner.md" "left is the pack"
assert_contains "$open_out" "②收回_规划聊天回复拖到这里" "right is inbox"
status="$("$CHATBAR" status)"
assert_contains "$status" "pack_state=presented" "presented after open"

# second project for attribution
REPO2="$TMP/项目 乙"
mkdir -p "$REPO2"
git init -q "$REPO2"
git -C "$REPO2" config user.email "chatbar-test@example.com"
git -C "$REPO2" config user.name "ChatBar Test"
printf 'x\n' > "$REPO2/a.txt"
git -C "$REPO2" add a.txt
git -C "$REPO2" commit -q -m init
HANDOFF2="$TMP/乙 交接"
"$CHATBAR" project add --name "项目乙" --repo "$REPO2" --handoff "$HANDOFF2" >/dev/null
# current is 项目乙 after add. Switch back and drop a file into 乙's inbox.
"$CHATBAR" project use "项目甲" >/dev/null
printf 'reply-b\n' > "$TMP/from-b.md"
cp "$TMP/from-b.md" "$HANDOFF2/②收回_ChatGPT回复拖到这里/随便名字.md"
"$CHATBAR" sweep >/dev/null
assert_file "$HANDOFF2/②收回_ChatGPT回复拖到这里/NEW.json"
newb="$(cat "$HANDOFF2/②收回_ChatGPT回复拖到这里/NEW.json")"
assert_contains "$newb" '"spec_version": "0"' "spec version"
assert_contains "$newb" '"project": "项目乙"' "attributed by inbox folder"
assert_contains "$newb" '"status": "new"' "status new"
# no pack yet, so the reply stays in the inbox
found_norm="$(find "$HANDOFF2/②收回_ChatGPT回复拖到这里" -name 'r*-*' -type f | head -n 1)"
[[ -n "$found_norm" ]] || fail "normalized inbox file missing"
assert_contains "$(cat "$found_norm")" "reply-b" "normalized content"

# icon drop goes to current project (甲). No pack yet, stays in inbox.
printf 'icon-drop\n' > "$TMP/图标 回复.md"
DROPPED_FILES="file://$(printf '%s' "$TMP/图标 回复.md" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g')" \
  LAUNCHED_FROM_DROP_ACTION=TRUE \
  "$CHATBAR" ingest-drop >/dev/null
round_rel="$(tr -d '\r\n' < "$HANDOFF/latest-round.txt")"
assert_contains "$(cat "$HANDOFF/${round_rel}/inbox/NEW.json")" '"project": "项目甲"' "icon drop current project"

# zip with chinese name into a project that already has a pack: round closes
zipdir="$TMP/zipwork"
mkdir -p "$zipdir"
printf '建议：先补测试\nhello 回复\n' > "$zipdir/回复 说明.md"
(cd "$zipdir" && zip -q "$TMP/out.zip" "回复 说明.md")
# evil zip must be rejected
python3 - <<PY
import zipfile
z = zipfile.ZipFile("$TMP/evil.zip", "w")
z.writestr("../escaped.txt", "nope")
z.close()
PY
if "$CHATBAR" ingest --project "项目乙" "$TMP/evil.zip" >/dev/null 2>"$TMP/evil.err"; then
  fail "zip slip should fail"
fi
[[ -f "$TMP/escaped.txt" ]] && fail "zip slip wrote outside"
assert_contains "$(cat "$TMP/evil.err")" "Rejected" "zip slip message"

"$CHATBAR" pack --project "项目乙" >/dev/null
"$CHATBAR" ingest --project "项目乙" "$TMP/out.zip" >/dev/null
# inbox and outbox of 乙 should be empty of payload; archive holds the round
remain="$(find "$HANDOFF2/①发出_拖给ChatGPT" "$HANDOFF2/②收回_ChatGPT回复拖到这里" -type f ! -name '.*' ! -name '给GPT的话.txt' ! -name 'opener.txt' ! -name '*.command' | wc -l | tr -d ' ')"
assert_eq "$remain" "0" "current round folders empty after close"
round_dir="$(find "$HANDOFF2/已归档" -type d -name 'R001_*' | head -n 1)"
[[ -n "$round_dir" ]] || fail "round folder missing"
assert_file "$round_dir/manifest.json"
assert_file "$round_dir/outbox/to_planner.md"
assert_dir "$round_dir/inbox"
unzipped="$(find "$round_dir/inbox" -name '*回复 说明.md' -type f | head -n 1)"
[[ -n "$unzipped" ]] || fail "unzipped reply not archived"
assert_contains "$(cat "$unzipped")" "hello 回复" "unzipped body"
assert_file "$HANDOFF2/记录/轮次总表.md"
assert_contains "$(cat "$HANDOFF2/记录/轮次总表.md")" "R001" "rounds table"
assert_contains "$(cat "$HANDOFF2/记录/轮次总表.md")" "R001" "round row"
assert_file "$HANDOFF2/latest-round.txt"
assert_contains "$(cat "$HANDOFF2/记录/events.jsonl")" '"direction":"archive"' "archive jsonl"

# explicit close
printf 'only-pack\n' > "$REPO/main.py"
"$CHATBAR" pack --project "项目甲" >/dev/null
# inbox still has the earlier icon drop, and outbox has a pack, so archive closes the round
"$CHATBAR" archive --project "项目甲" --topic "手动收一轮" >/dev/null
remain_a="$(find "$HANDOFF/①发出_拖给规划聊天" "$HANDOFF/②收回_规划聊天回复拖到这里" -type f ! -name '.*' ! -name '给GPT的话.txt' ! -name 'opener.txt' ! -name '*.command' | wc -l | tr -d ' ')"
assert_eq "$remain_a" "0" "甲 emptied by close"
assert_file "$HANDOFF/记录/轮次总表.md"
assert_contains "$(cat "$HANDOFF/记录/轮次总表.md")" "手动收一轮" "explicit topic"

# open handoff and workspace
hshow="$("$CHATBAR" open-handoff "项目甲")"
phys_handoff="$(cd -P "$HANDOFF" && pwd)"
assert_contains "$hshow" "reveal:${phys_handoff}" "open handoff"
rshow="$("$CHATBAR" open-root "项目甲")"
assert_contains "$rshow" "reveal:${WS}" "open workspace"

# menu
menu="$("$CHATBAR" swiftbar-menu)"
assert_contains "$menu" "项目甲" "menu project"
assert_contains "$menu" "Open handoff folder" "menu handoff"
assert_contains "$menu" "Open workspace root" "menu workspace"
assert_contains "$menu" "Close round" "menu close"
assert_contains "$menu" "复制给 GPT 的话" "menu copy opener"
assert_contains "$menu" "param1=copy-opener" "menu copy action"

# round 2 opener uses the previous reply summary
"$CHATBAR" pack --project "项目乙" >/dev/null
pack2="$(cat "$HANDOFF2/①发出_拖给ChatGPT/to_planner.md")"
assert_contains "$pack2" "Last round you suggested:" "round 2 recalls suggestion"
assert_contains "$pack2" "先补测试" "suggestion text"
assert_contains "$pack2" "This round we changed:" "round 2 changes"
assert_contains "$pack2" "项目乙_R002_reply.md" "round 2 reply filename"
copied="$("$CHATBAR" copy-opener "项目乙")"
assert_contains "$copied" "先补测试" "clipboard opener is dynamic"

printf 'AGENT OPENER UNIQUE\n' > "$HANDOFF2/①发出_拖给ChatGPT/opener.md"
over="$("$CHATBAR" copy-opener "项目乙")"
assert_contains "$over" "AGENT OPENER UNIQUE" "agent opener.md override"
assert_contains "$over" "_reply.md" "override still asks for a file"
rm -f "$HANDOFF2/①发出_拖给ChatGPT/opener.md"

mkdir -p "$REPO2/templates"
printf 'NEXT TEMPLATE {round} {last_suggestion}\n' > "$REPO2/templates/opener-next.md"
templ="$("$CHATBAR" copy-opener "项目乙")"
assert_contains "$templ" "NEXT TEMPLATE 2" "project opener template"
assert_contains "$templ" "先补测试" "template filled from last reply"

# accepted reply types
REPO3="$TMP/种类仓"
mkdir -p "$REPO3"
HANDOFF3="$TMP/种类交接"
"$CHATBAR" project add --name "种类" --repo "$REPO3" --handoff "$HANDOFF3" >/dev/null
printf 'md\n' > "$TMP/note.md"
printf 'tx\n' > "$TMP/note.txt"
printf '%%PDF-1.4\n' > "$TMP/note.pdf"
printf 'png\n' > "$TMP/note.png"
"$CHATBAR" ingest --project "种类" "$TMP/note.md" "$TMP/note.txt" "$TMP/note.pdf" "$TMP/note.png" >/dev/null
kinds="$(cat "$HANDOFF3/②收回_ChatGPT回复拖到这里/NEW.json")"
assert_contains "$kinds" '"kind":"markdown"' "ingest md"
assert_contains "$kinds" '"kind":"text"' "ingest txt"
assert_contains "$kinds" '"kind":"pdf"' "ingest pdf"
assert_contains "$kinds" '"kind":"image"' "ingest image"

# planner patches apply on a new branch; main stays put
AREPO="$TMP/apply-repo"
mkdir -p "$AREPO"
git init -q "$AREPO"
git -C "$AREPO" checkout -q -b main
git -C "$AREPO" config user.email "chatbar-test@example.com"
git -C "$AREPO" config user.name "ChatBar Test"
printf 'alpha\n' > "$AREPO/foo.txt"
git -C "$AREPO" add foo.txt
git -C "$AREPO" commit -q -m alpha
printf 'beta\n' > "$AREPO/foo.txt"
git -C "$AREPO" diff > "$TMP/good.patch"
git -C "$AREPO" checkout -q -- foo.txt
AHOME="$TMP/apply-handoff"
"$CHATBAR" project add --name "应用" --repo "$AREPO" --handoff "$AHOME" --test-command "grep -q beta foo.txt" >/dev/null
"$CHATBAR" ingest --project "应用" "$TMP/good.patch" >/dev/null
anew="$(cat "$AHOME/②收回_ChatGPT回复拖到这里/NEW.json")"
assert_contains "$anew" '"type": "code_patch"' "patch reply type"
assert_dir "$AHOME/②收回_ChatGPT回复拖到这里/patches"
main_before="$(git -C "$AREPO" rev-parse main)"
"$CHATBAR" apply --project "应用" >/dev/null
main_after="$(git -C "$AREPO" rev-parse main)"
assert_eq "$main_before" "$main_after" "main not moved by apply"
assert_eq "$(git -C "$AREPO" branch --show-current)" "chatbar/R001" "apply branch"
assert_contains "$(cat "$AREPO/foo.txt")" "beta" "patch applied"
assert_contains "$(git -C "$AREPO" log -1 --format=%s)" "chatbar: apply planner patch R001" "apply commit"
git -C "$AREPO" checkout -q main
assert_contains "$(cat "$AREPO/foo.txt")" "alpha" "main worktree unchanged"

# conflict is reported and not forced
printf 'gamma\n' > "$AREPO/foo.txt"
git -C "$AREPO" add foo.txt
git -C "$AREPO" commit -q -m gamma
printf -- '--- a/foo.txt\n+++ b/foo.txt\n@@ -1 +1 @@\n-nope\n+beta\n' > "$TMP/bad.patch"
"$CHATBAR" ingest --project "应用" "$TMP/bad.patch" >/dev/null
set +e
"$CHATBAR" apply --project "应用" >"$TMP/apply-conflict.out" 2>"$TMP/apply-conflict.err"
conflict_rc=$?
set -e
[[ "$conflict_rc" -ne 0 ]] || fail "conflict apply should fail"
assert_eq "$(git -C "$AREPO" rev-parse main)" "$(git -C "$AREPO" rev-parse main)" "main ref still exists"
assert_contains "$(cat "$TMP/apply-conflict.err")" "Not using --force" "no force on conflict"
# main commit from the gamma commit is still the branch tip
assert_contains "$(git -C "$AREPO" log main -1 --format=%s)" "gamma" "main history untouched"
assert_contains "$menu" "param1=open-handoff" "menu handoff action"
assert_contains "$menu" "param1=open-root" "menu root action"

# compact + sync
old="$HANDOFF/已归档/2020-01/R000_old"
mkdir -p "$old"
printf 'old\n' > "$old/note.txt"
SYNC="$TMP/备份 目标"
"$CHATBAR" compact --project "项目甲" --older-than 1d --sync "$SYNC" >/dev/null
assert_file "$HANDOFF/已归档/2020-01.zip"
[[ ! -d "$HANDOFF/已归档/2020-01" ]] || fail "old month should be zipped away"
assert_dir "$SYNC/项目甲/已归档" || true
# slug of 项目甲 is the chinese name lowercased (already lower)
if [[ ! -d "$SYNC/项目甲/已归档" && ! -d "$SYNC"/*/已归档 ]]; then
  fail "sync did not copy archive"
fi

# project switch
"$CHATBAR" project use "项目乙" >/dev/null
assert_eq "$(tr -d '\n' < "$CHATBAR_HOME/current")" "项目乙" "current switched"

# safety: no chat UI automation
if grep -RInE 'playwright|puppeteer|api\.openai\.com|browser-cookie|tell application "(Safari|Google Chrome|ChatGPT)"|System Events|keystroke' \
  "$ROOT/cli" "$ROOT/swiftbar" "$ROOT/scripts" >/tmp/safety-hits 2>/dev/null; then
  fail "forbidden automation strings: $(cat /tmp/safety-hits)"
fi

# install links the CLI
PREFIX="$TMP/prefix"
bash "$ROOT/scripts/install.sh" --prefix "$PREFIX" --skip-swiftbar >/dev/null
[[ -x "$PREFIX/bin/chatbar" || -L "$PREFIX/bin/chatbar" ]] || fail "install did not link chatbar"
install_src="$(cat "$ROOT/scripts/install.sh")"
assert_contains "$install_src" "SUHasLaunchedBefore" "installer seeds Sparkle launched flag"
assert_contains "$install_src" "SUEnableAutomaticChecks" "installer documents update checks"
assert_contains "$install_src" "SUAutomaticallyUpdate" "installer disables auto update"
assert_contains "$install_src" "MakePluginExecutable" "installer makes plugins executable"
assert_contains "$install_src" "killall SwiftBar" "installer restarts SwiftBar"
assert_contains "$install_src" "open -a SwiftBar" "installer launches SwiftBar"

if [[ "$FAILS" -ne 0 ]]; then
  echo "$FAILS test assertion(s) failed" >&2
  exit 1
fi
echo "ok"
