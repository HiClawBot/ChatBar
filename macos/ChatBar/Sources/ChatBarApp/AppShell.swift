import AppKit
import ChatBarCore
import Combine
import CoreServices
import SwiftUI
import UserNotifications

// Local files, the pasteboard, and Finder only. This process never controls a chat app.

final class ProcessCommandRunner: CommandRunning {
    func run(executable: String, arguments: [String], environment: [String: String], standardInput: String?) throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        environment.forEach { env[$0.key] = $0.value }
        process.environment = env
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        if let standardInput {
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(standardInput.utf8))
            try? input.fileHandleForWriting.close()
        } else {
            try process.run()
        }
        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global().async {
            outData = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = error.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
        process.waitUntilExit()
        return CLIResult(
            code: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

final class CardModel: ObservableObject {
    @Published var projectName = ""
    @Published var round = 1
    @Published var phase: CardPhase = .empty
    @Published var openerText = ""
    @Published var openerExpanded = false
    @Published var autoExchange = false
    @Published var projectAuto = false
    @Published var projects: [ProjectStatus] = []
    @Published var pending: [PendingItem] = []
    @Published var rounds: [RoundSummary] = []
    @Published var errorLine = ""
    @Published var tipMinutesText = "0"
    @Published var tipCostText = "0"
    @Published var tipMinutesField = "3"
    @Published var tipCostField = "0"
    @Published var sceneEvents: [SceneEvent] = []
    @Published var settingsVisible = false
    @Published var nextLine = ""
    @Published var nextFile = ""
    @Published var nextOpener = ""

    var bridge: CLIBridge?
    var onIcon: (IconStyle) -> Void = { _ in }
    var presentSettings: () -> Void = {}
    var presentAdd: () -> Void = {}
    private var loadedOpener = ""
    private var saveItem: DispatchWorkItem?
    private var knownReplies = Set<String>()
    private var knownPending = Set<String>()
    private var primed = false
    private var lastPackStamp = ""

    var preview: String { OpenerPreview.line(from: openerText) }

    func refresh() {
        guard let bridge else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let statusResult = try? bridge.run(.status)
            let pendingResult = try? bridge.run(.downloadsPending)
            DispatchQueue.main.async {
                self.apply(status: statusResult, pending: pendingResult)
            }
        }
    }

    func openerChanged() {
        guard openerText != loadedOpener, !projectName.isEmpty else { return }
        saveItem?.cancel()
        let text = openerText
        let name = projectName
        let work = DispatchWorkItem { [weak self] in self?.saveOpener(name: name, text: text) }
        saveItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func resetOpener() {
        guard let bridge, !projectName.isEmpty else { return }
        let name = projectName
        DispatchQueue.global().async {
            _ = try? bridge.run(.openerReset(name))
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func copyBundle() {
        guard let bridge, !projectName.isEmpty else { return }
        let name = projectName
        let text = openerText
        saveOpener(name: name, text: text)
        DispatchQueue.global(qos: .userInitiated).async {
            let bundle = try? bridge.run(.bundle(name))
            var files: [String] = []
            if let bundle, let document = try? JSONDocuments.bundle(Data(bundle.stdout.utf8)) {
                files = document.files
            }
            DispatchQueue.main.async {
                PasteboardWriter.write(opener: text, files: files, mode: .bundle)
                _ = try? bridge.run(.markPresented(name))
                let chat = self.projects.first { $0.name == name }?.chatName ?? "ChatGPT"
                Notifier.post(
                    title: "ChatBar",
                    body: L10n.format("notify.ready", self.round, chat)
                )
                self.refresh()
            }
        }
    }

    func reveal() { run(.reveal(projectName)) }
    func openRoot() { run(.openHandoff(projectName)) }
    func pack() { run(.pack(projectName)) }
    func archiveRound() { run(.archive(projectName)) }
    func applyPatch() { run(.apply(projectName)) }
    func selectRoom(_ name: String) {
        projectName = name
        run(.projectUse(name))
    }
    func loadBar() {
        loadTip()
        loadScene()
    }
    func saveTipAssumptions(minutes: String, cost: String) {
        var patch = ConfigPatch()
        patch.tipMinutes = minutes
        patch.tipCost = cost
        run(.configSet(patch))
        loadTip()
    }
    func closeSettings() { settingsVisible = false }
    func addProject() { presentAdd() }

    func createProject(name: String, repo: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !repo.isEmpty else { return }
        run(.projectAdd(name: trimmed, repo: repo, handoff: "", chat: "", templates: true))
    }

    private func loadTip() {
        guard let bridge else { return }
        DispatchQueue.global().async {
            guard let result = try? bridge.run(.tip), result.ok,
                  let tip = try? JSONDocuments.tip(Data(result.stdout.utf8)) else { return }
            DispatchQueue.main.async {
                self.tipMinutesText = String(format: "%.0f", tip.minutesSaved)
                self.tipCostText = String(format: "%.2f", tip.costSaved)
                self.tipMinutesField = String(tip.minutesPerAction)
                self.tipCostField = String(tip.costPerRound)
            }
        }
    }

    private func loadScene() {
        guard let bridge else { return }
        DispatchQueue.global().async {
            guard let result = try? bridge.run(.sceneLog), result.ok,
                  let log = try? JSONDocuments.scene(Data(result.stdout.utf8)) else { return }
            DispatchQueue.main.async { self.sceneEvents = log.events }
        }
    }

    func copyFilesOnly() {
        guard let bridge, !projectName.isEmpty else { return }
        let name = projectName
        DispatchQueue.global().async {
            let bundle = try? bridge.run(.bundle(name))
            var files: [String] = []
            if let bundle, let document = try? JSONDocuments.bundle(Data(bundle.stdout.utf8)) {
                files = document.files
            }
            DispatchQueue.main.async { PasteboardWriter.write(opener: "", files: files, mode: .files) }
        }
    }

    func copyOpenerOnly() {
        PasteboardWriter.write(opener: openerText, files: [], mode: .opener)
    }
    func setMaster(_ on: Bool) {
        var patch = ConfigPatch()
        patch.autoExchange = on
        run(.configSet(patch))
    }
    func setProjectAuto(_ on: Bool) {
        guard !projectName.isEmpty else { return }
        run(.projectAuto(name: projectName, enabled: on))
    }
    func assign(path: String, project: String) {
        run(.downloadsAssign(file: path, project: project))
    }

    private func saveOpener(name: String, text: String) {
        guard let bridge, text != loadedOpener else { return }
        DispatchQueue.global().async {
            _ = try? bridge.run(.openerSave(name), standardInput: text)
            DispatchQueue.main.async { self.loadedOpener = text }
        }
    }

    private func run(_ command: CLICommand) {
        guard let bridge else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? bridge.run(command)
            DispatchQueue.main.async { self.refresh() }
        }
    }

    private func apply(status: CLIResult?, pending pendingResult: CLIResult?) {
        guard let status, status.ok, let doc = try? JSONDocuments.status(Data(status.stdout.utf8)) else { return }
        projects = doc.projects
        autoExchange = doc.autoExchange
        let current = doc.projects.first { $0.current } ?? doc.projects.first
        projectName = current?.name ?? ""
        round = current?.round ?? 1
        projectAuto = current?.projectAuto ?? false
        phase = CardPhaseResolver.resolve(project: current)
        errorLine = current?.error ?? ""
        if case .copy = phase, openerExpanded == false, loadedOpener.isEmpty {
            openerExpanded = true
        }
        onIcon(IconStyleResolver.style(projects: doc.projects, dropHighlighted: false))
        if let pendingResult, pendingResult.ok,
           let pendingDoc = try? JSONDocuments.pending(Data(pendingResult.stdout.utf8)) {
            pending = pendingDoc.items
            if primed {
                let fresh = Set(pendingDoc.items.map(\.path)).subtracting(knownPending)
                if !fresh.isEmpty {
                    Notifier.post(title: "ChatBar", body: L10n.text("notify.pending"))
                }
            }
            knownPending = Set(pendingDoc.items.map(\.path))
        }
        if let current {
            let stamp = current.packAt + current.presentedAt + current.inboxState
            if primed, current.inboxState == "new", !knownReplies.contains(current.name + ":\(current.round)") {
                knownReplies.insert(current.name + ":\(current.round)")
                Notifier.post(title: "ChatBar", body: L10n.format("notify.reply", current.name))
            }
            if stamp != lastPackStamp {
                lastPackStamp = stamp
                loadOpener(current.name)
                loadRounds(current.name)
            }
        }
        primed = true
        loadNext(project: current)
    }

    func performNext() {
        let opener = nextOpener.isEmpty ? openerText : nextOpener
        PasteboardWriter.write(opener: opener, files: [], mode: .opener)
        guard !nextFile.isEmpty, FileManager.default.fileExists(atPath: nextFile) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: nextFile)])
    }

    private func loadNext(project: ProjectStatus?) {
        guard let bridge else {
            applyNext(NextStepFallback.make(project: project))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = try? bridge.run(.next)
            if let result, result.ok, let step = try? JSONDocuments.next(Data(result.stdout.utf8)) {
                DispatchQueue.main.async { self.applyNext(step, outbox: project?.outboxDir ?? "") }
            } else {
                DispatchQueue.main.async { self.applyNext(NextStepFallback.make(project: project), outbox: project?.outboxDir ?? "") }
            }
        }
    }

    private func applyNext(_ step: NextStep, outbox: String) {
        nextLine = step.line(chinese: L10n.chinese)
        if step.file.hasPrefix("/") {
            nextFile = step.file
        } else if !step.file.isEmpty, !outbox.isEmpty {
            nextFile = (outbox as NSString).appendingPathComponent(step.file)
        } else {
            nextFile = ""
        }
        nextOpener = step.opener
    }

    private func loadOpener(_ name: String) {
        guard let bridge else { return }
        DispatchQueue.global().async {
            guard let result = try? bridge.run(.openerShow(name)), result.ok,
                  let doc = try? JSONDocuments.opener(Data(result.stdout.utf8)) else { return }
            DispatchQueue.main.async {
                if self.openerText == self.loadedOpener {
                    self.openerText = doc.text
                    self.loadedOpener = doc.text
                }
            }
        }
    }

    private func loadRounds(_ name: String) {
        guard let bridge else { return }
        DispatchQueue.global().async {
            guard let result = try? bridge.run(.rounds(name)), result.ok,
                  let doc = try? JSONDocuments.rounds(Data(result.stdout.utf8)) else { return }
            DispatchQueue.main.async { self.rounds = doc.rounds.reversed() }
        }
    }
}

