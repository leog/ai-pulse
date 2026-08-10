import Foundation

/// Centralized, configurable stale/expiration rules. All timing decisions
/// live here so they are testable and never scattered across views.
public struct StalenessConfiguration: Codable, Sendable, Hashable {
    /// A working agent with no update for this long is shown as stale.
    public var workingStaleAfter: TimeInterval
    /// Completed agents are removed after this delay; nil means never.
    public var completedRemovalDelay: TimeInterval?
    /// A working agent silent for this long is demoted to disconnected —
    /// a source that died mid-turn emits no terminal event, so silence is
    /// the only signal left. nil means never demote on a timer.
    public var workingDisconnectAfter: TimeInterval?

    public init(
        workingStaleAfter: TimeInterval = 600,
        completedRemovalDelay: TimeInterval? = 60,
        workingDisconnectAfter: TimeInterval? = 1800
    ) {
        self.workingStaleAfter = workingStaleAfter
        self.completedRemovalDelay = completedRemovalDelay
        self.workingDisconnectAfter = workingDisconnectAfter
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

    /// Disconnection demotes a silent working agent instead of letting it
    /// claim progress forever. The same treatment `RestorePolicy` applies at
    /// launch, but reachable while the app stays running.
    public static func shouldDisconnect(
        _ agent: Agent,
        at date: Date,
        configuration: StalenessConfiguration
    ) -> Bool {
        guard let threshold = configuration.workingDisconnectAfter else { return false }
        return agent.state == .working
            && date.timeIntervalSince(agent.lastUpdatedAt) >= threshold
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
