import AppKit
import ChatBarCore
import SwiftUI

/// Full window. Projects are private rooms. The compact card is docked on the side.
struct BarWindowView: View {
    @ObservedObject var model: CardModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("bar.title"))
                        .font(.system(size: 22, weight: .semibold))
                    rooms
                    tipJar
                    scene
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            CardView(model: model)
                .padding(12)
        }
        .frame(minWidth: 860, minHeight: 520)
        .background(.ultraThinMaterial)
        .onAppear { model.loadBar() }
    }

    private var rooms: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("bar.room"))
                .font(.system(size: 13, weight: .semibold))
            if model.projects.isEmpty {
                Text(L10n.text("card.empty")).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(model.projects, id: \.name) { project in
                        Button {
                            model.selectRoom(project.name)
                        } label: {
                            RoomTile(project: project, selected: project.name == model.projectName)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var tipJar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("bar.tip")).font(.system(size: 13, weight: .semibold))
            Text(L10n.format("bar.tipMinutes", model.tipMinutesText))
            Text(L10n.format("bar.tipCost", model.tipCostText))
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
    }

    private var scene: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("bar.scene")).font(.system(size: 13, weight: .semibold))
            Text(L10n.text("bar.sceneLater"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            BarScenePlaceholder(events: model.sceneEvents)
        }
    }
}

struct RoomTile: View {
    let project: ProjectStatus
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(light)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).lineLimit(1).font(.system(size: 13, weight: .medium))
                Text("R\(project.round)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
        )
    }

    private var light: Color {
        if project.newTask ?? (project.inboxState == "new") { return .red }
        if !project.error.isEmpty { return .orange }
        if project.packState == "ready" || project.packState == "presented" { return .accentColor }
        return Color.primary.opacity(0.28)
    }
}

/// Placeholder for a later animation of robots at the relay steps.
struct BarScenePlaceholder: View {
    let events: [SceneEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if events.isEmpty {
                Text("—").foregroundStyle(.secondary)
            } else {
                ForEach(events.suffix(8)) { event in
                    HStack {
                        Text(RelayStep.label(direction: event.direction, chinese: L10n.chinese))
                            .font(.system(size: 12, weight: .medium))
                        Text(event.project).lineLimit(1).font(.system(size: 12))
                        Spacer()
                        Text("R\(event.round)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

struct SettingsView: View {
    @ObservedObject var model: CardModel
    @State private var opensBar: Bool
    @State private var minutes: String
    @State private var cost: String

    init(model: CardModel) {
        self.model = model
        _opensBar = State(initialValue: StatusClickPreference.resolve(
            UserDefaults.standard.string(forKey: StatusClickPreference.storageKey)
        ).leftOpensBar)
        _minutes = State(initialValue: model.tipMinutesField)
        _cost = State(initialValue: model.tipCostField)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("menu.settings")).font(.headline)
            Picker(L10n.text("settings.leftClick"), selection: $opensBar) {
                Text(L10n.text("settings.leftBar")).tag(true)
                Text(L10n.text("settings.leftCard")).tag(false)
            }
            .pickerStyle(.radioGroup)
            LabeledContent(L10n.text("settings.tipMinutes")) {
                TextField(L10n.text("settings.tipMinutes"), text: $minutes).labelsHidden()
            }
            LabeledContent(L10n.text("settings.tipCost")) {
                TextField(L10n.text("settings.tipCost"), text: $cost).labelsHidden()
            }
            HStack {
                Spacer()
                Button(L10n.text("settings.save")) {
                    StatusClickPreferenceStore.setOpensBar(opensBar)
                    model.saveTipAssumptions(minutes: minutes, cost: cost)
                    model.closeSettings()
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

enum StatusClickPreferenceStore {
    static func current() -> StatusClickPreference {
        StatusClickPreference.resolve(UserDefaults.standard.string(forKey: StatusClickPreference.storageKey))
    }

    static func setOpensBar(_ opensBar: Bool) {
        UserDefaults.standard.set(opensBar ? "bar" : "card", forKey: StatusClickPreference.storageKey)
    }
}

final class BarWindowController {
    let window: NSWindow

    init(model: CardModel) {
        let host = NSHostingController(rootView: BarWindowView(model: model))
        window = NSWindow(contentViewController: host)
        window.title = "ChatBar"
        window.setContentSize(NSSize(width: 920, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
