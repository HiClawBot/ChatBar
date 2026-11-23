# Local hook scripts. MIT License.
# hooks/on_inbox runs after a reply is ingested.
# Scripts may notify a local agent. They must not automate a chat app.

cb_run_inbox_hooks() {
  local round="$1"
  local new_json="$2"
  local root dir script base
  root="$(cb_install_root)"
  for dir in "$(cb_home)/hooks/on_inbox" "${root}/hooks/on_inbox"; do
    [[ -d "$dir" ]] || continue
    local found
    found=0
    shopt -s nullglob
    for script in "$dir"/*; do
      [[ -f "$script" && -x "$script" ]] || continue
      base="$(basename "$script")"
      case "$base" in
        README*|*.sample|.*) continue ;;
      esac
      found=1
      CHATBAR_HOOK=on_inbox \
        CHATBAR_PROJECT="${CB_NAME:-}" \
        CHATBAR_ROUND="$round" \
        CHATBAR_HANDOFF="${CB_HANDOFF:-}" \
        CHATBAR_NEW_JSON="$new_json" \
        CHATBAR_REPO="${CB_REPO:-}" \
        "$script" || cb_warn "hook failed: ${script}"
    done
    shopt -u nullglob
    [[ "$found" == 0 ]] || true
  done
}
