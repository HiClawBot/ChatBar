# Move matching downloads into the project inbox, then ingest.
# Never removes a download unless mv has relocated it.
# Does not talk to a chat app. MIT License.

cb_glob_escape() {
  local s="$1" out="" i c len
  len="${#s}"
  i=0
  while [[ "$i" -lt "$len" ]]; do
    c="${s:i:1}"
    case "$c" in
      \\|\*|\?|\[) out="${out}\\${c}" ;;
      *) out="${out}${c}" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

cb_glob_match() {
  local name="$1" pat="$2" rc
  local IFS=
  set -f
  # shellcheck disable=SC2254
  case "$name" in
    $pat) rc=0 ;;
    *) rc=1 ;;
  esac
  set +f
  return "$rc"
}

cb_is_partial_name() {
  local base lower
  base="$(basename "$1")"
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.crdownload|*.download|*.part|*.partial) return 0 ;;
  esac
  return 1
}

cb_project_route_round() {
  local idx="$1" handoff pack_state pack_round round
  handoff="${CB_P_HANDOFF[$idx]}"
  pack_state="$(cb_state_get "$handoff" "pack-state" "none")"
  pack_round="$(cb_state_get "$handoff" "pack-round" "0")"
  round="$(cb_state_get "$handoff" "round" "1")"
  case "$round" in
    ''|*[!0-9]*) round=1 ;;
  esac
  if [[ "$pack_state" != "none" && "$pack_round" =~ ^[0-9]+$ && "$pack_round" != "0" ]]; then
    printf '%s' "$pack_round"
  else
    printf '%s' "$round"
  fi
}

