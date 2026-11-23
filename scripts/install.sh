#!/bin/bash
# Install the chatbar CLI and the SwiftBar menu-bar host.
# No code signing. Does not automate any chat app.
#
# SwiftBar 2.x first-launch UI (from AppDelegate.swift / PreferencesStore.swift):
# - Plugin folder alert when PluginDirectory is missing or the folder does not exist.
# - Sparkle "check for updates automatically?" when SUHasLaunchedBefore is unset.
# There is no separate welcome/onboarding UserDefaults key in SwiftBar 2.x.
# SUEnableAutomaticChecks is set false on purpose so Sparkle stays quiet.
# A running SwiftBar rewrites preferences from memory when it quits, so we
# quit it before writing defaults, then launch it again after the plugin link.
set -euo pipefail

cb_install_root() {
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
  cd "$(dirname "$source")/.." && pwd
}

# zh when the first preferred language starts with zh, otherwise en.
cb_ui_lang() {
  local first=""
  if command -v defaults >/dev/null 2>&1; then
    first="$(defaults read -g AppleLanguages 2>/dev/null | grep -E -o '[A-Za-z]{2}([-_][A-Za-z0-9]+)?' | head -n 1 || true)"
  fi
  case "$first" in
    zh*) printf 'zh' ;;
    *) printf 'en' ;;
  esac
}

LANG_UI="$(cb_ui_lang)"

cb_say() {
  local key="$1"
  case "${LANG_UI}:${key}" in
    zh:cli_linked) printf '命令行已放在 %s\n' "$2" ;;
    en:cli_linked) printf 'Command-line tool: %s\n' "$2" ;;
    zh:path_hint) printf '终端里若找不到 chatbar，请把 %s 加入 PATH。\n' "$2" ;;
    en:path_hint) printf 'If the terminal cannot find chatbar, add %s to PATH.\n' "$2" ;;
    zh:not_mac) printf '%s\n' '命令行已安装。SwiftBar 只在 macOS 上提供菜单栏。' ;;
    en:not_mac) printf '%s\n' 'The command line is installed. SwiftBar provides the menu bar on macOS only.' ;;
    zh:no_brew) printf '%s\n' '没有找到 Homebrew。请从 https://github.com/swiftbar/SwiftBar/releases 安装 SwiftBar，然后重新运行本脚本。' ;;
    en:no_brew) printf '%s\n' 'Homebrew was not found. Install SwiftBar from https://github.com/swiftbar/SwiftBar/releases and run this script again.' ;;
    zh:installing_host) printf '%s\n' '正在安装菜单栏宿主 SwiftBar。下面是 Homebrew 自己的安装日志，不是 ChatBar 的对话框。' ;;
    en:installing_host) printf '%s\n' 'Installing the SwiftBar menu-bar host. The log below is Homebrew, not a ChatBar dialog.' ;;
    zh:swiftbar_missing) printf '%s\n' 'SwiftBar 没有装上，菜单栏项还不会出现。' ;;
    en:swiftbar_missing) printf '%s\n' 'SwiftBar is not installed, so the menu item will not appear yet.' ;;
    zh:unknown) printf '不认识的参数：%s\n' "$2" ;;
    en:unknown) printf 'Unknown argument: %s\n' "$2" ;;
    zh:ready) printf '%s\n' 'ChatBar 已就绪，看菜单栏右上角的 ⇄ ChatBar。' ;;
    en:ready) printf '%s\n' 'ChatBar is ready. Look for ⇄ ChatBar at the right of the menu bar.' ;;
    zh:ready_note) printf '%s\n' 'ChatBar 已就绪，看菜单栏右上角的 ⇄ ChatBar' ;;
    en:ready_note) printf '%s\n' 'ChatBar is ready. Look for ⇄ ChatBar at the right of the menu bar.' ;;
    *) printf '%s\n' "$key" ;;
  esac
}

cb_notify_ready() {
  command -v osascript >/dev/null 2>&1 || return 0
  local body
  body="$(cb_say ready_note)"
  body="${body%$'\n'}"
  osascript - "$body" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display notification (item 1 of argv) with title "ChatBar"
end run
APPLESCRIPT
}

