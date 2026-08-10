import Foundation

/// Wire-format payload for the local event protocol (Milestone 4).
/// Defined now so the domain model and the transport model evolve together.
public struct AgentEventPayload: Codable, Sendable, Equatable {
    public struct AgentDescriptor: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var provider: String
        public var instance: String?
        public var icon: String?

        public init(id: String, name: String, provider: String, instance: String? = nil, icon: String? = nil) {
            self.id = id
            self.name = name
            self.provider = provider
            self.instance = instance
            self.icon = icon
        }
    }

    public struct ProjectInfo: Codable, Sendable, Equatable {
        public var name: String?
        public var path: String?

        public init(name: String? = nil, path: String? = nil) {
            self.name = name
            self.path = path
        }
    }

    /// Typed action descriptor; `type` is validated against a known set,
    /// never interpreted as a command string.
    public struct ActionDescriptor: Codable, Sendable, Equatable {
        public var type: String
        public var label: String?
        public var url: String?
        public var bundleIdentifier: String?

        public init(type: String, label: String? = nil, url: String? = nil, bundleIdentifier: String? = nil) {
            self.type = type
            self.label = label
            self.url = url
            self.bundleIdentifier = bundleIdentifier
        }
    }

    public var version: Int
    public var agent: AgentDescriptor
    public var state: AgentState
    public var message: String?
    public var project: ProjectInfo?
    public var action: ActionDescriptor?
    public var occurredAt: Date
    public var expiresAt: Date?
    public var sequence: Int?
    /// PID of the process backing the agent, for local liveness checks.
    public var pid: Int?

    public init(
        version: Int = 1,
        agent: AgentDescriptor,
        state: AgentState,
        message: String? = nil,
        project: ProjectInfo? = nil,
        action: ActionDescriptor? = nil,
        occurredAt: Date = Date(),
        expiresAt: Date? = nil,
        sequence: Int? = nil,
        pid: Int? = nil
    ) {
        self.version = version
        self.agent = agent
        self.state = state
        self.message = message
        self.project = project
        self.action = action
        self.occurredAt = occurredAt
        self.expiresAt = expiresAt
        self.sequence = sequence
        self.pid = pid
    }
}
