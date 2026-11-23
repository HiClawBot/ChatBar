# open / reveal / copy-opener / status / folders. MIT License.
# open and the generated .command show outbox (left) and inbox (right) together.

cb_parse_target_flags() {
  CB_FLAG_NAME=""
  CB_FLAG_HANDOFF=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) CB_FLAG_NAME="${2:-}"; shift 2 ;;
      --handoff) CB_FLAG_HANDOFF="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        if [[ -z "$CB_FLAG_NAME" ]]; then
          CB_FLAG_NAME="$1"
          shift
        else
          cb_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
}

cb_select_project_target() {
  cb_parse_target_flags "$@"
  if [[ -n "$CB_FLAG_HANDOFF" ]]; then
    local idx
    idx="$(cb_project_find_by_handoff "$CB_FLAG_HANDOFF")" || cb_die "no project for handoff: ${CB_FLAG_HANDOFF}"
    cb_load_project_fields "$idx"
  else
    cb_resolve_project_arg "$CB_FLAG_NAME"
  fi
  cb_current_set "$CB_NAME"
  cb_ensure_layout "$CB_HANDOFF"
}

cb_active_round() {
  local pack_state pack_round round
  pack_state="$(cb_state_get "$CB_HANDOFF" "pack-state" "none")"
  pack_round="$(cb_state_get "$CB_HANDOFF" "pack-round" "0")"
  round="$(cb_state_get "$CB_HANDOFF" "round" "1")"
  if [[ "$pack_state" != "none" && "$pack_round" != "0" ]]; then
    printf '%s' "$pack_round"
  else
    printf '%s' "$round"
  fi
}

cb_cmd_copy_opener() {
  cb_select_project_target "$@"
  local opener
  opener="$(cb_publish_opener)"
  cb_clipboard_copy "$opener"
  printf '%s\n' "$opener"
}

# The file the user drags this round. Falls back to the stable pack name.
cb_drag_pack_path() {
  local round="${1:-}"
  local named
  if [[ -z "$round" ]]; then
    round="$(cb_active_round)"
  fi
  named="$(cb_dir "$CB_HANDOFF" outbox)/$(cb_pack_filename "$round")"
  if [[ -f "$named" ]]; then
    printf '%s' "$named"
  else
    printf '%s' "$(cb_dir "$CB_HANDOFF" outbox)/to_planner.md"
  fi
}

# Sets CB_NEXT_STATE, CB_NEXT_TEXT, CB_NEXT_ROUND, CB_NEXT_FILE, CB_NEXT_REPLY.
cb_next_fields() {
  local pack_state inbox_state inbox_round round label pack_path
  pack_state="$(cb_state_get "$CB_HANDOFF" "pack-state" "none")"
  inbox_state="$(cb_state_get "$CB_HANDOFF" "inbox-state" "none")"
  inbox_round="$(cb_state_get "$CB_HANDOFF" "inbox-round" "0")"
  round="$(cb_active_round)"
  if [[ "$inbox_state" == "new" ]]; then
    if [[ "$inbox_round" != "0" ]]; then
      round="$inbox_round"
    fi
    label="$(cb_round_label "$round")"
    CB_NEXT_STATE="inbox"
    CB_NEXT_ROUND="$round"
    CB_NEXT_FILE="$(cb_pack_filename "$round")"
    CB_NEXT_REPLY="$(cb_reply_download_name "$CB_NAME" "$round")"
    CB_NEXT_TEXT="已收到 ${label}，交给 agent 处理中，你不用做事"
    return 0
  fi
  label="$(cb_round_label "$round")"
  pack_path="$(cb_dir "$CB_HANDOFF" outbox)/$(cb_pack_filename "$round")"
  CB_NEXT_ROUND="$round"
  CB_NEXT_FILE="$(cb_pack_filename "$round")"
  CB_NEXT_REPLY="$(cb_reply_download_name "$CB_NAME" "$round")"
  if [[ "$pack_state" == "ready" && -f "$pack_path" ]]; then
    CB_NEXT_STATE="ready"
    CB_NEXT_TEXT="现在：① 点『复制给 g 的话』→ ② 在 g 里 Cmd+V → ③ 把 ${CB_NEXT_FILE} 拖进去 → ④ 发送"
    return 0
  fi
  if [[ "$pack_state" == "presented" ]]; then
    CB_NEXT_STATE="waiting"
    CB_NEXT_TEXT="等 g 回复，回完点下载 ${CB_NEXT_REPLY}"
    return 0
  fi
  CB_NEXT_STATE="need_pack"
  CB_NEXT_TEXT="现在：让 agent 跑 chatbar pack，你先不用做事"
}

