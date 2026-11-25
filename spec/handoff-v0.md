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

The round file is `outbox/to_chatgpt_R00N.md`. A hand-written file for the current round is ready when its outbox has an opener (`给GPT的话.txt`, `opener.txt`, or `opener.md`).

`chatbar next --json [PROJECT]` returns `step`, `title_short`, `action_label`, `project`, `round`, and `file`. The last field is a local path or an empty string. Use `chatbar step advance PROJECT ROUND STEP` to run the shown action. The command checks the project, round and step against current local state. `chatbar step back PROJECT ROUND STEP` goes back where the menu offers that action.

| Step | Menu action | `file` |
| --- | --- | --- |
| `no_project` | 还没有项目 | Empty |
| `need_pack` | 等待本地助手打包 | Empty |
| `copy` | 复制给 g 的话 | Round pack |
| `paste` | 我已粘贴 | Round pack |
| `drag` | 拖文件 | Round pack to select in Finder |
| `send` | 我已拖入并发送 | Round pack |
| `wait` | 打开下载文件夹 | Expected ZIP in Downloads |
| `received` | 收好了 | Receipt manifest in inbox or archive |
| `result` | 查看结果 | The local agent result at `agent-result.json` |

The first menu row shows the current action. The header displays a short title and icon. An unread reply or changed local agent result shows a red dot for its project and sets the header to「新任务」. Selecting a project row changes the current project. Administrative actions live under「更多」.

Local progress is recorded in `menu-progress`. A previous `pack-state=presented` alone is insufficient to infer that a user sent anything. A new archived or unarchived reply updates `menu-receipt`. Switching projects keeps both state files intact.

Manual menu bar drops and refreshes work with auto-exchange off. Background inbox sweeps require the global and project `auto` flags. With both flags on, sweeps also collect a settled ZIP in Downloads at the expected filename after the user confirms they sent that round. The download remains in Downloads.

## Writes

Manifests and state files are written to a temp file in the same directory, then renamed. A `.lock` directory serializes writers.
