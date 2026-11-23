import AppKit
import ChatBarCore
import Combine
import CoreServices
import SwiftUI
import UserNotifications

// Local files, the pasteboard, and Finder only. This process never controls a chat app.

final class CardModel: ObservableObject {
    @Published var projectName = ""
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
    @Published private(set) var nextStep: NextStep?

    var bridge: CLIBridge?
    var onIcon: (IconStyle) -> Void = { _ in }
    var presentSettings: () -> Void = {}
    var presentAdd: () -> Void = {}
    var onFirstRefresh: (() -> Void)?
    var onWatchPaths: ([String]) -> Void = { _ in }
    private let commands = DispatchQueue(label: "chatbar.commands", qos: .userInitiated)
    private var refreshID = 0
    private var commandInFlight = false
    private var openerProject = ""
    private var loadedOpener = ""
    private var saveItem: DispatchWorkItem?
    private var knownReplies = Set<String>()
    private var knownPending = Set<String>()
    private var primed = false
    private var lastPackStamp = ""
    private var reportedFirstRefresh = false

    var preview: String { OpenerPreview.line(from: openerText) }

    var statusTitle: String {
        if projects.contains(where: { $0.newTask == true }) { return "新任务" }
        return nextStep?.titleShort ?? "ChatBar"
    }

    func refresh(automatic: Bool = false, commandError: String? = nil) {
        guard let bridge, !commandInFlight else { return }
        refreshID += 1
        let id = refreshID
        commands.async {
            if automatic { _ = try? bridge.run(.sweep(automatic: true)) }
            let status = try? bridge.run(.status)
            let document = status.flatMap { result in
                result.ok ? try? JSONDocuments.status(Data(result.stdout.utf8)) : nil
            }
            let current = document?.projects.first { $0.current } ?? document?.projects.first
            let next = document.map { _ in Result { try bridge.nextStep(project: current?.name) } }
            let pendingResult = try? bridge.run(.downloadsPending)
            DispatchQueue.main.async {
                guard id == self.refreshID else { return }
                self.apply(status: status, document: document, next: next, pending: pendingResult)
                if let commandError { self.errorLine = commandError }
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
        guard !projectName.isEmpty else { return }
        saveItem?.cancel()
        run(.openerReset(projectName))
    }

    func reveal() { run(.reveal(projectName)) }
    func openHandoff() { run(.openHandoff(projectName)) }
    func openRoot() { run(.openRoot(projectName)) }
    func pack() { run(.pack(projectName)) }
    func archiveRound() { run(.archive(projectName)) }
    func applyPatch() { run(.apply(projectName)) }
    func sweep() { run(.sweep(automatic: false)) }
    func selectRoom(_ name: String) { run(.projectUse(name)) }

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
        guard let bridge, name == openerProject, text != loadedOpener else { return }
        commands.async {
            guard let result = try? bridge.run(.openerSave(name), standardInput: text), result.ok else { return }
            DispatchQueue.main.async {
                guard self.openerProject == name else { return }
                self.loadedOpener = text
            }
        }
    }

    private func run(_ command: CLICommand, opener: (project: String, text: String)? = nil) {
        guard let bridge, !commandInFlight else { return }
        commandInFlight = true
        refreshID += 1
        nextStep = nil
        commands.async {
            let error: String?
            do {
                if let opener {
                    let saved = try bridge.run(.openerSave(opener.project), standardInput: opener.text)
                    if !saved.ok {
                        let message = Self.failureLine(saved, fallback: "chatbar opener save (\(saved.code))")
                        DispatchQueue.main.async { self.finishCommand(error: message) }
                        return
                    }
                }
                let result = try bridge.run(command)
                error = result.ok ? nil : Self.failureLine(result, fallback: "chatbar (\(result.code))")
            } catch let failure {
                error = failure.localizedDescription
            }
            DispatchQueue.main.async { self.finishCommand(error: error) }
        }
    }

    private func finishCommand(error: String?) {
        commandInFlight = false
        refresh(automatic: true, commandError: error)
    }

    private func apply(
        status: CLIResult?,
        document: StatusDocument?,
        next: Result<NextStep, Error>?,
        pending pendingResult: CLIResult?
    ) {
        defer { noteFirstRefresh() }
        guard let doc = document else {
            nextStep = nil
            errorLine = status.map { Self.failureLine($0, fallback: "chatbar status (\($0.code))") } ?? "chatbar 没有返回"
            return
        }
        projects = doc.projects
        autoExchange = doc.autoExchange
        let current = doc.projects.first { $0.current } ?? doc.projects.first
        let name = current?.name ?? ""
        if projectName != name {
            projectName = name
            openerProject = name
            openerText = ""
            loadedOpener = ""
            openerExpanded = false
            rounds = []
            lastPackStamp = ""
        }
        projectAuto = current?.projectAuto ?? false
        errorLine = current?.error ?? ""
        switch next {
        case .success(let step):
            nextStep = step
            if step.step == .copy && loadedOpener.isEmpty { openerExpanded = true }
        case .failure(let error):
            nextStep = nil
            errorLine = error.localizedDescription
        case nil:
            nextStep = nil
        }
        var paths = doc.projects.map(\.handoff)
        if doc.autoExchange, let downloads = doc.downloadDir { paths.append(downloads) }
        onWatchPaths(paths)
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
            let stamp = current.packAt + current.presentedAt + current.inboxState + String(current.round)
            if primed, let nextStep, nextStep.step == .received, nextStep.titleShort == "新任务",
               knownReplies.insert(current.name + ":\(nextStep.round)").inserted {
                Notifier.post(title: "ChatBar", body: L10n.format("notify.reply", current.name))
            }
            if stamp != lastPackStamp {
                lastPackStamp = stamp
                loadOpener(current.name)
                loadRounds(current.name)
            }
        }
        primed = true
    }

