# SwiftBar menu. Clicks call the CLI. MIT License.

# Status only. The project row does not offer a second copy action.
cb_menu_round_status() {
  cb_next_fields
  case "$CB_NEXT_STATE" in
    ready) printf '第 %s 轮 · 待发给 g' "$CB_NEXT_ROUND" ;;
    waiting) printf '第 %s 轮 · 等 g 回复' "$CB_NEXT_ROUND" ;;
    inbox) printf '第 %s 轮 · 新任务' "$CB_NEXT_ROUND" ;;
    *) printf '第 %s 轮 · 待打包' "$CB_NEXT_ROUND" ;;
  esac
}

cb_menu_title_safe() {
  local s="$1"
  s="${s//|/／}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

cb_project_is_new() {
  local inbox zip dl round
  if [[ "$(cb_state_get "$CB_HANDOFF" "inbox-state" "none")" == "new" ]]; then
    return 0
  fi
  inbox="$(cb_dir "$CB_HANDOFF" inbox)"
  if [[ -f "${inbox}/NEW.json" || -f "${CB_HANDOFF}/agent-result.json" ]]; then
    return 0
  fi
  round="$(cb_active_round)"
  zip="$(cb_reply_download_name "$CB_NAME" "$round")"
  if [[ -f "${inbox}/${zip}" ]]; then
    return 0
  fi
  dl="${CHATBAR_DOWNLOADS:-${HOME}/Downloads}"
  if [[ -f "${dl}/${zip}" ]]; then
    return 0
  fi
  return 1
}

cb_menu_more() {
  local bin="$1"
  local enc="" current=""
  current="$(cb_current_name 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    enc="$(cb_b64enc "$current")"
  elif [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    enc="$(cb_b64enc "${CB_P_NAME[0]}")"
  fi
  printf '%s\n' '更多'
  printf -- '-- 打包 | bash=%s param1=pack terminal=false refresh=true\n' "$bin"
  printf -- '-- 打开收发窗口 | bash=%s param1=reveal terminal=false\n' "$bin"
  if [[ -n "$enc" ]]; then
    printf -- '-- 打开交接目录 | bash=%s param1=open-handoff param2=b64:%s terminal=false\n' "$bin" "$enc"
    printf -- '-- 打开项目根目录 | bash=%s param1=open-root param2=b64:%s terminal=false\n' "$bin" "$enc"
    printf -- '-- 归档 | bash=%s param1=archive param2=b64:%s terminal=false refresh=true\n' "$bin" "$enc"
    printf -- '-- 结束本轮 | bash=%s param1=archive param2=b64:%s terminal=false refresh=true\n' "$bin" "$enc"
  fi
  printf -- '-- 刷新 | refresh=true\n'
  printf -- '-- 添加项目… | bash=%s param1=project param2=pick-folder terminal=false refresh=true\n' "$bin"
  printf -- '-- 检查更新 | bash=%s param1=update param2=--check terminal=false refresh=true\n' "$bin"
  printf -- '-- 还原上一版 | bash=%s param1=update param2=--rollback terminal=false refresh=true\n' "$bin"
  printf -- '-- 设置 | bash=%s param1=open-home terminal=false\n' "$bin"
}

cb_cmd_swiftbar_menu() {
  local bin
  bin="$(cb_chatbar_bin)"
  cb_projects_load
  local headline="添加"
  local action=""
  local action_enc=""
  local any_new=0
  local i
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    local current="" idx=0
    current="$(cb_current_name 2>/dev/null || true)"
    if [[ -n "$current" ]]; then
      for i in "${!CB_P_NAME[@]}"; do
        if [[ "${CB_P_NAME[$i]}" == "$current" ]]; then
          idx="$i"
          break
        fi
      done
    fi
    cb_load_project_fields "$idx"
    cb_next_fields
    headline="$CB_NEXT_TITLE"
    action="$CB_NEXT_ACTION"
    action_enc="$(cb_b64enc "$CB_NAME")"
    for i in "${!CB_P_NAME[@]}"; do
      cb_load_project_fields "$i"
      if cb_project_is_new; then
        any_new=1
        break
      fi
    done
  fi
  if [[ "$any_new" == 1 ]]; then
    headline="新任务"
    printf '%s | sfimage=circle.fill color=#DC2626 size=16\n' "$(cb_menu_title_safe "$headline")"
  elif [[ "$headline" == "复制" ]]; then
    printf '%s | sfimage=shippingbox color=#1D4ED8 size=16\n' "$(cb_menu_title_safe "$headline")"
  else
    printf '%s | sfimage=arrow.left.arrow.right size=16\n' "$(cb_menu_title_safe "$headline")"
  fi
  printf '%s\n' '---'
  if [[ "$action" == "复制给 g" && -n "$action_enc" ]]; then
    printf '复制给 g | bash=%s param1=handoff-now param2=b64:%s terminal=false refresh=true\n' \
      "$bin" "$action_enc"
  elif [[ "$action" == "打开下载" ]]; then
    printf '打开下载 | bash=%s param1=open-downloads terminal=false refresh=true\n' "$bin"
  fi
  local auto_word="关"
  if cb_auto_global_on; then
    auto_word="开"
  fi
  printf '自动收发：%s | bash=%s param1=auto param2=toggle terminal=false refresh=true\n' \
    "$auto_word" "$bin"
  if [[ -f "$(cb_update_flag_path)" ]]; then
    printf '有更新 | bash=%s param1=update terminal=false refresh=true size=12 color=#1D4ED8\n' "$bin"
  fi
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    printf '还没有项目 | size=12 color=#888888\n'
  else
    local current=""
    current="$(cb_current_name 2>/dev/null || true)"
    for i in "${!CB_P_NAME[@]}"; do
      local name status enc checked color dot proj_auto
      name="${CB_P_NAME[$i]}"
      cb_load_project_fields "$i"
      status="$(cb_menu_round_status)"
      enc="$(cb_b64enc "$name")"
      checked=""
      color=""
      dot=""
      if [[ "$name" == "$current" ]]; then
        checked=" checked=true"
      fi
      if cb_project_is_new; then
        dot="● "
        color=" color=#C2410C"
      fi
      if cb_auto_project_on; then
        proj_auto="开"
      else
        proj_auto="关"
      fi
      printf '%s%s · %s | bash=%s param1=project param2=use param3=b64:%s terminal=false refresh=true%s%s\n' \
        "$dot" \
        "$(cb_menu_title_safe "$name")" \
        "$status" \
        "$bin" \
        "$enc" \
        "$checked" \
        "$color"
      printf -- '-- 打开 | bash=%s param1=open param2=b64:%s terminal=false\n' "$bin" "$enc"
      printf -- '-- 自动收发：%s | bash=%s param1=auto param2=toggle-project param3=b64:%s terminal=false refresh=true\n' \
        "$proj_auto" "$bin" "$enc"
      printf -- '-- 结束本轮 | bash=%s param1=archive param2=b64:%s terminal=false refresh=true\n' "$bin" "$enc"
    done
  fi
  printf '%s\n' '---'
  cb_menu_more "$bin"
  printf '发送永远由你手动 | size=12 color=#888888\n'
}
