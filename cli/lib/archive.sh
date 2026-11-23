# Per-round archive. Outbox and inbox keep only the current round.
# Closed rounds live in archive/YYYY-MM/Rnnn_YYYY-MM-DD_HHMM_slug/.
# MIT License.

# Raw planner zips land in <archive>/YYYY-MM/Rnnn_raw so a later sweep
# cannot unpack the same archive again.
cb_archive_dest() {
  local handoff="$1"
  local round="$2"
  local label
  label="$(cb_round_label "$round")"
  printf '%s/%s/%s_raw' "$(cb_dir "$handoff" archive)" "$(cb_today)" "$label"
}

cb_move_to_archive() {
  local src="$1"
  local dest_dir="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$dest_dir"
  local base dest
  base="$(basename "$src")"
  dest="${dest_dir}/${base}"
  if [[ -e "$dest" ]]; then
    dest="${dest_dir}/$(date +%H%M%S)-${base}"
  fi
  mv -f "$src" "$dest"
  printf '%s' "$dest"
}

cb_slug() {
  local s="$1"
  local out="" i c len
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  len="${#s}"
  i=0
  while [[ "$i" -lt "$len" ]]; do
    c="${s:i:1}"
    case "$c" in
      [a-z0-9._-]) out="${out}${c}" ;;
      [[:space:]]|"/"|":") out="${out}-" ;;
      *)
        if printf '%s' "$c" | grep -q '^[ -~]$'; then
          out="${out}-"
        else
          out="${out}${c}"
        fi
        ;;
    esac
    i=$((i + 1))
  done
  while [[ "$out" == *--* ]]; do
    out="${out//--/-}"
  done
  out="${out#-}"
  out="${out%-}"
  if [[ -z "$out" ]]; then
    out="round"
  fi
  if [[ "${#out}" -gt 40 ]]; then
    out="${out:0:40}"
    out="${out%-}"
  fi
  printf '%s' "$out"
}

cb_guess_topic() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
    return 0
  fi
  local f line
  for f in "${CB_HANDOFF}/topic.txt" "${CB_REPO}/topic.txt"; do
    if [[ -f "$f" ]]; then
      line="$(head -n 1 "$f" | tr -d '\r')"
      line="$(cb_trim "$line")"
      if [[ -n "$line" ]]; then
        printf '%s' "$line"
        return 0
      fi
    fi
  done
  for f in "${CB_REPO}/status.md" "${CB_HANDOFF}/status.md"; do
    [[ -f "$f" ]] || continue
    line="$(grep -E '^(Topic|主题)[[:space:]]*[:：]' "$f" | head -n 1 || true)"
    if [[ -n "$line" ]]; then
      line="${line#*:}"
      line="${line#*：}"
      line="$(cb_trim "$line")"
      if [[ -n "$line" ]]; then
        printf '%s' "$line"
        return 0
      fi
    fi
  done
  printf '%s' "round"
}