struct CardView: View {
    @ObservedObject var model: CardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NextStepBanner(model: model)
            header
            if !model.pending.isEmpty { pendingList }
            opener
            primary
            folders
            if !model.rounds.isEmpty { timeline }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .animation(.easeInOut(duration: 0.18), value: model.phaseToken)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.projectName.isEmpty ? "ChatBar" : model.projectName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(model.projectName.isEmpty ? "" : "R\(model.round)")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            HStack {
                Button(L10n.format("auto.title", model.autoExchange ? L10n.text("auto.on") : L10n.text("auto.off"))) {
                    model.setMaster(!model.autoExchange)
                }
                .buttonStyle(.bordered)
                .tint(model.autoExchange ? Color.accentColor : Color.secondary)
                Spacer()
                if !model.projectName.isEmpty {
                    Button("\(L10n.text("auto.project"))：\(model.projectAuto ? L10n.text("auto.on") : L10n.text("auto.off"))") {
                        model.setProjectAuto(!model.projectAuto)
                    }
                    .buttonStyle(.bordered)
                }
                Menu {
                    Button("打包") { model.pack() }
                    Button("结束本轮") { model.archiveRound() }
                    Button("应用补丁") { model.applyPatch() }
                    Button("只复制文件") { model.copyFilesOnly() }
                    Button("只复制开场白") { model.copyOpenerOnly() }
                    Divider()
                    Menu(L10n.text("menu.more")) {
                        Button(L10n.text("menu.add")) { model.addProject() }
                        Button(L10n.text("menu.settings")) { model.presentSettings() }
                    }
                    Divider()
                    Text(L10n.text("menu.safety"))
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var pendingList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("pick.title")).font(.system(size: 12, weight: .semibold))
            ForEach(model.pending, id: \.path) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(1).font(.system(size: 12))
                        Text(reason(item.reason)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu(L10n.text("pick.choose")) {
                        ForEach(model.projects, id: \.name) { project in
                            Button(project.name) { model.assign(path: item.path, project: project.name) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    private var opener: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.text("opener.title")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(model.openerExpanded ? L10n.text("opener.hide") : L10n.text("opener.show")) {
                    model.openerExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
            }
            if model.openerExpanded {
                TextEditor(text: $model.openerText)
                    .font(.system(size: 13))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    .onChange(of: model.openerText) { _ in model.openerChanged() }
                Button(L10n.text("opener.reset"), action: model.resetOpener)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if !model.preview.isEmpty {
                Text(model.preview).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var primary: some View {
        Button(action: primaryAction) {
            Text(primaryTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!primaryEnabled)
        .tint(primaryEnabled ? Color.accentColor : Color.secondary)
    }

    private var folders: some View {
        HStack {
            folderButton("tray.and.arrow.up", L10n.text("folder.out"), model.reveal)
            folderButton("tray.and.arrow.down", L10n.text("folder.in"), model.reveal)
            folderButton("folder", L10n.text("folder.root"), model.openRoot)
        }
    }

    private var timeline: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.rounds.prefix(3).enumerated()), id: \.offset) { _, round in
                Text(round.label)
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            Spacer()
        }
    }

    private func folderButton(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var primaryTitle: String {
        switch model.phase {
        case .copy(let round): return L10n.format("card.copy", round)
        case .waiting: return L10n.text("card.waiting") + " · " + ElapsedText.phrase(seconds: waitingElapsed, chinese: L10n.chinese)
        case .reply: return L10n.text("card.reply")
        case .idle: return L10n.text("card.idle")
        case .failed: return model.errorLine.isEmpty ? L10n.text("card.failed") : model.errorLine
        case .empty: return L10n.text("card.empty")
        }
    }

    private var waitingElapsed: TimeInterval {
        if case .waiting(_, let elapsed) = model.phase { return elapsed }
        return 0
    }

    private var primaryEnabled: Bool {
        if case .copy = model.phase { return true }
        if case .reply = model.phase { return true }
        if case .empty = model.phase { return true }
        return false
    }

    private func primaryAction() {
        switch model.phase {
        case .copy: model.copyBundle()
        case .reply: model.reveal()
        case .empty: model.addProject()
        default: break
        }
    }

    private func reason(_ code: String) -> String {
        switch code {
        case "ambiguous": return L10n.text("pick.ambiguous")
        case "round_mismatch": return L10n.text("pick.round")
        default: return L10n.text("pick.nomatch")
        }
    }
}

private extension CardModel {
    var phaseToken: String {
        switch phase {
        case .copy(let round): return "copy\(round)"
        case .waiting(let round, _): return "wait\(round)"
        case .reply(let round): return "reply\(round)"
        case .idle(let round): return "idle\(round)"
        case .failed(let message): return "fail\(message)"
        case .empty: return "empty"
        }
    }
}

enum PasteboardWriter {
    enum Mode { case bundle, files, opener }

    /// Plain file URLs plus a string item. No file promises, and nothing is sent anywhere.
    static func write(opener: String, files: [String], mode: Mode) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let urls: [NSURL] = files.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return NSURL(fileURLWithPath: path)
        }
        switch mode {
        case .opener:
            pasteboard.setString(opener, forType: .string)
        case .files:
            pasteboard.writeObjects(urls)
        case .bundle:
            var items: [NSPasteboardWriting] = []
            if !opener.isEmpty {
                let text = NSPasteboardItem()
                text.setString(opener, forType: .string)
                items.append(text)
            }
            items.append(contentsOf: urls)
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
    }
}

enum Notifier {
    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum StatusIcon {
    static func image(style: IconStyle, appearance: NSAppearance) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            draw(style: style, in: NSRect(x: 0, y: 0, width: 18, height: 18), appearance: appearance)
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func draw(style: IconStyle, in rect: NSRect, appearance: NSAppearance) {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let gray = dark ? NSColor(calibratedWhite: 0.78, alpha: 1) : NSColor(calibratedWhite: 0.38, alpha: 1)
        let color: NSColor = (style == .ready || style == .highlighted) ? .controlAccentColor : gray
        color.setStroke()
        let bowl = NSBezierPath(ovalIn: NSRect(x: 4.2, y: 8, width: 9.6, height: 7.2))
        bowl.lineWidth = 1.35
        bowl.stroke()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 9, y: 3.1))
        stem.line(to: NSPoint(x: 9, y: 8))
        stem.lineWidth = 1.35
        stem.lineCapStyle = .round
        stem.stroke()
        let base = NSBezierPath()
        base.move(to: NSPoint(x: 4.6, y: 2.5))
        base.line(to: NSPoint(x: 13.4, y: 2.5))
        base.lineWidth = 1.35
        base.lineCapStyle = .round
        base.stroke()
        if style == .reply {
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.1, y: 12.1, width: 4.6, height: 4.6)).fill()
        }
    }
}

final class FolderWatcher {
    var onChange: (() -> Void)?
    private var stream: FSEventStreamRef?
    private var context = FSEventStreamContext()

    func start(_ paths: [String]) {
        stop()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }
        context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange?()
            },
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = CardModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var barWindow: BarWindowController?
    private var settingsWindow: NSWindow?
    private let watcher = FolderWatcher()
    private var debounce: DispatchWorkItem?
    private var watchCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = UserDefaults.standard.string(forKey: "handoffHome").flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("handoff")
        let executable = CLILocator.executable() ?? "/usr/bin/false"
        model.bridge = CLIBridge(executable: executable, home: (home as NSString).expandingTildeInPath, runner: ProcessCommandRunner())
        model.onIcon = { [weak self] style in self?.applyIcon(style) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.window?.registerForDraggedTypes([.fileURL])
            let drop = DropView(frame: button.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.onClick = { [weak self] in self?.handleClick(primary: true) }
            drop.onRightClick = { [weak self] in self?.handleClick(primary: false) }
            drop.onDrop = { [weak self] paths in self?.ingest(paths) }
            drop.onHighlight = { [weak self] on in
                self?.applyIcon(IconStyleResolver.style(projects: self?.model.projects ?? [], dropHighlighted: on))
            }
            button.addSubview(drop)
        }
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: CardView(model: model))
        popover.contentViewController = host
        applyIcon(.idle)
        watcher.onChange = { [weak self] in self?.scheduleRefresh() }
        watchCancellable = model.$projects.sink { [weak self] projects in
            self?.watch(projects)
        }
        model.presentSettings = { [weak self] in self?.showSettings() }
        model.presentAdd = { [weak self] in self?.showAddProject() }
        model.refresh()
        if let requested = LaunchRequest.view(from: CommandLine.arguments) {
            present(requested)
        } else if !UserDefaults.standard.bool(forKey: "welcomeShown") {
            let alert = NSAlert()
            alert.messageText = L10n.text("welcome.title")
            alert.informativeText = L10n.text("welcome.body")
            alert.addButton(withTitle: L10n.text("welcome.ok"))
            alert.runModal()
            UserDefaults.standard.set(true, forKey: "welcomeShown")
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let view = LaunchRequest.view(from: url) {
                present(view)
            }
        }
    }

