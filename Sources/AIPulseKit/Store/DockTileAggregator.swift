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
    public static func summarize(
        _ agents: [Agent],
        order: [AgentState] = StatusPriority.defaultOrder
    ) -> DockTileSummary {
        let unacknowledged = agents.filter { $0.state.requiresAttention && !$0.isAcknowledged }
        let urgentCount = unacknowledged.count

        var emphasis: DockTileEmphasis = .neutral
        for state in order {
            let candidate: DockTileEmphasis? = switch state {
            case .failed:
                unacknowledged.contains { $0.state == .failed } ? .failure : nil
            case .waitingForInput, .approvalRequired:
                unacknowledged.contains { $0.state == state } ? .attention : nil
            case .working:
                agents.contains { $0.state == .working } ? .working : nil
            default:
                nil
            }
            if let candidate {
                emphasis = candidate
                break
            }
        }
        return DockTileSummary(emphasis: emphasis, urgentCount: urgentCount)
    }
}
