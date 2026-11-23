# Build the planner pack. MIT License.
# Stable file: <handoff>/outbox/to_planner.md
# Drag file for this round: <handoff>/outbox/to_chatgpt_R00N.md
# Drag that file into the planner chat yourself (ChatGPT is the default example).

cb_git_excludes() {
  printf '%s\n' \
    ':(exclude).env' \
    ':(exclude).env.*' \
    ':(exclude)**/.env' \
    ':(exclude)**/.env.*' \
    ':(exclude)**/*.pem' \
    ':(exclude)**/*.key' \
    ':(exclude)**/id_rsa' \
    ':(exclude)**/id_rsa.*' \
    ':(exclude)**/credentials.json' \
    ':(exclude).chatbar/**' \
    ':(exclude)**/.chatbar/**'
}

cb_collect_sensitive_names() {
  local repo="$1"
  local line path
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    path="${line:3}"
    path="${path#\"}"
    path="${path%\"}"
    if cb_path_looks_sensitive "$path"; then
      printf '%s\n' "$path"
    fi
  done < <(git -C "$repo" status --short --untracked-files=all 2>/dev/null || true)
}

cb_section_file() {
  local path="$1"
  local title="$2"
  if [[ -f "$path" ]]; then
    printf '## %s\n\n' "$title"
    cat "$path"
    printf '\n'
  fi
}

cb_extract_questions() {
  local repo="$1"
  local handoff="$2"
  if [[ -f "${repo}/questions.md" ]]; then
    cat "${repo}/questions.md"
    return 0
  fi
  if [[ -f "${handoff}/questions.md" ]]; then
    cat "${handoff}/questions.md"
    return 0
  fi
  local status=""
  if [[ -f "${repo}/status.md" ]]; then
    status="${repo}/status.md"
  elif [[ -f "${handoff}/status.md" ]]; then
    status="${handoff}/status.md"
  fi
  if [[ -n "$status" ]] && grep -E -q '^## (Questions|问题|Open questions)' "$status"; then
    awk '
      /^## (Questions|问题|Open questions)/ { p=1; next }
      /^## / { if (p) exit }
      p { print }
    ' "$status"
    return 0
  fi
  printf '%s\n' '（没有单独的问题。不确定时请把问题写在回复里，不要试错。）'
  printf '%s\n' 'No separate questions. If you are unsure, write questions in the reply instead of trial and error.'
}

cb_try_full_pack() {
  local repo="$1"
  local dest="$2"
  if command -v repomix >/dev/null 2>&1; then
    if (cd "$repo" && repomix --style markdown -o "$dest" -i "**/.env,**/.env.*,**/*.pem,**/*.key,**/.chatbar/**,.chatbar/**,**/secrets/**" >/dev/null 2>&1); then
      printf 'repomix'
      return 0
    fi
    cb_warn "repomix failed; pack continues without the full-repo file"
  fi
  if command -v code2prompt >/dev/null 2>&1; then
    if (cd "$repo" && code2prompt -o "$dest" . >/dev/null 2>&1); then
      printf 'code2prompt'
      return 0
    fi
    if (cd "$repo" && code2prompt --output "$dest" . >/dev/null 2>&1); then
      printf 'code2prompt'
      return 0
    fi
    cb_warn "code2prompt failed; pack continues without the full-repo file"
  fi
  if ! command -v repomix >/dev/null 2>&1 && ! command -v code2prompt >/dev/null 2>&1; then
    cb_warn "full pack skipped: neither repomix nor code2prompt is installed"
  fi
  return 1
}

