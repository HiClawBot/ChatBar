# Canonical roles (outbox/inbox/archive/log) -> display directory names.
# Display names are local config. NEW.json lives in the inbox-role folder.
# MIT License. See spec/handoff-v0.md.

CB_CFG_LOADED=0
CB_CFG_HOME=""
CB_CFG_CHAT=""
CB_CFG_OUTBOX=""
CB_CFG_INBOX=""
CB_CFG_ARCHIVE=""
CB_CFG_LOG=""
CB_CFG_SYNC=""
CB_CFG_DOWNLOADS_WATCH=""
CB_CFG_AUTO_COPY=""
CB_CFG_AUTO_EXCHANGE=""
CB_CFG_TIP_MINUTES=""
CB_CFG_TIP_COST=""
CB_CFG_DOWNLOAD_DIRS=""
CB_CFG_DOWNLOAD_GLOBS=""

CB_ROLE_HANDOFF=""
CB_ROLE_CHAT=""
CB_ROLE_OUTBOX=""
CB_ROLE_INBOX=""
CB_ROLE_ARCHIVE=""
CB_ROLE_LOG=""

cb_builtin_template() {
  case "$1" in
    outbox) printf '%s' '①发出_拖给{chat}' ;;
    inbox) printf '%s' '②收回_{chat}回复拖到这里' ;;
    archive) printf '%s' '已归档' ;;
    log) printf '%s' '记录' ;;
    *) return 1 ;;
  esac
}

cb_apply_chat_token() {
  local template="$1"
  local chat="$2"
  printf '%s' "${template//\{chat\}/$chat}"
}

cb_load_global_config() {
  local home
  home="$(cb_home)"
  if [[ "${CB_CFG_LOADED:-0}" == 1 && "${CB_CFG_HOME:-}" == "$home" ]]; then
    return 0
  fi
  CB_CFG_LOADED=1
  CB_CFG_HOME="$home"
  CB_CFG_CHAT=""
  CB_CFG_OUTBOX=""
  CB_CFG_INBOX=""
  CB_CFG_ARCHIVE=""
  CB_CFG_LOG=""
  CB_CFG_SYNC=""
  CB_CFG_DOWNLOADS_WATCH=""
  CB_CFG_AUTO_COPY=""
  CB_CFG_AUTO_EXCHANGE=""
  CB_CFG_TIP_MINUTES=""
  CB_CFG_TIP_COST=""
  CB_CFG_DOWNLOAD_DIRS=""
  CB_CFG_DOWNLOAD_GLOBS=""
  local file="${home}/config.yaml"
  [[ -f "$file" ]] || return 0
  local line trimmed key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="$(cb_trim "$line")"
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    [[ "$trimmed" == projects:* ]] && break
    key="$(cb_trim "${trimmed%%:*}")"
    val="$(cb_unquote "${trimmed#*:}")"
    case "$key" in
      chat_name) CB_CFG_CHAT="$val" ;;
      outbox_name) CB_CFG_OUTBOX="$val" ;;
      inbox_name) CB_CFG_INBOX="$val" ;;
      archive_name) CB_CFG_ARCHIVE="$val" ;;
      log_name) CB_CFG_LOG="$val" ;;
      sync_to) CB_CFG_SYNC="$val" ;;
      downloads_watch) CB_CFG_DOWNLOADS_WATCH="$val" ;;
      auto_copy_on_ready) CB_CFG_AUTO_COPY="$val" ;;
      auto_exchange) CB_CFG_AUTO_EXCHANGE="$val" ;;
      tip_minutes_per_action) CB_CFG_TIP_MINUTES="$val" ;;
      tip_cost_per_round) CB_CFG_TIP_COST="$val" ;;
      download_dir)
        if [[ -z "${CB_CFG_DOWNLOAD_DIRS}" ]]; then
          CB_CFG_DOWNLOAD_DIRS="$val"
        else
          CB_CFG_DOWNLOAD_DIRS="${CB_CFG_DOWNLOAD_DIRS}"$'\n'"$val"
        fi
        ;;
      download_glob)
        if [[ -z "${CB_CFG_DOWNLOAD_GLOBS}" ]]; then
          CB_CFG_DOWNLOAD_GLOBS="$val"
        else
          CB_CFG_DOWNLOAD_GLOBS="${CB_CFG_DOWNLOAD_GLOBS}"$'\n'"$val"
        fi
        ;;
    esac
  done < "$file"
}