    func present(_ view: AppView) {
        switch view {
        case .bar:
            openBar()
        case .card:
            showCard()
        case .settings:
            showSettings()
        }
    }

    private func handleClick(primary: Bool) {
        let opensBar = StatusClickPreferenceStore.current().leftOpensBar
        let showBar = primary ? opensBar : !opensBar
        if showBar {
            openBar()
        } else {
            toggleCard()
        }
    }

    private func openBar() {
        if popover.isShown { popover.performClose(nil) }
        model.refresh()
        if barWindow == nil {
            barWindow = BarWindowController(model: model)
        }
        barWindow?.show()
    }

    private func showCard() {
        guard let button = statusItem?.button else { return }
        model.refresh()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showAddProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("add.choose")
        panel.message = L10n.text("add.message")
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.model.createProject(name: url.lastPathComponent, repo: url.path)
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "ChatBar"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func toggleCard() {
        guard statusItem?.button != nil else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showCard()
        }
    }

    private func applyIcon(_ style: IconStyle) {
        let appearance = statusItem?.button?.effectiveAppearance ?? NSAppearance.currentDrawing()
        statusItem?.button?.image = StatusIcon.image(style: style, appearance: appearance)
    }

    private func watch(_ projects: [ProjectStatus]) {
        var paths = projects.flatMap { [$0.inboxDir, $0.outboxDir] }
        if model.autoExchange {
            paths.append((NSHomeDirectory() as NSString).appendingPathComponent("Downloads"))
        }
        watcher.start(paths)
    }

