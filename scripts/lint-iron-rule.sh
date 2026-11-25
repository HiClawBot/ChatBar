#!/bin/bash
# Fail if ChatBar code references chat-app automation.
# Patterns are built from pieces so this file does not contain the banned phrases.
set -euo pipefail

root="${1:-}"
if [[ -z "$root" ]]; then
  source="${BASH_SOURCE[0]}"
  while [[ -L "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    target="$(readlink "$source")"
    if [[ "$target" != /* ]]; then
      source="${dir}/${target}"
    else
      source="$target"
    fi
  done
  root="$(cd -P "$(dirname "$source")/.." && pwd)"
fi

p_post="$(printf '%s%s' 'CGEvent' 'Post')"
p_ax="$(printf '%s%s' 'AXUI' 'Element')"
p_key="$(printf '%s%s' 'key' 'stroke')"
p_events="$(printf '%s %s' 'System' 'Events')"
p_click="$(printf '%s %s' 'click ' 'button')"
p_bid="$(printf '%s.%s.%s' 'com' 'openai' 'chat')"
p_pw="$(printf '%s%s' 'play' 'wright')"
p_pp="$(printf '%s%s' 'puppet' 'eer')"
p_sel="$(printf '%s%s' 'selen' 'ium')"
p_safari="$(printf 'tell application "%s"' 'Safari')"
p_chrome="$(printf 'tell application "%s"' 'Google Chrome')"
p_chat="$(printf 'tell application "%s"' 'ChatGPT')"
p_api="$(printf '%s.%s' 'api.openai' 'com')"

pattern="${p_post}|${p_ax}|${p_key}|${p_events}|${p_click}|${p_bid}|${p_pw}|${p_pp}|${p_sel}|${p_safari}|${p_chrome}|${p_chat}|${p_api}"

scan=()
for dir in cli swiftbar macos scripts hooks packaging; do
  if [[ -d "${root}/${dir}" ]]; then
    scan+=("${root}/${dir}")
  fi
done
if [[ "${#scan[@]}" -eq 0 ]]; then
  echo "iron-rule: nothing to scan under ${root}" >&2
  exit 1
fi

hits="$(grep -RInE --exclude='lint-iron-rule.sh' --exclude='*.sample' "$pattern" "${scan[@]}" || true)"
if [[ -n "$hits" ]]; then
  echo "iron-rule: banned chat automation reference:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "iron-rule: ok"
