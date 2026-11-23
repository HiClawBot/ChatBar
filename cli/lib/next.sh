# One next action for the person at the keyboard. MIT License.
# Does not open a chat app. The button in the app only copies text and selects a Finder file.

cb_next_round_file() {
  local outdir="$1"
  local round="$2"
  local label alias stable plain
  label="$(cb_round_label "$round")"
  alias="${outdir}/to_chatgpt_${label}.md"
  plain="${outdir}/to_chatgpt.md"
  stable="${outdir}/to_planner.md"
  if [[ ! -f "$alias" && -f "$stable" ]]; then
    cp "$stable" "$alias"
  fi
  if [[ -f "$alias" ]]; then
    printf '%s' "$alias"
  elif [[ -f "$plain" ]]; then
    printf '%s' "$plain"
  elif [[ -f "$stable" ]]; then
    printf '%s' "$stable"
  fi
}

cb_cmd_next() {
  cb_projects_load
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    printf '%s\n' '{"project":"","round":0,"action":"add","line_zh":"点「添加项目」，选你的代码文件夹。","line_en":"Choose Add Project and pick your code folder.","file":"","opener":""}'
    return 0
  fi
  local name
  name="$(cb_current_name 2>/dev/null || true)"
  if [[ -z "$name" ]]; then
    name="${CB_P_NAME[0]}"
  fi
  cb_resolve_project_arg "$name"
  cb_ensure_layout "$CB_HANDOFF"
  local round err file opener action zh en
  round="$(cb_active_round)"
  case "$round" in
    ''|*[!0-9]*) round=1 ;;
  esac
  err=""
  if [[ -f "${CB_HANDOFF}/last-error" ]]; then
    err="$(head -n 1 "${CB_HANDOFF}/last-error" | tr -d '\r')"
  fi
  local inbox_state pack_state
  inbox_state="$(cb_state_get "$CB_HANDOFF" "inbox-state" "none")"
  pack_state="$(cb_state_get "$CB_HANDOFF" "pack-state" "none")"
  file="$(cb_next_round_file "$(cb_dir "$CB_HANDOFF" outbox)" "$round")"
  opener="$(cb_editable_opener)"
  if [[ "$inbox_state" == "new" ]]; then
    action="review"
    zh="回复到了。打开收回夹，让助手处理这一轮。"
    en="The reply is in. Open the inbox and let your agent handle this round."
  elif [[ -n "$err" ]]; then
    action="fix"
    zh="先处理这个错误：${err}"
    en="Deal with this first: ${err}"
  elif [[ -n "$file" && "$pack_state" == "presented" ]]; then
    action="wait"
    zh="如果还没发，把选中的文件拖进 ChatGPT，自己点发送。发完把回复下载下来。"
    en="If you have not sent it, drag the selected file into ChatGPT and press send yourself. Then download the reply."
  elif [[ -n "$file" ]]; then
    action="send"
    zh="点右边按钮，然后把选中的文件拖进 ChatGPT，自己点发送。"
    en="Press the button, then drag the selected file into ChatGPT and press send yourself."
  else
    action="pack"
    zh="这一轮还没有文件。让助手运行 chatbar pack。"
    en="This round has no file yet. Ask your agent to run chatbar pack."
  fi
  printf '{'
  printf '"project":"%s",' "$(cb_json_escape "$CB_NAME")"
  printf '"round":%s,' "$round"
  printf '"round_label":"%s",' "$(cb_round_label "$round")"
  printf '"action":"%s",' "$action"
  printf '"line_zh":"%s",' "$(cb_json_escape "$zh")"
  printf '"line_en":"%s",' "$(cb_json_escape "$en")"
  printf '"file":"%s",' "$(cb_json_escape "$file")"
  printf '"opener":"%s"' "$(cb_json_escape "$opener")"
  printf '}\n'
}
