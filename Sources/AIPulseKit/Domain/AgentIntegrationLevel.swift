import Foundation

/// How much an integration can actually know about an agent. Presence-only
/// integrations must never claim interactive states like waitingForInput.
public enum AgentIntegrationLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    /// A process or application appears to exist; state stays unknown
    /// unless explicit events arrive.
    case presenceOnly = 1
    /// Working / completed / failed lifecycle events.
    case activityLifecycle = 2
    /// Waiting for input, approval required, resumed, acknowledged.
    case interactiveLifecycle = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
