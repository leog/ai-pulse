import Foundation

/// Urgency ordering for agent states. Lower rank means more urgent.
public enum StatusPriority {
    public static func rank(_ state: AgentState) -> Int {
        switch state {
        case .approvalRequired: 0
        case .waitingForInput: 1
        case .failed: 2
        case .working: 3
        case .completed: 4
        case .disconnected: 5
        case .idle: 6
        case .unknown: 7
        }
    }

    /// Sorts by urgency, then most recent state transition, then stable ID so
    /// equal-priority agents never reorder arbitrarily between renders.
    public static func sort(_ agents: [Agent]) -> [Agent] {
        agents.sorted { a, b in
            let ra = rank(a.state)
            let rb = rank(b.state)
            if ra != rb { return ra < rb }
            if a.stateChangedAt != b.stateChangedAt { return a.stateChangedAt > b.stateChangedAt }
            return a.id < b.id
        }
    }
}
