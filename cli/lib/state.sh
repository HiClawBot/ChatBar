# Per-project handoff state files. MIT License.
# Contract: spec/handoff-v0.md

cb_read_line() {
  local file="$1"
  local default="$2"
  if [[ -f "$file" ]]; then
    tr -d '\r\n' < "$file"
  else
    printf '%s' "$default"
  fi
}

cb_ensure_layout() {
  local handoff="$1"
  mkdir -p "$handoff"
  if [[ "${CB_ROLE_HANDOFF:-}" == "$handoff" && -n "${CB_ROLE_OUTBOX:-}" ]]; then
    :
  elif [[ -f "${handoff}/folders.json" ]]; then
    CB_ROLE_OUTBOX="$(cb_folders_json_role "$handoff" outbox)"
    CB_ROLE_INBOX="$(cb_folders_json_role "$handoff" inbox)"
    CB_ROLE_ARCHIVE="$(cb_folders_json_role "$handoff" archive)"
    CB_ROLE_LOG="$(cb_folders_json_role "$handoff" log)"
    CB_ROLE_CHAT="$(cb_folders_json_chat "$handoff" 2>/dev/null || printf '%s' "ChatGPT")"
    CB_ROLE_HANDOFF="$handoff"
  else
    CB_ROLE_CHAT="$(cb_effective_chat_name "")"
    CB_ROLE_OUTBOX="$(cb_effective_role_name outbox "" "")"
    CB_ROLE_INBOX="$(cb_effective_role_name inbox "" "")"
    CB_ROLE_ARCHIVE="$(cb_effective_role_name archive "" "")"
    CB_ROLE_LOG="$(cb_effective_role_name log "" "")"
    CB_ROLE_HANDOFF="$handoff"
  fi
  cb_migrate_role_dirs "$handoff"
  cb_write_folders_json "$handoff"
  mkdir -p "$(cb_dir "$handoff" outbox)" "$(cb_dir "$handoff" inbox)" "$(cb_dir "$handoff" archive)" "$(cb_dir "$handoff" log)"
  cb_write_open_command "$handoff"
  if [[ ! -f "${handoff}/round" ]]; then
    cb_atomic_write_string "${handoff}/round" "1"
  fi
  if [[ ! -f "${handoff}/pack-state" ]]; then
    cb_atomic_write_string "${handoff}/pack-state" "none"
  fi
  if [[ ! -f "${handoff}/pack-round" ]]; then
    cb_atomic_write_string "${handoff}/pack-round" "0"
  fi
  if [[ ! -f "${handoff}/inbox-state" ]]; then
    cb_atomic_write_string "${handoff}/inbox-state" "none"
  fi
  if [[ ! -f "${handoff}/inbox-round" ]]; then
    cb_atomic_write_string "${handoff}/inbox-round" "0"
  fi
  if [[ ! -f "${handoff}/inbox-source" ]]; then
    cb_atomic_write_string "${handoff}/inbox-source" ""
  fi
  if [[ ! -f "${handoff}/inbox-at" ]]; then
    cb_atomic_write_string "${handoff}/inbox-at" ""
  fi
  if [[ -n "${CB_NAME:-}" ]] && declare -F cb_publish_opener >/dev/null 2>&1; then
    cb_publish_opener >/dev/null || true
  fi
}

cb_state_get() {
  local handoff="$1"
  local key="$2"
  local default="$3"
  cb_read_line "${handoff}/${key}" "$default"
}

cb_state_set() {
  local handoff="$1"
  local key="$2"
  local value="$3"
  cb_atomic_write_string "${handoff}/${key}" "$value"
}
