import Foundation

public enum CardPhase: Equatable {
    case copy(round: Int)
    case waiting(round: Int, elapsed: TimeInterval)
    case reply(round: Int)
    case idle(round: Int)
    case failed(String)
    case empty
}

public struct ProjectStatus: Equatable, Decodable {
    public var name: String
    public var repo: String
    public var handoff: String
    public var workspace: String
    public var current: Bool
    public var chatName: String
    public var round: Int
    public var packState: String
    public var inboxState: String
    public var packFile: String
    public var inboxDir: String
    public var outboxDir: String
    public var presentedAt: String
    public var packAt: String
    public var roundsFile: String
    public var menuState: String
    public var error: String
    public var projectAuto: Bool
    public var newTask: Bool?
    public var slug: String

    enum CodingKeys: String, CodingKey {
        case name, repo, handoff, workspace, current, round, error, slug
        case chatName = "chat_name"
        case packState = "pack_state"
        case inboxState = "inbox_state"
        case packFile = "pack_file"
        case inboxDir = "inbox_dir"
        case outboxDir = "outbox_dir"
        case presentedAt = "presented_at"
        case packAt = "pack_at"
        case roundsFile = "rounds_file"
        case menuState = "menu_state"
        case projectAuto = "project_auto"
        case newTask = "new_task"
    }

    public func elapsed(now: Date) -> TimeInterval {
        let raw = presentedAt.isEmpty ? packAt : presentedAt
        guard let date = StatusClock.date(from: raw) else { return 0 }
        return max(0, now.timeIntervalSince(date))
    }
}

public struct StatusDocument: Equatable, Decodable {
    public var home: String
    public var autoExchange: Bool
    public var downloadDir: String?
    public var projects: [ProjectStatus]

    enum CodingKeys: String, CodingKey {
        case home, projects
        case autoExchange = "auto_exchange"
        case downloadDir = "download_dir"
    }
}

public struct OpenerDocument: Equatable, Decodable {
    public var project: String
    public var round: Int
    public var source: String
    public var text: String
    public var generated: String
}

public struct BundleDocument: Equatable, Decodable {
    public var project: String
    public var round: Int
    public var chatName: String
    public var opener: String
    public var files: [String]

    enum CodingKeys: String, CodingKey {
        case project, round, opener, files
        case chatName = "chat_name"
    }
}

public struct RoundSummary: Equatable, Decodable {
    public var label: String
    public var when: String
    public var topic: String
    public var status: String
}

public struct RoundsDocument: Equatable, Decodable {
    public var rounds: [RoundSummary]
}

public struct PendingItem: Equatable, Decodable {
    public var path: String
    public var name: String
    public var reason: String
    public var project: String
    public var detail: String
}

public struct PendingDocument: Equatable, Decodable {
    public var items: [PendingItem]
}

public enum StatusClock {
    public static func date(from raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

public enum CardPhaseResolver {
    public static func resolve(project: ProjectStatus?, now: Date = Date()) -> CardPhase {
        guard let project else { return .empty }
        if project.inboxState == "new" {
            return .reply(round: project.round)
        }
        if !project.error.isEmpty {
            return .failed(project.error)
        }
        if project.packState == "ready" {
            return .copy(round: project.round)
        }
        if project.packState == "presented" {
            return .waiting(round: project.round, elapsed: project.elapsed(now: now))
        }
        return .idle(round: project.round)
    }
}

public enum IconStyle: Equatable {
    case idle
    case ready
    case reply
    case highlighted
}

public enum StatusClickPreference: String, Equatable {
    case bar
    case card

    public static let storageKey = "leftClickOpens"

    public static func resolve(_ stored: String?) -> StatusClickPreference {
        stored == StatusClickPreference.card.rawValue ? .card : .bar
    }

    public var leftOpensBar: Bool { self == .bar }
}

public enum RelayStep {
    public static func label(direction: String, chinese: Bool) -> String {
        switch direction {
        case "to_planner":
            return chinese ? "聊天" : "chat"
        case "from_planner":
            return chinese ? "台球" : "billiards"
        case "archive":
            return chinese ? "飞镖" : "darts"
        default:
            return chinese ? "接力" : "relay"
        }
    }
}

public struct TipEstimate: Equatable, Decodable {
    public var actions: Int
    public var rounds: Int
    public var minutesPerAction: Double
    public var costPerRound: Double
    public var minutesSaved: Double
    public var costSaved: Double
    public var machine: String

    enum CodingKeys: String, CodingKey {
        case actions, rounds, machine
        case minutesPerAction = "minutes_per_action"
        case costPerRound = "cost_per_round"
        case minutesSaved = "minutes_saved"
        case costSaved = "cost_saved"
    }
}

public struct SceneEvent: Equatable, Decodable, Identifiable {
    public var timestamp: String
    public var project: String
    public var round: Int
    public var direction: String
    public var machine: String

    public var id: String { "\(timestamp)|\(project)|\(round)|\(direction)" }

    enum CodingKeys: String, CodingKey {
        case timestamp, project, round, direction, machine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        project = try container.decodeIfPresent(String.self, forKey: .project) ?? ""
        round = try container.decodeIfPresent(Int.self, forKey: .round) ?? 0
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        machine = try container.decodeIfPresent(String.self, forKey: .machine) ?? ""
    }
}

public struct SceneLog: Equatable, Decodable {
    public var events: [SceneEvent]
}

public enum IconStyleResolver {
    public static func style(projects: [ProjectStatus], dropHighlighted: Bool) -> IconStyle {
        if dropHighlighted { return .highlighted }
        if projects.contains(where: { $0.newTask ?? ($0.inboxState == "new") }) { return .reply }
        if projects.contains(where: { $0.packState == "ready" || $0.packState == "presented" }) {
            return .ready
        }
        return .idle
    }
}

public enum ElapsedText {
    public static func phrase(seconds: TimeInterval, chinese: Bool) -> String {
        let whole = max(0, Int(seconds))
        if whole < 60 {
            return chinese ? "刚刚" : "just now"
        }
        let minutes = whole / 60
        if minutes < 60 {
            return chinese ? "\(minutes) 分钟" : "\(minutes) min"
        }
        let hours = minutes / 60
        return chinese ? "\(hours) 小时" : "\(hours) h"
    }
}

public enum OpenerPreview {
    public static func line(from text: String, limit: Int = 42) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end]) + "…"
    }
}

public enum JSONDocuments {
    public static func status(_ data: Data) throws -> StatusDocument {
        try JSONDecoder().decode(StatusDocument.self, from: data)
    }

    public static func opener(_ data: Data) throws -> OpenerDocument {
        try JSONDecoder().decode(OpenerDocument.self, from: data)
    }

    public static func bundle(_ data: Data) throws -> BundleDocument {
        try JSONDecoder().decode(BundleDocument.self, from: data)
    }

    public static func rounds(_ data: Data) throws -> RoundsDocument {
        try JSONDecoder().decode(RoundsDocument.self, from: data)
    }

    public static func pending(_ data: Data) throws -> PendingDocument {
        try JSONDecoder().decode(PendingDocument.self, from: data)
    }

    public static func tip(_ data: Data) throws -> TipEstimate {
        try JSONDecoder().decode(TipEstimate.self, from: data)
    }

    public static func scene(_ data: Data) throws -> SceneLog {
        try JSONDecoder().decode(SceneLog.self, from: data)
    }

    public static func next(_ data: Data) throws -> NextStep {
        try JSONDecoder().decode(NextStep.self, from: data)
    }
}
