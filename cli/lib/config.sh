# ~/handoff/config.yaml read and write. MIT License.

cb_cfg_append_lines() {
  local current="$1"
  local extra="$2"
  if [[ -z "$current" ]]; then
    printf '%s' "$extra"
  elif [[ -z "$extra" ]]; then
    printf '%s' "$current"
  else
    printf '%s\n%s' "$current" "$extra"
  fi
}

cb_config_reload() {
  CB_CFG_LOADED=0
  cb_load_global_config
}

cb_flag_on() {
  local v
  v="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    1|true|on|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Master switch for automatic receive and copy. Empty means off.
cb_auto_exchange_enabled() {
  local home
  home="$(cb_home)"
  if [[ -f "$home/auto" ]]; then
    [[ "$(cb_state_get "$home" auto off)" == on ]]
    return
  fi
  cb_load_global_config
  if cb_flag_on "${CB_CFG_AUTO_EXCHANGE:-}"; then
    return 0
  fi
  if cb_flag_on "${CB_CFG_DOWNLOADS_WATCH:-}"; then
    return 0
  fi
  return 1
}

cb_downloads_watch_enabled() {
  cb_auto_exchange_enabled
}

cb_auto_copy_enabled() {
  cb_load_global_config
  local v
  v="$(printf '%s' "${CB_CFG_AUTO_COPY:-}" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    1|true|on|yes) return 0 ;;
    *) return 1 ;;
  esac
}

