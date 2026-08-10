import Foundation
import Observation

/// Single source of truth for all agent state. Every surface (pill, hover
/// card, agent list, future Dock tile) renders from this store; none of them
/// interpret raw events independently.
@MainActor
@Observable
public final class AgentStore {
    public private(set) var agentsByID: [String: Agent] = [:]

    /// IDs of agents currently considered stale, refreshed by `sweep`.
    public private(set) var staleAgentIDs: Set<String> = []

    public init() {}

    /// All agents, urgency-sorted with stable tie-breaking.
    public var allSorted: [Agent] {
        StatusPriority.sort(Array(agentsByID.values))
    }

    /// Agents eligible for the pill (muted agents stay in the list window only).
    public var pillAgents: [Agent] {
        StatusPriority.sort(agentsByID.values.filter { !$0.isMuted })
    }

    /// Splits pill agents into the visible slice and an overflow count.
    public func visibleAgents(maxCount: Int) -> (visible: [Agent], overflow: Int) {
        let agents = pillAgents
        guard agents.count > maxCount, maxCount > 0 else { return (agents, 0) }
        return (Array(agents.prefix(maxCount)), agents.count - maxCount)
    }

    public func agent(id: String) -> Agent? {
        agentsByID[id]
    }

    /// Inserts or replaces an agent. A state change resets acknowledgement
    /// and stamps `stateChangedAt`.
    public func upsert(_ agent: Agent) {
        var incoming = agent
        if let existing = agentsByID[agent.id] {
            if existing.state != incoming.state {
                incoming.stateChangedAt = incoming.lastUpdatedAt
                incoming.isAcknowledged = false
            } else {
                incoming.stateChangedAt = existing.stateChangedAt
                incoming.isAcknowledged = existing.isAcknowledged
            }
            incoming.isMuted = existing.isMuted
        }
        agentsByID[agent.id] = incoming
    }

    public func acknowledge(id: String) {
        guard var agent = agentsByID[id] else { return }
        agent.isAcknowledged = true
        agentsByID[id] = agent
    }

    /// Clears every pending attention state at once — the lights indicator
    /// has no per-agent surface, so acknowledgement is aggregate too.
    public func acknowledgeAll() {
        for (id, var agent) in agentsByID where !agent.isAcknowledged {
            agent.isAcknowledged = true
            agentsByID[id] = agent
        }
    }

    public func setMuted(id: String, muted: Bool) {
        guard var agent = agentsByID[id] else { return }
        agent.isMuted = muted
        agentsByID[id] = agent
    }

    public func remove(id: String) {
        agentsByID.removeValue(forKey: id)
        staleAgentIDs.remove(id)
    }

    /// Applies a protocol event through the reducer. The only mutation path
    /// for inbound events, so sequencing rules cannot be bypassed.
    @discardableResult
    public func apply(_ event: AgentEventPayload) -> AgentReducer.Outcome {
        let outcome = AgentReducer.reduce(existing: agentsByID[event.agent.id], event: event)
        if case let .applied(agent) = outcome {
            upsert(agent)
        }
        return outcome
    }

    /// Removes expired agents, demotes agents whose source is provably or
    /// probably gone, and recomputes staleness. Called periodically; `date`
    /// and `isProcessAlive` are injectable for tests.
    public func sweep(
        at date: Date = Date(),
        configuration: StalenessConfiguration = .default,
        isProcessAlive: (Int32) -> Bool = ProcessLiveness.isAlive
    ) {
        let expired = agentsByID.values.filter {
            StalenessPolicy.shouldExpire($0, at: date, configuration: configuration)
        }
        for agent in expired {
            agentsByID.removeValue(forKey: agent.id)
        }

        // A source that dies mid-turn emits no Stop/SessionEnd, so its agent
        // would claim "working" forever. Two demotion paths to disconnected,
        // mirroring RestorePolicy's launch-time treatment of live-only
        // states: a dead backing process (checked immediately), or silence
        // past the configured threshold when no PID is known.
        for (id, var agent) in agentsByID {
            let liveOnly = agent.state == .working || agent.state == .idle || agent.state == .unknown
            let sourceDead = liveOnly && agent.sourceProcessID.map { !isProcessAlive($0) } ?? false
            let silentTooLong = StalenessPolicy.shouldDisconnect(agent, at: date, configuration: configuration)
            guard sourceDead || silentTooLong else { continue }
            agent.state = .disconnected
            agent.stateChangedAt = date
            agentsByID[id] = agent
        }

        let stale = Set(
            agentsByID.values
                .filter { StalenessPolicy.isStale($0, at: date, configuration: configuration) }
                .map(\.id)
        )
        if stale != staleAgentIDs {
            staleAgentIDs = stale
        }
    }
}
