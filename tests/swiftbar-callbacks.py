"""Replay the literal SwiftBar actions with isolated local handoff data."""
import base64
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import zipfile


def verify(cli, fixture):
    home = fixture / "交接 目录"
    downloads = fixture / "下载 目录"
    downloads.mkdir()
    env = dict(
        os.environ,
        CHATBAR_HOME=str(home),
        CHATBAR_DOWNLOADS=str(downloads),
        CHATBAR_NO_OPEN="1",
        CHATBAR_NO_NOTIFY="1",
        CHATBAR_NO_CLIPBOARD="1",
        CHATBAR_SWEEP_SETTLE="0",
    )

    def run(*args):
        result = subprocess.run(args, env=env, text=True, capture_output=True)
        if result.returncode or "tr: illegal option" in result.stderr:
            raise AssertionError(f"{args!r}: {result.returncode} {result.stderr}")
        return result.stdout

    def menu():
        return run(cli, "swiftbar-menu").splitlines()

    def invoke(criteria):
        for line in menu()[2:]:
            if " | bash=" not in line:
                continue
            tail = line.split(" | ", 1)[1]
            params = dict(arg.split("=", 1) for arg in shlex.split(tail))
            if not all(params.get(key) == value for key, value in criteria.items()):
                continue
            assert params["terminal"] == "false", params
            arguments = [params[f"param{i}"] for i in range(1, 6) if f"param{i}" in params]
            assert any(arg.startswith("b64:") for arg in arguments), arguments
            return run(params["bash"], *arguments)
        raise AssertionError(f"menu action missing: {criteria!r}")

    def current():
        return json.loads(run(cli, "next", "--json"))

    def primary(expected_step, title, action):
        lines = menu()
        assert lines[0].split(" | ", 1)[0] == title, lines[0][:100]
        assert lines[2].split(" | ", 1)[0] == action, lines[2]
        data = current()
        assert (data["step"], data["title_short"], data["action_label"]) == (expected_step, title, action), data
        print(f"{expected_step} | {title} | {action}", flush=True)

    names = ("agents-bar", "project with spaces", "项目 甲")
    paths = {}
    for index, name in enumerate(names):
        encoded = run(
            "/bin/bash", "-c",
            'source "$1"; encoded="$(cb_b64enc "$2")"; printf "%s\\n" "$encoded"; cb_b64dec "$encoded"',
            "_", cli, name,
        ).splitlines()
        assert encoded == [base64.urlsafe_b64encode(name.encode()).decode().rstrip("="), name], encoded
        repo = fixture / f"repo-{index}"
        paths[name] = fixture / f"handoff-{index}"
        run("git", "init", "-q", repo)
        run("git", "-C", repo, "-c", "user.name=ChatBar Test", "-c",
            "user.email=tests@example.com", "commit", "--allow-empty", "-qm", "fixture")
        run(cli, "project", "add", "--name", name, "--repo", repo, "--handoff", paths[name])
        print(f"round-trip: {name}", flush=True)

    for name in names:
        project_arg = "b64:" + base64.urlsafe_b64encode(name.encode()).decode().rstrip("=")
        invoke({"param1": "project", "param2": "use", "param3": project_arg})
        assert current()["project"] == name
        print(f"callback project use: {name}", flush=True)

    name = names[-1]
    target = "b64:" + base64.urlsafe_b64encode(name.encode()).decode().rstrip("=")
    expected_open = "reveal:" + str(paths[name].resolve())
    assert invoke({"param1": "open-handoff", "param2": target}).strip() == expected_open
    print(f"callback open-handoff: {name}", flush=True)
    invoke({"param1": "auto", "param2": "on", "param3": target})
    assert run(cli, "auto", "status", "--project", name).strip() == "on"
    print(f"callback project auto on: {name}", flush=True)
    run(cli, "auto", "on")
    run(cli, "pack", "--quiet")

    for step, title, action in [
        ("copy", "复制", "复制给 g 的话"),
        ("paste", "粘贴", "我已粘贴"),
        ("drag", "拖文件", "拖文件 · to_chatgpt_R001.md"),
        ("send", "拖文件", "我已拖入并发送"),
    ]:
        primary(step, title, action)
        output = invoke({"param1": "step", "param2": "advance", "param3": target, "param5": step})
        if step == "drag":
            assert output.strip() == "reveal:" + current()["file"], output
    primary("wait", "等 g", "打开下载文件夹")
    with zipfile.ZipFile(current()["file"], "w") as reply:
        reply.writestr("reply.md", "reply fixture")
    run(cli, "sweep", "--auto")
    primary("received", "新任务", "收好了")
    invoke({"param1": "step", "param2": "advance", "param3": target, "param5": "received"})
    primary("received", "收好了", "收好了")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="chatbar-w005.") as tmp:
        verify(Path(sys.argv[1]).resolve(), Path(tmp))
