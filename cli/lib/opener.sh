# Dynamic per-round opener for the planner chat. MIT License.
# Agents may override a round by writing <outbox>/opener.md before pack.
# Project templates: templates/opener-round1.md and templates/opener-next.md.

cb_round_label() {
  printf 'R%03d' "${1:-0}"
}

# Stable id used in download filenames. ASCII is lowercased; spaces become hyphens.
cb_project_slug() {
  local name="$1"
  name="$(cb_sanitize_filename "$name")"
  name="${name// /-}"
  printf '%s' "$name" | tr '[:upper:]' '[:lower:]'
}

# The only file the user drags for this round.
cb_pack_filename() {
  printf 'to_chatgpt_%s.md' "$(cb_round_label "$1")"
}

# The download ChatGPT should offer after this round.
cb_reply_download_name() {
  local name="$1"
  local round="$2"
  local safe
  safe="$(cb_sanitize_filename "$name")"
  safe="${safe// /-}"
  printf '%s_round%s_reply.zip' "$safe" "$round"
}

# The planner must name the download <slug>_round<N>_reply.md (or .zip).
cb_reply_basename() {
  local name="$1"
  local round="$2"
  printf '%s_round%s_reply.md' "$(cb_project_slug "$name")" "$round"
}

cb_clip_text() {
  local text="$1"
  local max="${2:-180}"
  text="$(printf '%s' "$text" | tr '\n\r\t' '   ')"
  while [[ "$text" == *"  "* ]]; do
    text="${text//  / }"
  done
  text="$(cb_trim "$text")"
  if [[ "${#text}" -gt "$max" ]]; then
    text="${text:0:$max}"
  fi
  printf '%s' "$text"
}

cb_delivery_sentence() {
  local file="$1"
  local hash="$2"
  printf '%s' "Please return a downloadable Markdown file named ${file} (zip it if there are attachments). If you change code, return a unified diff against commit ${hash} (\`\`\`diff or a .patch). Do not commit. Do not reply with only a share/canvas link or only inline chat text."
}

