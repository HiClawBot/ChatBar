import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Runs the bundled CLI without inheriting the GUI's stdin or waiting on a full pipe.
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

        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        let inputPipe: Pipe?
        if standardInput != nil {
            let pipe = Pipe()
            inputPipe = pipe
            process.standardInput = pipe
        } else if let nullInput = FileHandle(forReadingAtPath: "/dev/null") {
            inputPipe = nil
            process.standardInput = nullInput
        } else {
            inputPipe = nil
            process.standardInput = FileHandle.nullDevice
        }

        // Drain both pipes on their own queues before the child can fill a 64KB buffer.
        let outQueue = DispatchQueue(label: "chatbar.cli.stdout")
        let errQueue = DispatchQueue(label: "chatbar.cli.stderr")
        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        outQueue.async {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            outData = data
            lock.unlock()
            group.leave()
        }
        group.enter()
        errQueue.async {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            errData = data
            lock.unlock()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            try? output.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            try? inputPipe?.fileHandleForWriting.close()
            _ = group.wait(timeout: .now() + 1)
            let message = "failed to start \(executable) \(arguments.joined(separator: " ")): \(error.localizedDescription)"
            Self.log(message)
            throw error
        }

        if let inputPipe {
            if let standardInput, !standardInput.isEmpty {
                inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
            }
            try? inputPipe.fileHandleForWriting.close()
        }

        var timedOut = false
        if group.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            Self.stop(process)
            _ = group.wait(timeout: .now() + 1)
        }
        if process.isRunning {
            Self.stop(process)
        }
        process.waitUntilExit()

        lock.lock()
        let stdout = String(decoding: outData, as: UTF8.self)
        var stderr = String(decoding: errData, as: UTF8.self)
        lock.unlock()

        var code = process.terminationStatus
        if timedOut {
            code = 124
            let note = "chatbar timed out after \(Int(timeout.rounded()))s: \(executable) \(arguments.joined(separator: " "))"
            stderr = stderr.isEmpty ? note : stderr + "\n" + note
            Self.log(note)
        } else if code != 0 {
            Self.log("chatbar exit \(code): \(executable) \(arguments.joined(separator: " "))\n\(stderr)")
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