cb_next_emit() {
  local as_json="$1"
  if [[ "$as_json" == 1 ]]; then
    printf '{"text":"%s","state":"%s","round":%s,"file":"%s","reply_file":"%s"}\n' \
      "$(cb_json_escape "$CB_NEXT_TEXT")" \
      "$CB_NEXT_STATE" \
      "${CB_NEXT_ROUND:-0}" \
      "$(cb_json_escape "${CB_NEXT_FILE:-}")" \
      "$(cb_json_escape "${CB_NEXT_REPLY:-}")"
  else
    printf '%s\n' "$CB_NEXT_TEXT"
  fi
}

cb_cmd_next() {
  local as_json=0
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) as_json=1; shift ;;
      --project) name="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
          shift
        else
          cb_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
  cb_projects_load
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    CB_NEXT_STATE="no_project"
    CB_NEXT_TEXT="现在：先添加项目"
    CB_NEXT_ROUND=0
    CB_NEXT_FILE=""
    CB_NEXT_REPLY=""
    cb_next_emit "$as_json"
    return 0
  fi
  cb_resolve_project_arg "$name"
  cb_next_fields
  cb_next_emit "$as_json"
}

# Copy the opener and select the exact round file. Does not send anything.
cb_cmd_handoff_now() {
  cb_select_project_target "$@"
  local round pack opener
  round="$(cb_active_round)"
  pack="$(cb_dir "$CB_HANDOFF" outbox)/$(cb_pack_filename "$round")"
  if [[ ! -f "$pack" ]]; then
    cb_die "还没有 $(cb_pack_filename "$round")。先让 agent 跑 chatbar pack"
  fi
  opener="$(cb_publish_opener)"
  cb_clipboard_bundle "$opener" "$pack"
  cb_reveal_path "$pack"
  printf 'file:%s\n' "$pack"
}

cb_show_dir() {
  local target="$1"
  if [[ -n "${CHATBAR_NO_OPEN:-}" || "$(uname -s)" != "Darwin" ]]; then
    printf 'reveal:%s\n' "$target"
    return 0
  fi
  open "$target" || cb_warn "open failed: ${target}"
}

cb_cmd_open_handoff() {
  cb_select_project_target "$@"
  cb_show_dir "$CB_HANDOFF"
}

cb_cmd_open_root() {
  cb_select_project_target "$@"
  if [[ ! -d "$CB_WORKSPACE" ]]; then
    cb_die "workspace does not exist: ${CB_WORKSPACE}"
  fi
  cb_show_dir "$CB_WORKSPACE"
}

cb_cmd_reveal() {
  cb_select_project_target "$@"
  local outdir inbox pack
  outdir="$(cb_dir "$CB_HANDOFF" outbox)"
  inbox="$(cb_dir "$CB_HANDOFF" inbox)"
  pack="$(cb_drag_pack_path "$(cb_active_round)")"
  if [[ ! -f "$pack" ]]; then
    cb_warn "还没有可拖出的包。No pack yet. Run: chatbar pack"
    pack=""
  fi
  cb_open_pair "$outdir" "$inbox" "$pack"
}

cb_cmd_open() {
  cb_select_project_target "$@"
  local round opener outdir inbox pack
  round="$(cb_active_round)"
  opener="$(cb_build_opener "$round")"
  cb_write_opener_files "$opener"
  cb_clipboard_copy "$opener"
  printf 'opener:%s\n' "$opener"
  outdir="$(cb_dir "$CB_HANDOFF" outbox)"
  inbox="$(cb_dir "$CB_HANDOFF" inbox)"
  pack="$(cb_drag_pack_path "$round")"
  if [[ -f "$pack" ]]; then
    cb_lock "$CB_HANDOFF"
    cb_state_set "$CB_HANDOFF" "pack-state" "presented"
    cb_unlock "$CB_HANDOFF"
  else
    cb_warn "还没有可拖出的包。No pack yet. Run: chatbar pack"
    pack=""
  fi
  cb_open_pair "$outdir" "$inbox" "$pack"
}

