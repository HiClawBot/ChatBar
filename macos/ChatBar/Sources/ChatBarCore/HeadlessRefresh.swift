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
        do {
            let status = try bridge.run(.status)
            guard status.ok else {
                fputs("dump-state: status \(status.code) \(status.stderr)\n", stderr)
                return 1
            }
            let document = try JSONDocuments.status(Data(status.stdout.utf8))
            let project = document.projects.first { $0.current } ?? document.projects.first
            let step = try bridge.nextStep(project: project?.name)
            print("project: \(step.project)")
            print("round: \(step.round)")
            print("step: \(step.step.rawValue)")
            print("title_short: \(step.titleShort)")
            print("action_label: \(step.actionLabel)")
            print("file: \(step.file)")
            return 0
        } catch {
            fputs("dump-state: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
