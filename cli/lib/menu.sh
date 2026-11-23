# SwiftBar menu. Clicks call the CLI. MIT License.

cb_menu_title_safe() {
  local s="$1"
  s="${s//|/／}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  # SwiftBar uses leading hyphens for submenu indentation.
  [[ "$s" != -* ]] || s="－${s#-}"
  printf '%s' "$s"
}

cb_menu_command() {
  local label="$1" bin="$2" i=1 arg
  shift 2
  printf '%s | bash="%s"' "$label" "$bin"
  for arg in "$@"; do
    printf ' param%s=%s' "$i" "$arg"
    i=$((i + 1))
  done
  printf ' terminal=false refresh=true\n'
}

cb_menu_toggle() {
  local prefix="$1" bin="$2" path="${3:-}" name="${4:-}" value=on
  cb_auto_enabled "$path" && value=off
  cb_menu_command "${prefix}$(cb_auto_label "$path")" "$bin" auto "$value" ${name:+"$name"}
}

cb_menu_more() {
  local bin="$1" step="$2" round="$3" enc="$4" back="$5" i name project
  printf '%s\n' '更多'
  if [[ -n "$back" ]]; then
    cb_menu_command '-- 上一步' "$bin" step back "$enc" "$round" "$step"
  fi
  if [[ -n "$enc" ]]; then
    cb_menu_command '-- 打包' "$bin" pack --project "$enc"
    cb_menu_command '-- 打开收发窗口' "$bin" reveal "$enc"
    cb_menu_command '-- 归档' "$bin" archive "$enc"
    cb_menu_command '-- 结束本轮' "$bin" close "$enc"
  fi
  cb_menu_command '-- 刷新' "$bin" sweep
  cb_menu_command '-- 添加项目…' "$bin" project pick-folder
  cb_menu_command '-- 检查更新' "$bin" update --check
  if cb_update_previous "$(cb_install_root)" >/dev/null; then
    cb_menu_command '-- 还原上一版' "$bin" update --rollback
  fi
  cb_menu_command '-- 设置' "$bin" open-home
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      name="${CB_P_NAME[$i]}"
      project="b64:$(cb_b64enc "$name")"
      printf -- '-- %s\n' "$(cb_menu_title_safe "$name")"
      cb_menu_toggle '---- ' "$bin" "${CB_P_HANDOFF[$i]}" "$project"
      cb_menu_command '---- 打开交接目录' "$bin" open-handoff "$project"
      cb_menu_command '---- 打开项目根目录' "$bin" open-root "$project"
    done
  fi
}

cb_cmd_swiftbar_menu() {
  local bin current step label title icon round enc="" back i new=0 status name checked dot
  local -a rows
  rows=()
  bin="$(cb_chatbar_bin)"
  cb_next_load_project ""
  cb_next_fields
  current="$CB_NEXT_PROJECT"
  step="$CB_NEXT_STEP"
  label="$CB_NEXT_LABEL"
  title="$CB_NEXT_TITLE"
  icon="$CB_NEXT_ICON"
  round="$CB_NEXT_ROUND"
  back="$CB_NEXT_BACK"
  [[ -z "$current" ]] || enc="b64:$(cb_b64enc "$current")"
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      cb_load_project_fields "$i"
      cb_next_fields
      name="$(cb_menu_title_safe "$CB_NAME")"
      checked=""
      dot=""
      [[ "$CB_NAME" != "$current" ]] || checked=" checked=true"
      if [[ "$CB_NEXT_NEW" == 1 ]]; then
        new=1
        dot=" sfimage=circle.fill sfcolor=#DC2626"
      fi
      case "$CB_NEXT_STEP" in
        copy|paste|drag|send) status=待发 ;;
        wait) status='等 g' ;;
        received) status=收好了 ;;
        result) status=有结果 ;;
        *) status=待打包 ;;
      esac
      rows+=("$(cb_menu_command "$name · 第${CB_NEXT_ROUND}轮 · $status" "$bin" \
        project use "b64:$(cb_b64enc "$CB_NAME")")${checked}${dot}")
    done
  fi

  if [[ "$new" == 1 ]]; then
    printf '%s\n' '新任务 | sfimage=circle.fill sfcolor=#DC2626 dropdown=false'
  else
    printf '%s | sfimage=%s dropdown=false\n' "$title" "$icon"
  fi
  printf '%s\n' '---'
  case "$step" in
    no_project|need_pack) printf '%s | color=#888888\n' "$label" ;;
    *) cb_menu_command "$(cb_menu_title_safe "$label")" "$bin" step advance "$enc" "$round" "$step" ;;
  esac
  cb_menu_toggle '' "$bin"
  if cb_update_available; then
    cb_menu_command '有更新' "$bin" update
  fi
  if [[ "${#rows[@]}" -gt 0 ]]; then
    printf '%s\n' '---' "${rows[@]}"
  fi
  printf '%s\n' '---'
  cb_menu_more "$bin" "$step" "$round" "$enc" "$back"
}
