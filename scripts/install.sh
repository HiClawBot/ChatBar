#!/bin/bash
# Install the chatbar CLI and symlink the SwiftBar plugin.
# No code signing. Does not automate any chat app.
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
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

chmod +x "${ROOT}/cli/chatbar" "${ROOT}/swiftbar/chatbar.1m.sh"
mkdir -p "${PREFIX}/bin"
ln -sfn "${ROOT}/cli/chatbar" "${PREFIX}/bin/chatbar"
echo "CLI: ${PREFIX}/bin/chatbar"
case ":${PATH}:" in
  *":${PREFIX}/bin:"*) ;;
  *) echo "Add to PATH: export PATH=\"${PREFIX}/bin:\$PATH\"" ;;
esac

if [[ "$SKIP_SWIFTBAR" == 1 ]]; then
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SwiftBar is macOS only. The CLI is installed."
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install SwiftBar from https://github.com/swiftbar/SwiftBar/releases" >&2
else
  if ! brew list --cask swiftbar >/dev/null 2>&1; then
    brew install --cask swiftbar || brew install swiftbar
  fi
fi

if [[ -z "$PLUGINS" ]] && command -v defaults >/dev/null 2>&1; then
  PLUGINS="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
  PLUGINS="${PLUGINS/#\~/${HOME}}"
fi
if [[ -z "$PLUGINS" ]]; then
  PLUGINS="${HOME}/.swiftbar"
  defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGINS" || true
fi
mkdir -p "$PLUGINS"
ln -sfn "${ROOT}/swiftbar/chatbar.1m.sh" "${PLUGINS}/chatbar.1m.sh"
echo "SwiftBar plugin: ${PLUGINS}/chatbar.1m.sh"
echo "Restart SwiftBar if the menu item does not appear."

if [[ "$WITH_LAUNCHD" == 1 ]]; then
  "${PREFIX}/bin/chatbar" watch install || true
fi
