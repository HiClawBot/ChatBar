# 安全 / Safety

ChatBar 不操作任何聊天软件。发送永远是你亲手把文件拖进对话。

ChatBar does not operate any chat app. Sending is always you dragging a file into the chat yourself.

## 禁止 / Forbidden

贡献者和脚本都不得：

- 用 Playwright、Puppeteer 或其它工具驱动 ChatGPT 网页或桌面端
- 用 AppleScript / osascript 去点、打字、控制浏览器或聊天窗口
- 安装浏览器扩展，读取 Cookie 或会话
- 用用户的 ChatGPT 账号调用 OpenAI API
- 把 MCP 或其它隧道接到 ChatGPT

Contributors must not add browser automation, UI scripting of a chat app, cookie or session access, calls on the user's chat account, or a tunnel into ChatGPT.

## 允许的本机操作 / Allowed local use

- `pbcopy` 只把开场白放进剪贴板
- `open` 打开 Finder
- `osascript` 只用来给 Finder 的两个窗口摆位置，以及弹出一条本机通知

这些都不接触浏览器或聊天软件。

`pbcopy` only fills the clipboard. `open` only opens Finder. `osascript` is only used to place two Finder windows and to post a local notification.

## 代码怎么进仓库 / How code gets into the repo

规划对话不提交。它只在回复文件里给出 unified diff 或带路径的完整文件。本地助手在新分支 `chatbar/R<NNN>` 上 `git apply --3way`，跑测试，再开 PR。`main` 不被移动。冲突会报告，不会 `--force`。

The planner chat does not commit. A local agent applies the diff on a new branch and opens a PR. `main` is not moved. Conflicts are reported and not forced.
