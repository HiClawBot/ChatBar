import XCTest
@testable import ChatBarCore

final class CoreTests: XCTestCase {
    func testPathKeepsSpacesAndChinese() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chatbar-解码 目录-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("我的 文件.md")
        try Data("hi".utf8).write(to: file)
        let encoded = "file://" + percent(file.path)
        XCTAssertEqual(PathDecode.decodeDroppedItem(encoded), file.path)
        let doubled = percent(encoded)
        XCTAssertEqual(PathDecode.decodeDroppedItem(doubled), file.path)
        let plus = dir.appendingPathComponent("a+b.txt")
        try Data("p".utf8).write(to: plus)
        XCTAssertEqual(PathDecode.decodeDroppedItem("file://" + percent(plus.path)), plus.path)
        let literal = dir.appendingPathComponent("a%20b.txt")
        try Data("x".utf8).write(to: literal)
        XCTAssertEqual(PathDecode.decodeDroppedItem(literal.path), literal.path)
        try FileManager.default.removeItem(at: dir)
    }

    func testIngestKeepsADroppedFolderOfFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("注 释.md")
        try Data("a".utf8).write(to: file)
        let paths = PathDecode.filesForIngest(
            [dir.path],
            isDirectory: { $0 == dir.path },
            children: { _ in ["注 释.md"] },
            exists: { $0 == dir.path || $0 == file.path }
        )
        XCTAssertEqual(paths, [file.path])
        try FileManager.default.removeItem(at: dir)
    }

    func testPhaseAndElapsed() throws {
        let project = try sample(pack: "ready", inbox: "none", presented: "", packAt: "2026-11-23T15:00:00Z")
        XCTAssertEqual(CardPhaseResolver.resolve(project: project), .copy(round: 2))
        let waiting = try sample(pack: "presented", inbox: "none", presented: "2026-11-23T15:00:00Z", packAt: "")
        let now = StatusClock.date(from: "2026-11-23T15:04:30Z")!
        if case .waiting(_, let elapsed) = CardPhaseResolver.resolve(project: waiting, now: now) {
            XCTAssertEqual(Int(elapsed), 270)
        } else {
            XCTFail("expected waiting")
        }
        XCTAssertEqual(ElapsedText.phrase(seconds: 10, chinese: true), "刚刚")
        XCTAssertEqual(ElapsedText.phrase(seconds: 120, chinese: true), "2 分钟")
        XCTAssertEqual(ElapsedText.phrase(seconds: 7200, chinese: false), "2 h")
        let reply = try sample(pack: "ready", inbox: "new", presented: "", packAt: "")
        XCTAssertEqual(CardPhaseResolver.resolve(project: reply), .reply(round: 2))
        XCTAssertEqual(OpenerPreview.line(from: "第一行\n第二行"), "第一行")
    }

    func testAutoExchangeDecodesOffAndPendingAmbiguity() throws {
        let status = """
        {"home":"/tmp/交接 目录","auto_exchange":false,"projects":[{
          "name":"项目 甲","repo":"/r","handoff":"/h","workspace":"/w","current":true,
          "chat_name":"ChatGPT","round":1,"pack_state":"none","inbox_state":"none",
          "pack_file":"","inbox_dir":"/in","outbox_dir":"/out","presented_at":"",
          "pack_at":"","rounds_file":"/log","menu_state":"idle","error":"",
          "project_auto":false,"slug":"项目-甲"
        }]}
        """
        let doc = try JSONDocuments.status(Data(status.utf8))
        XCTAssertFalse(doc.autoExchange)
        XCTAssertEqual(doc.projects[0].name, "项目 甲")
        XCTAssertFalse(doc.projects[0].projectAuto)
        XCTAssertEqual(doc.projects[0].slug, "项目-甲")
        let pending = """
        {"items":[{"path":"/下载/foo_round1_reply.md","name":"foo_round1_reply.md","reason":"ambiguous","project":"","detail":"Foo,foo"}]}
        """
        let items = try JSONDocuments.pending(Data(pending.utf8))
        XCTAssertEqual(items.items[0].reason, "ambiguous")
        XCTAssertEqual(items.items[0].name, "foo_round1_reply.md")
    }

    func testBridgePassesPathsAsSeparateArguments() throws {
        var patch = ConfigPatch()
        patch.autoExchange = false
        XCTAssertEqual(
            CLIArguments.make(.configSet(patch)),
            ["config", "set", "--auto-exchange", "off"]
        )
        XCTAssertEqual(
            CLIArguments.make(.projectAuto(name: "项目 甲", enabled: true)),
            ["project", "auto", "项目 甲", "on"]
        )
        XCTAssertEqual(
            CLIArguments.make(.downloadsAssign(file: "/下载/我的 文件.md", project: "项目 甲")),
            ["downloads-assign", "--file", "/下载/我的 文件.md", "--project", "项目 甲"]
        )
        let bridge = CLIBridge(executable: "/opt/chatbar", home: "/交接 目录", runner: FakeRunner())
        let overlay = bridge.environmentOverlay()
        XCTAssertEqual(overlay["CHATBAR_HOME"], "/交接 目录")
        XCTAssertEqual(overlay["CHATBAR_NO_NOTIFY"], "1")
        XCTAssertEqual(overlay["CHATBAR_NO_REWRITE"], "1")
        XCTAssertTrue(overlay["PATH"]?.contains("/opt/homebrew/bin") == true)
        XCTAssertTrue(overlay["PATH"]?.contains("/usr/bin") == true)
        XCTAssertNotNil(overlay["HOME"])
        XCTAssertNil(overlay["CHATBAR_NO_CLIPBOARD"])
        XCTAssertEqual(
            CLIBridge.resolvedHome(defaults: nil, environment: ["CHATBAR_HOME": "/tmp/handoff-link"]),
            "/tmp/handoff-link"
        )
        XCTAssertTrue(CLIBridge.resolvedHome(defaults: "  ", environment: [:]).hasSuffix("/handoff"))
        XCTAssertEqual(HotKeySpec.default.display, "⌥⌘C")
        XCTAssertEqual(StatusClickPreference.resolve(nil), .bar)
        XCTAssertTrue(StatusClickPreference.resolve("bar").leftOpensBar)
        XCTAssertFalse(StatusClickPreference.resolve("card").leftOpensBar)
        XCTAssertEqual(RelayStep.label(direction: "to_planner", chinese: true), "聊天")
        XCTAssertEqual(RelayStep.label(direction: "from_planner", chinese: false), "billiards")
        XCTAssertEqual(RelayStep.label(direction: "archive", chinese: true), "飞镖")
        XCTAssertEqual(LaunchRequest.view(from: ["ChatBar", "--show", "bar"]), .bar)
        XCTAssertEqual(LaunchRequest.view(from: ["ChatBar", "--show", "settings"]), .settings)
        XCTAssertNil(LaunchRequest.view(from: ["ChatBar"]))
        let card = URL(string: "chatbar-app://open?view=card")!
        XCTAssertEqual(LaunchRequest.view(from: card), .card)
        XCTAssertNil(LaunchRequest.view(from: URL(string: "https://example.com/?view=bar")!))
        XCTAssertEqual(IconStyleResolver.style(projects: [], dropHighlighted: false), .idle)
    }

    func testSixFieldNextStepAndCallbacks() throws {
        let cases: [(String, NextStep.Kind, Bool, Bool)] = [
            ("no_project", .noProject, false, false),
            ("need_pack", .needPack, false, false),
            ("copy", .copy, true, false),
            ("paste", .paste, true, true),
            ("drag", .drag, true, true),
            ("send", .send, true, true),
            ("wait", .wait, true, true),
            ("received", .received, true, false),
            ("result", .result, true, false)
        ]
        for (raw, expected, advances, backs) in cases {
            let json = """
            {"step":"\(raw)","title_short":"拖文件","action_label":"我已拖入并发送",
             "project":"项目 甲","round":2,"file":"/临时 目录/to_chatgpt_R002.md"}
            """
            let step = try JSONDocuments.next(Data(json.utf8))
            XCTAssertEqual(step.step, expected)
            XCTAssertEqual(step.titleShort, "拖文件")
            XCTAssertEqual(step.actionLabel, "我已拖入并发送")
            XCTAssertEqual(step.project, "项目 甲")
            XCTAssertEqual(step.round, 2)
            XCTAssertEqual(step.file, "/临时 目录/to_chatgpt_R002.md")
            XCTAssertEqual(step.canAdvance, advances)
            XCTAssertEqual(step.canGoBack, backs)
            if advances {
                let project = "b64:" + Data(step.project.utf8).base64EncodedString()
                    .replacingOccurrences(of: "=", with: "")
                XCTAssertEqual(CLIArguments.make(.step(.advance, step)), ["step", "advance", project, "2", raw])
                if backs {
                    XCTAssertEqual(CLIArguments.make(.step(.back, step)), ["step", "back", project, "2", raw])
                }
            }
        }
        XCTAssertEqual(CLIArguments.make(.next(project: nil)), ["next", "--json"])
        XCTAssertEqual(CLIArguments.make(.next(project: "agents-bar")), ["next", "--json", "--project", "b64:YWdlbnRzLWJhcg"])
        XCTAssertThrowsError(try JSONDocuments.next(Data(#"{"state":"ready","text":"legacy"}"#.utf8)))
    }

    func testCLIProcessDoesNotDeadlockOnPipesOrStdin() throws {
        let runner = ProcessCommandRunner(timeout: 5)
        let echo = try runner.run(executable: "/bin/bash", arguments: ["-c", "printf 'out'; printf 'err' >&2"], environment: [:], standardInput: nil)
        XCTAssertEqual(echo.code, 0)
        XCTAssertEqual(echo.stdout, "out")
        XCTAssertEqual(echo.stderr, "err")

        let stdin = try runner.run(
            executable: "/bin/bash",
            arguments: ["-c", "read line; printf 'done:%s' \"$line\""],
            environment: ["CHATBAR_HOME": "~/handoff"],
            standardInput: nil
        )
        XCTAssertEqual(stdin.code, 0)
        XCTAssertEqual(stdin.stdout, "done:")
        let merged = ProcessCommandRunner.mergedEnvironment(overlay: ["CHATBAR_HOME": "~/handoff"])
        XCTAssertFalse(merged["CHATBAR_HOME"]?.hasPrefix("~") == true)
        XCTAssertTrue(merged["PATH"]?.contains("/opt/homebrew/bin") == true)
        XCTAssertEqual(merged["CHATBAR_NO_REWRITE"], "1")

        let fed = try runner.run(
            executable: "/bin/bash",
            arguments: ["-c", "read line; printf '%s' \"$line\""],
            environment: [:],
            standardInput: "你好\n"
        )
        XCTAssertEqual(fed.stdout, "你好")

        let big = try runner.run(
            executable: "/bin/bash",
            arguments: ["-c", "dd if=/dev/zero bs=1024 count=256 2>/dev/null | base64"],
            environment: [:],
            standardInput: nil
        )
        XCTAssertEqual(big.code, 0)
        XCTAssertGreaterThan(big.stdout.count, 60_000)

        let started = Date()
        let hung = try ProcessCommandRunner(timeout: 0.4).run(
            executable: "/bin/sleep",
            arguments: ["30"],
            environment: [:],
            standardInput: nil
        )
        XCTAssertEqual(hung.code, 124)
        XCTAssertTrue(hung.stderr.contains("timed out"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    private func percent(_ value: String) -> String {
        value.utf8.map { String(format: "%%%02X", $0) }.joined()
    }

    private func sample(pack: String, inbox: String, presented: String, packAt: String) throws -> ProjectStatus {
        let json = """
        {"name":"P","repo":"/r","handoff":"/h","workspace":"/w","current":true,"chat_name":"ChatGPT",
         "round":2,"pack_state":"\(pack)","inbox_state":"\(inbox)","pack_file":"","inbox_dir":"/i",
         "outbox_dir":"/o","presented_at":"\(presented)","pack_at":"\(packAt)","rounds_file":"/l",
         "menu_state":"idle","error":"","project_auto":false,"slug":"p"}
        """
        return try JSONDecoder().decode(ProjectStatus.self, from: Data(json.utf8))
    }
}

private final class FakeRunner: CommandRunning {
    func run(executable: String, arguments: [String], environment: [String: String], standardInput: String?) throws -> CLIResult {
        CLIResult(code: 0, stdout: "", stderr: "")
    }
}
