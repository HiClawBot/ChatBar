# Iron Rule / 铁律

ChatBar must never click, script, or automate the ChatGPT web or desktop app.

ChatBar 不得点击、脚本化或自动化 ChatGPT 的网页或桌面应用。

This is a hard boundary for every contributor and every agent working in this repository.

## Forbidden / 禁止

- AppleScript, System Events, accessibility, or posted input events aimed at a chat app or a browser
- Browser extensions
- Reading cookies or tokens
- Calling an API with the user's chat account

## Allowed / 允许

- Local files, including the handoff folders
- The pasteboard, which the user pastes with Cmd+V
- Finder windows, placed with NSWorkspace or AppleScript that talks only to Finder

Sending a message stays a human action.

## Where it is checked / 检查

`scripts/lint-iron-rule.sh` fails the build if code references those mechanisms. `tests/run.sh` runs that check.