    private func scheduleRefresh() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let bridge = self.model.bridge else { return }
            if self.model.autoExchange {
                DispatchQueue.global().async {
                    _ = try? bridge.run(.downloadsScan(force: false))
                    DispatchQueue.main.async { self.model.refresh() }
                }
            } else {
                self.model.refresh()
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func ingest(_ paths: [String]) {
        guard let bridge = model.bridge, !model.projectName.isEmpty else { return }
        let files = PathDecode.filesForIngest(
            paths,
            isDirectory: { path in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            },
            children: { path in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] },
            exists: { FileManager.default.fileExists(atPath: $0) }
        )
        let name = model.projectName
        DispatchQueue.global().async {
            _ = try? bridge.run(.ingest(project: name, paths: files))
            DispatchQueue.main.async { self.model.refresh() }
        }
    }
}

final class DropView: NSView {
    var onDrop: (([String]) -> Void)?
    var onHighlight: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { nil }

    override func mouseUp(with event: NSEvent) { onClick?() }
    override func rightMouseUp(with event: NSEvent) { onRightClick?() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHighlight?(true)
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onHighlight?(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHighlight?(false)
        let pasteboard = sender.draggingPasteboard
        var raw: [String] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            raw.append(contentsOf: urls.map(\.path))
        }
        if let text = pasteboard.string(forType: .fileURL) { raw.append(text) }
        let files = PathDecode.filesForIngest(
            raw,
            isDirectory: { path in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            },
            children: { path in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] },
            exists: { FileManager.default.fileExists(atPath: $0) }
        )
        guard !files.isEmpty else { return false }
        onDrop?(files)
        return true
    }
}

@main
enum ChatBarMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            exit(L10n.selfTest())
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

struct NextStepBanner: View {
    @ObservedObject var model: CardModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(model.nextLine.isEmpty ? L10n.text("card.idle") : model.nextLine)
                .font(.system(size: 18, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L10n.text("next.button")) { model.performNext() }
                .disabled(model.nextFile.isEmpty && model.nextOpener.isEmpty && model.openerText.isEmpty)
                .buttonStyle(.borderedProminent)
        }
    }
}
