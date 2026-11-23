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
        XCTAssertEqual(bridge.environmentOverlay()["CHATBAR_HOME"], "/交接 目录")
        XCTAssertEqual(bridge.environmentOverlay()["CHATBAR_NO_NOTIFY"], "1")
        XCTAssertNil(bridge.environmentOverlay()["CHATBAR_NO_CLIPBOARD"])
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
        let waiting = try sample(pack: "presented", inbox: "none", presented: "", packAt: "")
        let step = NextStepFallback.make(project: waiting) { path in
            path.hasSuffix("to_chatgpt_R002.md")
        }
        XCTAssertEqual(step.action, "wait")
        XCTAssertTrue(step.file.hasSuffix("to_chatgpt_R002.md"))
        XCTAssertTrue(step.lineZh.contains("ChatGPT"))
        let reply = try sample(pack: "ready", inbox: "new", presented: "", packAt: "")
        XCTAssertEqual(NextStepFallback.make(project: reply, fileExists: { _ in false }).action, "review")
        XCTAssertEqual(NextStepFallback.make(project: nil).action, "add")
        XCTAssertEqual(IconStyleResolver.style(projects: [], dropHighlighted: false), .idle)
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