cb_parse_reply_name() {
  local base="$1" lower
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  CB_DL_SLUG=""
  CB_DL_ROUND=""
  if [[ "$lower" =~ ^(.+)_round([0-9]+)_reply\.(md|zip)$ ]]; then
    CB_DL_SLUG="${BASH_REMATCH[1]}"
    CB_DL_ROUND=$((10#${BASH_REMATCH[2]}))
    return 0
  fi
  return 1
}

# A header line in the first 30 lines that contains R### and the project slug.
cb_header_round_for_slug() {
  local file="$1" slug="$2" line n=0 low sluglow
  sluglow="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')"
  [[ -f "$file" ]] || return 1
  local ext
  ext="$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    md|txt|markdown|text) ;;
    *) return 1 ;;
  esac
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ "$n" -le 30 ]] || break
    low="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    [[ "$low" == *"$sluglow"* ]] || continue
    if [[ "$line" =~ (^|[^0-9A-Za-z])R([0-9]{3})([^0-9]|$) ]]; then
      CB_DL_ROUND=$((10#${BASH_REMATCH[2]}))
      return 0
    fi
  done < "$file"
  return 1
}

# Decide where a download goes.
# Sets CB_ROUTE_STATUS to ok, ambiguous, round_mismatch, or nomatch.
# On ok, CB_ROUTE_PROJECT and CB_ROUTE_ROUND are set.
# Does not move the file. Only projects with auto_exchange on are candidates.
cb_route_download() {
  local file="$1"
  local base slug_hits=0 round_hits=0 i slug proj_round name
  CB_ROUTE_STATUS="nomatch"
  CB_ROUTE_PROJECT=""
  CB_ROUTE_ROUND=""
  CB_ROUTE_DETAIL=""
  base="$(basename "$file")"
  cb_projects_load
  local -a ok_names=() bad_names=()
  if cb_parse_reply_name "$base"; then
    if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
      for i in "${!CB_P_NAME[@]}"; do
        cb_auto_enabled "${CB_P_HANDOFF[$i]}" || continue
        slug="$(cb_project_slug "${CB_P_NAME[$i]}")"
        [[ "$slug" == "$CB_DL_SLUG" ]] || continue
        slug_hits=$((slug_hits + 1))
        proj_round="$(cb_project_route_round "$i")"
        if [[ "$proj_round" == "$CB_DL_ROUND" ]]; then
          ok_names+=("${CB_P_NAME[$i]}")
        else
          bad_names+=("${CB_P_NAME[$i]}:$proj_round")
        fi
      done
    fi
    if [[ "$slug_hits" -gt 1 ]]; then
      CB_ROUTE_STATUS="ambiguous"
      CB_ROUTE_ROUND="$CB_DL_ROUND"
      CB_ROUTE_DETAIL="$(printf '%s\n' "${ok_names[@]+"${ok_names[@]}"}" "${bad_names[@]+"${bad_names[@]}"}" | paste -sd, -)"
      return 0
    fi
    if [[ "${#ok_names[@]}" -eq 1 ]]; then
      CB_ROUTE_STATUS="ok"
      CB_ROUTE_PROJECT="${ok_names[0]}"
      CB_ROUTE_ROUND="$CB_DL_ROUND"
      return 0
    fi
    if [[ "$slug_hits" -eq 1 ]]; then
      CB_ROUTE_STATUS="round_mismatch"
      CB_ROUTE_PROJECT="${bad_names[0]%%:*}"
      CB_ROUTE_ROUND="$CB_DL_ROUND"
      CB_ROUTE_DETAIL="${bad_names[0]#*:}"
      return 0
    fi
  fi
  ok_names=()
  bad_names=()
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      cb_auto_enabled "${CB_P_HANDOFF[$i]}" || continue
      name="${CB_P_NAME[$i]}"
      slug="$(cb_project_slug "$name")"
      if cb_header_round_for_slug "$file" "$slug"; then
        proj_round="$(cb_project_route_round "$i")"
        if [[ "$proj_round" == "$CB_DL_ROUND" ]]; then
          ok_names+=("$name")
        else
          bad_names+=("${name}:$proj_round")
          round_hits=$((round_hits + 1))
        fi
      fi
    done
  fi
  if [[ "${#ok_names[@]}" -gt 1 ]]; then
    CB_ROUTE_STATUS="ambiguous"
    CB_ROUTE_DETAIL="$(printf '%s\n' "${ok_names[@]}" | paste -sd, -)"
    return 0
  fi
  if [[ "${#ok_names[@]}" -eq 1 && "$round_hits" -gt 0 ]]; then
    CB_ROUTE_STATUS="ambiguous"
    CB_ROUTE_DETAIL="$(printf '%s\n' "${ok_names[@]}" "${bad_names[@]}" | paste -sd, -)"
    return 0
  fi
  if [[ "${#ok_names[@]}" -eq 1 ]]; then
    CB_ROUTE_STATUS="ok"
    CB_ROUTE_PROJECT="${ok_names[0]}"
    CB_ROUTE_ROUND="$CB_DL_ROUND"
    return 0
  fi
  if [[ "$round_hits" -gt 0 ]]; then
    CB_ROUTE_STATUS="round_mismatch"
    CB_ROUTE_PROJECT="${bad_names[0]%%:*}"
    CB_ROUTE_DETAIL="${bad_names[0]#*:}"
    return 0
  fi
  CB_ROUTE_STATUS="nomatch"
  return 0
}

cb_unique_dest() {
  local dir="$1" base="$2" stem ext n candidate
  mkdir -p "$dir"
  if [[ "$base" == *.* && "${base#.}" == "$base" ]]; then
    stem="${base%.*}"
    ext=".${base##*.}"
  else
    stem="$base"
    ext=""
  fi
  candidate="${dir}/${base}"
  if [[ ! -e "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  n=2
  while [[ -e "${dir}/${stem}-${n}${ext}" ]]; do
    n=$((n + 1))
    if [[ "$n" -gt 500 ]]; then
      break
    fi
  done
  printf '%s' "${dir}/${stem}-${n}${ext}"
}

cb_ledger_file() {
  printf '%s' "$(cb_home)/.download-sizes.tsv"
}

cb_ledger_get() {
  local want="$1" p s
  [[ -f "$(cb_ledger_file)" ]] || return 0
  while IFS="$(printf '\t')" read -r p s || [[ -n "${p:-}" ]]; do
    if [[ "$p" == "$want" ]]; then
      printf '%s' "$s"
      return 0
    fi
  done < "$(cb_ledger_file)"
}

cb_ledger_rewrite() {
  local drop="$1" add_path="${2:-}" add_size="${3:-}"
  local file tmp p s
  file="$(cb_ledger_file)"
  tmp="${file}.tmp.$$"
  : > "$tmp"
  if [[ -f "$file" ]]; then
    while IFS="$(printf '\t')" read -r p s || [[ -n "${p:-}" ]]; do
      [[ -n "$p" ]] || continue
      [[ "$p" == "$drop" ]] && continue
      printf '%s\t%s\n' "$p" "$s" >> "$tmp"
    done < "$file"
  fi
  if [[ -n "$add_path" ]]; then
    printf '%s\t%s\n' "$add_path" "$add_size" >> "$tmp"
  fi
  mv -f "$tmp" "$file"
}

cb_file_is_stable() {
  local file="$1" size prev
  if [[ "${CHATBAR_DOWNLOADS_REQUIRE_STABLE:-1}" == "0" ]]; then
    return 0
  fi
  size="$(wc -c < "$file" | tr -d '[:space:]')"
  prev="$(cb_ledger_get "$file")"
  cb_ledger_rewrite "$file" "$file" "$size"
  if [[ -z "$prev" || "$prev" != "$size" ]]; then
    return 1
  fi
  return 0
}

cb_download_dirs() {
  cb_load_global_config
  if [[ -z "${CB_CFG_DOWNLOAD_DIRS:-}" ]]; then
    printf '%s\n' "${HOME}/Downloads"
    return 0
  fi
  printf '%s\n' "$CB_CFG_DOWNLOAD_DIRS"
}

cb_sha256_file() {
  local file="$1" out
  if command -v sha256sum >/dev/null 2>&1; then
    out="$(sha256sum "$file")"
  elif command -v shasum >/dev/null 2>&1; then
    out="$(shasum -a 256 "$file")"
  else
    cb_die "sha256sum or shasum is required"
  fi
  printf '%s' "${out%% *}"
}

cb_sha_ledger() {
  printf '%s' "$(cb_home)/ingest-sha.tsv"
}

cb_sha_seen() {
  local project="$1" round="$2" sha="$3" p r s
  [[ -f "$(cb_sha_ledger)" ]] || return 1
  while IFS="$(printf '\t')" read -r p r s _ || [[ -n "${p:-}" ]]; do
    if [[ "$p" == "$project" && "$r" == "$round" && "$s" == "$sha" ]]; then
      return 0
    fi
  done < "$(cb_sha_ledger)"
  return 1
}

cb_sha_record() {
  local project="$1" round="$2" sha="$3" src="$4"
  cb_ensure_home
  printf '%s\t%s\t%s\t%s\t%s\n' "$project" "$round" "$sha" "$(cb_now_iso)" "$src" >> "$(cb_sha_ledger)"
}

cb_dup_note_file() {
  printf '%s' "$(cb_home)/download-duplicates.tsv"
}

cb_dup_already_logged() {
  local path="$1" sha="$2" p s
  [[ -f "$(cb_dup_note_file)" ]] || return 1
  while IFS="$(printf '\t')" read -r p s || [[ -n "${p:-}" ]]; do
    if [[ "$p" == "$path" && "$s" == "$sha" ]]; then
      return 0
    fi
  done < "$(cb_dup_note_file)"
  return 1
}

cb_log_download() {
  local kind="$1"
  shift
  cb_ensure_home
  printf '%s\t%s' "$(cb_now_iso)" "$kind" >> "$(cb_home)/downloads.log"
  local part
  for part in "$@"; do
    printf '\t%s' "$part" >> "$(cb_home)/downloads.log"
  done
  printf '\n' >> "$(cb_home)/downloads.log"
}

cb_pending_file() {
  printf '%s' "$(cb_home)/download-pending.tsv"
}

cb_write_pending() {
  local body="$1"
  cb_ensure_home
  if [[ -z "$body" ]]; then
    : > "$(cb_pending_file)"
    return 0
  fi
  printf '%s\n' "$body" | cb_atomic_write "$(cb_pending_file)"
}

cb_notify_pending_once() {
  local path="$1" reason="$2" note_file seen
  note_file="$(cb_home)/download-notified.tsv"
  seen="${path}"$'\t'"${reason}"
  if [[ -f "$note_file" ]] && grep -F -x -q -- "$seen" "$note_file"; then
    return 0
  fi
  cb_ensure_home
  printf '%s\n' "$seen" >> "$note_file"
  cb_notify "ChatBar" "有下载无法自动归入项目。打开 ChatBar，在卡片里选择项目。文件仍留在原地。"
}

cb_ingest_routed_file() {
  local file="$1" project="$2" round="$3" sha
  sha="$(cb_sha256_file "$file")"
  if cb_sha_seen "$project" "$round" "$sha"; then
    if ! cb_dup_already_logged "$file" "$sha"; then
      cb_ensure_home
      printf '%s\t%s\n' "$file" "$sha" >> "$(cb_dup_note_file)"
      cb_log_download "duplicate" "$project" "$round" "$sha" "$file"
      printf 'duplicate\t%s\t%s\t%s\t%s\n' "$project" "$round" "$sha" "$file"
    fi
    return 0
  fi
  local idx inbox dest
  idx="$(cb_project_find "$project")" || return 1
  cb_load_project_fields "$idx"
  cb_ensure_layout "$CB_HANDOFF"
  inbox="$(cb_dir "$CB_HANDOFF" inbox)"
  dest="$(cb_unique_dest "$inbox" "$(basename "$file")")"
  if mv "$file" "$dest"; then
    cb_ledger_rewrite "$file"
    cb_log_download "moved" "$project" "$file" "$dest"
    printf 'moved\t%s\t%s\n' "$project" "$dest"
    if cb_cmd_ingest --project "$project" --source downloads-watch -- "$dest"; then
      cb_sha_record "$project" "$round" "$sha" "$file"
    else
      cb_warn "ingest failed: ${dest}"
    fi
  else
    cb_warn "move failed, left in place: ${file}"
  fi
}

cb_cmd_downloads_scan() {
  local force=0
  if [[ "${1:-}" == "--force" ]]; then
    force=1
  fi
  if [[ "$force" == 0 ]] && ! cb_auto_exchange_enabled; then
    cb_write_pending ""
    return 0
  fi
  cb_projects_load
  local dir f base pending=""
  while IFS= read -r dir <&3 || [[ -n "$dir" ]]; do
    [[ -n "$dir" && -d "$dir" ]] || continue
    shopt -s nullglob
    for f in "$dir"/*; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f")"
      case "$base" in
        .*) continue ;;
      esac
      if cb_is_partial_name "$base"; then
        continue
      fi
      if ! cb_file_is_stable "$f"; then
        continue
      fi
      cb_route_download "$f"
      case "$CB_ROUTE_STATUS" in
        ok)
          cb_ingest_routed_file "$f" "$CB_ROUTE_PROJECT" "$CB_ROUTE_ROUND"
          ;;
        ambiguous|round_mismatch|nomatch)
          local row
          row="$(printf '%s\t%s\t%s\t%s' "$f" "$CB_ROUTE_STATUS" "$CB_ROUTE_PROJECT" "$CB_ROUTE_DETAIL")"
          if [[ -z "$pending" ]]; then pending="$row"; else pending="${pending}"$'\n'"$row"; fi
          printf 'pending\t%s\t%s\t%s\t%s\n' "$CB_ROUTE_STATUS" "$f" "$CB_ROUTE_PROJECT" "$CB_ROUTE_DETAIL"
          cb_notify_pending_once "$f" "$CB_ROUTE_STATUS"
          ;;
      esac
    done
    shopt -u nullglob
  done 3<<EOF
$(cb_download_dirs)
EOF
  cb_write_pending "$pending"
}

cb_cmd_downloads_pending() {
  local file line path reason project detail first=1
  file="$(cb_pending_file)"
  printf '{"items":['
  if [[ -f "$file" ]]; then
    while IFS="$(printf '\t')" read -r path reason project detail || [[ -n "${path:-}" ]]; do
      [[ -n "$path" ]] || continue
      if [[ "$first" == 1 ]]; then first=0; else printf ','; fi
      printf '{"path":"%s","name":"%s","reason":"%s","project":"%s","detail":"%s"}' \
        "$(cb_json_escape "$path")" \
        "$(cb_json_escape "$(basename "$path")")" \
        "$(cb_json_escape "$reason")" \
        "$(cb_json_escape "$project")" \
        "$(cb_json_escape "$detail")"
    done < "$file"
  fi
  printf ']}\n'
}

cb_cmd_downloads_assign() {
  local file="" project=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      *) cb_die "usage: chatbar downloads-assign --file PATH --project NAME" ;;
    esac
  done
  [[ -n "$file" && -n "$project" ]] || cb_die "usage: chatbar downloads-assign --file PATH --project NAME"
  [[ -f "$file" ]] || cb_die "not a file: ${file}"
  if cb_is_partial_name "$file"; then
    cb_die "still downloading: ${file}"
  fi
  project="$(cb_decode_cli_arg "$project")"
  cb_projects_load
  local idx round
  idx="$(cb_project_find "$project")" || cb_die "unknown project: ${project}"
  round="$(cb_project_route_round "$idx")"
  cb_ingest_routed_file "$file" "$project" "$round"
  if [[ -f "$(cb_pending_file)" ]]; then
    local kept="" line path rest
    while IFS= read -r line || [[ -n "$line" ]]; do
      path="${line%%$'\t'*}"
      [[ "$path" == "$file" ]] && continue
      if [[ -z "$kept" ]]; then kept="$line"; else kept="${kept}"$'\n'"$line"; fi
    done < "$(cb_pending_file)"
    cb_write_pending "$kept"
  fi
}