cb_cmd_pack() {
  local name="" repo_filter="" do_full=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) name="${2:-}"; shift 2 ;;
      --repo)
        repo_filter="${2:-}"
        shift 2
        ;;
      --full) do_full=1; shift ;;
      --no-full) do_full=0; shift ;;
      --quiet) CB_QUIET=1; shift ;;
      --) shift; break ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        if [[ -z "$name" ]]; then name="$1"; shift; else cb_die "unexpected argument: $1"; fi
        ;;
    esac
  done
  if [[ -n "$repo_filter" ]]; then
    local idx
    if ! idx="$(cb_project_find_by_repo "$repo_filter")"; then
      [[ "$CB_QUIET" == 1 ]] || cb_warn "no ChatBar project for repo: ${repo_filter}"
      return 0
    fi
    cb_load_project_fields "$idx"
  else
    cb_resolve_project_arg "$name"
  fi
  cb_ensure_layout "$CB_HANDOFF"
  cb_lock "$CB_HANDOFF"

  local inbox_state round pack_round
  inbox_state="$(cb_state_get "$CB_HANDOFF" "inbox-state" "none")"
  round="$(cb_state_get "$CB_HANDOFF" "round" "1")"
  pack_round="$(cb_state_get "$CB_HANDOFF" "pack-round" "0")"

  if [[ "$inbox_state" == "new" ]]; then
    cb_warn "inbox 有未处理回复，仍按当前轮次打包。Unprocessed reply; refreshing this round."
  fi

  local opener reply_file base_commit
  base_commit="$(cb_main_commit "$CB_REPO")"
  printf '%s\n' "$base_commit" | cb_atomic_write "${CB_HANDOFF}/pack-base"
  opener="$(cb_build_opener "$round")"
  reply_file="$(cb_reply_basename "$CB_NAME" "$round")"
  local stamp
  stamp="$(cb_now_stamp)"
  local work
  work="$(mktemp -d)"
  local raw="${work}/pack.md"
  local redacted="${work}/pack.redacted.md"
  local count_file="${work}/count"

  {
    printf '# %s — round %s\n\n' "$CB_NAME" "$round"
    printf '%s\n\n' "$opener"
    printf '<!-- chatbar-spec: %s -->\n\n' "$CB_SPEC_VERSION"
    printf 'Base commit (main): %s\n\n' "$base_commit"
    printf '%s\n' '把这个文件拖进规划对话（默认示例是 ChatGPT）。发送由你亲手完成。ChatBar 不会打开聊天页面、不会读账号或 Cookie。'
    printf '%s\n\n' 'Drag this file into your planner chat (ChatGPT is the default example). You send it yourself. ChatBar does not open the chat page and does not read accounts or cookies.'

    if [[ -f "${CB_REPO}/status.md" ]]; then
      cb_section_file "${CB_REPO}/status.md" "Status"
    elif [[ -f "${CB_HANDOFF}/status.md" ]]; then
      cb_section_file "${CB_HANDOFF}/status.md" "Status"
    else
      printf '## Status\n\n（仓库里还没有 status.md）\nNo status.md in the repo yet.\n\n'
    fi

    printf '## Open questions\n\n'
    cb_extract_questions "$CB_REPO" "$CB_HANDOFF"
    printf '\n'

    if git -C "$CB_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      printf '## Git status\n\n```\n'
      git -C "$CB_REPO" status --short --untracked-files=all 2>/dev/null || true
      printf '\n```\n\n'
      local -a excludes
      excludes=()
      while IFS= read -r ex; do
        [[ -n "$ex" ]] && excludes+=("$ex")
      done < <(cb_git_excludes)
      printf '## Diff stat\n\n```\n'
      if git -C "$CB_REPO" rev-parse --verify HEAD >/dev/null 2>&1; then
        git -C "$CB_REPO" diff --stat HEAD -- . "${excludes[@]}" 2>/dev/null || true
      else
        printf '%s\n' '(no commits yet)'
      fi
      printf '\n```\n\n'
      printf '## Diff (staged + unstaged)\n\n```diff\n'
      if git -C "$CB_REPO" rev-parse --verify HEAD >/dev/null 2>&1; then
        git -C "$CB_REPO" diff HEAD -- . "${excludes[@]}" 2>/dev/null | head -c "${CHATBAR_DIFF_MAX:-200000}" || true
      else
        printf '%s\n' '(no commits yet)'
      fi
      printf '\n```\n\n'
      local diff_bytes
      diff_bytes="$(git -C "$CB_REPO" diff HEAD -- . "${excludes[@]}" 2>/dev/null | wc -c | tr -d '[:space:]')"
      if [[ "${diff_bytes:-0}" -gt "${CHATBAR_DIFF_MAX:-200000}" ]]; then
        printf '%s\n\n' "Diff truncated to ${CHATBAR_DIFF_MAX:-200000} bytes. 差异过长，已截断。"
      fi
    else
      printf '## Git status\n\n（不是 git 仓库，没有 diff）\nNot a git repository; no diff.\n\n'
    fi

    local sensitive=""
    sensitive="$(cb_collect_sensitive_names "$CB_REPO" || true)"
    if [[ -n "$sensitive" ]]; then
      printf '## Warnings\n\n'
      printf '%s\n' '下列文件名像密钥或 dotenv，没有把内容打进 diff。'
      printf '%s\n' 'These paths look like secrets or dotenv files. Their contents were not included.'
      printf '\n```\n%s\n```\n\n' "$sensitive"
    fi
  } > "$raw"

  cb_redact_stream "$count_file" < "$raw" > "$redacted"
  local redacted_count=0
  if [[ -f "$count_file" ]]; then
    redacted_count="$(tr -d '[:space:]' < "$count_file")"
  fi
  if [[ "${redacted_count:-0}" != 0 ]]; then
    {
      printf '\n## Warnings\n\n'
      printf '已涂掉约 %s 处疑似密钥。Values that looked like secrets were redacted (%s).\n' "$redacted_count" "$redacted_count"
    } >> "$redacted"
    cb_warn "redacted ${redacted_count} likely secret line(s) in the pack"
  fi
  CB_DOWNLOAD_NAME="$(cb_reply_download_name "$CB_NAME" "$round")"
  cb_print_delivery_section "$reply_file" "$base_commit" "$(cb_round_label "$round")" >> "$redacted"

  local outdir
  outdir="$(cb_dir "$CB_HANDOFF" outbox)"
  local oldf
  shopt -s nullglob
  for oldf in "$outdir"/to_planner-*.md; do
    rm -f "$oldf"
  done
  shopt -u nullglob
  local stable="${outdir}/to_planner.md"
  local round_pack="${outdir}/$(cb_pack_filename "$round")"
  local snapshot="${outdir}/to_planner-${stamp}-r${round}.md"
  local old_round
  shopt -s nullglob
  for old_round in "$outdir"/to_chatgpt_R*.md; do
    [[ "$old_round" == "$round_pack" ]] && continue
    rm -f "$old_round"
  done
  shopt -u nullglob
  cat "$redacted" | cb_atomic_write "$stable"
  cat "$redacted" | cb_atomic_write "$round_pack"
  cat "$redacted" | cb_atomic_write "$snapshot"
  cb_write_opener_files "$opener"

  local full_note=""
  if [[ "$do_full" == 1 ]]; then
    local full_path="${outdir}/to_planner-full-${stamp}-r${round}.md"
    local tool=""
    if tool="$(cb_try_full_pack "$CB_REPO" "$full_path")"; then
      full_note="Full repo pack (${tool}): $(basename "$full_path")"
      cb_note "$full_note"
    fi
  fi

  cb_state_set "$CB_HANDOFF" "pack-state" "ready"
  cb_state_set "$CB_HANDOFF" "pack-round" "$round"

  local bytes files_json
  bytes="$(cb_bytes "$stable")"
  local snap_bytes
  snap_bytes="$(cb_bytes "$snapshot")"
  local total=$((bytes + snap_bytes))
  files_json="$(printf '[{"path":"%s","bytes":%s},{"path":"%s","bytes":%s}]' \
    "$(cb_json_escape "$(cb_rel_under "$CB_HANDOFF" "$stable")")" "$bytes" \
    "$(cb_json_escape "$(cb_rel_under "$CB_HANDOFF" "$snapshot")")" "$snap_bytes")"
  if [[ -n "$full_note" ]]; then
    local full_file full_b
    full_file="$(ls -1 "${outdir}/to_planner-full-${stamp}-r${round}.md" 2>/dev/null || true)"
    if [[ -n "$full_file" ]]; then
      full_b="$(cb_bytes "$full_file")"
      total=$((total + full_b))
      files_json="${files_json%]},{\"path\":\"$(cb_rel_under "$CB_HANDOFF" "$full_file")\",\"bytes\":${full_b}}]"
    fi
  fi
  cb_log_event "$CB_HANDOFF" "$CB_NAME" "$round" "to_planner" "$files_json" "$total"
  cb_unlock "$CB_HANDOFF"
  rm -rf "$work"
  cb_note "packed ${CB_NAME} round ${round}"
  cb_note "${stable}"
  cb_notify "ChatBar" "「${CB_NAME}」第 ${round} 轮已打包，可以拖进规划对话。"
}