cb_print_project_status() {
  local idx="$1"
  cb_load_project_fields "$idx"
  cb_ensure_layout "$CB_HANDOFF"
  local current="no"
  local cur
  if cur="$(cb_current_name 2>/dev/null || true)" && [[ "$cur" == "$CB_NAME" ]]; then
    current="yes"
  fi
  local pack_state inbox_state pack_round round pack_file tool
  pack_state="$(cb_state_get "$CB_HANDOFF" "pack-state" "none")"
  inbox_state="$(cb_state_get "$CB_HANDOFF" "inbox-state" "none")"
  pack_round="$(cb_state_get "$CB_HANDOFF" "pack-round" "0")"
  round="$(cb_state_get "$CB_HANDOFF" "round" "1")"
  pack_file="$(cb_drag_pack_path "$(cb_active_round)")"
  [[ -f "$pack_file" ]] || pack_file=""
  if command -v repomix >/dev/null 2>&1; then
    tool="repomix"
  elif command -v code2prompt >/dev/null 2>&1; then
    tool="code2prompt"
  else
    tool="none"
  fi
  printf '[project]\n'
  printf 'name=%s\n' "$CB_NAME"
  printf 'repo=%s\n' "$CB_REPO"
  printf 'handoff=%s\n' "$CB_HANDOFF"
  printf 'workspace=%s\n' "$CB_WORKSPACE"
  printf 'current=%s\n' "$current"
  printf 'chat_name=%s\n' "$CB_ROLE_CHAT"
  printf 'round=%s\n' "$round"
  printf 'pack_state=%s\n' "$pack_state"
  printf 'pack_round=%s\n' "$pack_round"
  printf 'pack_file=%s\n' "$pack_file"
  printf 'inbox_state=%s\n' "$inbox_state"
  printf 'outbox_dir=%s\n' "$(cb_dir "$CB_HANDOFF" outbox)"
  printf 'inbox_dir=%s\n' "$(cb_dir "$CB_HANDOFF" inbox)"
  printf 'archive_dir=%s\n' "$(cb_dir "$CB_HANDOFF" archive)"
  printf 'log_dir=%s\n' "$(cb_dir "$CB_HANDOFF" log)"
  printf 'open_command=%s\n' "${CB_HANDOFF}/打开收发两个窗口.command"
  if [[ -f "${CB_HANDOFF}/latest-round.txt" ]]; then
    printf 'latest_round=%s\n' "$(tr -d '\r\n' < "${CB_HANDOFF}/latest-round.txt")"
  else
    printf 'latest_round=\n'
  fi
  printf 'full_pack_tool=%s\n' "$tool"
  printf 'opener=%s\n' "$(cb_build_opener "$(cb_active_round)")"
  printf '\n'
}

cb_cmd_status() {
  cb_parse_target_flags "$@"
  cb_projects_load
  if [[ -n "$CB_FLAG_NAME" || -n "$CB_FLAG_HANDOFF" ]]; then
    if [[ -n "$CB_FLAG_HANDOFF" ]]; then
      local idx
      idx="$(cb_project_find_by_handoff "$CB_FLAG_HANDOFF")" || cb_die "no project for handoff: ${CB_FLAG_HANDOFF}"
      cb_print_project_status "$idx"
    else
      local idx2
      idx2="$(cb_project_find "$(cb_decode_cli_arg "$CB_FLAG_NAME")")" || cb_die "unknown project: ${CB_FLAG_NAME}"
      cb_print_project_status "$idx2"
    fi
    return 0
  fi
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    printf 'projects=0\n'
    return 0
  fi
  local i
  for i in "${!CB_P_NAME[@]}"; do
    cb_print_project_status "$i"
  done
}

cb_cmd_folders() {
  cb_select_project_target "$@"
  printf 'chat_name=%s\n' "$CB_ROLE_CHAT"
  printf 'outbox=%s\n' "$CB_ROLE_OUTBOX"
  printf 'inbox=%s\n' "$CB_ROLE_INBOX"
  printf 'archive=%s\n' "$CB_ROLE_ARCHIVE"
  printf 'log=%s\n' "$CB_ROLE_LOG"
  printf 'outbox_dir=%s\n' "$(cb_dir "$CB_HANDOFF" outbox)"
  printf 'inbox_dir=%s\n' "$(cb_dir "$CB_HANDOFF" inbox)"
  printf 'archive_dir=%s\n' "$(cb_dir "$CB_HANDOFF" archive)"
  printf 'log_dir=%s\n' "$(cb_dir "$CB_HANDOFF" log)"
  printf 'new_json=%s\n' "$(cb_dir "$CB_HANDOFF" inbox)/NEW.json"
  printf 'folders_json=%s\n' "${CB_HANDOFF}/folders.json"
}
