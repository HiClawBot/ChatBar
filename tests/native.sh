# Native menu, downloads, opener edits, and the iron rule.
# Sourced by tests/run.sh. Uses the same CHATBAR binary and helpers.

NATIVE_OLD_HOME="$CHATBAR_HOME"
export CHATBAR_HOME="$TMP/native-home 根"
mkdir -p "$CHATBAR_HOME"

NREPO="$TMP/native-repo"
mkdir -p "$NREPO"
git init -q "$NREPO"
git -C "$NREPO" config user.email "chatbar-test@example.com"
git -C "$NREPO" config user.name "ChatBar Test"
printf 'one\n' > "$NREPO/a.txt"
git -C "$NREPO" add a.txt
git -C "$NREPO" commit -q -m init
NHOME="$TMP/native-handoff"
"$CHATBAR" project add --name "下载甲" --repo "$NREPO" --handoff "$NHOME" --download-patterns 'extra-*.txt' >/dev/null

DLDIR="$TMP/下载 目录"
mkdir -p "$DLDIR"
off="$("$CHATBAR" config get --json)"
assert_contains "$off" '"auto_exchange":false' "auto exchange defaults off"
"$CHATBAR" config set --download-dir "$DLDIR" >/dev/null
printf 'early\n' > "$DLDIR/下载甲_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
"$CHATBAR" downloads-scan >/dev/null
assert_file "$DLDIR/下载甲_round1_reply.md"
"$CHATBAR" config set --chat-name "规划 聊天" --auto-exchange on >/dev/null
cfg="$("$CHATBAR" config get --json)"
assert_contains "$cfg" "规划 聊天" "config keeps spaced chat name"
assert_contains "$cfg" "$DLDIR" "config keeps download dir"
assert_contains "$cfg" '"auto_exchange":true' "master switch can be turned on"
assert_contains "$cfg" '"auto_copy_on_ready":false' "auto copy stays off until asked"

st="$("$CHATBAR" status --json)"
assert_contains "$st" '"menu_state":"idle"' "json idle before pack"
assert_contains "$st" '"name":"下载甲"' "json project name"

"$CHATBAR" pack --project "下载甲" >/dev/null
bundle="$("$CHATBAR" bundle --json "下载甲")"
assert_contains "$bundle" "to_planner.md" "bundle names the pack"
assert_contains "$bundle" '"round":1' "bundle round"
assert_contains "$bundle" "下载甲_round1_reply.md" "bundle opener names the reply file"

printf '%s' '用户改过的开场白' | "$CHATBAR" opener save "下载甲" >/dev/null
outbox="$NHOME/①发出_拖给规划 聊天"
# chat token is applied, so the folder name includes the spaced chat name.
if [[ ! -d "$outbox" ]]; then
  outbox="$(dirname "$(find "$NHOME" -name opener.md -print -quit)")"
fi
assert_file "$outbox/opener.md"
assert_file "$outbox/opener.generated.md"
assert_eq "$(cat "$outbox/opener.md")" "用户改过的开场白" "opener.md is the edit"
assert_not_contains "$(cat "$outbox/opener.generated.md")" "用户改过的开场白" "generated keeps the agent text"
assert_file "$NHOME/记录/opener-edits.md"
assert_contains "$(cat "$NHOME/记录/opener-edits.md")" "user-edit" "edit is logged"
shown="$("$CHATBAR" opener show "下载甲")"
assert_contains "$shown" '"source":"user"' "show reports user source"
assert_contains "$shown" '用户改过的开场白' "show returns the edit"
"$CHATBAR" opener reset "下载甲" >/dev/null
[[ ! -f "$outbox/opener.md" ]] || fail "reset should remove opener.md"
assert_file "$outbox/opener.generated.md"
shown2="$("$CHATBAR" opener show "下载甲")"
assert_contains "$shown2" '"source":"generated"' "reset returns to generated"
bundle2="$("$CHATBAR" bundle --json "下载甲")"
assert_not_contains "$bundle2" "用户改过的开场白" "bundle uses generated opener after reset"

"$CHATBAR" mark-presented "下载甲" >/dev/null
st2="$("$CHATBAR" status --json --project "下载甲")"
assert_contains "$st2" '"pack_state":"presented"' "mark presented"
assert_contains "$st2" '"presented_at":"20' "presented timestamp"

# Master is on; this project is not opted in, so a perfect name stays put.
rm -f "$DLDIR/下载甲_round1_reply.md"
printf 'hello-route\n' > "$DLDIR/下载甲_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
"$CHATBAR" downloads-scan >/dev/null
assert_file "$DLDIR/下载甲_round1_reply.md"
"$CHATBAR" project auto "下载甲" on >/dev/null
st_auto="$("$CHATBAR" status --json --project "下载甲")"
assert_contains "$st_auto" '"project_auto":true' "project auto flag"
assert_contains "$st_auto" '"slug":"下载甲"' "project slug"
assert_contains "$st_auto" '"auto_exchange":true' "master flag in status"
"$CHATBAR" project auto "下载甲" off >/dev/null
rm -f "$DLDIR/下载甲_round1_reply.md"

