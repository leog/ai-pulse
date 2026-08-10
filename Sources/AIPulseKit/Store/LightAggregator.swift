import Foundation

/// Single aggregate signal for the lights indicator: one strip for all
/// agents, deliberately without per-agent or per-provider distinction.
public enum LightSignal: String, Sendable, Equatable {
    /// No agents at all.
    case off
    /// Agents connected but none active.
    case idle
    /// At least one agent working.
    case working
    /// Something finished and nothing more urgent is happening.
    case success
    /// At least one unacknowledged agent waits for input or approval.
    case attention
    /// At least one unacknowledged failure.
    case failure
}

public enum LightAggregator {
    public static func signal(for agents: [Agent]) -> LightSignal {
        if agents.contains(where: { $0.state == .failed && !$0.isAcknowledged }) {
            return .failure
        }
        if agents.contains(where: {
            ($0.state == .waitingForInput || $0.state == .approvalRequired) && !$0.isAcknowledged
        }) {
            return .attention
        }
        if agents.contains(where: { $0.state == .working }) {
            return .working
        }
        if agents.contains(where: { $0.state == .completed }) {
            return .success
        }
        return agents.isEmpty ? .off : .idle
    }
}
