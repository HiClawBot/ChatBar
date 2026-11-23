# Handoff spec 0

Agent-agnostic layout. Display folder names are local config; roles are fixed.

## Roles

| Role | Default display name |
| --- | --- |
| outbox | `①发出_拖给{chat}` |
| inbox | `②收回_{chat}回复拖到这里` |
| archive | `已归档` |
| log | `记录` |

`{chat}` defaults to `ChatGPT`. Resolve names from built-in defaults, then `~/handoff/config.yaml`, then the project in `projects.yaml`. The resolved map is `<handoff>/folders.json`. `NEW.json` lives in the inbox-role folder.

## NEW.json

```json
{
  "spec_version": "0",
  "project": "Name",
  "round": 1,
  "status": "new",
  "type": "reply",
  "base_commit": "<git sha or none>",
  "patches": [],
  "files": []
}
```

`type` is `code_patch` when the reply contains a unified diff (```` ```diff ````, a `.patch` / `.diff` file) or full files with a path header (`File: path`). Those are copied under the inbox role folder at `patches/` (`*.patch` and `patches/files/...`). Each patch object includes `"type": "code_patch"`.

After a zip unpacks, the original zip moves to `<archive>/YYYY-MM/Rnnn_raw/` so a later sweep cannot unpack it again. `<log>/ingested.sha256` records the sha256 of each ingested file. Sweep skips those hashes, and it skips a project while another process holds `<handoff>/.lock`.

## Archive

Outbox and inbox keep only the current round. A finished round moves to:

`archive/YYYY-MM/R001_YYYY-MM-DD_HHMM_topic/`

The log role folder holds `轮次总表.md` and `events.jsonl` (`spec_version`, timestamp, project, round, direction, files, bytes, approx_tokens).

## Apply

`chatbar apply` checks out `chatbar/R<NNN>` from `base_commit` and runs `git apply --3way`. It does not use `--force` and does not move `main`. Optional `test_command` in `projects.yaml` runs afterward. A clean apply is committed on that branch so an agent can open a PR.

## Next step

The drag file for round N is `outbox/to_chatgpt_R00N.md` (also written as `to_planner.md`). A hand-written file for the current round counts as ready when an opener is in the outbox (`给GPT的话.txt`, `opener.txt`, or `opener.md`) and that round has no ingested reply. `chatbar next` prints one short Chinese sentence for the current action. `chatbar next --json` returns `text`, `state` (`need_pack`, `ready`, `waiting`, `inbox`, `no_project`), `round`, `file`, and `reply_file` so a native menu bar can show the same sentence. `chatbar handoff-now` copies the opener and selects that exact file in Finder. It does not click or type into any chat app.

The menu (SwiftBar and a native menu bar) is three parts:

1. The title is that one sentence.
2. One primary action for the current state. `ready`: `① 复制并选中文件（然后去 g 粘贴、拖入、发送）` (`handoff-now`). `waiting`: `打开下载文件夹` (`open-downloads`). `inbox` and `need_pack`: no action. Do not also show a separate “copy the opener” item.
3. Project rows are status only (`name · 第 N 轮 · 待发给 g`), and a click switches the current project. Per-project folder and close-round items appear only when there is more than one project, and only under `更多`. Pack, reveal, archive, refresh, add-project, and settings live under `更多`. Footer: `发送永远由你手动`.

## Writes

Manifests and state files are written to a temp file in the same directory, then renamed. A `.lock` directory serializes writers.
