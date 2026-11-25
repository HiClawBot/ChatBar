import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Runs the bundled CLI with private file-backed I/O and a deadline for the child process.
public final class ProcessCommandRunner: CommandRunning {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        standardInput: String?
    ) throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = Self.mergedEnvironment(overlay: environment)

        let files = FileManager.default
        let capture = files.temporaryDirectory.appendingPathComponent("chatbar-cli-\(UUID().uuidString)")
        try files.createDirectory(at: capture, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: capture) }

        let stdoutURL = capture.appendingPathComponent("stdout")
        let stderrURL = capture.appendingPathComponent("stderr")
        try Data().write(to: stdoutURL)
        try Data().write(to: stderrURL)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        defer { try? stdoutHandle.close() }
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer { try? stderrHandle.close() }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let stdinURL = capture.appendingPathComponent("stdin")
        let input: FileHandle
        if let standardInput {
            try Data(standardInput.utf8).write(to: stdinURL)
            input = try FileHandle(forReadingFrom: stdinURL)
        } else {
            input = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/null"))
        }
        defer { try? input.close() }
        process.standardInput = input

        // A descendant may keep an inherited output descriptor open after the CLI
        // exits. The CLI's termination, independent of output EOF, owns the deadline.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        let command = ([executable] + arguments).joined(separator: " ")
        do {
            try process.run()
        } catch {
            Self.log("failed to start \(command): \(error.localizedDescription)")
            throw error
        }
        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut && process.isRunning
        if timedOut { Self.stop(process) }
        process.waitUntilExit()

        let stdout = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
        var stderr = String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
        let code: Int32 = timedOut ? 124 : process.terminationStatus
        if timedOut {
            let note = "chatbar timed out after \(String(format: "%g", timeout))s"
            stderr = stderr.isEmpty ? note : stderr + "\n" + note
            Self.log("\(note): \(command)")
        } else if code != 0 {
            Self.log("chatbar exit \(code): \(command)\n\(stderr)")
        }

        return CLIResult(code: code, stdout: stdout, stderr: stderr)
    }

    /// GUI apps do not inherit a shell PATH. Homebrew, HOME, and CHATBAR_HOME are explicit.
    public static func mergedEnvironment(overlay: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let homeDir = overlay["HOME"] ?? env["HOME"] ?? NSHomeDirectory()
        env["HOME"] = homeDir.isEmpty ? NSHomeDirectory() : homeDir
        for (key, value) in overlay {
            env[key] = value
        }
        let prefix = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let current = env["PATH"] ?? ""
        if !current.hasPrefix("/opt/homebrew/bin:") {
            env["PATH"] = current.isEmpty ? prefix : prefix + ":" + current
        }
        if (env["CHATBAR_HOME"] ?? "").isEmpty {
            env["CHATBAR_HOME"] = (env["HOME"]! as NSString).appendingPathComponent("handoff")
        } else if let raw = env["CHATBAR_HOME"] {
            env["CHATBAR_HOME"] = (raw as NSString).expandingTildeInPath
        }
        if (env["CHATBAR_NO_NOTIFY"] ?? "").isEmpty {
            env["CHATBAR_NO_NOTIFY"] = "1"
        }
        if (env["CHATBAR_NO_REWRITE"] ?? "").isEmpty {
            env["CHATBAR_NO_REWRITE"] = "1"
        }
        env["GIT_TERMINAL_PROMPT"] = "0"
        return env
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.4)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func log(_ message: String) {
        fputs("ChatBar: \(message)\n", stderr)
    }
}
