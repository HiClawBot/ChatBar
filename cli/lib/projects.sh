# ~/handoff/projects.yaml and the current-project pointer. MIT License.
# Bash 3.2: parallel arrays, no associative arrays.

CB_P_NAME=()
CB_P_REPO=()
CB_P_HANDOFF=()
CB_P_OPENER=()
CB_P_CHAT=()
CB_P_OUTBOX_NAME=()
CB_P_INBOX_NAME=()
CB_P_ARCHIVE_NAME=()
CB_P_LOG_NAME=()
CB_P_WORKSPACE=()
CB_P_SYNC=()
CB_P_TEST=()

cb_projects_reset_current() {
  CB_CUR_IN=0
  CB_CUR_NAME=""
  CB_CUR_REPO=""
  CB_CUR_HANDOFF=""
  CB_CUR_OPENER=""
  CB_CUR_CHAT=""
  CB_CUR_OUTBOX=""
  CB_CUR_INBOX=""
  CB_CUR_ARCHIVE=""
  CB_CUR_LOG=""
  CB_CUR_WORKSPACE=""
  CB_CUR_SYNC=""
  CB_CUR_TEST=""
}

cb_projects_flush_current() {
  if [[ "${CB_CUR_IN:-0}" == 1 && -n "${CB_CUR_NAME:-}" ]]; then
    local handoff="${CB_CUR_HANDOFF:-}"
    if [[ -z "$handoff" && -n "${CB_CUR_REPO:-}" ]]; then
      handoff="${CB_CUR_REPO}/.chatbar"
    fi
    CB_P_NAME+=("$CB_CUR_NAME")
    CB_P_REPO+=("${CB_CUR_REPO:-}")
    CB_P_HANDOFF+=("$handoff")
    CB_P_OPENER+=("${CB_CUR_OPENER:-}")
    CB_P_CHAT+=("${CB_CUR_CHAT:-}")
    CB_P_OUTBOX_NAME+=("${CB_CUR_OUTBOX:-}")
    CB_P_INBOX_NAME+=("${CB_CUR_INBOX:-}")
    CB_P_ARCHIVE_NAME+=("${CB_CUR_ARCHIVE:-}")
    CB_P_LOG_NAME+=("${CB_CUR_LOG:-}")
    CB_P_WORKSPACE+=("${CB_CUR_WORKSPACE:-}")
    CB_P_SYNC+=("${CB_CUR_SYNC:-}")
    CB_P_TEST+=("${CB_CUR_TEST:-}")
  fi
  cb_projects_reset_current
}

cb_projects_load() {
  CB_P_NAME=()
  CB_P_REPO=()
  CB_P_HANDOFF=()
  CB_P_OPENER=()
  CB_P_CHAT=()
  CB_P_OUTBOX_NAME=()
  CB_P_INBOX_NAME=()
  CB_P_ARCHIVE_NAME=()
  CB_P_LOG_NAME=()
  CB_P_WORKSPACE=()
  CB_P_SYNC=()
  CB_P_TEST=()
  cb_projects_reset_current
  local file line trimmed key val
  file="$(cb_home)/projects.yaml"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="$(cb_trim "$line")"
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    if [[ "$trimmed" == "- "* || "$trimmed" == "-" ]]; then
      cb_projects_flush_current
      CB_CUR_IN=1
      trimmed="$(cb_trim "${trimmed#-}")"
      [[ -z "$trimmed" ]] && continue
    fi
    [[ "${CB_CUR_IN:-0}" == 1 ]] || continue
    key="$(cb_trim "${trimmed%%:*}")"
    val="$(cb_unquote "${trimmed#*:}")"
    case "$key" in
      name) CB_CUR_NAME="$val" ;;
      repo) CB_CUR_REPO="$val" ;;
      handoff) CB_CUR_HANDOFF="$val" ;;
      opener) CB_CUR_OPENER="$val" ;;
      chat_name) CB_CUR_CHAT="$val" ;;
      outbox_name) CB_CUR_OUTBOX="$val" ;;
      inbox_name) CB_CUR_INBOX="$val" ;;
      archive_name) CB_CUR_ARCHIVE="$val" ;;
      log_name) CB_CUR_LOG="$val" ;;
      workspace) CB_CUR_WORKSPACE="$val" ;;
      sync_to) CB_CUR_SYNC="$val" ;;
      test_command) CB_CUR_TEST="$val" ;;
    esac
  done < "$file"
  cb_projects_flush_current
}

