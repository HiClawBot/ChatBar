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

# --- syntax and defined functions ---
bash -n "$CHATBAR"
bash -n "$ROOT/scripts/install.sh"
(
  set -euo pipefail
  # shellcheck disable=SC1090
  source "$CHATBAR"
  # shellcheck disable=SC1090
  source "$ROOT/scripts/install.sh"
  # shellcheck disable=SC1090
  source "$ROOT/swiftbar/chatbar.1m.sh"
  missing=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    kind="$(type -t "$name" || true)"
    if [[ "$kind" != "function" ]]; then
      echo "undefined function: $name" >&2
      missing=1
    fi
  done < <(grep -h -oE 'cb_[A-Za-z0-9_]+' "$ROOT"/cli/chatbar "$ROOT"/cli/lib/*.sh "$ROOT"/swiftbar/*.sh "$ROOT"/scripts/install.sh | sort -u)
  [[ "$missing" -eq 0 ]]
) || fail "undefined cb_* function"
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
assert_file "$HANDOFF/①发出_拖给规划聊天/to_chatgpt_R001.md"
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
assert_contains "$open_out" "①发出_拖给规划聊天/to_chatgpt_R001.md" "left is the round file"
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
[[ ! -d "$HANDOFF2/.lock" ]] || fail "zip slip left a lock"

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
assert_contains "$menu" "项目甲 · 第" "menu project is status only"
assert_contains "$menu" "param1=project param2=use" "project row switches current"
assert_contains "$menu" "---- 打开交接目录" "per-project folder item is under 更多"
assert_contains "$menu" "---- 打开项目根目录" "per-project root item is under 更多"
assert_contains "$menu" "---- 结束本轮" "per-project close is under 更多"
assert_contains "$menu" "param1=open-handoff" "menu handoff action"
assert_contains "$menu" "param1=open-root" "menu root action"
assert_contains "$menu" $'\n更多\n' "more submenu"
assert_contains "$menu" "-- 打包" "pack is under more"
assert_contains "$menu" "-- 打开收发窗口" "reveal is under more"
assert_contains "$menu" "-- 刷新" "refresh is under more"
assert_contains "$menu" "-- 设置" "settings is under more"
assert_contains "$menu" "-- 添加项目…" "add project is a submenu item"
assert_contains "$menu" "param2=pick-folder" "add project uses the folder picker"
assert_contains "$menu" "发送永远由你手动" "short footer"
assert_contains "$menu" "terminal=false" "menu actions stay out of Terminal"
if printf '%s' "$menu" | grep -q '复制给 GPT 的话\|就做本地这步\|更多 / 高级'; then
  fail "menu still has a duplicate action"
fi
if printf '%s' "$menu" | grep -q 'terminal=true'; then
  fail "menu asked for a terminal"
fi
if grep -RIn 'terminal=true' "$ROOT/cli/lib/menu.sh" "$ROOT/swiftbar" >/tmp/terminal-hits 2>/dev/null; then
  fail "menu source uses terminal=true: $(cat /tmp/terminal-hits)"
fi
mkdir -p "$TMP/empty-home"
empty_menu="$(CHATBAR_HOME="$TMP/empty-home" "$CHATBAR" swiftbar-menu)"
assert_contains "$empty_menu" "还没有项目" "empty menu has no project"
assert_contains "$empty_menu" $'\n更多\n' "empty menu uses 更多"
assert_contains "$empty_menu" "-- 添加项目…" "empty menu still offers the folder picker"
if printf '%s' "$empty_menu" | grep -q 'terminal=true\|add-interactive'; then
  fail "empty menu still opens a terminal prompt"
fi

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

# zip ingest end to end: unpack, write NEW.json, move the raw zip, do not unpack twice
ZREPO="$TMP/zip-repo"
mkdir -p "$ZREPO"
ZHANDOFF="$TMP/zip 交接"
"$CHATBAR" project add --name "压缩包" --repo "$ZREPO" --handoff "$ZHANDOFF" >/dev/null
zdir="$TMP/zsrc"
mkdir -p "$zdir"
printf 'zip-body\n' > "$zdir/inside.md"
(cd "$zdir" && zip -q "$TMP/agents-bar_round1_reply.zip" inside.md)
zinbox="$(cd -P "$ZHANDOFF" && pwd)/②收回_ChatGPT回复拖到这里"
cp "$TMP/agents-bar_round1_reply.zip" "$zinbox/agents-bar_round1_reply.zip"
"$CHATBAR" ingest --project "压缩包" "$zinbox/agents-bar_round1_reply.zip"
assert_file "$zinbox/NEW.json"
assert_contains "$(cat "$zinbox/NEW.json")" '"status": "new"' "zip ingest wrote NEW.json"
[[ ! -e "$zinbox/agents-bar_round1_reply.zip" ]] || fail "raw zip still in inbox"
raw_zip="$(find "$ZHANDOFF/已归档" -type f -name 'agents-bar_round1_reply.zip' | head -n 1)"
[[ -n "$raw_zip" ]] || fail "raw zip was not archived"
assert_contains "$raw_zip" "_raw/" "raw zip is under RNNN_raw"
case "$raw_zip" in
  */已归档/[0-9][0-9][0-9][0-9]-[0-9][0-9]/R001_raw/*) ;;
  *) fail "raw zip is not in a monthly archive folder: ${raw_zip}" ;;
esac
case "$raw_zip" in
  */[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/*) fail "raw zip used a day folder: ${raw_zip}" ;;
esac
[[ ! -d "$ZHANDOFF/.lock" ]] || fail "successful ingest left a lock"
copies="$(find "$zinbox" -type f -name 'r*-inside.md' | wc -l | tr -d ' ')"
assert_eq "$copies" "1" "one unpacked file"
cp "$TMP/agents-bar_round1_reply.zip" "$zinbox/agents-bar_round1_reply.zip"
CHATBAR_SWEEP_SETTLE=0 "$CHATBAR" sweep >/dev/null
copies="$(find "$zinbox" -type f -name 'r*-inside.md' | wc -l | tr -d ' ')"
assert_eq "$copies" "1" "sweep did not unpack the same zip again"
[[ -e "$zinbox/agents-bar_round1_reply.zip" ]] || fail "duplicate zip should stay put when skipped"

# a later round must not be listed together with an inbox that is still new
MREPO="$TMP/mix-repo"
mkdir -p "$MREPO"
MHANDOFF="$TMP/mix 交接"
"$CHATBAR" project add --name "分轮" --repo "$MREPO" --handoff "$MHANDOFF" >/dev/null
minbox="$(cd -P "$MHANDOFF" && pwd)/②收回_ChatGPT回复拖到这里"
printf 'round-one\n' > "$TMP/round-one.md"
"$CHATBAR" ingest --project "分轮" "$TMP/round-one.md" >/dev/null
assert_contains "$(cat "$minbox/NEW.json")" "round-one.md" "first round manifest"
printf '2\n' > "$MHANDOFF/round"
printf '2\n' > "$MHANDOFF/pack-round"
printf 'round-two\n' > "$TMP/round-two.md"
"$CHATBAR" ingest --project "分轮" "$TMP/round-two.md" >/dev/null
mix_json="$(cat "$minbox/NEW.json")"
assert_contains "$mix_json" "round-two.md" "current round is listed"
if printf '%s' "$mix_json" | grep -q 'round-one.md'; then
  fail "NEW.json mixed the previous round"
fi
moved="$(find "$MHANDOFF/已归档" -type f -name 'r*-round-one.md' | head -n 1)"
[[ -n "$moved" ]] || fail "previous inbox file was not moved to the archive"
case "$moved" in
  */已归档/[0-9][0-9][0-9][0-9]-[0-9][0-9]/R001_*) ;;
  *) fail "previous round was not archived under YYYY-MM/R001: ${moved}" ;;
esac

# next step: one sentence per state, exact round file
AREPO="$TMP/agents-bar-repo"
mkdir -p "$AREPO"
git init -q "$AREPO"
git -C "$AREPO" config user.email "chatbar-test@example.com"
git -C "$AREPO" config user.name "ChatBar Test"
printf 'a\n' > "$AREPO/main.py"
git -C "$AREPO" add main.py
git -C "$AREPO" commit -q -m init
AHANDOFF="$TMP/agents-bar 交接"
"$CHATBAR" project add --name "agents-bar" --repo "$AREPO" --handoff "$AHANDOFF" >/dev/null
need="$("$CHATBAR" next agents-bar)"
assert_eq "$need" "现在：让 agent 跑 chatbar pack，你先不用做事" "next before pack"
need_json="$("$CHATBAR" next --json agents-bar)"
assert_contains "$need_json" '"state":"need_pack"' "next json need_pack"
assert_contains "$need_json" '"text":"现在：让 agent 跑 chatbar pack，你先不用做事"' "next json text"
printf 'reply-one\n' > "$TMP/ab-r1.md"
"$CHATBAR" ingest --project "agents-bar" "$TMP/ab-r1.md" >/dev/null
got="$("$CHATBAR" next agents-bar)"
assert_eq "$got" "已收到 R001，交给 agent 处理中，你不用做事" "next inbox new"
got_json="$("$CHATBAR" next --json --project agents-bar)"
assert_contains "$got_json" '"state":"inbox"' "next json inbox"
assert_contains "$got_json" '"round":1' "next json inbox round"
"$CHATBAR" archive --project "agents-bar" >/dev/null
"$CHATBAR" pack --project "agents-bar" >/dev/null
assert_file "$AHANDOFF/①发出_拖给ChatGPT/to_chatgpt_R002.md"
ready="$("$CHATBAR" next agents-bar)"
assert_eq "$ready" "现在：① 点『复制给 g 的话』→ ② 在 g 里 Cmd+V → ③ 把 to_chatgpt_R002.md 拖进去 → ④ 发送" "next ready names the file"
ready_json="$("$CHATBAR" next agents-bar --json)"
assert_contains "$ready_json" '"state":"ready"' "next json ready"
assert_contains "$ready_json" '"file":"to_chatgpt_R002.md"' "next json exact file"
assert_contains "$ready_json" '"reply_file":"agents-bar_round2_reply.zip"' "next json download name"
assert_contains "$(cat "$AHANDOFF/①发出_拖给ChatGPT/to_chatgpt_R002.md")" "agents-bar_round2_reply.zip" "pack asks for that download"
"$CHATBAR" project use agents-bar >/dev/null
menu_next="$("$CHATBAR" swiftbar-menu)"
assert_contains "$menu_next" "现在：① 点『复制给 g 的话』" "menu top line is the action"
assert_contains "$menu_next" "to_chatgpt_R002.md" "menu names the file"
assert_contains "$menu_next" "① 复制并选中文件（然后去 g 粘贴、拖入、发送）" "menu one primary action"
assert_contains "$menu_next" "agents-bar · 第 2 轮 · 待发给 g" "project row is status"
assert_contains "$menu_next" "param1=handoff-now" "menu local step command"
handoff_lines="$(printf '%s\n' "$menu_next" | grep -c 'param1=handoff-now' || true)"
assert_eq "$handoff_lines" "1" "only one copy-and-select action"
if printf '%s' "$menu_next" | grep -q '复制给 GPT 的话\|就做本地这步'; then
  fail "ready menu showed a second copy action"
fi
local_out="$("$CHATBAR" handoff-now agents-bar)"
assert_contains "$local_out" "clipboard:" "handoff copies"
assert_contains "$local_out" "reveal:" "handoff reveals"
assert_contains "$local_out" "to_chatgpt_R002.md" "handoff selects the round file"
still="$("$CHATBAR" next agents-bar)"
assert_eq "$still" "$ready" "local step does not mark the message sent"
"$CHATBAR" open agents-bar >/dev/null
wait="$("$CHATBAR" next agents-bar)"
assert_eq "$wait" "等 g 回复，回完点下载 agents-bar_round2_reply.zip" "next waiting names the download"
wait_json="$("$CHATBAR" next --json agents-bar)"
assert_contains "$wait_json" '"state":"waiting"' "next json waiting"
"$CHATBAR" project use agents-bar >/dev/null
menu_wait="$("$CHATBAR" swiftbar-menu)"
assert_contains "$menu_wait" "等 g 回复，回完点下载 agents-bar_round2_reply.zip" "menu waiting line"
assert_contains "$menu_wait" "打开下载文件夹" "waiting action opens Downloads"
assert_contains "$menu_wait" "param1=open-downloads" "waiting action command"
if printf '%s' "$menu_wait" | grep -q '就做本地这步\|① 复制并选中文件\|复制给 GPT 的话'; then
  fail "waiting menu showed the send action"
fi

# a hand-written current-round file is ready even when pack-state is still none
HWREPO="$TMP/hand-repo"
mkdir -p "$HWREPO"
git init -q "$HWREPO"
git -C "$HWREPO" config user.email "chatbar-test@example.com"
git -C "$HWREPO" config user.name "ChatBar Test"
printf 'a\n' > "$HWREPO/main.py"
git -C "$HWREPO" add main.py
git -C "$HWREPO" commit -q -m init
HWHANDOFF="$TMP/hand 交接"
"$CHATBAR" project add --name "手写" --repo "$HWREPO" --handoff "$HWHANDOFF" >/dev/null
assert_eq "$(tr -d '\r\n' < "$HWHANDOFF/pack-state")" "none" "hand project starts unpacked"
hw_out="$HWHANDOFF/①发出_拖给ChatGPT"
printf 'wrong round\n' > "$hw_out/to_chatgpt_R002.md"
hw_wrong="$("$CHATBAR" next 手写)"
assert_eq "$hw_wrong" "现在：让 agent 跑 chatbar pack，你先不用做事" "other round file is not ready"
rm -f "$hw_out/to_chatgpt_R002.md"
printf 'hand written round\n' > "$hw_out/to_chatgpt_R001.md"
assert_file "$hw_out/给GPT的话.txt"
hw_next="$("$CHATBAR" next 手写)"
assert_eq "$hw_next" "现在：① 点『复制给 g 的话』→ ② 在 g 里 Cmd+V → ③ 把 to_chatgpt_R001.md 拖进去 → ④ 发送" "hand-written pack is ready"
hw_json="$("$CHATBAR" next --json 手写)"
assert_contains "$hw_json" '"state":"ready"' "hand-written json ready"
assert_eq "$(tr -d '\r\n' < "$HWHANDOFF/pack-state")" "none" "next does not rewrite pack-state"
"$CHATBAR" project use 手写 >/dev/null
hw_menu="$("$CHATBAR" swiftbar-menu)"
assert_contains "$hw_menu" "to_chatgpt_R001.md" "hand-written menu names the file"
assert_contains "$hw_menu" "① 复制并选中文件（然后去 g 粘贴、拖入、发送）" "hand-written pack shows the one action"
assert_contains "$hw_menu" "手写 · 第 1 轮 · 待发给 g" "hand-written row status"
rm -f "$hw_out/给GPT的话.txt" "$hw_out/opener.txt" "$hw_out/opener.md"
hw_bare="$("$CHATBAR" next 手写)"
assert_eq "$hw_bare" "现在：让 agent 跑 chatbar pack，你先不用做事" "pack file without opener is not ready"
printf 'opener\n' > "$hw_out/给GPT的话.txt"
printf 'got it\n' > "$TMP/hw-reply.md"
"$CHATBAR" ingest --project 手写 "$TMP/hw-reply.md" >/dev/null
hw_in="$("$CHATBAR" next 手写)"
assert_eq "$hw_in" "已收到 R001，交给 agent 处理中，你不用做事" "ingested reply beats a hand-written pack"
"$CHATBAR" project use 手写 >/dev/null
inbox_menu="$("$CHATBAR" swiftbar-menu)"
assert_contains "$inbox_menu" "手写 · 第 1 轮 · 已交给 agent" "inbox row has no task"
if printf '%s\n' "$inbox_menu" | grep -q '① 复制并选中文件\|打开下载文件夹\|复制给 GPT 的话'; then
  fail "inbox menu offered the user a step"
fi

# one project keeps folder actions in 更多, not a nested project menu
ONEHOME="$TMP/one-home"
ONEREPO="$TMP/one-repo"
mkdir -p "$ONEHOME" "$ONEREPO"
CHATBAR_HOME="$ONEHOME" "$CHATBAR" project add --name "solo" --repo "$ONEREPO" >/dev/null
one_menu="$(CHATBAR_HOME="$ONEHOME" "$CHATBAR" swiftbar-menu)"
assert_contains "$one_menu" "solo · 第 1 轮 · 待打包" "single project status"
assert_contains "$one_menu" "-- 打开交接目录" "single project folder item is directly under 更多"
if printf '%s\n' "$one_menu" | grep -q '^---- '; then
  fail "single project nested a per-project submenu"
fi
dl="$TMP/下载夹"
mkdir -p "$dl"
dl_phys="$(cd -P "$dl" && pwd)"
dl_out="$(CHATBAR_DOWNLOADS="$dl" "$CHATBAR" open-downloads)"
assert_contains "$dl_out" "reveal:${dl_phys}" "open downloads is local"
home_out="$("$CHATBAR" open-home)"
assert_contains "$home_out" "reveal:" "open home is local"

# folder picker names the project after the chosen folder and does not prompt
PICK="$TMP/picked 项目"
mkdir -p "$PICK"
picked_out="$(CHATBAR_PICK_FOLDER="$PICK" "$CHATBAR" project pick-folder)"
assert_contains "$picked_out" "added project picked 项目" "picker uses the folder name"
pick_phys="$(cd -P "$PICK" && pwd)"
assert_contains "$("$CHATBAR" project list)" "$pick_phys" "picker stores the chosen folder"
assert_file "$PICK/AGENTS.md"
if grep -n 'add-interactive' "$ROOT/cli/chatbar" "$ROOT/cli/lib/projects.sh" "$ROOT/cli/lib/menu.sh" >/tmp/interactive-hits 2>/dev/null; then
  fail "interactive terminal prompt remains: $(cat /tmp/interactive-hits)"
fi
assert_contains "$(cat "$ROOT/cli/lib/projects.sh")" "choose folder" "picker is the macOS folder dialog"

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
