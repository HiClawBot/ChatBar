# Local notifications only. MIT License.
# display notification is a local banner. It does not script any chat app
# or browser. See docs/SAFETY.md.

cb_notify() {
  local title="$1"
  local body="$2"
  if [[ -n "${CHATBAR_NO_NOTIFY:-}" ]]; then
    return 0
  fi
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  command -v osascript >/dev/null 2>&1 || return 0
  title="${title//\"/}"
  body="${body//\"/}"
  title="${title//$'\n'/ }"
  body="${body//$'\n'/ }"
  osascript -e "display notification \"${body}\" with title \"${title}\"" >/dev/null 2>&1 || true
}

cb_clipboard_copy() {
  local text="$1"
  if [[ -n "${CHATBAR_NO_CLIPBOARD:-}" ]]; then
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]] && command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$text" | pbcopy || true
    return 0
  fi
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$text" | wl-copy || true
    return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard || true
    return 0
  fi
  return 0
}

cb_reveal_path() {
  local target="$1"
  if [[ -n "${CHATBAR_NO_OPEN:-}" || "$(uname -s)" != "Darwin" ]]; then
    printf 'reveal:%s\n' "$target"
    return 0
  fi
  if [[ -f "$target" ]]; then
    open -R "$target" || cb_warn "open -R failed: ${target}"
  elif [[ -d "$target" ]]; then
    open "$target" || cb_warn "open failed: ${target}"
  else
    cb_warn "nothing to reveal: ${target}"
    return 1
  fi
}
