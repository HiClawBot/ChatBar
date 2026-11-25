# Optional git hook and inbox watcher. MIT License.

cb_xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

cb_cmd_hook_install() {
  local repo=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      *)
        if [[ -z "$repo" ]]; then repo="$1"; shift; else cb_die "unexpected argument: $1"; fi
        ;;
    esac
  done
  if [[ -z "$repo" ]]; then
    repo="$(pwd)"
  fi
  repo="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || cb_die "not a git repo: ${repo}"
  local hook="${repo}/.git/hooks/post-commit"
  local marker="chatbar hook"
  if [[ -f "$hook" ]] && grep -q "$marker" "$hook"; then
    cb_note "hook already installed"
    return 0
  fi
  local block
  block="$(cat <<'EOF'

# chatbar hook — refresh the planner pack after a commit. Never fails the commit.
# Does not touch a planner chat.
if command -v chatbar >/dev/null 2>&1; then
  chatbar pack --auto --repo "$(git rev-parse --show-toplevel)" --quiet || true
fi
EOF
)"
  if [[ -f "$hook" ]]; then
    printf '%s\n' "$block" >> "$hook"
  else
    {
      printf '%s\n' '#!/bin/bash'
      printf '%s\n' "$block"
    } > "$hook"
  fi
  chmod +x "$hook"
  cb_note "installed ${hook}"
}

cb_cmd_watch_install() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    cb_warn "launchd watcher is macOS only"
    return 1
  fi
  local bin plist agents
  bin="$(cb_chatbar_bin)"
  agents="${HOME}/Library/LaunchAgents"
  mkdir -p "$agents"
  plist="${agents}/com.hiclawbot.chatbar.sweep.plist"
  cb_projects_load
  local paths="" i inbox
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      cb_load_project_fields "$i"
      cb_ensure_layout "$CB_HANDOFF"
      inbox="$(cb_dir "$CB_HANDOFF" inbox)"
      paths="${paths}    <string>$(cb_xml_escape "$inbox")</string>
"
    done
  fi
  if [[ -z "$paths" ]]; then
    paths="    <string>$(cb_xml_escape "$(cb_home)")</string>
"
  fi
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.hiclawbot.chatbar.sweep</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(cb_xml_escape "$bin")</string>
    <string>sweep</string>
    <string>--auto</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CHATBAR_HOME</key>
    <string>$(cb_xml_escape "$(cb_home)")</string>
    <key>CHATBAR_SWEEP_SETTLE</key>
    <string>1</string>
  </dict>
  <key>WatchPaths</key>
  <array>
${paths}  </array>
  <key>StartInterval</key>
  <integer>30</integer>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
  launchctl unload "$plist" >/dev/null 2>&1 || true
  launchctl load "$plist"
  cb_note "launchd watcher installed: ${plist}"
}

cb_cmd_watch_uninstall() {
  local plist="${HOME}/Library/LaunchAgents/com.hiclawbot.chatbar.sweep.plist"
  if [[ -f "$plist" ]]; then
    if command -v launchctl >/dev/null 2>&1; then
      launchctl unload "$plist" >/dev/null 2>&1 || true
    fi
    rm -f "$plist"
  fi
  cb_note "launchd watcher removed"
}

cb_cmd_watch_run() {
  cb_projects_load
  local -a dirs
  dirs=()
  local i
  if [[ "${#CB_P_NAME[@]}" -gt 0 ]]; then
    for i in "${!CB_P_NAME[@]}"; do
      cb_load_project_fields "$i"
      cb_ensure_layout "$CB_HANDOFF"
      dirs+=("$(cb_dir "$CB_HANDOFF" inbox)")
    done
  fi
  if command -v fswatch >/dev/null 2>&1 && [[ "${#dirs[@]}" -gt 0 ]]; then
    cb_note "watching with fswatch"
    fswatch -0 "${dirs[@]}" | while IFS= read -r -d '' _; do
      "$CB_BIN" sweep --auto || true
    done
    return 0
  fi
  cb_note "fswatch not installed; polling every ${CHATBAR_WATCH_INTERVAL:-3}s"
  while true; do
    cb_cmd_sweep --auto || true
    sleep "${CHATBAR_WATCH_INTERVAL:-3}"
  done
}

cb_cmd_watch() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    install) cb_cmd_watch_install "$@" ;;
    uninstall) cb_cmd_watch_uninstall "$@" ;;
    run) cb_cmd_watch_run "$@" ;;
    *) cb_die "usage: chatbar watch install|uninstall|run" ;;
  esac
}
