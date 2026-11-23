import Foundation

/// The six fields emitted by `chatbar next --json`.
public struct NextStep: Equatable, Decodable {
    public enum Kind: String, Decodable {
        case noProject = "no_project"
        case needPack = "need_pack"
        case copy, paste, drag, send, wait, received, result
    }

    public enum Direction: String {
        case advance, back
    }

    public let step: Kind
    public let titleShort: String
    public let actionLabel: String
    public let project: String
    public let round: Int
    public let file: String

    private enum CodingKeys: String, CodingKey {
        case step, project, round, file
        case titleShort = "title_short"
        case actionLabel = "action_label"
    }

    public var canAdvance: Bool {
        !project.isEmpty && round > 0 && step != .noProject && step != .needPack
    }

    public var canGoBack: Bool {
        guard canAdvance else { return false }
        switch step {
        case .paste, .drag, .send, .wait: return true
        default: return false
        }
    }
}