cb_projects_save() {
  local file i
  cb_ensure_home
  file="$(cb_home)/projects.yaml"
  {
    printf '%s\n' "# ChatBar projects — handoff spec 0. Rewritten by \`chatbar project\`."
    printf '%s\n' "projects:"
    if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
      for i in "${!CB_P_NAME[@]}"; do
        printf '  - name: %s\n' "$(cb_yaml_quote "${CB_P_NAME[$i]}")"
        printf '    repo: %s\n' "$(cb_yaml_quote "${CB_P_REPO[$i]}")"
        printf '    handoff: %s\n' "$(cb_yaml_quote "${CB_P_HANDOFF[$i]}")"
        if [[ -n "${CB_P_OPENER[$i]}" ]]; then
          printf '    opener: %s\n' "$(cb_yaml_quote "${CB_P_OPENER[$i]}")"
        fi
        if [[ -n "${CB_P_CHAT[$i]:-}" ]]; then
          printf '    chat_name: %s\n' "$(cb_yaml_quote "${CB_P_CHAT[$i]}")"
        fi
        if [[ -n "${CB_P_OUTBOX_NAME[$i]:-}" ]]; then
          printf '    outbox_name: %s\n' "$(cb_yaml_quote "${CB_P_OUTBOX_NAME[$i]}")"
        fi
        if [[ -n "${CB_P_INBOX_NAME[$i]:-}" ]]; then
          printf '    inbox_name: %s\n' "$(cb_yaml_quote "${CB_P_INBOX_NAME[$i]}")"
        fi
        if [[ -n "${CB_P_ARCHIVE_NAME[$i]:-}" ]]; then
          printf '    archive_name: %s\n' "$(cb_yaml_quote "${CB_P_ARCHIVE_NAME[$i]}")"
        fi
        if [[ -n "${CB_P_LOG_NAME[$i]:-}" ]]; then
          printf '    log_name: %s\n' "$(cb_yaml_quote "${CB_P_LOG_NAME[$i]}")"
        fi
        if [[ -n "${CB_P_WORKSPACE[$i]:-}" ]]; then
          printf '    workspace: %s\n' "$(cb_yaml_quote "${CB_P_WORKSPACE[$i]}")"
        fi
        if [[ -n "${CB_P_SYNC[$i]:-}" ]]; then
          printf '    sync_to: %s\n' "$(cb_yaml_quote "${CB_P_SYNC[$i]}")"
        fi
        if [[ -n "${CB_P_TEST[$i]:-}" ]]; then
          printf '    test_command: %s\n' "$(cb_yaml_quote "${CB_P_TEST[$i]}")"
        fi
      done
    fi
  } | cb_atomic_write "$file"
}

cb_project_count() {
  cb_projects_load
  printf '%s' "${#CB_P_NAME[@]}"
}

