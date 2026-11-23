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

# Copy the opener and, on macOS, also place the pack file on the pasteboard.
# A later Cmd+V can paste both. This only touches the local pasteboard.
cb_clipboard_bundle() {
  local text="$1"
  local file="$2"
  if [[ -n "${CHATBAR_NO_CLIPBOARD:-}" ]]; then
    printf 'clipboard:%s\n' "$file"
    return 0
  fi
  cb_clipboard_copy "$text"
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  command -v osascript >/dev/null 2>&1 || return 0
  [[ -f "$file" ]] || return 0
  osascript - "$text" "$file" <<'APPLESCRIPT' >/dev/null 2>&1 || true
use framework "Foundation"
use framework "AppKit"
on run argv
  set theText to item 1 of argv
  set thePath to item 2 of argv
  set pb to current application's NSPasteboard's generalPasteboard()
  set fileURL to current application's NSURL's fileURLWithPath:thePath
  pb's clearContents()
  pb's writeObjects:{fileURL}
  pb's setString:theText forType:"public.utf8-plain-text"
end run
APPLESCRIPT
}

cb_clipboard_copy() {
  local text="$1"
  if [[ -n "${CHATBAR_NO_CLIPBOARD:-}" ]]; then
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]] && command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$text" | pbcopy
    return $?
  fi
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$text" | wl-copy
    return $?
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard
    return $?
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
    open -R "$target" || { cb_warn "open -R failed: ${target}"; return 1; }
  elif [[ -d "$target" ]]; then
    open "$target" || cb_warn "open failed: ${target}"
  else
    cb_warn "nothing to reveal: ${target}"
    return 1
  fi
}
