# SwiftBar menu. Clicks call the CLI. MIT License.

# Status only. The project row does not offer a second copy action.
cb_menu_round_status() {
  cb_next_fields
  case "$CB_NEXT_STATE" in
    ready) printf '第 %s 轮 · 待发给 g' "$CB_NEXT_ROUND" ;;
    waiting) printf '第 %s 轮 · 等 g 回复' "$CB_NEXT_ROUND" ;;
    inbox) printf '第 %s 轮 · 已交给 agent' "$CB_NEXT_ROUND" ;;
    *) printf '第 %s 轮 · 待打包' "$CB_NEXT_ROUND" ;;
  esac
}

cb_menu_title_safe() {
  local s="$1"
  s="${s//|/／}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

cb_menu_more() {
  local bin="$1"
  local n="${#CB_P_NAME[@]}"
  local i name enc
  printf '%s\n' '更多'
  printf -- '-- 打包 | bash=%s param1=pack terminal=false refresh=true\n' "$bin"
  printf -- '-- 打开收发窗口 | bash=%s param1=reveal terminal=false\n' "$bin"
  if [[ "$n" -eq 1 ]]; then
    enc="$(cb_b64enc "${CB_P_NAME[0]}")"
    printf -- '-- 打开交接目录 | bash=%s param1=open-handoff param2=b64:%s terminal=false\n' "$bin" "$enc"
    printf -- '-- 打开项目根目录 | bash=%s param1=open-root param2=b64:%s terminal=false\n' "$bin" "$enc"
    printf -- '-- 归档 | bash=%s param1=archive param2=b64:%s terminal=false refresh=true\n' "$bin" "$enc"
    printf -- '-- 结束本轮 | bash=%s param1=archive param2=b64:%s terminal=false refresh=true\n' "$bin" "$enc"
  elif [[ "$n" -gt 1 ]]; then
    printf -- '-- 归档 | bash=%s param1=archive terminal=false refresh=true\n' "$bin"
    for i in "${!CB_P_NAME[@]}"; do
      name="${CB_P_NAME[$i]}"
      enc="$(cb_b64enc "$name")"
      printf -- '-- %s\n' "$(cb_menu_title_safe "$name")"
      printf -- '---- 打开交接目录 | bash=%s param1=open-handoff param2=b64:%s terminal=false\n' "$bin" "$enc"
      printf -- '---- 打开项目根目录 | bash=%s param1=open-root param2=b64:%s terminal=false\n' "$bin" "$enc"
      printf -- '---- 结束本轮 | bash=%s param1=archive param2=b64:%s terminal=false refresh=true\n' "$bin" "$enc"
    done
  fi
  printf -- '-- 刷新 | refresh=true\n'
  printf -- '-- 添加项目… | bash=%s param1=project param2=pick-folder terminal=false refresh=true\n' "$bin"
  printf -- '-- 设置 | bash=%s param1=open-home terminal=false\n' "$bin"
}

cb_cmd_swiftbar_menu() {
  local bin
  bin="$(cb_chatbar_bin)"
  cb_projects_load
  local headline="现在：先添加项目"
  local headline_state="no_project"
  local headline_enc=""
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
    headline="$CB_NEXT_TEXT"
    headline_state="$CB_NEXT_STATE"
    headline_enc="$(cb_b64enc "$CB_NAME")"
  fi
  case "$headline_state" in
    inbox)
      printf '%s | sfimage=tray.and.arrow.down color=#C2410C size=16\n' "$(cb_menu_title_safe "$headline")"
      ;;
    ready)
      printf '%s | sfimage=shippingbox color=#1D4ED8 size=16\n' "$(cb_menu_title_safe "$headline")"
      ;;
    *)
      printf '%s | sfimage=arrow.left.arrow.right size=16\n' "$(cb_menu_title_safe "$headline")"
      ;;
  esac
  printf '%s\n' '---'
  if [[ "$headline_state" == "ready" && -n "$headline_enc" ]]; then
    printf '① 复制并选中文件（然后去 g 粘贴、拖入、发送） | bash=%s param1=handoff-now param2=b64:%s terminal=false refresh=true\n' \
      "$bin" "$headline_enc"
  elif [[ "$headline_state" == "waiting" ]]; then
    printf '打开下载文件夹 | bash=%s param1=open-downloads terminal=false\n' "$bin"
  fi
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    printf '还没有项目 | size=12 color=#888888\n'
  else
    local current=""
    current="$(cb_current_name 2>/dev/null || true)"
    for i in "${!CB_P_NAME[@]}"; do
      local name status enc checked color
      name="${CB_P_NAME[$i]}"
      cb_load_project_fields "$i"
      status="$(cb_menu_round_status)"
      enc="$(cb_b64enc "$name")"
      checked=""
      color=""
      if [[ "$name" == "$current" ]]; then
        checked=" checked=true"
      fi
      if [[ "$CB_NEXT_STATE" == "inbox" ]]; then
        color=" color=#C2410C"
      fi
      printf '%s · %s | bash=%s param1=project param2=use param3=b64:%s terminal=false refresh=true%s%s\n' \
        "$(cb_menu_title_safe "$name")" \
        "$status" \
        "$bin" \
        "$enc" \
        "$checked" \
        "$color"
    done
  fi
  printf '%s\n' '---'
  cb_menu_more "$bin"
  printf '发送永远由你手动 | size=12 color=#888888\n'
}
