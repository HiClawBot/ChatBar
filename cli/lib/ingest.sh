# Ingest planner replies: unzip, rename, attribute, write inbox/NEW.json.
# MIT License.

cb_ledger_file() {
  printf '%s/ingested.sha256' "$(cb_dir "$1" log)"
}

cb_ledger_has() {
  local handoff="$1"
  local sum="$2"
  local file
  file="$(cb_ledger_file "$handoff")"
  [[ -f "$file" ]] || return 1
  grep -q -E "^${sum}([[:space:]]|$)" "$file"
}

cb_ledger_add() {
  local handoff="$1"
  local sum="$2"
  local name="$3"
  local file dir
  file="$(cb_ledger_file "$handoff")"
  dir="$(dirname "$file")"
  mkdir -p "$dir"
  if cb_ledger_has "$handoff" "$sum"; then
    return 0
  fi
  printf '%s  %s\n' "$sum" "$name" >> "$file"
}

cb_lock_held_by_other() {
  local dir="$1"
  local lock="${dir}/.lock"
  local pid
  [[ -d "$lock" ]] || return 1
  pid="$(cat "${lock}/pid" 2>/dev/null || true)"
  if [[ -z "$pid" || "$pid" == "$$" ]]; then
    return 1
  fi
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  return 1
}

cb_ingest_on_exit() {
  local rc=$?
  if [[ -n "${CB_INGEST_LOCKDIR:-}" ]]; then
    cb_unlock "$CB_INGEST_LOCKDIR" || true
    CB_INGEST_LOCKDIR=""
    if [[ "$rc" -ne 0 ]]; then
      printf 'chatbar: ingest failed (exit %s). Lock released.\n' "$rc" >&2
    fi
  fi
}

cb_is_zip() {
  local f="$1" sig
  [[ -f "$f" ]] || return 1
  sig="$(od -An -N 4 -tx1 "$f" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  case "$sig" in
    504b0304|504b0506|504b0708) return 0 ;;
    *) return 1 ;;
  esac
}

cb_zip_entries() {
  local zip="$1"
  if unzip -Z1 "$zip" >/dev/null 2>&1; then
    unzip -Z1 "$zip"
    return 0
  fi
  if tar -tf "$zip" >/dev/null 2>&1; then
    tar -tf "$zip"
    return 0
  fi
  return 1
}

cb_zip_entries_safe() {
  local zip="$1"
  local entry bad=0
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    case "$entry" in
      /*|../*|*/../*|*/..|..)
        cb_warn "拒绝 zip 路径。Rejected zip entry: ${entry}"
        bad=1
        ;;
      *\\*)
        cb_warn "拒绝 zip 路径。Rejected zip entry: ${entry}"
        bad=1
        ;;
    esac
    if [[ "$entry" == *":"* && "$entry" != *"://"* ]]; then
      # Windows drive-style "C:..." 
      case "$entry" in
        [A-Za-z]:*)
          cb_warn "拒绝 zip 路径。Rejected zip entry: ${entry}"
          bad=1
          ;;
      esac
    fi
  done < <(cb_zip_entries "$zip")
  [[ "$bad" == 0 ]]
}

cb_file_kind() {
  local name lower
  name="$(basename "$1")"
  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.md) printf 'markdown' ;;
    *.txt) printf 'text' ;;
    *.zip) printf 'zip' ;;
    *.pdf) printf 'pdf' ;;
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.heic|*.heif|*.tif|*.tiff|*.bmp|*.svg) printf 'image' ;;
    *) printf 'file' ;;
  esac
}

