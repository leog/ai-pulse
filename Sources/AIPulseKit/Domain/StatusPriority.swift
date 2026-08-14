import Foundation

/// Urgency ordering for agent states. Lower rank means more urgent. Every
/// surface (icon sort, lights aggregation, Dock tile) derives from one order
/// so they never disagree; users can rearrange it in Settings.
public enum StatusPriority {
    /// Built-in order, most urgent first.
    public static let defaultOrder: [AgentState] = [
        .approvalRequired, .waitingForInput, .failed, .working,
        .completed, .disconnected, .idle, .unknown,
    ]

    /// Repairs an arbitrary order into a full permutation: drops duplicates,
    /// then appends missing states in default position. Keeps stored
    /// preferences valid when states are added in a later version.
    public static func normalize(_ order: [AgentState]) -> [AgentState] {
        var seen = Set<AgentState>()
        var result = order.filter { seen.insert($0).inserted }
        result.append(contentsOf: defaultOrder.filter { !seen.contains($0) })
        return result
    }

    public static func rank(_ state: AgentState, order: [AgentState] = defaultOrder) -> Int {
        order.firstIndex(of: state) ?? order.count
    }

    /// Sorts by urgency, then most recent state transition, then stable ID so
    /// equal-priority agents never reorder arbitrarily between renders.
    public static func sort(_ agents: [Agent], order: [AgentState] = defaultOrder) -> [Agent] {
        agents.sorted { a, b in
            let ra = rank(a.state, order: order)
            let rb = rank(b.state, order: order)
            if ra != rb { return ra < rb }
            if a.stateChangedAt != b.stateChangedAt { return a.stateChangedAt > b.stateChangedAt }
            return a.id < b.id
        }
    }
}
