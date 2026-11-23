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
