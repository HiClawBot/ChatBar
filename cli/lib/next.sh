# One local handoff action at a time. Progress and receipt acknowledgement are per project.

cb_next_fields() {
  local round pack outdir progress progress_round phase sent_at receipt receipt_round receipt_state result result_hash
  local pack_state
  CB_NEXT_PROJECT="${CB_NAME:-}"
  CB_NEXT_ROUND=0
  CB_NEXT_FILE=""
  CB_NEXT_NEW=0
  CB_NEXT_BACK=""
  CB_NEXT_SENT_AT=0
  CB_NEXT_RESULT_HASH=""
  CB_NEXT_STEP=no_project
  if [[ -n "$CB_NEXT_PROJECT" ]]; then
    round="$(cb_active_round)"
    CB_NEXT_ROUND="$round"
    CB_NEXT_STEP=need_pack
    outdir="$(cb_dir "$CB_HANDOFF" outbox)"
    pack="${outdir}/$(cb_pack_filename "$round")"
    pack_state="$(cb_state_get "$CB_HANDOFF" pack-state none)"
    if [[ -f "$pack" ]] && { [[ "$pack_state" != none ]] ||
      [[ -f "${outdir}/给GPT的话.txt" || -f "${outdir}/opener.txt" || -f "${outdir}/opener.md" ]]; }; then
      CB_NEXT_STEP=copy
      CB_NEXT_FILE="$pack"
      progress="$(cb_state_get "$CB_HANDOFF" menu-progress '')"
      IFS=' ' read -r progress_round phase sent_at <<< "$progress"
      if [[ "$progress_round" == "$round" ]]; then
        case "$phase" in
          paste) CB_NEXT_STEP=paste; CB_NEXT_BACK=copy ;;
          drag) CB_NEXT_STEP=drag; CB_NEXT_BACK=paste ;;
          send) CB_NEXT_STEP=send; CB_NEXT_BACK=drag ;;
          wait)
            CB_NEXT_STEP=wait
            CB_NEXT_BACK=send
            CB_NEXT_SENT_AT="${sent_at:-0}"
            CB_NEXT_FILE="$(cb_downloads_dir)/$(cb_reply_download_name "$CB_NAME" "$round")"
            ;;
        esac
      else
        CB_NEXT_NEW=1
      fi
    fi

    if receipt="$(cb_find_new_json "$CB_HANDOFF")"; then
      receipt_round="$(cb_json_line_value "$receipt" round || true)"
      receipt_state="$(cb_state_get "$CB_HANDOFF" menu-receipt '')"
      if [[ "$receipt" == "$(cb_dir "$CB_HANDOFF" inbox)/NEW.json" && "$receipt_state" != "$receipt_round seen" ]]; then
        receipt_state="$receipt_round unread"
      fi
      if [[ "$receipt_round" =~ ^[1-9][0-9]*$ && ( "$receipt_state" == "$receipt_round unread" ||
        ( "$receipt_state" == "$receipt_round seen" && "$CB_NEXT_STEP" == need_pack ) ) ]]; then
        CB_NEXT_STEP=received
        CB_NEXT_FILE="$receipt"
        CB_NEXT_ROUND="$receipt_round"
        CB_NEXT_BACK=""
        CB_NEXT_NEW=0
        if [[ "$receipt_state" == "$receipt_round unread" ]]; then
          CB_NEXT_NEW=1
        fi
      fi
    fi

    if [[ "${1:-}" != transfer && ( "$CB_NEXT_STEP" != received || "$CB_NEXT_NEW" == 0 ) ]]; then
      result="$CB_HANDOFF/agent-result.json"
      if [[ -f "$result" ]] && result_hash="$(cb_sha256 "$result")" &&
        [[ "$result_hash" != "$(cb_state_get "$CB_HANDOFF" menu-result-seen '')" ]]; then
        CB_NEXT_STEP=result
        CB_NEXT_FILE="$result"
        CB_NEXT_ROUND="$round"
        CB_NEXT_BACK=""
        CB_NEXT_NEW=1
        CB_NEXT_RESULT_HASH="$result_hash"
      fi
    fi
  fi

  case "$CB_NEXT_STEP" in
    no_project) CB_NEXT_TITLE=添加项目; CB_NEXT_LABEL=还没有项目; CB_NEXT_ICON=plus.circle ;;
    need_pack) CB_NEXT_TITLE=待打包; CB_NEXT_LABEL=等待本地助手打包; CB_NEXT_ICON=shippingbox ;;
    copy) CB_NEXT_TITLE=复制; CB_NEXT_LABEL='复制给 g 的话'; CB_NEXT_ICON=doc.on.doc ;;
    paste) CB_NEXT_TITLE=粘贴; CB_NEXT_LABEL=我已粘贴; CB_NEXT_ICON=clipboard ;;
    drag) CB_NEXT_TITLE=拖文件; CB_NEXT_LABEL="拖文件 · ${CB_NEXT_FILE##*/}"; CB_NEXT_ICON=doc ;;
    send) CB_NEXT_TITLE=拖文件; CB_NEXT_LABEL=我已拖入并发送; CB_NEXT_ICON=paperplane ;;
    wait) CB_NEXT_TITLE='等 g'; CB_NEXT_LABEL=打开下载文件夹; CB_NEXT_ICON=hourglass ;;
    result) CB_NEXT_TITLE=新任务; CB_NEXT_LABEL=查看结果; CB_NEXT_ICON=doc.text ;;
    received) CB_NEXT_TITLE=收好了; CB_NEXT_LABEL=收好了; CB_NEXT_ICON=checkmark.circle ;;
  esac
  if [[ "$CB_NEXT_NEW" == 1 ]]; then
    CB_NEXT_TITLE=新任务
  fi
}

