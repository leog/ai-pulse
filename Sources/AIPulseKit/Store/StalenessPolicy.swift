import Foundation

/// Centralized, configurable stale/expiration rules. All timing decisions
/// live here so they are testable and never scattered across views.
public struct StalenessConfiguration: Codable, Sendable, Hashable {
    /// A working agent with no update for this long is shown as stale.
    public var workingStaleAfter: TimeInterval
    /// Completed agents are removed after this delay; nil means never.
    public var completedRemovalDelay: TimeInterval?

    public init(
        workingStaleAfter: TimeInterval = 600,
        completedRemovalDelay: TimeInterval? = 60
    ) {
        self.workingStaleAfter = workingStaleAfter
        self.completedRemovalDelay = completedRemovalDelay
    }

    public static let `default` = StalenessConfiguration()
}

public enum StalenessPolicy {
    /// Stale = still nominally working but silent for too long. The agent
    /// stays visible; only its emphasis changes.
    public static func isStale(
        _ agent: Agent,
        at date: Date,
        configuration: StalenessConfiguration
    ) -> Bool {
        agent.state == .working
            && date.timeIntervalSince(agent.lastUpdatedAt) >= configuration.workingStaleAfter
    }

    /// Expiration removes an agent entirely. Waiting-for-input, approval and
    /// failure states never expire on a timer — only via a source-provided
    /// `expiresAt`, a new state, or user action.
    public static func shouldExpire(
        _ agent: Agent,
        at date: Date,
        configuration: StalenessConfiguration
    ) -> Bool {
        if let expiresAt = agent.expiresAt, date >= expiresAt {
            return true
        }
        if agent.state == .completed,
           let delay = configuration.completedRemovalDelay,
           date.timeIntervalSince(agent.stateChangedAt) >= delay {
            return true
        }
        return false
    }
}