cb_md_cell() {
  local s="$1"
  s="${s//|/／}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

cb_rounds_md_path() {
  printf '%s/%s' "$(cb_dir "$1" log)" "轮次总表.md"
}

cb_append_rounds_md() {
  local handoff="$1"
  local label="$2"
  local when="$3"
  local topic="$4"
  local sent="$5"
  local received="$6"
  local file row
  file="$(cb_rounds_md_path "$handoff")"
  row="$(printf '| %s | %s | %s | %s | %s | 已归档 |' \
    "$(cb_md_cell "$label")" \
    "$(cb_md_cell "$when")" \
    "$(cb_md_cell "$topic")" \
    "$(cb_md_cell "$sent")" \
    "$(cb_md_cell "$received")")"
  if [[ ! -f "$file" ]]; then
    {
      printf '%s\n' '# 轮次总表'
      printf '\n'
      printf '%s\n' '每一行是一轮：发出的包和收回的回复放在一起，不按天或按周拆开。'
      printf '\n'
      printf '%s\n' '| 轮次 | 时间 | 主题 | 发出 | 收回 | 状态 |'
      printf '%s\n' '| --- | --- | --- | --- | --- | --- |'
      printf '%s\n' "$row"
    } | cb_atomic_write "$file"
  else
    local body
    body="$(cat "$file")"
    printf '%s\n%s\n' "$body" "$row" | cb_atomic_write "$file"
  fi
}

cb_list_moved_files() {
  local dir="$1"
  local prefix="$2"
  local first=1
  local names="" json="[" f base b rel
  shopt -s nullglob
  for f in "$dir"/* "$dir"/.[!.]*; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    case "$base" in
      .|..|.tmp.*) continue ;;
    esac
    b="$(cb_bytes "$f")"
    rel="${prefix}/${base}"
    if [[ "$first" == 1 ]]; then
      first=0
    else
      json="${json},"
      names="${names}, "
    fi
    json="${json}{\"path\":\"$(cb_json_escape "$rel")\",\"bytes\":${b}}"
    names="${names}${base}"
  done
  shopt -u nullglob
  json="${json}]"
  printf '%s\n' "$names"
  printf '%s\n' "$json"
}

cb_move_children() {
  local src="$1"
  local dest="$2"
  mkdir -p "$dest"
  local f base
  shopt -s nullglob
  for f in "$src"/* "$src"/.[!.]*; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    case "$base" in
      .|..|.tmp.*|.lock) continue ;;
    esac
    mv -f "$f" "${dest}/${base}"
  done
  shopt -u nullglob
}

# Caller holds the handoff lock. Prints the archive directory on success.
cb_close_round_unlocked() {
  local topic_arg="${1:-}"
  local outdir inbox
  outdir="$(cb_dir "$CB_HANDOFF" outbox)"
  inbox="$(cb_dir "$CB_HANDOFF" inbox)"
  local has=0 f
  shopt -s nullglob
  for f in "$outdir"/* "$outdir"/.[!.]* "$inbox"/* "$inbox"/.[!.]*; do
    [[ -e "$f" ]] || continue
    case "$(basename "$f")" in
      .|..|.tmp.*|.lock) continue ;;
    esac
    has=1
    break
  done
  shopt -u nullglob
  if [[ "$has" == 0 ]]; then
    return 1
  fi

  local round_num
  round_num="$(cb_state_get "$CB_HANDOFF" "pack-round" "0")"
  if [[ "$round_num" == "0" ]]; then
    round_num="$(cb_state_get "$CB_HANDOFF" "round" "1")"
  fi
  local label stamp month topic slug dest when_iso when_human
  label="$(printf 'R%03d' "$round_num")"
  stamp="$(date '+%Y-%m-%d_%H%M')"
  month="$(date '+%Y-%m')"
  when_iso="$(cb_now_iso)"
  when_human="$(date '+%Y-%m-%d %H:%M')"
  topic="$(cb_guess_topic "$topic_arg")"
  slug="$(cb_slug "$topic")"
  dest="$(cb_dir "$CB_HANDOFF" archive)/${month}/${label}_${stamp}_${slug}"
  local n=2
  while [[ -e "$dest" ]]; do
    dest="$(cb_dir "$CB_HANDOFF" archive)/${month}/${label}_${stamp}_${slug}-${n}"
    n=$((n + 1))
  done
  mkdir -p "${dest}/outbox" "${dest}/inbox"
  cb_move_children "$outdir" "${dest}/outbox"
  cb_move_children "$inbox" "${dest}/inbox"

  local sent_meta recv_meta sent_names recv_names sent_json recv_json
  sent_meta="$(cb_list_moved_files "${dest}/outbox" "outbox")"
  recv_meta="$(cb_list_moved_files "${dest}/inbox" "inbox")"
  sent_names="$(printf '%s\n' "$sent_meta" | head -n 1)"
  sent_json="$(printf '%s\n' "$sent_meta" | tail -n 1)"
  recv_names="$(printf '%s\n' "$recv_meta" | head -n 1)"
  recv_json="$(printf '%s\n' "$recv_meta" | tail -n 1)"
  [[ -n "$sent_names" ]] || sent_names="-"
  [[ -n "$recv_names" ]] || recv_names="-"

  local manifest
  manifest="$(printf '{\n  "spec_version": "%s",\n  "project": "%s",\n  "round": %s,\n  "round_label": "%s",\n  "topic": "%s",\n  "closed_at": "%s",\n  "status": "archived",\n  "sent": %s,\n  "received": %s\n}\n' \
    "$CB_SPEC_VERSION" \
    "$(cb_json_escape "$CB_NAME")" \
    "$round_num" \
    "$label" \
    "$(cb_json_escape "$topic")" \
    "$when_iso" \
    "$sent_json" \
    "$recv_json")"
  printf '%s' "$manifest" | cb_atomic_write "${dest}/manifest.json"

  cb_append_rounds_md "$CB_HANDOFF" "$label" "$when_human" "$topic" "$sent_names" "$recv_names"
  local rel
  rel="$(cb_rel_under "$CB_HANDOFF" "$dest")"
  printf '%s\n' "$rel" | cb_atomic_write "${CB_HANDOFF}/latest-round.txt"

  local next=$((round_num + 1))
  cb_state_set "$CB_HANDOFF" "round" "$next"
  cb_state_set "$CB_HANDOFF" "pack-state" "none"
  cb_state_set "$CB_HANDOFF" "pack-round" "0"
  cb_state_set "$CB_HANDOFF" "inbox-state" "none"
  cb_state_set "$CB_HANDOFF" "inbox-round" "0"
  cb_state_set "$CB_HANDOFF" "inbox-source" ""
  cb_state_set "$CB_HANDOFF" "inbox-at" ""

  local bytes=0
  bytes="$(cb_bytes "${dest}/manifest.json")"
  local extra
  extra="$(printf '"topic":"%s","archive_path":"%s","round_label":"%s"' \
    "$(cb_json_escape "$topic")" \
    "$(cb_json_escape "$rel")" \
    "$label")"
  cb_log_event "$CB_HANDOFF" "$CB_NAME" "$round_num" "archive" \
    "$(printf '[{"path":"%s","bytes":%s}]' "$(cb_json_escape "${rel}/manifest.json")" "$bytes")" \
    "$bytes" "$extra"
  CB_LAST_ARCHIVE="$dest"
  printf '%s\n' "$dest"
  return 0
}

cb_effective_sync_target() {
  cb_load_global_config
  if [[ -n "${CB_SYNC:-}" ]]; then
    printf '%s' "$CB_SYNC"
  elif [[ -n "${CB_CFG_SYNC:-}" ]]; then
    printf '%s' "$CB_CFG_SYNC"
  fi
}

cb_sync_handoff_to() {
  local dest_root="$1"
  [[ -n "$dest_root" ]] || return 0
  local slug dest archive logmd
  slug="$(cb_slug "$CB_NAME")"
  dest="${dest_root}/${slug}"
  mkdir -p "$dest"
  archive="$(cb_dir "$CB_HANDOFF" archive)"
  logmd="$(cb_rounds_md_path "$CB_HANDOFF")"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$archive" "$dest/"
    if [[ -f "$logmd" ]]; then
      rsync -a "$logmd" "$dest/"
    fi
  else
    mkdir -p "$dest"
    cp -a "$archive" "$dest/"
    if [[ -f "$logmd" ]]; then
      cp -a "$logmd" "$dest/"
    fi
  fi
  cb_note "synced ${CB_NAME} -> ${dest}"
}

cb_cmd_archive() {
  local name="" topic="" do_sync=1 sync_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) name="${2:-}"; shift 2 ;;
      --topic) topic="${2:-}"; shift 2 ;;
      --sync) sync_path="${2:-}"; shift 2 ;;
      --no-sync) do_sync=0; shift ;;
      --force) shift ;;
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
  local dest
  if ! dest="$(cb_close_round_unlocked "$topic")"; then
    cb_unlock "$CB_HANDOFF"
    cb_die "这一轮是空的，没有可归档的文件。Nothing to archive."
  fi
  cb_unlock "$CB_HANDOFF"
  cb_publish_opener >/dev/null || true
  cb_note "closed round -> ${dest}"
  if [[ "$do_sync" == 1 ]]; then
    if [[ -z "$sync_path" ]]; then
      sync_path="$(cb_effective_sync_target || true)"
    fi
    if [[ -n "$sync_path" ]]; then
      cb_sync_handoff_to "$sync_path"
    fi
  fi
  cb_notify "ChatBar" "「${CB_NAME}」本轮已归档。"
}

cb_month_is_old() {
  local month="$1"
  local days="$2"
  local year m next_y next_m next_start end_epoch cutoff now
  year="${month%-*}"
  m="${month#*-}"
  m=$((10#$m))
  next_m=$((m + 1))
  next_y="$year"
  if [[ "$next_m" -eq 13 ]]; then
    next_m=1
    next_y=$((next_y + 1))
  fi
  next_start="$(printf '%04d-%02d-01' "$next_y" "$next_m")"
  if date -d "$next_start" +%s >/dev/null 2>&1; then
    end_epoch="$(date -d "$next_start" +%s)"
  else
    end_epoch="$(date -j -f '%Y-%m-%d' "$next_start" +%s)"
  fi
  now="$(date +%s)"
  cutoff=$((now - days * 86400))
  [[ "$end_epoch" -le "$cutoff" ]]
}

cb_days_from_spec() {
  local spec="$1"
  case "$spec" in
    *d) printf '%s' "${spec%d}" ;;
    *w) printf '%s' $(( ${spec%w} * 7 )) ;;
    *m) printf '%s' $(( ${spec%m} * 30 )) ;;
    *) printf '%s' "$spec" ;;
  esac
}

cb_compact_handoff() {
  local days="$1"
  local archive month base zip
  archive="$(cb_dir "$CB_HANDOFF" archive)"
  [[ -d "$archive" ]] || return 0
  shopt -s nullglob
  for month in "$archive"/*; do
    [[ -d "$month" ]] || continue
    base="$(basename "$month")"
    [[ "$base" =~ ^[0-9]{4}-[0-9]{2}$ ]] || continue
    if cb_month_is_old "$base" "$days"; then
      zip="${archive}/${base}.zip"
      (
        cd "$archive" || exit 1
        zip -qr "${base}.zip" "$base"
      )
      rm -rf "$month"
      cb_note "compacted ${base} -> ${zip}"
    fi
  done
  shopt -u nullglob
}

cb_cmd_compact() {
  local name="" older="90d" sync_path="" do_sync=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) name="${2:-}"; shift 2 ;;
      --older-than) older="${2:-90d}"; shift 2 ;;
      --sync) sync_path="${2:-}"; shift 2 ;;
      --no-sync) do_sync=0; shift ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else cb_die "unexpected argument: $1"; fi
        ;;
    esac
  done
  local days
  days="$(cb_days_from_spec "$older")"
  [[ "$days" =~ ^[0-9]+$ ]] || cb_die "bad duration: ${older}"
  cb_projects_load
  local -a indexes
  indexes=()
  if [[ -n "$name" ]]; then
    name="$(cb_decode_cli_arg "$name")"
    local idx
    idx="$(cb_project_find "$name")" || cb_die "unknown project: ${name}"
    indexes+=("$idx")
  else
    local i
    if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
      cb_note "no projects"
      return 0
    fi
    for i in "${!CB_P_NAME[@]}"; do
      indexes+=("$i")
    done
  fi
  local id
  for id in "${indexes[@]}"; do
    cb_load_project_fields "$id"
    cb_ensure_layout "$CB_HANDOFF"
    cb_lock "$CB_HANDOFF"
    cb_compact_handoff "$days"
    cb_unlock "$CB_HANDOFF"
    if [[ "$do_sync" == 1 ]]; then
      local target="$sync_path"
      if [[ -z "$target" ]]; then
        target="$(cb_effective_sync_target || true)"
      fi
      if [[ -n "$target" ]]; then
        cb_sync_handoff_to "$target"
      fi
    fi
  done
}

cb_cmd_sync() {
  local name="" sync_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) name="${2:-}"; shift 2 ;;
      --to) sync_path="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else cb_die "unexpected argument: $1"; fi
        ;;
    esac
  done
  cb_resolve_project_arg "$name"
  cb_ensure_layout "$CB_HANDOFF"
  if [[ -z "$sync_path" ]]; then
    sync_path="$(cb_effective_sync_target || true)"
  fi
  [[ -n "$sync_path" ]] || cb_die "no sync target. Set sync_to or pass --to PATH"
  cb_sync_handoff_to "$sync_path"
}