# An unpacked project stays on round 1, so ingest does not close a round and bump it.
RREPO="$TMP/route-repo"
mkdir -p "$RREPO"
"$CHATBAR" project add --name "路由" --repo "$RREPO" --handoff "$TMP/route-handoff" --auto-exchange on >/dev/null
printf 'hello-route\n' > "$DLDIR/路由_round1_reply.md"
printf 'wrong-round\n' > "$DLDIR/路由_round2_reply.md"
printf 'partial\n' > "$DLDIR/路由_round1_reply.md.crdownload"
printf 'part\n' > "$DLDIR/路由_round1_reply.md.part"
printf 'safari\n' > "$DLDIR/路由_round1_reply.md.download"
printf 'nope\n' > "$DLDIR/random.txt"
printf 'zip-body\n' > "$DLDIR/路由_round1_reply.zip"
"$CHATBAR" downloads-scan >/dev/null
assert_file "$DLDIR/路由_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
[[ ! -f "$DLDIR/路由_round1_reply.md" ]] || fail "slug plus matching round should move"
[[ ! -f "$DLDIR/路由_round1_reply.zip" ]] || fail "zip reply name should move"
assert_file "$DLDIR/路由_round2_reply.md"
assert_file "$DLDIR/random.txt"
assert_file "$DLDIR/路由_round1_reply.md.crdownload"
assert_file "$DLDIR/路由_round1_reply.md.part"
assert_file "$DLDIR/路由_round1_reply.md.download"
pending="$("$CHATBAR" downloads-pending)"
assert_contains "$pending" "round_mismatch" "round mismatch is reported"
assert_contains "$pending" "nomatch" "unknown file is reported"
assert_contains "$pending" "路由_round2_reply.md" "mismatch keeps the path"
assert_not_contains "$pending" ".crdownload" "partial downloads are not prompts"

# Header line with R### and the slug, on a project whose round is 1 and that has no pack.
HREPO="$TMP/header-repo"
mkdir -p "$HREPO"
"$CHATBAR" project add --name "抬头" --repo "$HREPO" --handoff "$TMP/header-handoff" --auto-exchange on >/dev/null
printf 'R001 抬头\nbody\n' > "$DLDIR/notes.md"
"$CHATBAR" downloads-scan >/dev/null
"$CHATBAR" downloads-scan >/dev/null
[[ ! -f "$DLDIR/notes.md" ]] || fail "header with slug and R001 should move"
assert_contains "$(cat "$CHATBAR_HOME/downloads.log")" "moved" "header move is logged"

# Two projects, one slug: do not move.
"$CHATBAR" project add --name "Foo" --repo "$HREPO" --handoff "$TMP/foo-handoff" --auto-exchange on >/dev/null
"$CHATBAR" project add --name "foo" --repo "$HREPO" --handoff "$TMP/foo2-handoff" --auto-exchange on >/dev/null
printf 'both\n' > "$DLDIR/foo_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
"$CHATBAR" downloads-scan >/dev/null
assert_file "$DLDIR/foo_round1_reply.md"
amb="$("$CHATBAR" downloads-pending)"
assert_contains "$amb" "ambiguous" "two slugs are ambiguous"
assert_contains "$amb" "foo_round1_reply.md" "ambiguous file stays listed"

# Same bytes for the same project and round are ingested once.
printf 'hello-route\n' > "$DLDIR/路由_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
"$CHATBAR" downloads-scan >/dev/null
assert_file "$DLDIR/路由_round1_reply.md"
assert_contains "$(cat "$CHATBAR_HOME/downloads.log")" "duplicate" "duplicate sha is logged"

# Explicit pick moves a file the watcher refused.
"$CHATBAR" downloads-assign --file "$DLDIR/random.txt" --project "抬头" >/dev/null
[[ ! -f "$DLDIR/random.txt" ]] || fail "assign should move the chosen file"

# Conflict suffix never deletes the existing inbox file.
CREPO="$TMP/conflict-repo"
mkdir -p "$CREPO"
"$CHATBAR" project add --name "冲突乙" --repo "$CREPO" --handoff "$TMP/conflict-handoff" --auto-exchange on >/dev/null
cinbox="$(find "$TMP/conflict-handoff" -type d -name '②收回_*' -print -quit)"
assert_dir "$cinbox"
printf 'keep-me\n' > "$cinbox/冲突乙_round1_reply.md"
printf 'reply-a\n' > "$DLDIR/冲突乙_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
"$CHATBAR" downloads-scan >/dev/null
assert_eq "$(cat "$cinbox/冲突乙_round1_reply.md")" "keep-me" "conflict must not delete the existing inbox file"
assert_contains "$(cat "$CHATBAR_HOME/downloads.log")" "冲突乙_round1_reply-2.md" "conflict suffix is logged"

