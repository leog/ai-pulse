import Foundation

/// Normalizes inbound protocol events into `Agent` values, enforcing
/// versioning, identity validation, sequencing, and safe-action mapping.
/// Duplicate and out-of-order events are rejected here, in one place.
public enum AgentReducer {
    public static let supportedVersion = 1
    public static let maxIDLength = 256
    public static let maxNameLength = 120
    public static let maxMessageLength = 500
    public static let maxPathLength = 1024

    public enum Rejection: String, Sendable, Equatable {
        case unsupportedVersion
        case invalidAgentID
        case duplicateSequence
        case outdatedSequence
        case outdatedTimestamp
    }

    public enum Outcome: Sendable, Equatable {
        case applied(Agent)
        case rejected(Rejection)
    }

    public static func reduce(existing: Agent?, event: AgentEventPayload) -> Outcome {
        guard event.version == supportedVersion else {
            return .rejected(.unsupportedVersion)
        }

        let id = event.agent.id
        guard !id.isEmpty,
              id.count <= maxIDLength,
              id.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return .rejected(.invalidAgentID)
        }

        if let existing {
            if let sequence = event.sequence {
                // Sequences are authoritative when both sides have one. An
                // event that introduces sequencing mid-stream is accepted
                // even if its wall clock trails ours — clocks are the weaker
                // signal.
                if let last = existing.lastSequence {
                    if sequence == last { return .rejected(.duplicateSequence) }
                    if sequence < last { return .rejected(.outdatedSequence) }
                }
            } else if event.occurredAt < existing.lastUpdatedAt {
                return .rejected(.outdatedTimestamp)
            }
        }

        // Start from the existing agent so user state (mute, acknowledgement)
        // and supplemental metadata survive; AgentStore.upsert then applies
        // its own transition rules on top.
        var agent = existing ?? Agent(id: id, displayName: "", provider: "")
        // Update-style events may omit identity fields; keep what we know,
        // falling back to the ID for a first sighting with no name.
        let name = event.agent.name.trimmingCharacters(in: .whitespaces)
        agent.displayName = name.isEmpty ? (existing?.displayName ?? id) : cap(name, maxNameLength)
        let provider = event.agent.provider.trimmingCharacters(in: .whitespaces)
        agent.provider = provider.isEmpty ? (existing?.provider ?? "unknown") : cap(provider, maxNameLength)
        agent.instanceName = event.agent.instance.map { cap($0, maxNameLength) } ?? existing?.instanceName
        if let icon = event.agent.icon, !icon.isEmpty {
            agent.iconSystemName = cap(icon, 64)
        }
        agent.state = event.state
        agent.taskSummary = event.message.map { cap($0, maxMessageLength) }
        agent.projectName = event.project?.name.map { cap($0, maxNameLength) }
        // Project paths are display/reveal metadata only; nothing ever
        // interprets them as commands.
        agent.projectPath = event.project?.path.map { cap($0, maxPathLength) }
        agent.lastUpdatedAt = event.occurredAt
        agent.stateChangedAt = event.occurredAt
        agent.expiresAt = event.expiresAt
        agent.action = mapAction(event.action)
        agent.lastSequence = event.sequence ?? existing?.lastSequence
        agent.integrationLevel = max(
            existing?.integrationLevel ?? .presenceOnly,
            inferredLevel(for: event.state)
        )
        return .applied(agent)
    }

    /// Only known typed actions survive; unknown types and unsafe URLs are
    /// dropped without failing the whole event.
    static func mapAction(_ descriptor: AgentEventPayload.ActionDescriptor?) -> AgentAction? {
        guard let descriptor else { return nil }
        switch descriptor.type {
        case "openURL":
            guard let raw = descriptor.url,
                  let url = URL(string: raw),
                  URLSafety.isSafe(url) else { return nil }
            return .openURL(url: url, label: cap(descriptor.label ?? "Open", maxNameLength))
        case "activateApplication":
            guard let bundleID = descriptor.bundleIdentifier, !bundleID.isEmpty else { return nil }
            return .activateApplication(bundleIdentifier: cap(bundleID, maxNameLength))
        case "showDetails":
            return .showDetails
        default:
            return nil
        }
    }

    /// Claiming an interactive state implies the integration supports the
    /// interactive lifecycle; the level never downgrades.
    static func inferredLevel(for state: AgentState) -> AgentIntegrationLevel {
        switch state {
        case .waitingForInput, .approvalRequired: .interactiveLifecycle
        case .working, .completed, .failed: .activityLifecycle
        default: .presenceOnly
        }
    }

    private static func cap(_ string: String, _ limit: Int) -> String {
        string.count <= limit ? string : String(string.prefix(limit))
    }
}
