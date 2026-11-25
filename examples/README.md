# 例子 / Examples

`templates/projects.yaml.example` 是项目清单的样子。

一次代码贡献的回复可以长这样：统一 diff 放在 markdown 里，ChatBar 会把它抽到收回夹的 `patches/`，并在 `NEW.json` 里标 `type: code_patch`。然后由本地助手运行 `chatbar apply`，在 `chatbar/R00N` 上开 PR，不碰 `main`。

A planner reply can carry a unified diff. ChatBar files it under `patches/` and a local agent applies it on `chatbar/R00N`.
