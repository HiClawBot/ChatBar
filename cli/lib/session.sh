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
  pack="${outdir}/to_planner.md"
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
  pack="${outdir}/to_planner.md"
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
  pack_file="$(cb_dir "$CB_HANDOFF" outbox)/to_planner.md"
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
  printf 'presented_at=%s\n' "$(cb_state_get "$CB_HANDOFF" "presented-at" "")"
  printf 'pack_at=%s\n' "$(cb_state_get "$CB_HANDOFF" "pack-at" "")"
  if [[ -f "${CB_HANDOFF}/latest-round.txt" ]]; then
    printf 'latest_round=%s\n' "$(tr -d '\r\n' < "${CB_HANDOFF}/latest-round.txt")"
  else
    printf 'latest_round=\n'
  fi
  printf 'full_pack_tool=%s\n' "$tool"
  printf 'opener=%s\n' "$(cb_build_opener "$(cb_active_round)")"
  printf '\n'
}

cb_menu_state_for() {
  local err="$1" inbox="$2" pack="$3"
  if [[ "$inbox" == "new" ]]; then
    printf 'new_reply'
  elif [[ -n "$err" ]]; then
    printf 'error'
  elif [[ "$pack" == "ready" ]]; then
    printf 'pack_waiting'
  else
    printf 'idle'
  fi
}

cb_status_project_json() {
  local idx="$1"
  cb_load_project_fields "$idx"
  cb_ensure_layout "$CB_HANDOFF"
  local current="false" cur
  if cur="$(cb_current_name 2>/dev/null || true)" && [[ "$cur" == "$CB_NAME" ]]; then
    current="true"
  fi
  local pack_state inbox_state pack_round round pack_file err menu
  pack_state="$(cb_state_get "$CB_HANDOFF" "pack-state" "none")"
  inbox_state="$(cb_state_get "$CB_HANDOFF" "inbox-state" "none")"
  pack_round="$(cb_state_get "$CB_HANDOFF" "pack-round" "0")"
  round="$(cb_state_get "$CB_HANDOFF" "round" "1")"
  case "$round" in
    ''|*[!0-9]*) round=0 ;;
  esac
  case "$pack_round" in
    ''|*[!0-9]*) pack_round=0 ;;
  esac
  pack_file="$(cb_dir "$CB_HANDOFF" outbox)/to_planner.md"
  [[ -f "$pack_file" ]] || pack_file=""
  err=""
  if [[ -f "${CB_HANDOFF}/last-error" ]]; then
    err="$(head -n 1 "${CB_HANDOFF}/last-error" | tr -d '\r')"
  fi
  menu="$(cb_menu_state_for "$err" "$inbox_state" "$pack_state")"
  local presented_at pack_at rounds_file
  presented_at="$(cb_state_get "$CB_HANDOFF" "presented-at" "")"
  pack_at="$(cb_state_get "$CB_HANDOFF" "pack-at" "")"
  rounds_file="$(cb_rounds_md_path "$CB_HANDOFF")"
  printf '{'
  printf '"name":"%s",' "$(cb_json_escape "$CB_NAME")"
  printf '"repo":"%s",' "$(cb_json_escape "$CB_REPO")"
  printf '"handoff":"%s",' "$(cb_json_escape "$CB_HANDOFF")"
  printf '"workspace":"%s",' "$(cb_json_escape "$CB_WORKSPACE")"
  printf '"current":%s,' "$current"
  printf '"chat_name":"%s",' "$(cb_json_escape "$CB_ROLE_CHAT")"
  printf '"round":%s,' "$round"
  printf '"pack_state":"%s",' "$(cb_json_escape "$pack_state")"
  printf '"pack_round":%s,' "$pack_round"
  printf '"pack_file":"%s",' "$(cb_json_escape "$pack_file")"
  printf '"inbox_state":"%s",' "$(cb_json_escape "$inbox_state")"
  printf '"outbox_dir":"%s",' "$(cb_json_escape "$(cb_dir "$CB_HANDOFF" outbox)")"
  printf '"inbox_dir":"%s",' "$(cb_json_escape "$(cb_dir "$CB_HANDOFF" inbox)")"
  printf '"presented_at":"%s",' "$(cb_json_escape "$presented_at")"
  printf '"pack_at":"%s",' "$(cb_json_escape "$pack_at")"
  printf '"rounds_file":"%s",' "$(cb_json_escape "$rounds_file")"
  local auto="false" slug
  if cb_flag_on "${CB_AUTO:-}"; then auto="true"; fi
  slug="$(cb_project_slug "$CB_NAME")"
  printf '"menu_state":"%s",' "$menu"
  printf '"error":"%s",' "$(cb_json_escape "$err")"
  printf '"project_auto":%s,' "$auto"
  printf '"slug":"%s"' "$(cb_json_escape "$slug")"
  printf '}'
}

cb_cmd_status() {
  local as_json=0
  if [[ "${1:-}" == "--json" ]]; then
    as_json=1
    shift
  fi
  cb_parse_target_flags "$@"
  cb_projects_load
  if [[ "$as_json" == 1 ]]; then
    local master="false"
    if cb_auto_exchange_enabled; then master="true"; fi
    printf '{'
    printf '"home":"%s",' "$(cb_json_escape "$(cb_home)")"
    printf '"auto_exchange":%s,' "$master"
    printf '"projects":['
    if [[ -n "$CB_FLAG_NAME" || -n "$CB_FLAG_HANDOFF" ]]; then
      local one
      if [[ -n "$CB_FLAG_HANDOFF" ]]; then
        one="$(cb_project_find_by_handoff "$CB_FLAG_HANDOFF")" || cb_die "no project for handoff: ${CB_FLAG_HANDOFF}"
      else
        one="$(cb_project_find "$(cb_decode_cli_arg "$CB_FLAG_NAME")")" || cb_die "unknown project: ${CB_FLAG_NAME}"
      fi
      cb_status_project_json "$one"
    elif [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
      local i
      for i in "${!CB_P_NAME[@]}"; do
        if [[ "$i" -gt 0 ]]; then printf ','; fi
        cb_status_project_json "$i"
      done
    fi
    printf ']}\n'
    return 0
  fi
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

cb_cmd_rounds() {
  cb_select_project_target "$@"
  local file line label when topic status
  file="$(cb_rounds_md_path "$CB_HANDOFF")"
  local -a rows
  rows=()
  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        '| ---'*|'| 轮次'*) continue ;;
        '|'*) rows+=("$line") ;;
      esac
    done < "$file"
  fi
  local start=0 n=${#rows[@]}
  if [[ "$n" -gt 3 ]]; then
    start=$((n - 3))
  fi
  printf '{"rounds":['
  local i=0 first=1 cell
  local -a cells
  while [[ "$start" -lt "$n" ]]; do
    line="${rows[$start]}"
    cells=()
    local rest="${line#|}"
    rest="${rest%|}"
    local IFS='|'
    set -f
    # shellcheck disable=SC2086
    set -- $rest
    set +f
    label="$(cb_trim "${1:-}")"
    when="$(cb_trim "${2:-}")"
    topic="$(cb_trim "${3:-}")"
    status="$(cb_trim "${6:-}")"
    if [[ "$first" == 1 ]]; then first=0; else printf ','; fi
    printf '{"label":"%s","when":"%s","topic":"%s","status":"%s"}' \
      "$(cb_json_escape "$label")" \
      "$(cb_json_escape "$when")" \
      "$(cb_json_escape "$topic")" \
      "$(cb_json_escape "$status")"
    start=$((start + 1))
    i=$((i + 1))
  done
  printf ']}\n'
}
