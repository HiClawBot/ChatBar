# 路线 / Roadmap

这些还没做。当前版本只做手工交接和本机补丁分支。

Not built yet. This version is the manual handoff plus local patch branches.

1. **下一步优先做原生 Mac 应用，用来去掉 SwiftBar。** 现在的菜单栏靠旁边安装的 SwiftBar。下一个版本用自己的 `NSStatusItem` 调用现有 `chatbar` CLI，这样安装时不再出现 SwiftBar 的界面。签名和 Homebrew Cask 仍往后放。
2. **多个规划对话。** Claude、Gemini、Grok 网页也可以当规划方。开场白按项目配置，ChatGPT 只是默认例子。
3. **轮次统计。** `events.jsonl` 已经记下时间和大约 token，以后的 `chatbar stats` 再做汇总。
4. **多人共享。** 交接目录可以放在带空格或中文的共享盘上。原子写入和 `.lock` 已经按这个准备，完整的团队模式还没有。

The native menu bar app is the next priority so ChatBar no longer depends on SwiftBar. More planner chats, a stats view, and shared-team workflows come after that. The CLI remains the engine.
