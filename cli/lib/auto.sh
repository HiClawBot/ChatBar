# Local auto-exchange only: opted-in Git hooks pack, and sweeps pick up named replies.

cb_auto_enabled() {
  local path
  if [[ -n "${1:-}" ]]; then
    path="$1"
  else
    path="$(cb_home)"
  fi
  [[ "$(cb_state_get "$path" auto off)" == on ]]
}

cb_auto_label() {
  if cb_auto_enabled "${1:-}"; then
    printf '自动收发：开'
  else
    printf '自动收发：关'
  fi
}

cb_cmd_auto() (
  local action="${1:-status}" name="" path value
  if [[ $# -gt 0 ]]; then shift; fi
  if [[ "$action" == toggle-project ]]; then action=toggle; fi
  case "${1:-}" in
    --project)
      [[ $# == 2 && -n "$2" ]] || cb_die "missing --project value"
      name="$2"
      ;;
    '') ;;
    *)
      [[ $# == 1 ]] || cb_die "expected one project name"
      name="$1"
      ;;
  esac
  if [[ -n "$name" ]]; then
    cb_resolve_project_arg "$name"
    path="$CB_HANDOFF"
  else
    path="$(cb_home)"
  fi
  case "$action" in
    status)
      if cb_auto_enabled "$path"; then printf 'on\n'; else printf 'off\n'; fi
      exit 0
      ;;
    enabled)
      cb_auto_enabled && cb_auto_enabled "$path"
      exit
      ;;
    on|off|toggle) ;;
    *) cb_die "usage: chatbar auto on|off|toggle|status [--project NAME]" ;;
  esac
  cb_lock "$path" || exit 1
  trap 'cb_unlock "$path"' EXIT
  value="$action"
  if [[ "$action" == toggle ]]; then
    if cb_auto_enabled "$path"; then value=off; else value=on; fi
  fi
  cb_state_set "$path" auto "$value"
  cb_note "$(cb_auto_label "$path")"
)

cb_sweep_download() (
  local name="$1" file round i hits=0
  cb_resolve_project_arg "$name"
  cb_auto_enabled && cb_auto_enabled "$CB_HANDOFF" || exit 0
  cb_lock "$CB_HANDOFF" || exit 1
  trap 'cb_unlock "$CB_HANDOFF"' EXIT
  cb_auto_enabled && cb_auto_enabled "$CB_HANDOFF" || exit 0
  cb_next_fields transfer
  [[ "$CB_NEXT_STEP" == wait ]] || exit 0
  file="$CB_NEXT_FILE"
  round="$CB_NEXT_ROUND"
  [[ -f "$file" && ! -L "$file" ]] || exit 0
  [[ "$(cb_mtime "$file")" -ge "$CB_NEXT_SENT_AT" ]] || exit 0
  cb_sweep_settle_skip "$file" && exit 0

  # Two project names can normalize to the same reply filename.
  for i in "${!CB_P_NAME[@]}"; do
    if [[ "$(cb_reply_download_name "${CB_P_NAME[$i]}" "$round")" == "${file##*/}" ]]; then
      hits=$((hits + 1))
    fi
  done
  [[ "$hits" == 1 ]] || exit 0
  cb_ledger_has "$CB_HANDOFF" "$(cb_sha256 "$file")" && exit 0
  cb_is_zip "$file" && unzip -tq "$file" >/dev/null 2>&1 || exit 0

  # The existing importer takes the same lock again. Let this subshell keep
  # its outer lock cleanup even if the importer changes the EXIT trap.
  (cb_ingest_project "$name" downloads "$file")
)

cb_sweep_downloads() {
  cb_auto_enabled && [[ "${#CB_P_NAME[@]}" -gt 0 ]] || return 0
  local name
  for name in "${CB_P_NAME[@]}"; do
    cb_sweep_download "$name" || cb_warn "could not collect download for ${name}"
  done
}
