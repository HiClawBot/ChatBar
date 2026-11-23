# ChatBar.org

ChatBar：macOS 菜单栏小工具，在 ChatGPT 和本地编码助手（Codex 等）之间拖拽交接文件，不做任何网页自动化。

ChatBar is a small macOS menu bar tool that shuttles files between ChatGPT and local coding agents (Codex and others) by drag and drop. It does not automate the web.

## 为什么做它 / Why

很多人同时付费使用 ChatGPT 和 Codex。ChatGPT 擅长规划和审阅，但读不到本地代码；Codex 的额度更贵；每一轮手工复制、打包、解压都很烦。用脚本去操作 ChatGPT 网页有违反服务条款、导致封号的风险。

Many people pay for both ChatGPT and Codex. ChatGPT is strong at planning and review, but it cannot read local code. Codex quota costs more. Copying, packing, and unzipping by hand every round is tedious. Automating the ChatGPT web UI risks a terms-of-service violation and an account ban.

## 好处 / Benefits

- 每一轮只拖两次：把打包文件拖进 ChatGPT，再把回复拖到菜单栏图标上。打包、解压、重命名、归档都是自动的。
- 菜单里一键切换多个本地项目，每个项目有自己的状态。
- 规划和审阅走 ChatGPT 的聊天额度，Codex 的额度留给改代码。
- 每一轮按日期归档，方便追溯。
- 从不接触 ChatGPT 的页面、账号或 Cookie。发送永远是你亲手做的，没有封号风险。
- MIT 开源，纯脚本，不需要签名。

- Only two drags per round: the pack into ChatGPT, the reply onto the menu bar icon. Packing, unzipping, renaming, and archiving are automatic.
- One click switches among many local projects, with per-project status in the menu.
- ChatGPT chat quota covers planning and review. Codex quota stays on code changes.
- Every round is archived by date for traceability.
- It never touches ChatGPT pages, accounts, or cookies. Sending is always manual, so there is no account risk.
- Open source (MIT), plain scripts, no code signing.

## 安装 / Install

目标是 Apple silicon、macOS 12 及以上。MVP 是脚本，不需要 Rosetta，也没有编译好的二进制。

**这个 MVP 的菜单栏跑在 SwiftBar 上。** 安装脚本会把 SwiftBar 装在 ChatBar 旁边，当作菜单栏宿主。ChatBar 自己还没有菜单栏程序；那是下一步要做的，就是为了去掉 SwiftBar。见 [ROADMAP.md](ROADMAP.md)。

**This MVP's menu bar runs on SwiftBar.** The installer puts SwiftBar next to ChatBar and uses it as the menu-bar host. ChatBar does not have its own menu-bar app yet. Removing that dependency is the next priority. See [ROADMAP.md](ROADMAP.md).

```bash
git clone https://github.com/HiClawBot/ChatBar.git
cd ChatBar
./scripts/install.sh
```

脚本会 `brew install --cask swiftbar`（失败再试 `brew install swiftbar`），把插件链进插件目录（仓库可以在带中文的外置盘上），然后**重启 SwiftBar**。`chatbar` 命令链到 `~/.local/bin`。可选 `./scripts/install.sh --launchd` 监听 inbox。

安装结束时你应该看到一条 ChatBar 通知：「ChatBar 已就绪，请查看菜单栏右上角」。菜单栏右上角出现图标和当前步骤。

安装脚本会在第一次打开 SwiftBar 之前写好它的偏好，所以**不该**再看到这些 SwiftBar 自己的对话框：

- 选择插件文件夹
- Sparkle 的「自动检查更新？」

自动检查更新被关掉了（`SUEnableAutomaticChecks` 为 false），避免安装时弹出 SwiftBar 的更新窗口。以后若要打开，到 SwiftBar 的设置里改。

安装过程中仍可能看到：

- Homebrew 下载 SwiftBar 时自己的英文安装日志
- macOS 第一次打开从网络安装的 SwiftBar 时，系统的「来自互联网的应用」确认。这是系统提示，不是 ChatBar 的

The script links the plugin even when the repo path is on an external volume and contains Chinese, then restarts SwiftBar so the menu item shows up. You should get a ChatBar notification: "ChatBar is ready. Check the right of the menu bar."

The installer writes SwiftBar's preferences before the first launch, so you should **not** see SwiftBar's own dialogs for choosing a plugin folder or for Sparkle's "check for updates automatically?". Automatic update checks are turned off (`SUEnableAutomaticChecks` is false) so that prompt stays away. You can turn checks back on later in SwiftBar's settings.

You may still see:

- Homebrew's own English log while it downloads SwiftBar
- One macOS confirmation the first time an app downloaded from the internet is opened. That prompt is from macOS, not from ChatBar.

交接数据默认在 `~/handoff`。可以是任意路径，包括带中文或空格的外置盘，例如 `/Volumes/4T_14000M_80G/HiBot/Projects/ChatBar/handoff`：

```bash
export CHATBAR_HOME="/你的路径/handoff"
chatbar project add --name "项目甲" --repo ~/code/foo --with-templates
```

## 两拖工作流 / Two-drag workflow

```text
本地助手 Codex / Grok
        |  chatbar pack（自动）
        v
 outbox/to_chatgpt_R00N.md  --① 你拖进规划对话（默认 ChatGPT）-->  规划对话
        ^                                                    |
        | 读 inbox/NEW.json                                  | ② 你把回复拖到菜单栏图标或 inbox
        |                                                    v
        +-------- chatbar ingest（自动解压、改名、识别补丁） --+
```

