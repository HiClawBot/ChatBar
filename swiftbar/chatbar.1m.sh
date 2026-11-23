#!/bin/bash
# <xbar.title>ChatBar</xbar.title>
# <xbar.version>v0.1.1</xbar.version>
# <xbar.author>HiClawBot</xbar.author>
# <xbar.author.github>HiClawBot</xbar.author.github>
# <xbar.desc>Drag files between a planner chat and local coding agents. No web automation.</xbar.desc>
# <xbar.droptypes>public.file-url</xbar.droptypes>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# SAFETY: dropping files here only ingests them locally.
# This plugin never controls a browser, ChatGPT, or any other chat app.

set -euo pipefail

cb_plugin_dir() {
  local source="${BASH_SOURCE[0]}"
  local dir target
  while [[ -L "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    target="$(readlink "$source")"
    if [[ "$target" != /* ]]; then
      source="${dir}/${target}"
    else
      source="$target"
    fi
  done
  cd -P "$(dirname "$source")" && pwd
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
PLUGIN_DIR="$(cb_plugin_dir)"
if [[ -x "${PLUGIN_DIR}/../cli/chatbar" ]]; then
  CHATBAR="$(cd "${PLUGIN_DIR}/../cli" && pwd)/chatbar"
elif command -v chatbar >/dev/null 2>&1; then
  CHATBAR="$(command -v chatbar)"
else
  printf '%s\n' '未安装 | sfimage=exclamationmark.circle sfcolor=#B91C1C dropdown=false'
  printf '%s\n' '---'
  printf '%s\n' '找不到 ChatBar'
  exit 0
fi

if [[ "${LAUNCHED_FROM_DROP_ACTION:-}" == "TRUE" || -n "${DROPPED_FILES:-}" || -n "${DROPPED_URL:-}" ]]; then
  "$CHATBAR" ingest-drop >/dev/null || true
fi
"$CHATBAR" sweep --auto >/dev/null || true
if [[ -z "${CHATBAR_NO_UPDATE:-}" ]]; then
  ( "$CHATBAR" update --check-if-due >/dev/null 2>&1 & )
fi
"$CHATBAR" swiftbar-menu
fi