cb_project_find() {
  local name="$1"
  local i
  cb_projects_load
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    return 1
  fi
  for i in "${!CB_P_NAME[@]}"; do
    if [[ "${CB_P_NAME[$i]}" == "$name" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

cb_project_find_by_handoff() {
  local want="$1"
  local canon i
  if [[ -d "$want" ]]; then
    canon="$(cb_abs_dir "$want")"
  else
    canon="$want"
  fi
  cb_projects_load
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    return 1
  fi
  for i in "${!CB_P_HANDOFF[@]}"; do
    if [[ "${CB_P_HANDOFF[$i]}" == "$canon" || "${CB_P_HANDOFF[$i]}" == "$want" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

cb_project_find_by_repo() {
  local repo="$1"
  local i canon
  canon="$(cb_abs_dir "$repo")"
  cb_projects_load
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    return 1
  fi
  for i in "${!CB_P_REPO[@]}"; do
    if [[ "${CB_P_REPO[$i]}" == "$canon" || "${CB_P_REPO[$i]}" == "$repo" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

cb_current_name() {
  local file
  file="$(cb_home)/current"
  [[ -f "$file" ]] || return 1
  local name
  name="$(tr -d '\r\n' < "$file")"
  [[ -n "$name" ]] || return 1
  printf '%s' "$name"
}

cb_current_set() {
  local name="$1"
  cb_ensure_home
  cb_lock "$(cb_home)"
  cb_atomic_write_string "$(cb_home)/current" "$name"
  cb_unlock "$(cb_home)"
}

cb_project_get() {
  # prints name, repo, handoff, opener on four lines
  local idx="$1"
  printf '%s\n' "${CB_P_NAME[$idx]}"
  printf '%s\n' "${CB_P_REPO[$idx]}"
  printf '%s\n' "${CB_P_HANDOFF[$idx]}"
  printf '%s\n' "${CB_P_OPENER[$idx]}"
}

cb_require_project_name() {
  local name="$1"
  local idx
  if [[ -z "$name" ]]; then
    name="$(cb_current_name)" || cb_die "没有当前项目。No current project. Run: chatbar project add --name NAME --repo PATH"
  fi
  idx="$(cb_project_find "$name")" || cb_die "找不到项目。Unknown project: ${name}"
  printf '%s' "$idx"
}

cb_copy_templates() {
  local repo="$1"
  local root src dest
  root="$(cb_install_root)"
  for src in AGENTS.md spec.md status.md; do
    dest="${repo}/${src}"
    if [[ -f "$dest" ]]; then
      cb_note "keep existing ${dest}"
    elif [[ -f "${root}/templates/${src}" ]]; then
      cp "${root}/templates/${src}" "$dest"
      cb_note "wrote ${dest}"
    fi
  done
  if [[ -d "${root}/templates" ]]; then
    mkdir -p "${repo}/templates"
    local opener_src base
    for opener_src in "${root}/templates"/opener*.md; do
      [[ -f "$opener_src" ]] || continue
      base="$(basename "$opener_src")"
      dest="${repo}/templates/${base}"
      if [[ -f "$dest" ]]; then
        cb_note "keep existing ${dest}"
      else
        cp "$opener_src" "$dest"
        cb_note "wrote ${dest}"
      fi
    done
  fi
}

cb_finish_project_layout() {
  local name="$1"
  local idx
  idx="$(cb_project_find "$name")" || cb_die "project disappeared: ${name}"
  cb_load_project_fields "$idx"
  cb_ensure_layout "$CB_HANDOFF"
  cb_current_set "$CB_NAME"
}

cb_cmd_project_add() {
  local name="" repo="" handoff="" opener="" with_templates=0
  local chat="" outbox_name="" inbox_name="" archive_name="" log_name="" workspace="" sync_to="" test_command=""
  local set_opener=0 set_chat=0 set_outbox=0 set_inbox=0 set_archive=0 set_log=0 set_workspace=0 set_sync=0 set_test=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --repo) repo="${2:-}"; shift 2 ;;
      --handoff) handoff="${2:-}"; shift 2 ;;
      --opener) opener="${2:-}"; set_opener=1; shift 2 ;;
      --chat-name) chat="${2:-}"; set_chat=1; shift 2 ;;
      --outbox-name) outbox_name="${2:-}"; set_outbox=1; shift 2 ;;
      --inbox-name) inbox_name="${2:-}"; set_inbox=1; shift 2 ;;
      --archive-name) archive_name="${2:-}"; set_archive=1; shift 2 ;;
      --log-name) log_name="${2:-}"; set_log=1; shift 2 ;;
      --workspace) workspace="${2:-}"; set_workspace=1; shift 2 ;;
      --sync-to) sync_to="${2:-}"; set_sync=1; shift 2 ;;
      --test-command) test_command="${2:-}"; set_test=1; shift 2 ;;
      --with-templates) with_templates=1; shift ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"; shift
        elif [[ -z "$repo" ]]; then
          repo="$1"; shift
        elif [[ -z "$handoff" ]]; then
          handoff="$1"; shift
        else
          cb_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
  [[ -n "$name" ]] || cb_die "missing --name"
  [[ -n "$repo" ]] || cb_die "missing --repo"
  [[ -d "$repo" ]] || cb_die "repo does not exist: ${repo}"
  repo="$(cb_abs_dir "$repo")"
  if [[ -z "$handoff" ]]; then
    handoff="${repo}/.chatbar"
  elif [[ "$handoff" != /* ]]; then
    handoff="$(pwd)/${handoff}"
  fi
  mkdir -p "$handoff"
  handoff="$(cb_abs_dir "$handoff")"
  cb_ensure_home
  cb_lock "$(cb_home)"
  cb_projects_load
  local i
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      if [[ "${CB_P_NAME[$i]}" == "$name" ]]; then
        CB_P_REPO[$i]="$repo"
        CB_P_HANDOFF[$i]="$handoff"
        if [[ "$set_opener" == 1 ]]; then CB_P_OPENER[$i]="$opener"; fi
        if [[ "$set_chat" == 1 ]]; then CB_P_CHAT[$i]="$chat"; fi
        if [[ "$set_outbox" == 1 ]]; then CB_P_OUTBOX_NAME[$i]="$outbox_name"; fi
        if [[ "$set_inbox" == 1 ]]; then CB_P_INBOX_NAME[$i]="$inbox_name"; fi
        if [[ "$set_archive" == 1 ]]; then CB_P_ARCHIVE_NAME[$i]="$archive_name"; fi
        if [[ "$set_log" == 1 ]]; then CB_P_LOG_NAME[$i]="$log_name"; fi
        if [[ "$set_workspace" == 1 ]]; then CB_P_WORKSPACE[$i]="$workspace"; fi
        if [[ "$set_sync" == 1 ]]; then CB_P_SYNC[$i]="$sync_to"; fi
        if [[ "$set_test" == 1 ]]; then CB_P_TEST[$i]="$test_command"; fi
        cb_projects_save
        cb_unlock "$(cb_home)"
        cb_finish_project_layout "$name"
        if [[ "$with_templates" == 1 ]]; then
          cb_copy_templates "$repo"
        fi
        cb_note "updated project ${name}"
        cb_note "handoff ${handoff}"
        return 0
      fi
    done
  fi
  CB_P_NAME+=("$name")
  CB_P_REPO+=("$repo")
  CB_P_HANDOFF+=("$handoff")
  if [[ "$set_opener" == 1 ]]; then
    CB_P_OPENER+=("$opener")
  else
    CB_P_OPENER+=("")
  fi
  if [[ "$set_chat" == 1 ]]; then CB_P_CHAT+=("$chat"); else CB_P_CHAT+=(""); fi
  if [[ "$set_outbox" == 1 ]]; then CB_P_OUTBOX_NAME+=("$outbox_name"); else CB_P_OUTBOX_NAME+=(""); fi
  if [[ "$set_inbox" == 1 ]]; then CB_P_INBOX_NAME+=("$inbox_name"); else CB_P_INBOX_NAME+=(""); fi
  if [[ "$set_archive" == 1 ]]; then CB_P_ARCHIVE_NAME+=("$archive_name"); else CB_P_ARCHIVE_NAME+=(""); fi
  if [[ "$set_log" == 1 ]]; then CB_P_LOG_NAME+=("$log_name"); else CB_P_LOG_NAME+=(""); fi
  if [[ "$set_workspace" == 1 ]]; then CB_P_WORKSPACE+=("$workspace"); else CB_P_WORKSPACE+=(""); fi
  if [[ "$set_sync" == 1 ]]; then CB_P_SYNC+=("$sync_to"); else CB_P_SYNC+=(""); fi
  if [[ "$set_test" == 1 ]]; then CB_P_TEST+=("$test_command"); else CB_P_TEST+=(""); fi
  cb_projects_save
  cb_unlock "$(cb_home)"
  cb_finish_project_layout "$name"
  if [[ "$with_templates" == 1 ]]; then
    cb_copy_templates "$repo"
  fi
  cb_note "added project ${name}"
  cb_note "handoff ${handoff}"
}

cb_cmd_project_list() {
  cb_projects_load
  local current="" i mark
  current="$(cb_current_name || true)"
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    cb_note "(no projects)"
    return 0
  fi
  for i in "${!CB_P_NAME[@]}"; do
    mark=" "
    if [[ "${CB_P_NAME[$i]}" == "$current" ]]; then
      mark="*"
    fi
    printf '%s %s\n' "$mark" "${CB_P_NAME[$i]}"
    printf '  repo: %s\n' "${CB_P_REPO[$i]}"
    printf '  handoff: %s\n' "${CB_P_HANDOFF[$i]}"
    if [[ -n "${CB_P_OPENER[$i]}" ]]; then
      printf '  opener: %s\n' "${CB_P_OPENER[$i]}"
    fi
    printf '  chat: %s\n' "$(cb_effective_chat_name "${CB_P_CHAT[$i]:-}")"
    printf '  outbox: %s\n' "$(basename "$(cb_project_role_dir "$i" outbox)")"
    printf '  inbox: %s\n' "$(basename "$(cb_project_role_dir "$i" inbox)")"
  done
}

cb_cmd_project_use() {
  local name="${1:-}"
  [[ -n "$name" ]] || cb_die "usage: chatbar project use NAME"
  name="$(cb_decode_cli_arg "$name")"
  cb_project_find "$name" >/dev/null || cb_die "unknown project: ${name}"
  cb_current_set "$name"
  cb_note "current project: ${name}"
}

# Local folder dialog only. Does not script any chat app or browser.
cb_pick_folder() {
  if [[ -n "${CHATBAR_PICK_FOLDER:-}" ]]; then
    printf '%s' "$CHATBAR_PICK_FOLDER"
    return 0
  fi
  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v osascript >/dev/null 2>&1; then
    cb_die "选文件夹需要 macOS。Agents use: chatbar project add --name NAME --repo PATH"
  fi
  local picked
  picked="$(osascript -e 'POSIX path of (choose folder with prompt "选择项目文件夹")' 2>/dev/null || true)"
  picked="$(cb_trim "$picked")"
  [[ -n "$picked" ]] || return 1
  printf '%s' "$picked"
}

cb_cmd_project_pick_folder() {
  local folder name
  if ! folder="$(cb_pick_folder)"; then
    cb_note "已取消"
    return 0
  fi
  folder="${folder%/}"
  [[ -d "$folder" ]] || cb_die "文件夹不存在: ${folder}"
  name="$(basename "$folder")"
  [[ -n "$name" && "$name" != "/" && "$name" != "." ]] || cb_die "无法从文件夹得到项目名"
  cb_cmd_project_add --name "$name" --repo "$folder" --with-templates
}

cb_load_project_fields() {
  # Sets CB_NAME CB_REPO CB_HANDOFF CB_OPENER from an index. Arrays must be loaded.
  local idx="$1"
  # find helpers are often called in a command substitution, which cannot
  # update this shell's arrays. Reload from disk when the slot is missing.
  if [[ -z "$idx" || -z "${CB_P_NAME[$idx]:-}" ]]; then
    cb_projects_load
  fi
  if [[ -z "$idx" || -z "${CB_P_NAME[$idx]:-}" ]]; then
    cb_die "project index not loaded: ${idx:-empty}"
  fi
  CB_NAME="${CB_P_NAME[$idx]}"
  CB_REPO="${CB_P_REPO[$idx]}"
  CB_HANDOFF="${CB_P_HANDOFF[$idx]}"
  CB_OPENER_RAW="${CB_P_OPENER[$idx]}"
  CB_OPENER="${CB_P_OPENER[$idx]}"
  CB_CHAT="${CB_P_CHAT[$idx]:-}"
  CB_OUTBOX_NAME="${CB_P_OUTBOX_NAME[$idx]:-}"
  CB_INBOX_NAME="${CB_P_INBOX_NAME[$idx]:-}"
  CB_ARCHIVE_NAME="${CB_P_ARCHIVE_NAME[$idx]:-}"
  CB_LOG_NAME="${CB_P_LOG_NAME[$idx]:-}"
  CB_WORKSPACE="${CB_P_WORKSPACE[$idx]:-}"
  CB_SYNC="${CB_P_SYNC[$idx]:-}"
  CB_TEST_COMMAND="${CB_P_TEST[$idx]:-}"
  if [[ -z "$CB_WORKSPACE" ]]; then
    CB_WORKSPACE="$CB_REPO"
  fi
  if [[ -z "$CB_OPENER" ]]; then
    CB_OPENER="$(cb_default_opener)"
  fi
  cb_apply_roles
}

cb_resolve_project_arg() {
  # $1 optional name or b64. Sets CB_* fields. Echoes nothing.
  local name="${1:-}"
  local idx
  if [[ -n "$name" ]]; then
    name="$(cb_decode_cli_arg "$name")"
  else
    name="$(cb_current_name)" || cb_die "没有当前项目。No current project. Run: chatbar project add --name NAME --repo PATH"
  fi
  idx="$(cb_project_find "$name")" || cb_die "找不到项目。Unknown project: ${name}"
  cb_load_project_fields "$idx"
}

cb_attribute_project() {
  local file="$1"
  local canon i inbox
  canon="$(cb_canon_file "$file")"
  cb_projects_load
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      local candidate mapped role_name
      candidate="$(cb_project_role_dir "$i" inbox)"
      mapped=""
      role_name=""
      if [[ -f "${CB_P_HANDOFF[$i]}/folders.json" ]]; then
        role_name="$(cb_folders_json_role "${CB_P_HANDOFF[$i]}" inbox 2>/dev/null || true)"
      fi
      if [[ -n "$role_name" ]]; then
        mapped="${CB_P_HANDOFF[$i]}/${role_name}"
      fi
      for inbox in "$candidate" "$mapped"; do
        [[ -n "$inbox" ]] || continue
        case "$canon" in
          "$inbox"/*)
            printf '%s' "${CB_P_NAME[$i]}"
            return 0
            ;;
        esac
      done
    done
  fi
  local cur
  if cur="$(cb_current_name)"; then
    printf '%s' "$cur"
    return 0
  fi
  cb_warn "无法归属文件，没有当前项目。Cannot attribute file, no current project: ${file}"
  return 1
}
