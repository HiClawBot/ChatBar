# Structured round log: <handoff>/log/events.jsonl
# Caller must hold the handoff lock. MIT License.

cb_log_event() {
  local handoff="$1"
  local project="$2"
  local round="$3"
  local direction="$4"
  local files_json="$5"
  local bytes="$6"
  local extra="${7:-}"
  local ts tokens line
  ts="$(cb_now_iso)"
  tokens="$(cb_approx_tokens "$bytes")"
  if [[ -z "$files_json" ]]; then
    files_json="[]"
  fi
  if [[ -z "$round" || ! "$round" =~ ^[0-9]+$ ]]; then
    round=0
  fi
  local machine
  machine="$(cb_machine_name)"
  line="$(printf '{"spec_version":"%s","timestamp":"%s","project":"%s","round":%s,"direction":"%s","machine":"%s","files":%s,"bytes":%s,"approx_tokens":%s}' \
    "$CB_SPEC_VERSION" \
    "$ts" \
    "$(cb_json_escape "$project")" \
    "$round" \
    "$(cb_json_escape "$direction")" \
    "$(cb_json_escape "$machine")" \
    "$files_json" \
    "$bytes" \
    "$tokens")"
  if [[ -n "$extra" ]]; then
    line="${line%\}}"
    line="${line},${extra}}"
  fi
  local logdir
  logdir="$(cb_dir "$handoff" log)"
  mkdir -p "$logdir"
  printf '%s\n' "$line" >> "${logdir}/events.jsonl"
  local claim
  claim="$(printf '{"spec_version":"%s","timestamp":"%s","project":"%s","round":%s,"machine":"%s","action":"%s"}' \
    "$CB_SPEC_VERSION" \
    "$ts" \
    "$(cb_json_escape "$project")" \
    "$round" \
    "$(cb_json_escape "$machine")" \
    "$(cb_json_escape "$direction")")"
  printf '%s\n' "$claim" >> "${logdir}/claims.jsonl"
}

cb_files_json_one() {
  local path="$1"
  local bytes="$2"
  printf '[{"path":"%s","bytes":%s}]' "$(cb_json_escape "$path")" "$bytes"
}