cb_print_delivery_section() {
  local file="$1"
  local hash="$2"
  local label="$3"
  cat <<EOF

## Delivery format

请把回复保存成可下载的 Markdown 文件，文件名必须是 \`${file}\`。
如果还有附件，请打成一个 zip 再提供下载。
不要只给分享链接或 Canvas 链接（需要登录的链接在本地打不开）。
不要只把回复写在聊天正文里。

如果要改代码：请针对当前 main 提交 \`${hash}\` 给出 unified diff（\`\`\`diff 代码块，或 .patch 文件），也可以给带路径标题的完整文件（例如 \`File: src/hello.py\` 后接代码块）。
不要在仓库里提交。本地助手会在新分支 \`${label}\`（chatbar/${label}）上 \`git apply --3way\`，跑测试，再开 PR。main 保持不动。有冲突就停，不会强行套用。

下载时请把文件命名为 \`${CB_DOWNLOAD_NAME:-reply.zip}\`。

Return a downloadable Markdown file named \`${file}\`.
If there are attachments, put them in one zip. Name the download \`${CB_DOWNLOAD_NAME:-reply.zip}\`.
Do not reply with only a share link or a canvas link (login-gated links cannot be read locally).
Do not reply with only inline chat text.

Base commit (main): \`${hash}\`
If you change code, return a unified diff against that commit (\`\`\`diff blocks or a .patch file), or full files with path headers such as \`File: path/to/file\`.
Do not commit. A local agent applies the diff on branch \`chatbar/${label}\` and opens a PR. main stays protected. Conflicts are reported, never forced.
EOF
}

cb_questions_oneline() {
  local text
  text="$(cb_extract_questions "$CB_REPO" "$CB_HANDOFF" 2>/dev/null || true)"
  text="$(cb_clip_text "$text" 240)"
  if [[ -z "$text" ]]; then
    text="the questions at the end of the pack"
  fi
  printf '%s' "$text"
}

cb_last_suggestion() {
  local rel="" dir="" f="" picked="" line=""
  if [[ -f "${CB_HANDOFF}/latest-round.txt" ]]; then
    rel="$(tr -d '\r\n' < "${CB_HANDOFF}/latest-round.txt")"
    dir="${CB_HANDOFF}/${rel}/inbox"
  fi
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    printf '%s' "nothing captured from the previous reply"
    return 0
  fi
  shopt -s nullglob
  local -a candidates
  candidates=("$dir"/*_reply.md "$dir"/*.md "$dir"/*.txt)
  shopt -u nullglob
  if [[ "${#candidates[@]}" -eq 0 ]]; then
    printf '%s' "nothing captured from the previous reply"
    return 0
  fi
  for f in "${candidates[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -q -E '^(建议|摘要|Summary|Suggested|Suggestion)[[:space:]]*[:：]|^## (建议|摘要|Summary)' "$f"; then
      picked="$f"
      break
    fi
  done
  if [[ -z "$picked" ]]; then
    for f in "${candidates[@]}"; do
      [[ -f "$f" ]] && picked="$f" && break
    done
  fi
  if [[ -z "$picked" ]]; then
    printf '%s' "nothing captured from the previous reply"
    return 0
  fi
  line="$(awk '
    /^## (建议|摘要|Summary|Suggested|Suggestion)/ { p=1; next }
    /^## / { if (p) exit }
    p { print }
  ' "$picked")"
  if [[ -z "$(cb_trim "$line")" ]]; then
    line="$(grep -E '^(建议|摘要|Summary|Suggested|Suggestion)[[:space:]]*[:：]' "$picked" | head -n 1 || true)"
  fi
  if [[ -z "$(cb_trim "$line")" ]]; then
    line="$(grep -v -E '^#|^$' "$picked" | head -n 4 || true)"
  fi
  line="$(cb_clip_text "$line" 180)"
  if [[ -z "$line" ]]; then
    line="nothing captured from the previous reply"
  fi
  printf '%s' "$line"
}

cb_this_round_changes() {
  local status_file="" text="" gitline="" joined=""
  if [[ -f "${CB_REPO}/status.md" ]]; then
    status_file="${CB_REPO}/status.md"
  elif [[ -f "${CB_HANDOFF}/status.md" ]]; then
    status_file="${CB_HANDOFF}/status.md"
  fi
  if [[ -n "$status_file" ]]; then
    text="$(awk '
      /^## (Questions|问题|Open questions)/ { exit }
      { print }
    ' "$status_file")"
  fi
  if git -C "$CB_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    gitline="$(git -C "$CB_REPO" log -3 --oneline 2>/dev/null | tr '\n' '; ' || true)"
    gitline="${gitline%; }"
    gitline="$(cb_trim "$gitline")"
  fi
  joined="$(cb_trim "$text")"
  if [[ -n "$gitline" ]]; then
    if [[ -n "$joined" ]]; then
      joined="${joined} git: ${gitline}"
    else
      joined="git: ${gitline}"
    fi
  fi
  joined="$(cb_clip_text "$joined" 220)"
  if [[ -z "$joined" ]]; then
    joined="see the diff in the pack"
  fi
  printf '%s' "$joined"
}

cb_find_opener_template() {
  local round="$1"
  local dir name
  local -a names
  if [[ "$round" -le 1 ]]; then
    names=(opener-round1.md opener.md)
  else
    names=(opener-next.md opener-roundn.md)
  fi
  for dir in "${CB_REPO}/templates" "${CB_HANDOFF}/templates"; do
    for name in "${names[@]}"; do
      if [[ -f "${dir}/${name}" ]]; then
        printf '%s' "${dir}/${name}"
        return 0
      fi
    done
  done
  return 1
}

cb_fill_opener_template() {
  local template="$1"
  local round="$2"
  local file="$3"
  local questions="$4"
  local last_suggestion="$5"
  local changed="$6"
  local attached="$7"
  local out="$template"
  out="${out//\{reply_file\}/$file}"
  out="${out//\{last_suggestion\}/$last_suggestion}"
  out="${out//\{changed\}/$changed}"
  out="${out//\{questions\}/$questions}"
  out="${out//\{attached\}/$attached}"
  out="${out//\{label\}/$(cb_round_label "$round")}"
  out="${out//\{name\}/$CB_NAME}"
  out="${out//\{project\}/$CB_NAME}"
  out="${out//\{round\}/$round}"
  out="${out//\{role\}/planner and reviewer}"
  printf '%s' "$out"
}

cb_builtin_opener_body() {
  local round="$1"
  local questions="$2"
  local last_suggestion="$3"
  local changed="$4"
  local attached="$5"
  if [[ "$round" -le 1 ]]; then
    printf '%s, round %s. I am the local coding agent; you are the planner and reviewer. Attached: %s. Open questions: %s.' \
      "$CB_NAME" "$round" "$attached" "$questions"
  else
    printf 'Round %s. Last round you suggested: %s. This round we changed: %s. Please review and answer: %s.' \
      "$round" "$last_suggestion" "$changed" "$questions"
  fi
}

# $1 round. $2 = 1 to honor <outbox>/opener.md, 0 for the agent/generated text.
cb_compose_opener() {
  local round="$1"
  local allow_override="${2:-1}"
  local file questions last_suggestion changed attached body template_path raw
  file="$(cb_reply_basename "$CB_NAME" "$round")"
  questions="$(cb_questions_oneline)"
  last_suggestion="$(cb_last_suggestion)"
  changed="$(cb_this_round_changes)"
  attached="the git diff (staged and unstaged), status, and open questions"
  body=""
  local override
  override="$(cb_dir "$CB_HANDOFF" outbox)/opener.md"
  if [[ "$allow_override" == 1 && -f "$override" && -s "$override" ]]; then
    body="$(cat "$override")"
  elif template_path="$(cb_find_opener_template "$round")"; then
    raw="$(cat "$template_path")"
    body="$(cb_fill_opener_template "$raw" "$round" "$file" "$questions" "$last_suggestion" "$changed" "$attached")"
  elif [[ -n "${CB_OPENER_RAW:-}" ]]; then
    body="$(cb_fill_opener_template "$CB_OPENER_RAW" "$round" "$file" "$questions" "$last_suggestion" "$changed" "$attached")"
  else
    body="$(cb_builtin_opener_body "$round" "$questions" "$last_suggestion" "$changed" "$attached")"
  fi
  body="$(cb_trim "$body")"
  local base_hash
  base_hash="$(cb_main_commit "$CB_REPO")"
  if [[ "$body" != *"$file"* ]]; then
    body="${body}"$'\n'"$(cb_delivery_sentence "$file" "$base_hash")"
  fi
  printf '%s' "$body"
}

# Print the opener for this round. Always ends with the delivery-format request.
cb_build_opener() {
  cb_compose_opener "$1" 1
}

cb_generated_opener() {
  cb_compose_opener "$1" 0
}

# Exact text the menu card edits. User file wins and is not rewritten here.
cb_editable_opener() {
  local path round
  path="$(cb_dir "$CB_HANDOFF" outbox)/opener.md"
  if [[ -f "$path" ]]; then
    cat "$path"
    return 0
  fi
  round="$(cb_active_round)"
  cb_generated_opener "$round"
}

cb_write_copy_command() {
  local outdir dest bin
  outdir="$(cb_dir "$CB_HANDOFF" outbox)"
  dest="${outdir}/复制开场白.command"
  if [[ -n "${CHATBAR_NO_REWRITE:-}" || -e "$dest" ]]; then
    return 0
  fi
  mkdir -p "$outdir"
  bin="$(cb_chatbar_bin)"
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' '# Copy this round'"'"'s opener to the clipboard (pbcopy).'
    printf '%s\n' '# Does not touch any browser or chat app.'
    printf '%s\n' 'HANDOFF="$(cd "$(dirname "$0")/.." && pwd)"'
    printf 'CHATBAR=%q\n' "$bin"
    printf '%s\n' 'if [[ ! -x "$CHATBAR" ]]; then'
    printf '%s\n' '  echo "chatbar not found: $CHATBAR" >&2'
    printf '%s\n' '  exit 1'
    printf '%s\n' 'fi'
    printf '%s\n' 'exec "$CHATBAR" copy-opener --handoff "$HANDOFF"'
  } | cb_atomic_write "$dest"
  chmod +x "$dest"
}

cb_write_opener_files() {
  local text="$1"
  local outdir
  outdir="$(cb_dir "$CB_HANDOFF" outbox)"
  mkdir -p "$outdir"
  local dest
  for dest in "${outdir}/给GPT的话.txt" "${outdir}/opener.txt"; do
    if [[ -f "$dest" && "$(cat "$dest")" == "$text" ]]; then continue; fi
    printf '%s\n' "$text" | cb_atomic_write "$dest"
  done
  cb_write_copy_command
}

cb_publish_opener() {
  local round text
  [[ -n "${CB_NAME:-}" ]] || return 0
  [[ -n "${CB_HANDOFF:-}" ]] || return 0
  round="$(cb_active_round)"
  text="$(cb_build_opener "$round")"
  cb_write_opener_files "$text"
  printf '%s' "$text"
}

cb_opener_note() {
  local kind="$1"
  local body="$2"
  local logdir dest
  logdir="$(cb_dir "$CB_HANDOFF" log)"
  mkdir -p "$logdir"
  dest="${logdir}/opener-edits.md"
  {
    if [[ -f "$dest" ]]; then
      cat "$dest"
      printf '\n'
    else
      printf '%s\n\n' '# Opener edits'
    fi
    printf '## %s round %s %s\n\n' "$(cb_now_iso)" "$(cb_active_round)" "$kind"
    printf '%s\n' "$body"
  } | cb_atomic_write "$dest"
  local bytes
  bytes="$(cb_bytes "$dest")"
  cb_log_event "$CB_HANDOFF" "$CB_NAME" "$(cb_active_round)" "opener_edit" \
    "$(cb_files_json_one "$(cb_rel_under "$CB_HANDOFF" "$dest")" "$bytes")" \
    "$bytes" "$(printf '"kind":"%s"' "$(cb_json_escape "$kind")")"
}

cb_cmd_opener_show() {
  cb_select_project_target "$@"
  local round text generated source path gen_path
  round="$(cb_active_round)"
  path="$(cb_dir "$CB_HANDOFF" outbox)/opener.md"
  gen_path="$(cb_dir "$CB_HANDOFF" outbox)/opener.generated.md"
  text="$(cb_editable_opener)"
  generated="$(cb_generated_opener "$round")"
  if [[ -f "$path" ]]; then
    source="user"
  else
    source="generated"
  fi
  printf '{'
  printf '"project":"%s",' "$(cb_json_escape "$CB_NAME")"
  printf '"round":%s,' "$round"
  printf '"source":"%s",' "$source"
  printf '"text":"%s",' "$(cb_json_escape "$text")"
  printf '"generated":"%s",' "$(cb_json_escape "$generated")"
  printf '"opener_path":"%s",' "$(cb_json_escape "$path")"
  printf '"generated_path":"%s"' "$(cb_json_escape "$gen_path")"
  printf '}\n'
}

cb_cmd_opener_save() {
  cb_select_project_target "$@"
  local text round outdir gen_path user_path diff_note
  text="$(cat)"
  [[ -n "$(cb_trim "$text")" ]] || cb_die "opener save: empty text"
  cb_ensure_layout "$CB_HANDOFF"
  round="$(cb_active_round)"
  outdir="$(cb_dir "$CB_HANDOFF" outbox)"
  mkdir -p "$outdir"
  gen_path="${outdir}/opener.generated.md"
  user_path="${outdir}/opener.md"
  cb_lock "$CB_HANDOFF"
  if [[ ! -s "$gen_path" ]]; then
    cb_generated_opener "$round" | cb_atomic_write "$gen_path"
  fi
  printf '%s' "$text" | cb_atomic_write "$user_path"
  if command -v diff >/dev/null 2>&1; then
    diff_note="$(diff -u "$gen_path" "$user_path" || true)"
  else
    diff_note="user edited opener ($(wc -c < "$user_path" | tr -d '[:space:]') bytes)"
  fi
  [[ -n "$diff_note" ]] || diff_note="user edited opener (no diff)"
  cb_opener_note "user-edit" "$diff_note"
  cb_unlock "$CB_HANDOFF"
  cb_publish_opener >/dev/null || true
  printf '%s\n' "saved ${user_path}"
}

cb_cmd_opener_reset() {
  cb_select_project_target "$@"
  local path
  path="$(cb_dir "$CB_HANDOFF" outbox)/opener.md"
  cb_ensure_layout "$CB_HANDOFF"
  cb_lock "$CB_HANDOFF"
  if [[ -f "$path" ]]; then
    rm -f "$path"
  fi
  cb_opener_note "user-reset" "Restored the agent opener. opener.md removed. opener.generated.md kept."
  cb_unlock "$CB_HANDOFF"
  cb_publish_opener >/dev/null || true
  printf '%s\n' "reset"
}
