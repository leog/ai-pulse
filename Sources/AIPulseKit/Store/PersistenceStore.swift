import Foundation

/// On-disk snapshot of agent status metadata. Contains only identity, the
/// latest normalized state, timestamps, acknowledgement, and integration
/// metadata — never prompts, responses, terminal output, or source code.
public struct PersistedState: Codable, Sendable {
    public var version: Int
    public var savedAt: Date
    public var agents: [Agent]

    public init(version: Int = PersistenceStore.formatVersion, savedAt: Date, agents: [Agent]) {
        self.version = version
        self.savedAt = savedAt
        self.agents = agents
    }
}

public struct PersistenceStore: Sendable {
    public static let formatVersion = 1

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("AIPulse", isDirectory: true)
            .appendingPathComponent("agents.json")
    }

    /// Returns the saved agents, or an empty list for a missing, corrupt, or
    /// incompatible file — a broken cache must never block launch.
    public func load() -> [Agent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistedState.self, from: data),
              state.version == Self.formatVersion else { return [] }
        return state.agents
    }

    public func save(_ agents: [Agent], at date: Date = Date()) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(PersistedState(savedAt: date, agents: agents)) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// State mapping applied when restoring persisted agents at launch.
public enum RestorePolicy {
    /// Unresolved attention states (waiting, approval, failed) restore as-is
    /// so they survive restarts. Live-only states (working, idle, unknown)
    /// restore as disconnected: their sources must report in again before
    /// AI Pulse claims anything about them.
    public static func rehydrate(_ agents: [Agent], at date: Date) -> [Agent] {
        agents.map { agent in
            var restored = agent
            switch agent.state {
            case .working, .idle, .unknown:
                restored.state = .disconnected
                restored.stateChangedAt = date
            case .waitingForInput, .approvalRequired, .failed, .completed, .disconnected:
                break
            }
            return restored
        }
    }
}