cb_normalized_original() {
  local base="$1"
  if [[ "$base" =~ ^r[0-9]+-[0-9]{8}-[0-9]{6}-(.*)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$base"
  fi
}

cb_manifest_write() {
  local handoff="$1"
  local project="$2"
  local round="$3"
  local source="$4"
  local status="$5"
  local received_at="$6"
  local tsv
  tsv="$(cb_dir "$handoff" inbox)/.files.tsv"
  local files_json="["
  local first=1
  local path original bytes from_zip zip_name
  if [[ -f "$tsv" ]]; then
    while IFS="$(printf '\t')" read -r path original bytes from_zip zip_name; do
      [[ -n "$path" ]] || continue
      if [[ "$first" == 1 ]]; then first=0; else files_json="${files_json},"; fi
      local flag="false"
      if [[ "$from_zip" == "1" || "$from_zip" == "true" ]]; then
        flag="true"
      fi
      local kind
      kind="$(cb_file_kind "$original")"
      files_json="${files_json}{\"path\":\"$(cb_json_escape "$path")\",\"original_name\":\"$(cb_json_escape "$original")\",\"bytes\":${bytes:-0},\"from_zip\":${flag},\"zip_name\":\"$(cb_json_escape "$zip_name")\",\"kind\":\"${kind}\"}"
    done < "$tsv"
  fi
  files_json="${files_json}]"
  local json
  json="$(printf '{\n  "spec_version": "%s",\n  "project": "%s",\n  "handoff": "%s",\n  "round": %s,\n  "received_at": "%s",\n  "source": "%s",\n  "status": "%s",\n  "direction": "from_planner",\n  "machine": "%s",\n  "type": "%s",\n  "base_commit": "%s",\n  "patches": %s,\n  "files": %s\n}\n' \
    "$CB_SPEC_VERSION" \
    "$(cb_json_escape "$project")" \
    "$(cb_json_escape "$handoff")" \
    "$round" \
    "$(cb_json_escape "$received_at")" \
    "$(cb_json_escape "$source")" \
    "$(cb_json_escape "$status")" \
    "$(cb_json_escape "$(cb_machine_name)")" \
    "${CB_REPLY_TYPE:-reply}" \
    "$(cb_json_escape "${CB_BASE_COMMIT:-none}")" \
    "${CB_PATCHES_JSON:-[]}" \
    "$files_json")"
  printf '%s' "$json" | cb_atomic_write "$(cb_dir "$handoff" inbox)/NEW.json"
}

cb_tsv_append() {
  local tsv="$1"
  local rel="$2"
  local original="$3"
  local bytes="$4"
  local from_zip="$5"
  local zip_name="$6"
  original="${original//$'\t'/ }"
  zip_name="${zip_name//$'\t'/ }"
  printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$original" "$bytes" "$from_zip" "$zip_name" >> "$tsv"
}

cb_place_file() {
  local handoff="$1"
  local round="$2"
  local stamp="$3"
  local src="$4"
  local original="$5"
  local from_zip="$6"
  local zip_name="$7"
  local safe dest rel bytes n=1
  local inbox
  inbox="$(cb_dir "$handoff" inbox)"
  safe="$(cb_sanitize_filename "$(basename "$original")")"
  dest="${inbox}/r${round}-${stamp}-${safe}"
  while [[ -e "$dest" ]]; do
    n=$((n + 1))
    dest="${inbox}/r${round}-${stamp}-${n}-${safe}"
  done
  # Copy to a temp name in the inbox directory, then rename (same-directory atomic).
  local tmp="${inbox}/.tmp.$$.${RANDOM}"
  cp "$src" "$tmp"
  mv -f "$tmp" "$dest"
  rel="$(cb_rel_under "$handoff" "$dest")"
  bytes="$(cb_bytes "$dest")"
  cb_tsv_append "${inbox}/.files.tsv" "$rel" "$original" "$bytes" "$from_zip" "$zip_name"
  # If the source lives in this inbox and is not the dest, remove it so sweep will not see it again.
  local canon_src canon_inbox
  canon_src="$(cb_canon_file "$src")"
  canon_inbox="$(cb_abs_dir "$(cb_dir "$handoff" inbox)")"
  case "$canon_src" in
    "$canon_inbox"/*)
      if [[ "$canon_src" != "$(cb_canon_file "$dest")" ]]; then
        rm -f "$src"
      fi
      ;;
  esac
}

cb_ingest_zip() {
  local handoff="$1"
  local round="$2"
  local stamp="$3"
  local zip="$4"
  cb_zip_entries_safe "$zip" || cb_die "zip rejected: ${zip}"
  local tmp
  tmp="$(mktemp -d)"
  unzip -q "$zip" -d "$tmp"
  local f relpath
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    relpath="${f#"$tmp"/}"
    case "$relpath" in
      ./*) relpath="${relpath#./}" ;;
    esac
    cb_place_file "$handoff" "$round" "$stamp" "$f" "$relpath" "1" "$(basename "$zip")"
  done < <(find "$tmp" -type f -print)
  rm -rf "$tmp"
  local canon_src canon_inbox raw_dir
  canon_src="$(cb_canon_file "$zip")"
  canon_inbox="$(cb_abs_dir "$(cb_dir "$handoff" inbox)")"
  case "$canon_src" in
    "$canon_inbox"/*)
      raw_dir="$(cb_archive_dest "$handoff" "$round")"
      cb_move_to_archive "$zip" "$raw_dir" >/dev/null
      ;;
  esac
}

cb_ingest_project() {
  local project="$1"
  local source="$2"
  shift 2
  local idx
  idx="$(cb_project_find "$project")" || cb_die "unknown project: ${project}"
  cb_load_project_fields "$idx"
  cb_ensure_layout "$CB_HANDOFF"
  cb_lock "$CB_HANDOFF" || cb_die "无法锁定交接目录。Could not lock ${CB_HANDOFF}"
  CB_INGEST_LOCKDIR="$CB_HANDOFF"
  trap cb_ingest_on_exit EXIT

  local inbox_state pack_state pack_round round stamp
  inbox_state="$(cb_state_get "$CB_HANDOFF" "inbox-state" "none")"
  pack_state="$(cb_state_get "$CB_HANDOFF" "pack-state" "none")"
  pack_round="$(cb_state_get "$CB_HANDOFF" "pack-round" "0")"
  round="$(cb_state_get "$CB_HANDOFF" "round" "1")"
  if [[ "$pack_state" != "none" && "$pack_round" != "0" ]]; then
    round="$pack_round"
  fi
  if [[ "$inbox_state" == "done" ]]; then
    cb_close_round_unlocked "" >/dev/null || true
    inbox_state="none"
  fi
  stamp="$(cb_now_stamp)"
  local f sum
  local -a fresh_files fresh_sums
  fresh_files=()
  fresh_sums=()
  for f in "$@"; do
    [[ -e "$f" ]] || cb_die "not found: ${f}"
    sum="$(cb_sha256 "$f")"
    if cb_ledger_has "$CB_HANDOFF" "$sum"; then
      cb_note "skip already ingested: ${f}"
      continue
    fi
    fresh_files+=("$f")
    fresh_sums+=("$sum")
  done
  local prev_inbox_round
  prev_inbox_round="$(cb_state_get "$CB_HANDOFF" "inbox-round" "0")"
  if [[ "$inbox_state" == "new" && "$prev_inbox_round" != "0" && "$prev_inbox_round" != "$round" ]]; then
    if [[ "${#fresh_files[@]}" -gt 0 ]]; then
      cb_archive_previous_inbox_unlocked "$prev_inbox_round" "${fresh_files[@]}" >/dev/null
    else
      cb_archive_previous_inbox_unlocked "$prev_inbox_round" >/dev/null
    fi
    inbox_state="none"
  fi
  if [[ "$inbox_state" != "new" ]]; then
    printf '' | cb_atomic_write "$(cb_dir "$CB_HANDOFF" inbox)/.files.tsv"
  fi

  if [[ "${#fresh_files[@]}" -eq 0 ]]; then
    cb_unlock "$CB_HANDOFF"
    CB_INGEST_LOCKDIR=""
    trap - EXIT
    cb_note "nothing new to ingest"
    return 0
  fi
  for f in "${fresh_files[@]}"; do
    if cb_is_zip "$f"; then
      cb_ingest_zip "$CB_HANDOFF" "$round" "$stamp" "$f"
    else
      cb_place_file "$CB_HANDOFF" "$round" "$stamp" "$f" "$(basename "$f")" "0" ""
    fi
  done

  cb_collect_patches "$CB_HANDOFF"
  if [[ -f "${CB_HANDOFF}/pack-base" ]]; then
    CB_BASE_COMMIT="$(tr -d '\r\n' < "${CB_HANDOFF}/pack-base")"
  else
    CB_BASE_COMMIT="$(cb_main_commit "$CB_REPO")"
  fi
  local received
  received="$(cb_now_iso)"
  cb_manifest_write "$CB_HANDOFF" "$CB_NAME" "$round" "$source" "new" "$received"
  cb_state_set "$CB_HANDOFF" "inbox-state" "new"
  cb_state_set "$CB_HANDOFF" "inbox-round" "$round"
  cb_state_set "$CB_HANDOFF" "inbox-source" "$source"
  cb_state_set "$CB_HANDOFF" "inbox-at" "$received"

  local bytes=0 b rel files_json="[" first=1
  local path original from_zip zip_name
  if [[ -f "$(cb_dir "$CB_HANDOFF" inbox)/.files.tsv" ]]; then
    while IFS="$(printf '\t')" read -r path original b from_zip zip_name; do
      [[ -n "$path" ]] || continue
      bytes=$((bytes + ${b:-0}))
      if [[ "$first" == 1 ]]; then first=0; else files_json="${files_json},"; fi
      files_json="${files_json}{\"path\":\"$(cb_json_escape "$path")\",\"bytes\":${b:-0}}"
    done < "$(cb_dir "$CB_HANDOFF" inbox)/.files.tsv"
  fi
  files_json="${files_json}]"
  cb_log_event "$CB_HANDOFF" "$CB_NAME" "$round" "from_planner" "$files_json" "$bytes"
  cb_clear_error "$CB_HANDOFF"
  local i
  for i in "${!fresh_sums[@]}"; do
    cb_ledger_add "$CB_HANDOFF" "${fresh_sums[$i]}" "$(basename "${fresh_files[$i]}")"
  done
  local closed="" new_json
  new_json="$(cb_dir "$CB_HANDOFF" inbox)/NEW.json"
  if [[ -f "$(cb_dir "$CB_HANDOFF" outbox)/to_planner.md" ]]; then
    closed="$(cb_close_round_unlocked "" || true)"
  fi
  if [[ -n "$closed" && -f "${closed}/inbox/NEW.json" ]]; then
    new_json="${closed}/inbox/NEW.json"
  fi
  cb_unlock "$CB_HANDOFF"
  CB_INGEST_LOCKDIR=""
  trap - EXIT
  if declare -F cb_run_inbox_hooks >/dev/null 2>&1; then
    cb_run_inbox_hooks "$round" "$new_json" || true
  fi
  if [[ -n "$closed" ]]; then
    cb_publish_opener >/dev/null || true
    cb_note "closed round -> ${closed}"
    cb_notify "ChatBar" "「${CB_NAME}」第 ${round} 轮已归档。"
  else
    cb_note "ingested ${CB_NAME} round ${round} (${bytes} bytes)"
    cb_notify "ChatBar" "已收到规划对话的回复，归入「${CB_NAME}」第 ${round} 轮。"
  fi
}

cb_cmd_ingest() {
  local source="cli"
  local project=""
  local -a files
  files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="${2:-}"; shift 2 ;;
      --source) source="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *) files+=("$1"); shift ;;
    esac
  done
  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      files+=("$1")
      shift
    done
  fi
  if [[ "${#files[@]}" -eq 0 ]]; then
    cb_die "usage: chatbar ingest [--project NAME] FILE..."
  fi
  if [[ -n "$project" ]]; then
    project="$(cb_decode_cli_arg "$project")"
    cb_ingest_project "$project" "$source" "${files[@]}"
    return 0
  fi
  local -a owners
  owners=()
  local f owner
  for f in "${files[@]}"; do
    owner="$(cb_attribute_project "$f")" || return 1
    owners+=("$owner")
  done
  local -a seen
  seen=()
  local i j found
  for i in "${!owners[@]}"; do
    found=0
    if [[ "${#seen[@]}" -gt 0 ]]; then
      for j in "${!seen[@]}"; do
        if [[ "${seen[$j]}" == "${owners[$i]}" ]]; then
          found=1
        fi
      done
    fi
    if [[ "$found" == 0 ]]; then
      seen+=("${owners[$i]}")
    fi
  done
  local group_name
  for group_name in "${seen[@]}"; do
    local -a group
    group=()
    for i in "${!owners[@]}"; do
      if [[ "${owners[$i]}" == "$group_name" ]]; then
        group+=("${files[$i]}")
      fi
    done
    cb_ingest_project "$group_name" "$source" "${group[@]}"
  done
}

cb_cmd_ingest_drop() {
  local raw="${DROPPED_FILES:-}"
  local url="${DROPPED_URL:-}"
  local -a items
  items=()
  if [[ -n "$raw" ]]; then
    while IFS= read -r -d '' path; do
      [[ -n "$path" ]] && items+=("$path")
    done < <(cb_split_dropped "$raw")
  fi
  if [[ -n "$url" ]]; then
    local decoded
    decoded="$(cb_decode_dropped_item "$url")"
    if [[ -n "$decoded" ]]; then
      items+=("$decoded")
    fi
  fi
  if [[ "${#items[@]}" -eq 0 ]]; then
    return 0
  fi
  local -a existing
  existing=()
  local p
  for p in "${items[@]}"; do
    if [[ -f "$p" ]]; then
      existing+=("$p")
    else
      cb_warn "skip missing drop: ${p}"
    fi
  done
  if [[ "${#existing[@]}" -eq 0 ]]; then
    return 0
  fi
  cb_cmd_ingest --source menu-bar-drop -- "${existing[@]}"
}

cb_sweep_settle_skip() {
  local f="$1"
  local settle="${CHATBAR_SWEEP_SETTLE:-1}"
  [[ "$settle" == 0 ]] && return 1
  local now mt
  now="$(date +%s)"
  mt="$(cb_mtime "$f")"
  if [[ $((now - mt)) -lt 1 ]]; then
    return 0
  fi
  return 1
}

cb_cmd_sweep() {
  cb_projects_load
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    return 0
  fi
  local i inbox f base
  local -a pending_names
  local -a pending_files
  pending_names=()
  pending_files=()
  for i in "${!CB_P_NAME[@]}"; do
    cb_load_project_fields "$i"
    if cb_lock_held_by_other "$CB_HANDOFF"; then
      cb_note "skip sweep while locked: ${CB_NAME}"
      continue
    fi
    cb_ensure_layout "$CB_HANDOFF"
    inbox="$(cb_dir "$CB_HANDOFF" inbox)"
    [[ -d "$inbox" ]] || continue
    shopt -s nullglob
    for f in "$inbox"/*; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f")"
      case "$base" in
        NEW.json|opener.txt|.*) continue ;;
        *.crdownload|*.download|*.part) continue ;;
      esac
      if cb_is_normalized_name "$base"; then
        continue
      fi
      if cb_ledger_has "$CB_HANDOFF" "$(cb_sha256 "$f")"; then
        continue
      fi
      if cb_sweep_settle_skip "$f"; then
        continue
      fi
      pending_names+=("${CB_P_NAME[$i]}")
      pending_files+=("$f")
    done
    shopt -u nullglob
  done
  if [[ "${#pending_files[@]}" -eq 0 ]]; then
    return 0
  fi
  local -a seen
  seen=()
  local n j found group_name
  for n in "${!pending_names[@]}"; do
    found=0
    if [[ "${#seen[@]}" -gt 0 ]]; then
      for j in "${!seen[@]}"; do
        if [[ "${seen[$j]}" == "${pending_names[$n]}" ]]; then
          found=1
        fi
      done
    fi
    if [[ "$found" == 0 ]]; then
      seen+=("${pending_names[$n]}")
    fi
  done
  for group_name in "${seen[@]}"; do
    local -a group
    group=()
    for n in "${!pending_names[@]}"; do
      if [[ "${pending_names[$n]}" == "$group_name" ]]; then
        group+=("${pending_files[$n]}")
      fi
    done
    cb_ingest_project "$group_name" "inbox-drop" "${group[@]}"
  done
}

cb_cmd_done() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) name="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else cb_die "unexpected argument: $1"; fi
        ;;
    esac
  done
  cb_resolve_project_arg "$name"
  cb_ensure_layout "$CB_HANDOFF"
  cb_lock "$CB_HANDOFF"
  local inbox_state
  inbox_state="$(cb_state_get "$CB_HANDOFF" "inbox-state" "none")"
  if [[ "$inbox_state" != "new" ]]; then
    cb_unlock "$CB_HANDOFF"
    cb_note "no new reply"
    return 0
  fi
  local dest
  if ! dest="$(cb_close_round_unlocked "")"; then
    cb_unlock "$CB_HANDOFF"
    cb_note "no new reply"
    return 0
  fi
  cb_unlock "$CB_HANDOFF"
  cb_publish_opener >/dev/null || true
  cb_note "marked done ${CB_NAME} -> ${dest}"
}
