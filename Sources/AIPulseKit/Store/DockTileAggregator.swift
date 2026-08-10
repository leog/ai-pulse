import Foundation

/// What the Dock tile should convey, aggregated from the same AgentStore
/// snapshot the pill renders — the two surfaces never interpret state
/// independently.
public enum DockTileEmphasis: String, Sendable, Equatable {
    case neutral
    case working
    case attention
    case failure
}

public struct DockTileSummary: Sendable, Equatable {
    public var emphasis: DockTileEmphasis
    /// Unacknowledged waiting / approval / failed agents; shown as the
    /// numeric badge when non-zero.
    public var urgentCount: Int

    public init(emphasis: DockTileEmphasis, urgentCount: Int) {
        self.emphasis = emphasis
        self.urgentCount = urgentCount
    }
}

public enum DockTileAggregator {
    public static func summarize(_ agents: [Agent]) -> DockTileSummary {
        let unacknowledged = agents.filter { $0.state.requiresAttention && !$0.isAcknowledged }
        let urgentCount = unacknowledged.count

        let emphasis: DockTileEmphasis
        if unacknowledged.contains(where: { $0.state == .failed }) {
            emphasis = .failure
        } else if !unacknowledged.isEmpty {
            emphasis = .attention
        } else if agents.contains(where: { $0.state == .working }) {
            emphasis = .working
        } else {
            emphasis = .neutral
        }
        return DockTileSummary(emphasis: emphasis, urgentCount: urgentCount)
    }
}