# Growing file waits until the size stays the same.
printf 'a' > "$DLDIR/抬头_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
printf 'abc' > "$DLDIR/抬头_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
assert_file "$DLDIR/抬头_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
[[ ! -f "$DLDIR/抬头_round1_reply.md" ]] || fail "stable size should move"

# Master off leaves a matching file alone. --force still requires the project flag, which stays on,
# so --force moves it. A disabled project does not move even with --force.
"$CHATBAR" config set --auto-exchange off >/dev/null
printf 'stay\n' > "$DLDIR/路由_round1_reply.md"
"$CHATBAR" downloads-scan >/dev/null
"$CHATBAR" downloads-scan >/dev/null
assert_file "$DLDIR/路由_round1_reply.md"
"$CHATBAR" project auto "路由" off >/dev/null
"$CHATBAR" downloads-scan --force >/dev/null
"$CHATBAR" downloads-scan --force >/dev/null
assert_file "$DLDIR/路由_round1_reply.md"

rounds="$("$CHATBAR" rounds "下载甲")"
assert_contains "$rounds" '"rounds":' "rounds json"

export CHATBAR_MACHINE="lan-host"
MREPO="$TMP/machine-repo"
mkdir -p "$MREPO"
"$CHATBAR" project add --name "机器" --repo "$MREPO" --handoff "$TMP/machine-handoff" >/dev/null
printf 'machine-note\n' > "$TMP/machine-note.md"
"$CHATBAR" ingest --project "机器" "$TMP/machine-note.md" >/dev/null
minbox="$(find "$TMP/machine-handoff" -type d -name '②收回_*' -print -quit)"
mnew="$(cat "$minbox/NEW.json")"
assert_contains "$mnew" '"machine": "lan-host"' "NEW.json names this machine"
mlog="$(find "$TMP/machine-handoff" -name events.jsonl -print -quit)"
assert_contains "$(cat "$mlog")" '"machine":"lan-host"' "event log names this machine"
mclaim="$(find "$TMP/machine-handoff" -name claims.jsonl -print -quit)"
assert_contains "$(cat "$mclaim")" '"machine":"lan-host"' "claim record names this machine"
assert_contains "$(cat "$mclaim")" '"action":"from_planner"' "claim records the action"
"$CHATBAR" config set --tip-minutes 4 --tip-cost 1.5 >/dev/null
tip="$("$CHATBAR" tip --json)"
assert_contains "$tip" '"minutes_per_action":4' "tip assumption is editable"
assert_contains "$tip" '"cost_per_round":1.5' "tip cost assumption is editable"
assert_contains "$tip" '"machine":"lan-host"' "tip names this machine"
assert_contains "$tip" '"minutes_saved":' "tip estimates minutes"
scene="$("$CHATBAR" log --json)"
assert_contains "$scene" '"direction":"from_planner"' "scene log is the jsonl feed"
unset CHATBAR_MACHINE

"$CHATBAR" project use "下载甲" >/dev/null
next="$("$CHATBAR" next --json)"
assert_contains "$next" '"action_label":' "next step has one instruction"
assert_contains "$next" 'to_chatgpt_R' "next step names the current round file"
assert_contains "$next" '"step":"copy"' "legacy presented state does not confirm sending"
native_arg="b64:$(cb_b64enc '下载甲')"
assert_eq "$("$CHATBAR" next --json --project "$native_arg")" "$next" "native project arguments decode on macOS"
"$CHATBAR" step advance "$native_arg" 1 copy >/dev/null
assert_contains "$("$CHATBAR" next --json --project "$native_arg")" '"step":"paste"' "encoded callback advances the project"


bash "$ROOT/scripts/lint-iron-rule.sh" "$ROOT"

BAD="$TMP/bad-iron"
mkdir -p "$BAD/cli"
printf '%s\n' "import something" > "$BAD/cli/nope.swift"
# The bad token is assembled so this test file is not the sample under scan.
printf '%s%s\n' 'CGEvent' 'Post(nil)' > "$BAD/cli/nope.swift"
set +e
bash "$ROOT/scripts/lint-iron-rule.sh" "$BAD" >/tmp/iron-bad.out 2>/tmp/iron-bad.err
iron_rc=$?
set -e
[[ "$iron_rc" -ne 0 ]] || fail "iron rule lint should fail on a banned reference"
assert_contains "$(cat /tmp/iron-bad.err /tmp/iron-bad.out)" "nope.swift" "lint names the file"

export CHATBAR_HOME="$NATIVE_OLD_HOME"
