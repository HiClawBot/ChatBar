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
  "machine": "<hostname>",
  "patches": [],
  "files": []
}
```

`type` is `code_patch` when the reply contains a unified diff (```` ```diff ````, a `.patch` / `.diff` file) or full files with a path header (`File: path`). Those are copied under the inbox role folder at `patches/` (`*.patch` and `patches/files/...`). Each patch object includes `"type": "code_patch"`.

## Archive

Outbox and inbox keep only the current round. A finished round moves to:

`archive/YYYY-MM/R001_YYYY-MM-DD_HHMM_topic/`

The log role folder holds `轮次总表.md`, `events.jsonl` (`spec_version`, timestamp, project, round, direction, machine, files, bytes, approx_tokens), and `claims.jsonl` (`spec_version`, timestamp, project, round, machine, action). `machine` is this computer's hostname. v0 stays on one machine; the field is there for a later local network.

## Apply

`chatbar apply` checks out `chatbar/R<NNN>` from `base_commit` and runs `git apply --3way`. It does not use `--force` and does not move `main`. Optional `test_command` in `projects.yaml` runs afterward. A clean apply is committed on that branch so an agent can open a PR.

## Writes

Manifests and state files are written to a temp file in the same directory, then renamed. A `.lock` directory serializes writers.
