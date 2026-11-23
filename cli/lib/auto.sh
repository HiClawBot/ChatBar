# Local auto ingest switch. Default off. Does not touch a planner chat.

cb_auto_global_file() {
  printf '%s/auto' "$(cb_home)"
}

cb_auto_global_on() {
  local file value
  file="$(cb_auto_global_file)"
  [[ -f "$file" ]] || return 1
  value="$(tr -d '\r\n' < "$file")"
  [[ "$value" == "on" ]]
}

cb_auto_project_on() {
  local file value
  file="${CB_HANDOFF}/auto"
  [[ -f "$file" ]] || return 1
  value="$(tr -d '\r\n' < "$file")"
  [[ "$value" == "on" ]]
}

cb_auto_word() {
  if [[ "$1" == "on" ]]; then
    printf '开'
  else
    printf '关'
  fi
}

cb_auto_label() {
  printf '自动收发：%s' "$(cb_auto_word "$1")"
}

cb_cmd_auto() {
  local action="${1:-status}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  local project=""
  if [[ "$action" == "toggle-project" ]]; then
    project="$(cb_decode_cli_arg "${1:-}")"
    action="toggle"
    if [[ $# -gt 0 ]]; then
      shift
    fi
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$(cb_decode_cli_arg "${2:-}")"; shift 2 ;;
      *) cb_die "unknown flag: $1" ;;
    esac
  done
  cb_ensure_home
  local file value
  if [[ -n "$project" ]]; then
    cb_resolve_project_arg "$project"
    file="${CB_HANDOFF}/auto"
  else
    file="$(cb_auto_global_file)"
  fi
  case "$action" in
    status)
      if [[ -n "$project" ]]; then
        if cb_auto_project_on; then printf 'on\n'; else printf 'off\n'; fi
      else
        if cb_auto_global_on; then printf 'on\n'; else printf 'off\n'; fi
      fi
      ;;
    enabled)
      cb_auto_global_on || return 1
      if [[ -n "$project" ]]; then
        cb_auto_project_on || return 1
      fi
      ;;
    on|off)
      printf '%s\n' "$action" > "$file"
      cb_note "$(cb_auto_label "$action")"
      ;;
    toggle)
      if [[ -n "$project" ]]; then
        if cb_auto_project_on; then value="off"; else value="on"; fi
      else
        if cb_auto_global_on; then value="off"; else value="on"; fi
      fi
      printf '%s\n' "$value" > "$file"
      cb_note "$(cb_auto_label "$value")"
      ;;
    *)
      cb_die "usage: chatbar auto on|off|toggle|status [--project NAME]"
      ;;
  esac
}
