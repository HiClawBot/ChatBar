import Foundation

public struct CLIResult: Equatable {
    public var code: Int32
    public var stdout: String
    public var stderr: String

    public var ok: Bool { code == 0 }

    public init(code: Int32, stdout: String, stderr: String) {
        self.code = code
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        standardInput: String?
    ) throws -> CLIResult
}

public struct ConfigPatch: Equatable {
    public var chatName: String?
    public var outboxName: String?
    public var inboxName: String?
    public var archiveName: String?
    public var logName: String?
    public var downloadsWatch: Bool?
    public var autoExchange: Bool?
    public var autoCopy: Bool?
    public var tipMinutes: String?
    public var tipCost: String?
    public var downloadDirs: [String]?
    public var downloadGlobs: [String]?

    public init() {}
}

public enum CLICommand: Equatable {
    case status
    case openerShow(String)
    case openerSave(String)
    case openerReset(String)
    case bundle(String)
    case markPresented(String)
    case rounds(String)
    case downloadsScan(force: Bool)
    case downloadsPending
    case downloadsAssign(file: String, project: String)
    case projectAuto(name: String, enabled: Bool)
    case configGet
    case configSet(ConfigPatch)
    case ingest(project: String, paths: [String])
    case reveal(String)
    case openHandoff(String)
    case openRoot(String)
    case archive(String)
    case pack(String)
    case apply(String)
    case projectAdd(name: String, repo: String, handoff: String, chat: String, templates: Bool)
    case projectUse(String)
    case tip
    case sceneLog
    case next
}

public enum CLIArguments {
    public static func make(_ command: CLICommand) -> [String] {
        switch command {
        case .status:
            return ["status", "--json"]
        case .openerShow(let name):
            return ["opener", "show", name]
        case .openerSave(let name):
            return ["opener", "save", name]
        case .openerReset(let name):
            return ["opener", "reset", name]
        case .bundle(let name):
            return ["bundle", "--json", name]
        case .markPresented(let name):
            return ["mark-presented", name]
        case .rounds(let name):
            return ["rounds", name]
        case .downloadsScan(let force):
            return force ? ["downloads-scan", "--force"] : ["downloads-scan"]
        case .downloadsPending:
            return ["downloads-pending"]
        case .downloadsAssign(let file, let project):
            return ["downloads-assign", "--file", file, "--project", project]
        case .projectAuto(let name, let enabled):
            return ["project", "auto", name, enabled ? "on" : "off"]
        case .configGet:
            return ["config", "get", "--json"]
        case .configSet(let patch):
            return configSet(patch)
        case .ingest(let project, let paths):
            return ["ingest", "--project", project, "--source", "menu-bar-drop", "--"] + paths
        case .reveal(let name):
            return ["reveal", name]
        case .openHandoff(let name):
            return ["open-handoff", name]
        case .openRoot(let name):
            return ["open-root", name]
        case .archive(let name):
            return ["archive", name]
        case .pack(let name):
            return ["pack", "--project", name]
        case .apply(let name):
            return ["apply", "--project", name]
        case .projectAdd(let name, let repo, let handoff, let chat, let templates):
            var args = ["project", "add", "--name", name, "--repo", repo]
            if !handoff.isEmpty { args += ["--handoff", handoff] }
            if !chat.isEmpty { args += ["--chat-name", chat] }
            if templates { args.append("--with-templates") }
            return args
        case .projectUse(let name):
            return ["project", "use", name]
        case .tip:
            return ["tip"]
        case .sceneLog:
            return ["log"]
        case .next:
            return ["next", "--json"]
        }
    }

    private static func configSet(_ patch: ConfigPatch) -> [String] {
        var args = ["config", "set"]
        if let chatName = patch.chatName { args += ["--chat-name", chatName] }
        if let outboxName = patch.outboxName { args += ["--outbox-name", outboxName] }
        if let inboxName = patch.inboxName { args += ["--inbox-name", inboxName] }
        if let archiveName = patch.archiveName { args += ["--archive-name", archiveName] }
        if let logName = patch.logName { args += ["--log-name", logName] }
        if let autoExchange = patch.autoExchange {
            args += ["--auto-exchange", autoExchange ? "on" : "off"]
        }
        if let downloadsWatch = patch.downloadsWatch {
            args += ["--downloads-watch", downloadsWatch ? "on" : "off"]
        }
        if let autoCopy = patch.autoCopy {
            args += ["--auto-copy", autoCopy ? "on" : "off"]
        }
        if let tipMinutes = patch.tipMinutes {
            args += ["--tip-minutes", tipMinutes]
        }
        if let tipCost = patch.tipCost {
            args += ["--tip-cost", tipCost]
        }
        if let downloadDirs = patch.downloadDirs {
            if downloadDirs.isEmpty {
                args.append("--clear-download-dirs")
            } else {
                for dir in downloadDirs { args += ["--download-dir", dir] }
            }
        }
        if let downloadGlobs = patch.downloadGlobs {
            if downloadGlobs.isEmpty {
                args.append("--clear-download-globs")
            } else {
                for glob in downloadGlobs { args += ["--download-glob", glob] }
            }
        }
        return args
    }
}

public struct CLIBridge {
    public var executable: String
    public var home: String
    public var runner: CommandRunning

    public init(executable: String, home: String, runner: CommandRunning) {
        self.executable = executable
        self.home = home
        self.runner = runner
    }

    /// Saved preference, then CHATBAR_HOME, then ~/handoff. A symlink is kept as given.
    public static func resolvedHome(
        defaults: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let chosen: String
        let stored = defaults?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty {
            chosen = stored
        } else if let fromEnv = environment["CHATBAR_HOME"], !fromEnv.isEmpty {
            chosen = fromEnv
        } else {
            chosen = (NSHomeDirectory() as NSString).appendingPathComponent("handoff")
        }
        return (chosen as NSString).expandingTildeInPath
    }

    /// Overlay passed to the CLI. Clipboard and Finder stay available.
    /// GUI apps do not get a login shell, so PATH and HOME are explicit.
    public func environmentOverlay() -> [String: String] {
        let process = ProcessInfo.processInfo.environment
        let homeDir = process["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let inherited = process["PATH"] ?? ""
        let prefix = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let path = inherited.isEmpty ? prefix : prefix + ":" + inherited
        return [
            "HOME": homeDir,
            "PATH": path,
            "CHATBAR_HOME": home,
            "CHATBAR_NO_NOTIFY": "1",
            "CHATBAR_NO_REWRITE": "1",
            "GIT_TERMINAL_PROMPT": "0"
        ]
    }

    public func run(_ command: CLICommand, standardInput: String? = nil) throws -> CLIResult {
        try runner.run(
            executable: executable,
            arguments: CLIArguments.make(command),
            environment: environmentOverlay(),
            standardInput: standardInput
        )
    }
}

public enum CLILocator {
    public static func executable(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let override = environment["CHATBAR_BIN"], FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let bundleResource = Bundle.main.resourceURL?.appendingPathComponent("cli/chatbar").path
        if let bundleResource, FileManager.default.isExecutableFile(atPath: bundleResource) {
            return bundleResource
        }
        var starts: [URL] = [Bundle.main.bundleURL]
        if let executableURL = Bundle.main.executableURL {
            starts.append(executableURL.deletingLastPathComponent())
        }
        starts.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        for start in starts {
            var url = start
            for _ in 0..<8 {
                let candidate = url.appendingPathComponent("cli/chatbar").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
                let parent = url.deletingLastPathComponent()
                if parent.path == url.path { break }
                url = parent
            }
        }
        return nil
    }
}