# $1 role, $2 project chat_name (empty = inherit), $3 project template override (empty = inherit)
cb_effective_role_name() {
  local role="$1"
  local chat="$2"
  local override="$3"
  cb_load_global_config
  if [[ -z "$chat" ]]; then
    chat="${CB_CFG_CHAT:-ChatGPT}"
  fi
  [[ -n "$chat" ]] || chat="ChatGPT"
  local template="$override"
  if [[ -z "$template" ]]; then
    case "$role" in
      outbox) template="${CB_CFG_OUTBOX:-}" ;;
      inbox) template="${CB_CFG_INBOX:-}" ;;
      archive) template="${CB_CFG_ARCHIVE:-}" ;;
      log) template="${CB_CFG_LOG:-}" ;;
    esac
  fi
  if [[ -z "$template" ]]; then
    template="$(cb_builtin_template "$role")"
  fi
  cb_apply_chat_token "$template" "$chat"
}

cb_effective_chat_name() {
  local chat="$1"
  cb_load_global_config
  if [[ -n "$chat" ]]; then
    printf '%s' "$chat"
  elif [[ -n "${CB_CFG_CHAT:-}" ]]; then
    printf '%s' "$CB_CFG_CHAT"
  else
    printf '%s' "ChatGPT"
  fi
}

cb_apply_roles() {
  CB_ROLE_HANDOFF="${CB_HANDOFF:-}"
  CB_ROLE_CHAT="$(cb_effective_chat_name "${CB_CHAT:-}")"
  CB_ROLE_OUTBOX="$(cb_effective_role_name outbox "${CB_CHAT:-}" "${CB_OUTBOX_NAME:-}")"
  CB_ROLE_INBOX="$(cb_effective_role_name inbox "${CB_CHAT:-}" "${CB_INBOX_NAME:-}")"
  CB_ROLE_ARCHIVE="$(cb_effective_role_name archive "${CB_CHAT:-}" "${CB_ARCHIVE_NAME:-}")"
  CB_ROLE_LOG="$(cb_effective_role_name log "${CB_CHAT:-}" "${CB_LOG_NAME:-}")"
}

cb_folders_json_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  local line val
  line="$(grep -E "^[[:space:]]*\"${key}\"[[:space:]]*:" "$file" | head -n 1 || true)"
  [[ -n "$line" ]] || return 1
  val="${line#*:}"
  val="$(cb_trim "$val")"
  val="${val%,}"
  val="$(cb_unquote "$(cb_trim "$val")")"
  printf '%s' "$val"
}

cb_folders_json_role() {
  cb_folders_json_value "$1/folders.json" "$2"
}

cb_folders_json_chat() {
  cb_folders_json_value "$1/folders.json" "chat_name"
}

cb_role_basename() {
  case "$1" in
    outbox) printf '%s' "$CB_ROLE_OUTBOX" ;;
    inbox) printf '%s' "$CB_ROLE_INBOX" ;;
    archive) printf '%s' "$CB_ROLE_ARCHIVE" ;;
    log) printf '%s' "$CB_ROLE_LOG" ;;
    *) return 1 ;;
  esac
}

cb_dir() {
  local handoff="$1"
  local role="$2"
  local name=""
  if [[ "${CB_ROLE_HANDOFF:-}" == "$handoff" ]]; then
    name="$(cb_role_basename "$role")"
  fi
  if [[ -z "$name" && -f "${handoff}/folders.json" ]]; then
    name="$(cb_folders_json_role "$handoff" "$role" 2>/dev/null || true)"
  fi
  if [[ -z "$name" ]]; then
    name="$(cb_effective_role_name "$role" "" "")"
  fi
  printf '%s/%s' "$handoff" "$name"
}

cb_write_folders_json() {
  local handoff="$1"
  local json
  json="$(printf '{\n  "spec_version": "%s",\n  "chat_name": "%s",\n  "roles": {\n    "outbox": "%s",\n    "inbox": "%s",\n    "archive": "%s",\n    "log": "%s"\n  }\n}\n' \
    "$CB_SPEC_VERSION" \
    "$(cb_json_escape "$CB_ROLE_CHAT")" \
    "$(cb_json_escape "$CB_ROLE_OUTBOX")" \
    "$(cb_json_escape "$CB_ROLE_INBOX")" \
    "$(cb_json_escape "$CB_ROLE_ARCHIVE")" \
    "$(cb_json_escape "$CB_ROLE_LOG")")"
  printf '%s' "$json" | cb_atomic_write "${handoff}/folders.json"
}

cb_migrate_role_dirs() {
  local handoff="$1"
  local role new old
  for role in outbox inbox archive log; do
    new="$(cb_role_basename "$role")"
    [[ -n "$new" ]] || continue
    old=""
    if [[ -f "${handoff}/folders.json" ]]; then
      old="$(cb_folders_json_role "$handoff" "$role" 2>/dev/null || true)"
    fi
    if [[ -n "$old" && "$old" != "$new" && -d "${handoff}/${old}" && ! -e "${handoff}/${new}" ]]; then
      mv "${handoff}/${old}" "${handoff}/${new}"
    fi
    if [[ "$role" != "$new" && -d "${handoff}/${role}" && ! -e "${handoff}/${new}" ]]; then
      mv "${handoff}/${role}" "${handoff}/${new}"
    fi
  done
}