# Resolve the current project consistently for both the menu and the CLI.
cb_next_load_project() {
  local name="$1" idx
  cb_projects_load
  if [[ -n "$name" ]]; then
    cb_resolve_project_arg "$name"
  elif [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    name="$(cb_current_name || true)"
    idx="$(cb_project_find "$name" || printf '0')"
    cb_load_project_fields "$idx"
  else
    CB_NAME=""
  fi
}

cb_cmd_next() {
  local as_json=0 name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) as_json=1; shift ;;
      --project)
        [[ $# -ge 2 ]] || cb_die "missing --project value"
        name="$2"; shift 2
        ;;
      -*) cb_die "unknown flag: $1" ;;
      *)
        [[ -z "$name" ]] || cb_die "unexpected argument: $1"
        name="$1"; shift
        ;;
    esac
  done
  cb_next_load_project "$name"
  cb_next_fields
  if [[ "$as_json" == 1 ]]; then
    printf '{"step":"%s","title_short":"%s","action_label":"%s","project":"%s","round":%s,"file":"%s"}\n' \
      "$CB_NEXT_STEP" "$CB_NEXT_TITLE" "$(cb_json_escape "$CB_NEXT_LABEL")" \
      "$(cb_json_escape "$CB_NEXT_PROJECT")" "$CB_NEXT_ROUND" "$(cb_json_escape "$CB_NEXT_FILE")"
  else
    printf '%s\n' "$CB_NEXT_LABEL"
  fi
}

# Menu callbacks carry the rendered project, round and phase. A stale or repeated
# confirmation cannot advance a different project, round or step.
cb_cmd_step() (
  local action="${1:-}" name="${2:-}" round="${3:-}" expected="${4:-}" next opener sent_at=0
  [[ $# == 4 && -n "$name" ]] || cb_die "usage: chatbar step advance|back PROJECT ROUND STEP"
  cb_resolve_project_arg "$name"
  cb_lock "$CB_HANDOFF" || exit 1
  trap 'cb_unlock "$CB_HANDOFF"' EXIT
  cb_next_fields
  [[ "$CB_NEXT_ROUND" == "$round" && "$CB_NEXT_STEP" == "$expected" ]] || exit 0
  case "$action:$CB_NEXT_STEP" in
    advance:copy)
      opener="$(cb_publish_opener)"
      cb_clipboard_copy "$opener" || exit 1
      next=paste
      ;;
    advance:paste) next=drag ;;
    advance:drag)
      cb_reveal_path "$CB_NEXT_FILE" || exit 1
      next=send
      ;;
    advance:send) next=wait; sent_at="$(date +%s)" ;;
    advance:wait) cb_cmd_open_downloads; exit ;;
    advance:received)
      cb_show_dir "${CB_NEXT_FILE%/*}" || exit 1
      cb_state_set "$CB_HANDOFF" menu-receipt "$round seen"
      exit
      ;;
    advance:result)
      cb_reveal_path "$CB_NEXT_FILE" || exit 1
      cb_state_set "$CB_HANDOFF" menu-result-seen "$CB_NEXT_RESULT_HASH"
      exit
      ;;
    back:*)
      [[ -n "$CB_NEXT_BACK" ]] || exit 0
      next="$CB_NEXT_BACK"
      ;;
    *) cb_die "invalid step action: $action ($expected)" ;;
  esac
  cb_state_set "$CB_HANDOFF" menu-progress "$round $next $sent_at"
)