cb_json_string_array() {
  local data="$1" first=1 line
  printf '['
  if [[ -n "$data" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      if [[ "$first" == 1 ]]; then first=0; else printf ','; fi
      printf '"%s"' "$(cb_json_escape "$line")"
    done <<EOF
$data
EOF
  fi
  printf ']'
}

cb_config_write() {
  local file
  cb_ensure_home
  file="$(cb_home)/config.yaml"
  {
    printf '%s\n' "# ChatBar config — handoff spec 0."
    if [[ -n "${CB_CFG_CHAT:-}" ]]; then
      printf 'chat_name: %s\n' "$(cb_yaml_quote "$CB_CFG_CHAT")"
    fi
    if [[ -n "${CB_CFG_OUTBOX:-}" ]]; then
      printf 'outbox_name: %s\n' "$(cb_yaml_quote "$CB_CFG_OUTBOX")"
    fi
    if [[ -n "${CB_CFG_INBOX:-}" ]]; then
      printf 'inbox_name: %s\n' "$(cb_yaml_quote "$CB_CFG_INBOX")"
    fi
    if [[ -n "${CB_CFG_ARCHIVE:-}" ]]; then
      printf 'archive_name: %s\n' "$(cb_yaml_quote "$CB_CFG_ARCHIVE")"
    fi
    if [[ -n "${CB_CFG_LOG:-}" ]]; then
      printf 'log_name: %s\n' "$(cb_yaml_quote "$CB_CFG_LOG")"
    fi
    if [[ -n "${CB_CFG_SYNC:-}" ]]; then
      printf 'sync_to: %s\n' "$(cb_yaml_quote "$CB_CFG_SYNC")"
    fi
    if [[ -n "${CB_CFG_AUTO_EXCHANGE:-}" ]]; then
      printf 'auto_exchange: %s\n' "$(cb_yaml_quote "$CB_CFG_AUTO_EXCHANGE")"
    fi
    if [[ -n "${CB_CFG_DOWNLOADS_WATCH:-}" ]]; then
      printf 'downloads_watch: %s\n' "$(cb_yaml_quote "$CB_CFG_DOWNLOADS_WATCH")"
    fi
    if [[ -n "${CB_CFG_AUTO_COPY:-}" ]]; then
      printf 'auto_copy_on_ready: %s\n' "$(cb_yaml_quote "$CB_CFG_AUTO_COPY")"
    fi
    if [[ -n "${CB_CFG_TIP_MINUTES:-}" ]]; then
      printf 'tip_minutes_per_action: %s\n' "$(cb_yaml_quote "$CB_CFG_TIP_MINUTES")"
    fi
    if [[ -n "${CB_CFG_TIP_COST:-}" ]]; then
      printf 'tip_cost_per_round: %s\n' "$(cb_yaml_quote "$CB_CFG_TIP_COST")"
    fi
    if [[ -n "${CB_CFG_DOWNLOAD_DIRS:-}" ]]; then
      local d
      while IFS= read -r d || [[ -n "$d" ]]; do
        [[ -n "$d" ]] || continue
        printf 'download_dir: %s\n' "$(cb_yaml_quote "$d")"
      done <<EOF
$CB_CFG_DOWNLOAD_DIRS
EOF
    fi
    if [[ -n "${CB_CFG_DOWNLOAD_GLOBS:-}" ]]; then
      local g
      while IFS= read -r g || [[ -n "$g" ]]; do
        [[ -n "$g" ]] || continue
        printf 'download_glob: %s\n' "$(cb_yaml_quote "$g")"
      done <<EOF
$CB_CFG_DOWNLOAD_GLOBS
EOF
    fi
  } | cb_atomic_write "$file"
  CB_CFG_LOADED=0
}

cb_cmd_config_get() {
  local as_json=0
  if [[ "${1:-}" == "--json" ]]; then
    as_json=1
  fi
  cb_load_global_config
  local eff_chat eff_out eff_in eff_ar eff_log watch copy
  eff_chat="$(cb_effective_chat_name "")"
  eff_out="$(cb_effective_role_name outbox "" "")"
  eff_in="$(cb_effective_role_name inbox "" "")"
  eff_ar="$(cb_effective_role_name archive "" "")"
  eff_log="$(cb_effective_role_name log "" "")"
  if cb_auto_exchange_enabled; then watch="true"; else watch="false"; fi
  if cb_auto_copy_enabled; then copy="true"; else copy="false"; fi
  if [[ "$as_json" == 1 ]]; then
    printf '{'
    printf '"home":"%s",' "$(cb_json_escape "$(cb_home)")"
    printf '"chat_name":"%s",' "$(cb_json_escape "${CB_CFG_CHAT:-}")"
    printf '"outbox_name":"%s",' "$(cb_json_escape "${CB_CFG_OUTBOX:-}")"
    printf '"inbox_name":"%s",' "$(cb_json_escape "${CB_CFG_INBOX:-}")"
    printf '"archive_name":"%s",' "$(cb_json_escape "${CB_CFG_ARCHIVE:-}")"
    printf '"log_name":"%s",' "$(cb_json_escape "${CB_CFG_LOG:-}")"
    printf '"auto_exchange":%s,' "$watch"
    printf '"downloads_watch":%s,' "$watch"
    printf '"auto_copy_on_ready":%s,' "$copy"
    printf '"download_dirs":'
    cb_json_string_array "${CB_CFG_DOWNLOAD_DIRS:-}"
    printf ','
    printf '"download_globs":'
    cb_json_string_array "${CB_CFG_DOWNLOAD_GLOBS:-}"
    printf ','
    printf '"effective_chat_name":"%s",' "$(cb_json_escape "$eff_chat")"
    printf '"effective_outbox":"%s",' "$(cb_json_escape "$eff_out")"
    printf '"effective_inbox":"%s",' "$(cb_json_escape "$eff_in")"
    printf '"effective_archive":"%s",' "$(cb_json_escape "$eff_ar")"
    printf '"effective_log":"%s",' "$(cb_json_escape "$eff_log")"
    printf '"tip_minutes_per_action":%s,' "$(cb_tip_minutes)"
    printf '"tip_cost_per_round":%s,' "$(cb_tip_cost)"
    printf '"machine":"%s"' "$(cb_json_escape "$(cb_machine_name)")"
    printf '}\n'
    return 0
  fi
  printf 'home=%s\n' "$(cb_home)"
  printf 'chat_name=%s\n' "${CB_CFG_CHAT:-}"
  printf 'outbox_name=%s\n' "${CB_CFG_OUTBOX:-}"
  printf 'inbox_name=%s\n' "${CB_CFG_INBOX:-}"
  printf 'archive_name=%s\n' "${CB_CFG_ARCHIVE:-}"
  printf 'log_name=%s\n' "${CB_CFG_LOG:-}"
  printf 'auto_exchange=%s\n' "$watch"
  printf 'downloads_watch=%s\n' "$watch"
  printf 'auto_copy_on_ready=%s\n' "$copy"
  printf 'effective_chat_name=%s\n' "$eff_chat"
  printf 'effective_outbox=%s\n' "$eff_out"
  printf 'effective_inbox=%s\n' "$eff_in"
}

cb_cmd_config_set() {
  cb_load_global_config
  local chat="${CB_CFG_CHAT:-}" outbox="${CB_CFG_OUTBOX:-}" inbox="${CB_CFG_INBOX:-}"
  local archive="${CB_CFG_ARCHIVE:-}" logn="${CB_CFG_LOG:-}"
  local watch="${CB_CFG_DOWNLOADS_WATCH:-}" copy="${CB_CFG_AUTO_COPY:-}" exchange="${CB_CFG_AUTO_EXCHANGE:-}"
  local tip_minutes="${CB_CFG_TIP_MINUTES:-}" tip_cost="${CB_CFG_TIP_COST:-}"
  local dirs="${CB_CFG_DOWNLOAD_DIRS:-}" globs="${CB_CFG_DOWNLOAD_GLOBS:-}"
  local set_dirs=0 set_globs=0 set_exchange=0 new_dirs="" new_globs=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chat-name) chat="${2:-}"; shift 2 ;;
      --outbox-name) outbox="${2:-}"; shift 2 ;;
      --inbox-name) inbox="${2:-}"; shift 2 ;;
      --archive-name) archive="${2:-}"; shift 2 ;;
      --log-name) logn="${2:-}"; shift 2 ;;
      --downloads-watch|--auto-exchange) exchange="${2:-}"; watch="${2:-}"; set_exchange=1; shift 2 ;;
      --auto-copy) copy="${2:-}"; shift 2 ;;
      --tip-minutes) tip_minutes="${2:-}"; shift 2 ;;
      --tip-cost) tip_cost="${2:-}"; shift 2 ;;
      --download-dir)
        set_dirs=1
        if [[ -z "$new_dirs" ]]; then new_dirs="${2:-}"; else new_dirs="${new_dirs}"$'\n'"${2:-}"; fi
        shift 2
        ;;
      --clear-download-dirs) set_dirs=1; new_dirs=""; shift ;;
      --download-glob)
        set_globs=1
        if [[ -z "$new_globs" ]]; then new_globs="${2:-}"; else new_globs="${new_globs}"$'\n'"${2:-}"; fi
        shift 2
        ;;
      --clear-download-globs) set_globs=1; new_globs=""; shift ;;
      *) cb_die "unknown config flag: $1" ;;
    esac
  done
  CB_CFG_CHAT="$chat"
  CB_CFG_OUTBOX="$outbox"
  CB_CFG_INBOX="$inbox"
  CB_CFG_ARCHIVE="$archive"
  CB_CFG_LOG="$logn"
  CB_CFG_DOWNLOADS_WATCH="$watch"
  CB_CFG_AUTO_EXCHANGE="$exchange"
  CB_CFG_AUTO_COPY="$copy"
  CB_CFG_TIP_MINUTES="$tip_minutes"
  CB_CFG_TIP_COST="$tip_cost"
  if [[ "$set_dirs" == 1 ]]; then
    CB_CFG_DOWNLOAD_DIRS="$new_dirs"
  else
    CB_CFG_DOWNLOAD_DIRS="$dirs"
  fi
  if [[ "$set_globs" == 1 ]]; then
    CB_CFG_DOWNLOAD_GLOBS="$new_globs"
  else
    CB_CFG_DOWNLOAD_GLOBS="$globs"
  fi
  cb_config_write
  if [[ "$set_exchange" == 1 ]]; then
    if cb_flag_on "$exchange"; then cb_cmd_auto on; else cb_cmd_auto off; fi
  fi
  cb_note "updated $(cb_home)/config.yaml"
}