    private func noteFirstRefresh() {
        guard !reportedFirstRefresh else { return }
        reportedFirstRefresh = true
        onFirstRefresh?()
    }

    private static func failureLine(_ result: CLIResult, fallback: String) -> String {
        let line = result.stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
        if let line, !line.isEmpty { return String(line) }
        return fallback
    }

    func performNext(_ direction: NextStep.Direction = .advance) {
        guard let step = nextStep, step.project == projectName else { return }
        guard direction == .advance ? step.canAdvance : step.canGoBack else { return }
        var opener: (String, String)?
        if direction == .advance, step.step == .copy,
           openerProject == step.project, openerText != loadedOpener {
            saveItem?.cancel()
            opener = (step.project, openerText)
        }
        run(.step(direction, step), opener: opener)
    }

    private func loadOpener(_ name: String) {
        guard let bridge else { return }
        commands.async {
            guard let result = try? bridge.run(.openerShow(name)), result.ok,
                  let doc = try? JSONDocuments.opener(Data(result.stdout.utf8)) else { return }
            DispatchQueue.main.async {
                if self.openerProject == name && self.openerText == self.loadedOpener {
                    self.openerText = doc.text
                    self.loadedOpener = doc.text
                }
            }
        }
    }

    private func loadRounds(_ name: String) {
        guard let bridge else { return }
        commands.async {
            guard let result = try? bridge.run(.rounds(name)), result.ok,
                  let doc = try? JSONDocuments.rounds(Data(result.stdout.utf8)) else { return }
            DispatchQueue.main.async {
                guard self.projectName == name else { return }
                self.rounds = doc.rounds.reversed()
            }
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
            if !model.rounds.isEmpty { timeline }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .animation(.easeInOut(duration: 0.18), value: model.nextStep)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.projectName.isEmpty ? "ChatBar" : model.projectName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(model.nextStep.flatMap { $0.project.isEmpty ? nil : "R\($0.round)" } ?? "")
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
                Menu(L10n.text("menu.more")) {
                    if model.nextStep?.canGoBack == true {
                        Button(L10n.text("menu.back")) { model.performNext(.back) }
                    }
                    if !model.projectName.isEmpty {
                        Button("打包") { model.pack() }
                        Button("打开收发窗口") { model.reveal() }
                        Button("结束本轮") { model.archiveRound() }
                        Button("应用补丁") { model.applyPatch() }
                        Menu(model.projectName) {
                            Button(L10n.format("auto.title", model.projectAuto ? L10n.text("auto.on") : L10n.text("auto.off"))) {
                                model.setProjectAuto(!model.projectAuto)
                            }
                            Button("打开交接目录") { model.openHandoff() }
                            Button("打开项目根目录") { model.openRoot() }
                        }
                    }
                    Button("刷新") { model.sweep() }
                    Button(L10n.text("menu.add")) { model.addProject() }
                    Button(L10n.text("menu.settings")) { model.presentSettings() }
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

    private func reason(_ code: String) -> String {
        switch code {
        case "ambiguous": return L10n.text("pick.ambiguous")
        case "round_mismatch": return L10n.text("pick.round")
        default: return L10n.text("pick.nomatch")
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = CardModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var barWindow: BarWindowController?
    private var settingsWindow: NSWindow?
    private var welcomePanel: NSPanel?
    private let watcher = FolderWatcher()
    private var debounce: DispatchWorkItem?
    private var watchedPaths = Set<String>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = CLIBridge.resolvedHome(
            defaults: UserDefaults.standard.string(forKey: "handoffHome"),
            environment: ProcessInfo.processInfo.environment
        )
        let executable = CLILocator.executable() ?? "/usr/bin/false"
        model.bridge = CLIBridge(executable: executable, home: home, runner: ProcessCommandRunner())
        model.onIcon = { [weak self] style in self?.applyIcon(style) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.imagePosition = .imageLeft
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
        watcher.onChange = { [weak self] in
            DispatchQueue.main.async { self?.scheduleRefresh() }
        }
        model.onWatchPaths = { [weak self] paths in self?.watch(paths) }
        model.presentSettings = { [weak self] in self?.showSettings() }
        model.presentAdd = { [weak self] in self?.showAddProject() }
        model.onFirstRefresh = { [weak self] in
            DispatchQueue.main.async { self?.showWelcomeIfNeeded() }
        }
        model.refresh(automatic: true)
        if let requested = LaunchRequest.view(from: CommandLine.arguments) {
            present(requested)
        }
    }

    /// Non-modal. The first refresh has already applied, so this does not block the CLI.
    private func showWelcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "welcomeShown") else { return }
        guard welcomePanel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 180),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.text("welcome.title")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let body = NSTextField(wrappingLabelWithString: L10n.text("welcome.body"))
        body.translatesAutoresizingMaskIntoConstraints = false
        let button = NSButton(title: L10n.text("welcome.ok"), target: self, action: #selector(dismissWelcome(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        let content = NSView()
        content.addSubview(body)
        content.addSubview(button)
        panel.contentView = content
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            body.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            button.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 16)
        ])
        panel.center()
        welcomePanel = panel
        panel.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func dismissWelcome(_ sender: Any?) {
        welcomePanel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === welcomePanel else { return }
        UserDefaults.standard.set(true, forKey: "welcomeShown")
        welcomePanel = nil
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
        model.refresh(automatic: true)
        if barWindow == nil {
            barWindow = BarWindowController(model: model)
        }
        barWindow?.show()
    }

    private func showCard() {
        guard let button = statusItem?.button else { return }
        model.refresh(automatic: true)
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
        statusItem?.button?.title = model.statusTitle
    }

    private func watch(_ paths: [String]) {
        let desired = Set(paths.filter { FileManager.default.fileExists(atPath: $0) })
        guard desired != watchedPaths else { return }
        watchedPaths = desired
        watcher.start(desired.sorted())
    }

    private func scheduleRefresh() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.refresh(automatic: self.model.autoExchange)
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
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
            let l10n = L10n.selfTest()
            if CommandLine.arguments.contains("--dump-state") {
                let dumped = HeadlessRefresh.dumpState()
                exit(l10n == 0 ? dumped : l10n)
            }
            exit(l10n)
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
        VStack(alignment: .leading, spacing: 8) {
            if let step = model.nextStep {
                Text(step.titleShort).font(.headline)
                if step.canAdvance {
                    Button { model.performNext() } label: {
                        Text(step.actionLabel).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .help(step.file)
                } else {
                    Text(step.actionLabel).foregroundStyle(.secondary)
                }
            }
            if !model.errorLine.isEmpty {
                Text(model.errorLine).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