cb_quit_swiftbar() {
  pgrep -x SwiftBar >/dev/null 2>&1 || return 0
  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'tell application "SwiftBar" to quit' >/dev/null 2>&1 || true
  fi
  local i=0
  while pgrep -x SwiftBar >/dev/null 2>&1; do
    i=$((i + 1))
    if [[ "$i" -ge 20 ]]; then
      killall SwiftBar >/dev/null 2>&1 || true
      break
    fi
    sleep 0.25
  done
  sleep 0.3
}

cb_launch_swiftbar() {
  if open -a SwiftBar >/dev/null 2>&1; then
    return 0
  fi
  if [[ -d /Applications/SwiftBar.app ]]; then
    open /Applications/SwiftBar.app >/dev/null 2>&1 || true
  fi
}

cb_seed_swiftbar_defaults() {
  local plugins="$1"
  # Automatic update checks are off so Sparkle does not ask on first launch.
  defaults write com.ameba.SwiftBar PluginDirectory -string "$plugins"
  defaults write com.ameba.SwiftBar MakePluginExecutable -bool true
  defaults write com.ameba.SwiftBar SUHasLaunchedBefore -bool true
  defaults write com.ameba.SwiftBar SUEnableAutomaticChecks -bool false
  defaults write com.ameba.SwiftBar SUAutomaticallyUpdate -bool false
  defaults write com.ameba.SwiftBar SUSendProfileInfo -bool false
  defaults write com.ameba.SwiftBar IncludeBetaUpdates -bool false
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
ROOT="$(cb_install_root)"
PREFIX="${PREFIX:-${HOME}/.local}"
SKIP_SWIFTBAR=0
WITH_LAUNCHD=0
PLUGINS="${SWIFTBAR_PLUGINS_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --skip-swiftbar) SKIP_SWIFTBAR=1; shift ;;
    --launchd) WITH_LAUNCHD=1; shift ;;
    --plugins-dir) PLUGINS="${2:-}"; shift 2 ;;
    *) cb_say unknown "$1" >&2; exit 1 ;;
  esac
done

chmod +x "${ROOT}/cli/chatbar" "${ROOT}/swiftbar/chatbar.1m.sh"
mkdir -p "${PREFIX}/bin"
ln -sfn "${ROOT}/cli/chatbar" "${PREFIX}/bin/chatbar"

if [[ "$SKIP_SWIFTBAR" == 1 ]]; then
  cb_say cli_linked "$PREFIX/bin/chatbar"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  cb_say not_mac
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  cb_say no_brew >&2
  exit 1
fi

if ! brew list --cask swiftbar >/dev/null 2>&1; then
  cb_say installing_host
  brew install --cask swiftbar || brew install swiftbar
fi

# Stop SwiftBar before writing defaults. If it is running, quit writes its
# in-memory preferences back and would erase PluginDirectory.
cb_quit_swiftbar

if [[ -z "$PLUGINS" ]] && command -v defaults >/dev/null 2>&1; then
  PLUGINS="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
  PLUGINS="${PLUGINS/#\~/${HOME}}"
fi
if [[ -z "$PLUGINS" ]]; then
  PLUGINS="${HOME}/.swiftbar"
fi
mkdir -p "$PLUGINS"
PLUGINS="$(cd "$PLUGINS" && pwd)"

cb_seed_swiftbar_defaults "$PLUGINS"
# Link after defaults, including when the script itself lives on an external
# volume whose path contains spaces or Chinese. Restart picks the new symlink up.
ln -sfn "${ROOT}/swiftbar/chatbar.1m.sh" "${PLUGINS}/chatbar.1m.sh"

if [[ "$WITH_LAUNCHD" == 1 ]]; then
  "${PREFIX}/bin/chatbar" watch install || true
fi

cb_launch_swiftbar
cb_notify_ready

path_extra=""
case ":${PATH}:" in
  *":${PREFIX}/bin:"*) ;;
  *) path_extra="$(cb_say path_hint "$PREFIX/bin")" ;;
esac
cb_say ready
if [[ -n "$path_extra" ]]; then
  printf '%s' "$path_extra"
fi
fi