cb_chatbar_bin() {
  if [[ -n "${CB_BIN:-}" && -x "${CB_BIN}" ]]; then
    printf '%s' "$CB_BIN"
    return 0
  fi
  local root
  root="$(cb_install_root)"
  if [[ -x "${root}/cli/chatbar" ]]; then
    printf '%s' "${root}/cli/chatbar"
    return 0
  fi
  command -v chatbar
}

cb_write_open_command() {
  local handoff="$1"
  local dest="${handoff}/打开收发两个窗口.command"
  # A launch-time status read must not point an existing helper at another binary.
  if [[ -n "${CHATBAR_NO_REWRITE:-}" || -e "$dest" ]]; then
    return 0
  fi
  local bin
  bin="$(cb_chatbar_bin)"
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' '# Generated by ChatBar.'
    printf '%s\n' '# Opens the outbox folder (left, pack selected) and the inbox folder (right).'
    printf '%s\n' '# Finder windows only. Does not touch any browser or chat app.'
    printf '%s\n' 'ROOT="$(cd "$(dirname "$0")" && pwd)"'
    printf 'CHATBAR=%q\n' "$bin"
    printf '%s\n' 'if [[ ! -x "$CHATBAR" ]]; then'
    printf '%s\n' '  echo "chatbar not found: $CHATBAR" >&2'
    printf '%s\n' '  exit 1'
    printf '%s\n' 'fi'
    printf '%s\n' 'exec "$CHATBAR" open --handoff "$ROOT"'
  } | cb_atomic_write "$dest"
  chmod +x "$dest"
}

# Finder placement only. Never targets a browser or a chat app.
cb_place_finder_windows() {
  local outbox="$1"
  local inbox="$2"
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  [[ -z "${CHATBAR_NO_OPEN:-}" ]] || return 0
  command -v osascript >/dev/null 2>&1 || return 0
  OUTBOX_PATH="$outbox" INBOX_PATH="$inbox" osascript <<'APPLESCRIPT'
tell application "Finder"
  try
    set outPosix to system attribute "OUTBOX_PATH"
    set inPosix to system attribute "INBOX_PATH"
    set outFolder to POSIX file outPosix as alias
    set inFolder to POSIX file inPosix as alias
    set desk to bounds of window of desktop
    set x0 to item 1 of desk
    set y0 to item 2 of desk
    set x1 to item 3 of desk
    set y1 to item 4 of desk
    set mid to x0 + ((x1 - x0) / 2)
    set topY to y0 + 80
    set botY to y1 - 48
    repeat with w in windows
      try
        set t to (target of w as alias)
        if t is outFolder then
          set bounds of w to {x0 + 8, topY, mid - 6, botY}
        else if t is inFolder then
          set bounds of w to {mid + 6, topY, x1 - 8, botY}
        end if
      end try
    end repeat
  end try
end tell
APPLESCRIPT
}

# Outbox on the left (pack selected when it exists), inbox on the right.
cb_open_pair() {
  local outbox="$1"
  local inbox="$2"
  local pack="${3:-}"
  mkdir -p "$outbox" "$inbox"
  if [[ -n "${CHATBAR_NO_OPEN:-}" || "$(uname -s)" != "Darwin" ]]; then
    if [[ -n "$pack" && -f "$pack" ]]; then
      printf 'reveal:%s\n' "$pack"
    else
      printf 'reveal:%s\n' "$outbox"
    fi
    printf 'reveal:%s\n' "$inbox"
    printf 'layout:outbox-left,inbox-right\n'
    return 0
  fi
  if [[ -n "$pack" && -f "$pack" ]]; then
    open -R "$pack" || cb_warn "open -R failed: ${pack}"
  else
    open "$outbox" || cb_warn "open failed: ${outbox}"
  fi
  open "$inbox" || cb_warn "open failed: ${inbox}"
  cb_place_finder_windows "$outbox" "$inbox" || cb_warn "Finder window placement failed"
}

cb_project_role_dir() {
  local idx="$1"
  local role="$2"
  local override=""
  case "$role" in
    outbox) override="${CB_P_OUTBOX_NAME[$idx]:-}" ;;
    inbox) override="${CB_P_INBOX_NAME[$idx]:-}" ;;
    archive) override="${CB_P_ARCHIVE_NAME[$idx]:-}" ;;
    log) override="${CB_P_LOG_NAME[$idx]:-}" ;;
  esac
  local name
  name="$(cb_effective_role_name "$role" "${CB_P_CHAT[$idx]:-}" "$override")"
  printf '%s/%s' "${CB_P_HANDOFF[$idx]}" "$name"
}