1. 助手运行 `chatbar pack` 后，「新任务」亮红点。点「复制给 g 的话」，开场白进剪贴板。
2. 在 g 里手动粘贴，回到菜单点「我已粘贴」。
3. 点「拖文件」，Finder 选中这一轮的 `to_chatgpt_R00N.md`。手动拖入 g 并发送，然后点「我已拖入并发送」。需要回退时，打开「更多 → 上一步」。
4. 等 g 回复，手动下载 ZIP。可以把 ZIP 或其他回复文件拖到 ChatBar 图标，也可以放入项目收回夹后点「更多 → 刷新」。开启自动收发时，符合当前项目和轮次的 ZIP 会从本机下载夹自动收件。
5. 收到回复后菜单亮红点。点「收好了」打开收件位置，包括已归档的回复。

项目行显示状态，点击即切换当前项目。新的回复、待发包或本地助手写入的 `agent-result.json` 会在对应项目行显示红点。打包、打开目录、归档、刷新、添加项目和设置都在「更多」里。

「自动收发」总开关与项目开关默认为关。两处都开启后，ChatBar 才会收取下载夹里的 `{项目}_roundN_reply.zip`。已安装 ChatBar Git 钩子的项目也会在提交后自动打包。粘贴、拖入聊天、发送和下载依然由人完成。

开场白按轮次现生成：第 1 轮是项目介绍、角色和附件说明；之后是「上一轮你建议了 X，这一轮我们改了 Y，请审阅并回答问题」。问题来自 `status.md`。助手也可以在打包前写出发出夹里的 `opener.md` 覆盖它。项目模板是 `templates/opener-round1.md` 和 `templates/opener-next.md`。发出夹里有可见的 `给GPT的话.txt`，以及双击即可复制的 `复制开场白.command`。

发出夹和收回夹的显示名可以改。默认是 `①发出_拖给ChatGPT` 和 `②收回_ChatGPT回复拖到这里`。`chat_name` 换成「规划聊天」时，文件夹会变成 `①发出_拖给规划聊天`。归档是 `已归档`，记录是 `记录`。规范见 `spec/handoff-v0.md`。

## ChatGPT 怎么贡献代码 / How ChatGPT should contribute

推荐做法：规划对话**不往仓库提交**。它在回复文件里给出针对当前 main 提交的 unified diff（\`\`\`diff 代码块或 `.patch`），或者带路径标题的完整文件（`File: src/hello.py` 后接代码块）。打包文件末尾的 Delivery format 会写上这个提交的 hash。

ChatBar 收到后：

- 把补丁写到收回夹的 `patches/`
- 在 `NEW.json` 里标 `type: code_patch`

本地助手（Codex、Grok）然后运行：

```bash
chatbar apply
```

这会从该提交拉出新分支 `chatbar/R001`，执行 `git apply --3way`，如果项目配置了 `test_command` 就跑测试，成功后在这条分支上提交。冲突会打印出来并停下，**不会** `--force`。`main` 不会被移动。助手再开 PR。`templates/AGENTS.md` 里写了这条规则。

The planner chat should not commit. It returns a unified diff against the main commit named in the pack, or full files with path headers. `chatbar apply` puts that diff on `chatbar/R<NNN>` with `git apply --3way`, runs tests when configured, and leaves `main` untouched. Conflicts are reported and not forced. The local agent opens the PR.

## 为什么按轮归档 / Why archive per round

发出夹和收回夹里只留**当前这一轮**。一轮结束（包已发出且回复已收回，或菜单里「结束本轮」）时，整轮搬到：

```text
已归档/2026-11/R001_2026-11-23_1455_主题/
```

按轮而不是按天或按周：一轮才是「发出了什么、收回了什么」的单位。按天会把一轮拆开，或把几轮混在一起。月份目录只是为了以后打包。`chatbar compact --older-than 90d` 会把旧月份打成 zip。`sync_to` 或 `chatbar sync --to` 可以复制备份。

`记录/轮次总表.md` 每一行是一轮。`记录/events.jsonl` 留给以后的统计。

## 安全 / Safety

不做网页自动化。细节在 [docs/SAFETY.md](docs/SAFETY.md)。贡献者规则在 [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)。

## 命令 / Commands

`pack`、`next`、`handoff-now`、`open`、`reveal`、`copy-opener`、`ingest`、`apply`、`archive`、`status`、`project add|list|use`。`chatbar next --json` 提供当前项目和步骤的结构化数据，字段见 [交接规范](spec/handoff-v0.md#next-step)。`chatbar help` 列出全部。

## 检查更新 / Updates

SwiftBar 每天后台检查一次公开发布。看到「有更新」时，点它才会下载和安装。也可以在「更多」里手动检查更新。`chatbar update` 下载 GitHub codeload 的源码压缩包并校验 SHA-256。旧版保存在安装目录旁的 `.prev-时间戳` 备份中，`chatbar update --rollback` 恢复上一份备份。请将交接目录和项目放在安装目录之外。

发布者用与 `VERSION` 一致的稳定标签（例如 `v0.1.1`）发布，并上传 `chatbar-source.sha256`。文件为一行 `<sha256> <40 位提交 SHA>`，哈希取公开地址 `https://codeload.github.com/HiClawBot/ChatBar/tar.gz/<提交 SHA>` 实际返回的压缩包字节。应从标签所指的提交生成校验文件，再将正式发布设为最新。

## 手动验收 / Manual check

1. 安装后，ChatBar 用图标和短标题显示当前步骤。
2. 从「复制给 g 的话」开始。核对剪贴板后点「我已粘贴」，下一步才可在 Finder 选中文件。
3. 点「我已拖入并发送」后，菜单进入「等 g」。将测试 ZIP 拖到 ChatBar 图标，菜单亮红点。点「收好了」确认可查看回复。
4. 若回复含有代码，`chatbar apply` 后当前分支是 `chatbar/R00N`。
