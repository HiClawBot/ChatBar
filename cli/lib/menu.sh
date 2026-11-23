# SwiftBar menu. Clicks call the CLI. MIT License.

cb_menu_label() {
  local inbox_state="$1"
  local pack_state="$2"
  if [[ "$inbox_state" == "new" ]]; then
    printf '%s' "新回复"
  elif [[ "$pack_state" == "ready" ]]; then
    printf '%s' "待拖出"
  elif [[ "$pack_state" == "presented" ]]; then
    printf '%s' "已给出"
  else
    printf '%s' "空闲"
  fi
}

cb_menu_title_safe() {
  local s="$1"
  s="${s//|/／}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

cb_cmd_swiftbar_menu() {
  local bin
  bin="$(cb_chatbar_bin)"
  cb_projects_load
  local replies=0 ready=0 i
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      local handoff inbox_state pack_state
      handoff="${CB_P_HANDOFF[$i]}"
      inbox_state="$(cb_state_get "$handoff" "inbox-state" "none")"
      pack_state="$(cb_state_get "$handoff" "pack-state" "none")"
      if [[ "$inbox_state" == "new" ]]; then
        replies=$((replies + 1))
      elif [[ "$pack_state" == "ready" ]]; then
        ready=$((ready + 1))
      fi
    done
  fi
  if [[ "$replies" -gt 0 ]]; then
    printf 'ChatBar %s | sfimage=tray.and.arrow.down color=#C2410C\n' "$replies"
  elif [[ "$ready" -gt 0 ]]; then
    printf 'ChatBar | sfimage=shippingbox color=#1D4ED8\n'
  else
    printf 'ChatBar | sfimage=arrow.left.arrow.right\n'
  fi
  printf '%s\n' '---'
  if [[ "${#CB_P_NAME[@]}" -eq 0 ]]; then
    printf '还没有项目 | bash=%s param1=project param2=add-interactive terminal=true refresh=true\n' "$bin"
  else
    local current=""
    current="$(cb_current_name 2>/dev/null || true)"
    for i in "${!CB_P_NAME[@]}"; do
      local name handoff label inbox_state pack_state enc checked color
      name="${CB_P_NAME[$i]}"
      handoff="${CB_P_HANDOFF[$i]}"
      inbox_state="$(cb_state_get "$handoff" "inbox-state" "none")"
      pack_state="$(cb_state_get "$handoff" "pack-state" "none")"
      label="$(cb_menu_label "$inbox_state" "$pack_state")"
      enc="$(cb_b64enc "$name")"
      checked=""
      color=""
      if [[ "$name" == "$current" ]]; then
        checked=" checked=true"
      fi
      if [[ "$inbox_state" == "new" ]]; then
        color=" color=#C2410C"
      fi
      printf '%s · %s | bash=%s param1=open param2=b64:%s terminal=false refresh=true%s%s\n' \
        "$(cb_menu_title_safe "$name")" \
        "$label" \
        "$bin" \
        "$enc" \
        "$checked" \
        "$color"
      printf '%s\n' "复制给 GPT 的话 · $(cb_menu_title_safe "$name") | bash=${bin} param1=copy-opener param2=b64:${enc} terminal=false"
      printf '%s\n' "-- 打开交接目录 · Open handoff folder | bash=${bin} param1=open-handoff param2=b64:${enc} terminal=false"
      printf '%s\n' "-- 打开项目根目录 · Open workspace root | bash=${bin} param1=open-root param2=b64:${enc} terminal=false"
      printf '%s\n' "-- 结束本轮 · Close round | bash=${bin} param1=archive param2=b64:${enc} terminal=false refresh=true"
    done
  fi
  printf '%s\n' '---'
  printf '打包当前项目 | bash=%s param1=pack terminal=false refresh=true\n' "$bin"
  printf '复制给 GPT 的话 | bash=%s param1=copy-opener terminal=false\n' "$bin"
  printf '打开收发窗口 | bash=%s param1=reveal terminal=false\n' "$bin"
  printf '归档 | bash=%s param1=archive terminal=false refresh=true\n' "$bin"
  printf '刷新 | refresh=true\n'
  printf '%s\n' '---'
  printf '添加项目… | bash=%s param1=project param2=add-interactive terminal=true refresh=true\n' "$bin"
  printf '发送永远手动，不操作规划对话页面 | size=12 color=#888888\n'
}
