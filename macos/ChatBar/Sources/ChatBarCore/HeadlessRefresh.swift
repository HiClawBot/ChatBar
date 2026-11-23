import Foundation

/// Runs the same status and next commands the menu bar uses, then prints the result.
public enum HeadlessRefresh {
    public static func dumpState() -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let home = CLIBridge.resolvedHome(defaults: nil, environment: environment)
        guard let executable = CLILocator.executable(environment: environment) else {
            fputs("dump-state: bundled chatbar CLI not found\n", stderr)
            return 1
        }
        let bridge = CLIBridge(
            executable: executable,
            home: home,
            runner: ProcessCommandRunner(timeout: 5)
        )
        let status: CLIResult
        let next: CLIResult
        do {
            status = try bridge.run(.status)
            next = try bridge.run(.next)
        } catch {
            fputs("dump-state: \(error.localizedDescription)\n", stderr)
            return 1
        }
        guard status.ok, let document = try? JSONDocuments.status(Data(status.stdout.utf8)) else {
            fputs("dump-state: status \(status.code) \(status.stderr)\n", stderr)
            return 1
        }
        guard next.ok, let step = try? JSONDocuments.next(Data(next.stdout.utf8)) else {
            fputs("dump-state: next \(next.code) \(next.stderr)\n", stderr)
            return 1
        }
        let project = document.projects.first { $0.current } ?? document.projects.first
        let name = project?.name ?? ""
        let line = step.verbatimLine
        print("project: \(name)")
        print("next: \(line)")
        if name.isEmpty || line.isEmpty {
            fputs("dump-state: empty project or next line\n", stderr)
            return 1
        }
        return 0
    }
}
