# Agents working in this repository

## Iron Rule / 铁律

Never click, script, or automate the ChatGPT web or desktop app. Do not add AppleScript or System Events against a chat app, accessibility hooks against another app, posted input events, browser automation, cookie or token access, or an API call on the user's account.

You may change local files, the pasteboard, and Finder window placement. The user copies, pastes, sends, and downloads.

`scripts/lint-iron-rule.sh` enforces this. Read [SECURITY.md](SECURITY.md) before adding a feature.

## Product shape

The menu bar app in `macos/ChatBar` is a shell over `cli/chatbar`. Put handoff behavior in the CLI so tests can run it, and keep the Swift app to windows, the pasteboard, and notifications.
