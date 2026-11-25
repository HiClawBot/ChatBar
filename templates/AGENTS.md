# ChatBar agent rules

You are a local coding agent (Codex, Grok, or similar). The planner chat (ChatGPT by default) never commits to this repo. It only returns a downloadable reply. You apply code, run tests, and open the pull request. `main` stays protected.

## Every turn

1. Read `folders.json` in the handoff directory (default `.chatbar/`) and open the inbox role folder.
2. If `NEW.json` is there and `"status"` is `"new"`, that is the current reply. If the inbox is empty, read `latest-round.txt` and the archived `NEW.json`.
3. When `"type"` is `"code_patch"`, do not edit `main` by hand from the chat. Run:
   ```bash
   chatbar apply
   ```
   That creates `chatbar/R<NNN>` from the base commit, runs `git apply --3way`, and runs `test_command` when the project has one. Conflicts stop the command. It does not use `--force`, and it does not move `main`.
4. If apply succeeds, run the project tests again if you need to, then open a pull request from `chatbar/R<NNN>`. Do not merge it into `main` yourself unless the user asked.
5. If there is no patch, follow the reply and edit the repo yourself on a branch, still not on `main`.
6. When the round is finished, run `chatbar done` if the reply is still open, then `chatbar pack`.

## Opener

`chatbar pack` writes a fresh opener for this round. To override it, put the text in the outbox role folder as `opener.md` before packing. Templates live in `templates/opener-round1.md` and `templates/opener-next.md`.

## When unsure

Write the question into `status.md` under `## Questions` or into `questions.md`. Do not trial-and-error against the planner chat. The next pack will include the question.

## Never

Do not automate the planner chat. Do not drive a browser, read cookies, or call the user's chat account. Sending a pack is the user's drag.
