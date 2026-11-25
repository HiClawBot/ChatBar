# ChatBar menu bar app

Apple silicon, macOS 13+. The app shells out to `cli/chatbar`.

```bash
make install
```

Open a view without clicking the icon:

```bash
open -a ChatBar --args --show bar
open -a ChatBar --args --show card
open -a ChatBar --args --show settings
open "chatbar-app://open?view=bar"
```

`view` is `bar`, `card`, or `settings`. Left-click opens the bar by default. Right-click opens the compact card. Settings can swap them.

## Round handoff

The status item shows the short title from `chatbar next --json`. The card shows one action for the current project and round. Pasting, dragging into the chat, sending, and downloading remain user actions. The card delegates each action and Back under More to `chatbar step`, so SwiftBar and the native menu share progress.

When both auto-exchange switches are on, the native watcher runs the same local sweep as SwiftBar. It collects the expected reply ZIP after send confirmation. A manual drop on the status item also works with the switches off.

`bash scripts/build-macos.sh` runs the packaged app in headless mode across a complete handoff using a temporary home and a test ZIP. The packaged executable prints the six decoded fields at each step.
