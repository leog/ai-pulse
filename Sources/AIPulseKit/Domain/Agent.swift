import Foundation

/// One agent *instance* (e.g. a specific Claude Code session in a specific
/// repository), not merely an AI provider.
public struct Agent: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var displayName: String
    public var provider: String
    public var instanceName: String?
    /// SF Symbol name used for the agent's glyph.
    public var iconSystemName: String
    public var state: AgentState
    public var taskSummary: String?
    public var projectName: String?
    public var projectPath: String?
    /// Bundle identifier of the application that owns this agent, if known.
    public var sourceApplicationBundleID: String?
    public var lastUpdatedAt: Date
    public var stateChangedAt: Date
    /// Source-provided expiration; the only way a waiting/approval state may
    /// disappear without resolution or user acknowledgement.
    public var expiresAt: Date?
    /// Optional explicit safe action supplied by the integration.
    public var action: AgentAction?
    /// Optional validated deep link supplied by the integration.
    public var deepLink: URL?
    public var isAcknowledged: Bool
    public var isMuted: Bool
    public var integrationLevel: AgentIntegrationLevel
    /// Highest sequence number accepted so far, when the source supplies one.
    public var lastSequence: Int?

    public init(
        id: String,
        displayName: String,
        provider: String,
        instanceName: String? = nil,
        iconSystemName: String = "cpu",
        state: AgentState = .unknown,
        taskSummary: String? = nil,
        projectName: String? = nil,
        projectPath: String? = nil,
        sourceApplicationBundleID: String? = nil,
        lastUpdatedAt: Date = Date(),
        stateChangedAt: Date = Date(),
        expiresAt: Date? = nil,
        action: AgentAction? = nil,
        deepLink: URL? = nil,
        isAcknowledged: Bool = false,
        isMuted: Bool = false,
        integrationLevel: AgentIntegrationLevel = .presenceOnly,
        lastSequence: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.instanceName = instanceName
        self.iconSystemName = iconSystemName
        self.state = state
        self.taskSummary = taskSummary
        self.projectName = projectName
        self.projectPath = projectPath
        self.sourceApplicationBundleID = sourceApplicationBundleID
        self.lastUpdatedAt = lastUpdatedAt
        self.stateChangedAt = stateChangedAt
        self.expiresAt = expiresAt
        self.action = action
        self.deepLink = deepLink
        self.isAcknowledged = isAcknowledged
        self.isMuted = isMuted
        self.integrationLevel = integrationLevel
        self.lastSequence = lastSequence
    }
}

public extension Agent {
    /// Secondary identity line: instance name, project name, or provider.
    var subtitle: String {
        instanceName ?? projectName ?? provider
    }
}
