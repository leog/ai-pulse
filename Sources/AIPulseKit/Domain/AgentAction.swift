import Foundation

/// Typed, safe actions an agent can expose. Never a shell command.
public enum AgentAction: Codable, Sendable, Hashable {
    case openURL(url: URL, label: String)
    case activateApplication(bundleIdentifier: String)
    case openProject(path: String)
    case showDetails
}

/// Resolves the safest click action for an agent, in fixed preference order:
/// validated deep link → owning application → project location → in-app details.
public enum ClickActionResolver {
    public static func resolve(for agent: Agent) -> AgentAction {
        if case let .openURL(url, label)? = agent.action, URLSafety.isSafe(url) {
            return .openURL(url: url, label: label)
        }
        if let deepLink = agent.deepLink, URLSafety.isSafe(deepLink) {
            return .openURL(url: deepLink, label: "Open \(agent.displayName)")
        }
        if let explicit = agent.action, case .activateApplication = explicit {
            return explicit
        }
        if let bundleID = agent.sourceApplicationBundleID {
            return .activateApplication(bundleIdentifier: bundleID)
        }
        if let path = agent.projectPath {
            return .openProject(path: path)
        }
        return .showDetails
    }
}

/// URL validation for anything received from an integration event.
public enum URLSafety {
    /// Conservative allowlist. `aipulse` is the app's own scheme.
    public static let allowedSchemes: Set<String> = ["https", "aipulse", "vscode", "cursor"]

    public static func isSafe(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }
}
