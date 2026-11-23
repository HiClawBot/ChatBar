import Foundation

public enum AppView: String, Equatable {
    case bar
    case card
    case settings
}

/// Opens a view without clicking the menu bar icon.
/// `chatbar-app://open?view=bar|card|settings` or `--show bar|card|settings`.
public enum LaunchRequest {
    public static func view(from arguments: [String]) -> AppView? {
        guard let index = arguments.firstIndex(of: "--show"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return AppView(rawValue: arguments[index + 1])
    }

    public static func view(from url: URL) -> AppView? {
        guard url.scheme == "chatbar-app" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let raw = items?.first(where: { $0.name == "view" })?.value else { return nil }
        return AppView(rawValue: raw)
    }
}
