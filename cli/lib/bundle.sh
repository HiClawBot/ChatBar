# Describe the files and opener for a local pasteboard bundle.
# This command does not write the pasteboard and does not paste into a chat app.
# The menu bar app places NSString + file URLs on NSPasteboard. The user pastes.

cb_bundle_skip_name() {
  local base="$1"
  case "$base" in
    .*|opener.md|opener.txt|opener.generated.md|给GPT的话.txt|*.command|to_planner-*)
      return 0
      ;;
  esac
  return 1
}

cb_cmd_bundle() {
  local as_json=1
  local -a args
  args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) as_json=1; shift ;;
      --text) as_json=0; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [[ "${#args[@]}" -gt 0 ]]; then
    cb_select_project_target "${args[@]}"
  else
    cb_select_project_target
  fi
  local round opener outdir pack f base
  round="$(cb_active_round)"
  opener="$(cb_editable_opener)"
  outdir="$(cb_dir "$CB_HANDOFF" outbox)"
  pack="${outdir}/to_planner.md"
  local -a files
  files=()
  if [[ -f "$pack" ]]; then
    files+=("$pack")
  fi
  if [[ -f "${outdir}/to_chatgpt.md" ]]; then
    files+=("${outdir}/to_chatgpt.md")
  fi
  if [[ -d "$outdir" ]]; then
    shopt -s nullglob
    for f in "$outdir"/*; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f")"
      if cb_bundle_skip_name "$base"; then
        continue
      fi
      if [[ "$f" == "$pack" || "$f" == "${outdir}/to_chatgpt.md" ]]; then
        continue
      fi
      files+=("$f")
    done
    shopt -u nullglob
  fi
  if [[ "$as_json" == 0 ]]; then
    printf 'round=%s\n' "$round"
    printf 'opener<<EOF\n%s\nEOF\n' "$opener"
    local one
    for one in "${files[@]+"${files[@]}"}"; do
      printf 'file=%s\n' "$one"
    done
    return 0
  fi
  printf '{'
  printf '"project":"%s",' "$(cb_json_escape "$CB_NAME")"
  printf '"round":%s,' "$round"
  printf '"round_label":"%s",' "$(cb_round_label "$round")"
  printf '"chat_name":"%s",' "$(cb_json_escape "$CB_ROLE_CHAT")"
  printf '"opener":"%s",' "$(cb_json_escape "$opener")"
  printf '"pack_file":"%s",' "$(cb_json_escape "$pack")"
  printf '"files":['
  local i
  if [[ "${#files[@]}" -gt 0 ]]; then
    for i in "${!files[@]}"; do
      if [[ "$i" -gt 0 ]]; then printf ','; fi
      printf '"%s"' "$(cb_json_escape "${files[$i]}")"
    done
  fi
  printf ']}\n'
}

cb_cmd_mark_presented() {
  cb_select_project_target "$@"
  cb_ensure_layout "$CB_HANDOFF"
  cb_lock "$CB_HANDOFF"
  cb_state_set "$CB_HANDOFF" "pack-state" "presented"
  cb_state_set "$CB_HANDOFF" "presented-at" "$(cb_now_iso)"
  cb_unlock "$CB_HANDOFF"
  printf '%s\n' "presented"
}
