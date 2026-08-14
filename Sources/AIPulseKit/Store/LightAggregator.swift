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
    public static func signal(
        for agents: [Agent],
        order: [AgentState] = StatusPriority.defaultOrder
    ) -> LightSignal {
        for state in order {
            guard let candidate = signal(for: state) else { continue }
            // Attention-type states stay quiet once acknowledged; a strip
            // that kept shouting after "got it" would train users to ignore it.
            let matches = if state.requiresAttention {
                agents.contains { $0.state == state && !$0.isAcknowledged }
            } else {
                agents.contains { $0.state == state }
            }
            if matches { return candidate }
        }
        return agents.isEmpty ? .off : .idle
    }

    /// The signal a state raises when it wins the priority scan; nil for
    /// states that only contribute to the idle/off fallback.
    private static func signal(for state: AgentState) -> LightSignal? {
        switch state {
        case .failed: .failure
        case .waitingForInput, .approvalRequired: .attention
        case .working: .working
        case .completed: .success
        case .idle, .disconnected, .unknown: nil
        }
    }
}
