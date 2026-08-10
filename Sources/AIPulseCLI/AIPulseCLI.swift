import Foundation
import AIPulseKit

/// `aipulse` — command-line publisher for the AI Pulse local event service.
///
///   aipulse health
///   aipulse agents
///   aipulse agent upsert --id ID --name NAME --state working [options]
///   aipulse agent update --id ID --state waitingForInput [options]
///   aipulse agent remove --id ID
///
/// Credentials come from the handshake file AI Pulse writes on launch
/// (override path with AIPULSE_CONFIG); no tokens on the command line.
@main
struct AIPulseCLI {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else {
            fail(usage)
        }
        let command = arguments.removeFirst()

        do {
            switch command {
            case "health":
                let flags = try Flags(arguments)
                let client = try client(from: flags, needsToken: false)
                try await print(response: client.get("/v1/health"))
            case "agents":
                let flags = try Flags(arguments)
                let client = try client(from: flags, needsToken: true)
                try await print(response: client.get("/v1/agents"))
            case "agent":
                try await agentCommand(arguments)
            case "claude-hook":
                await claudeHookCommand()
            case "help", "--help", "-h":
                Swift.print(usage)
            default:
                fail("unknown command '\(command)'\n\n\(usage)")
            }
        } catch let error as CLIError {
            fail(error.message)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func agentCommand(_ arguments: [String]) async throws {
        var arguments = arguments
        guard !arguments.isEmpty else { fail(usage) }
        let subcommand = arguments.removeFirst()
        let flags = try Flags(arguments)
        let client = try client(from: flags, needsToken: true)

        switch subcommand {
        case "upsert", "update":
            let id = try flags.require("id")
            let payload = try buildPayload(id: id, flags: flags)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let body = try encoder.encode(payload)
            let path = subcommand == "upsert"
                ? "/v1/agents/upsert"
                : "/v1/agents/\(escapePathComponent(id))/event"
            try await print(response: client.post(path, body: body))
        case "remove":
            let id = try flags.require("id")
            try await print(response: client.delete("/v1/agents/\(escapePathComponent(id))"))
        default:
            fail("unknown agent subcommand '\(subcommand)'\n\n\(usage)")
        }
    }

    private static func buildPayload(id: String, flags: Flags) throws -> AgentEventPayload {
        let stateRaw = try flags.require("state")
        guard let state = AgentState(rawValue: stateRaw) else {
            let valid = AgentState.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError("invalid state '\(stateRaw)'. Valid states: \(valid)")
        }

        var action: AgentEventPayload.ActionDescriptor?
        if let url = flags.value("open-url") {
            action = .init(type: "openURL", label: flags.value("open-label") ?? "Open", url: url)
        } else if let bundleID = flags.value("activate-app") {
            action = .init(type: "activateApplication", bundleIdentifier: bundleID)
        }

        var project: AgentEventPayload.ProjectInfo?
        if flags.value("project-name") != nil || flags.value("project-path") != nil {
            project = .init(name: flags.value("project-name"), path: flags.value("project-path"))
        }

        return AgentEventPayload(
            agent: .init(
                id: id,
                name: flags.value("name") ?? "",
                provider: flags.value("provider") ?? "",
                instance: flags.value("instance"),
                icon: flags.value("icon")
            ),
            state: state,
            message: flags.value("message"),
            project: project,
            action: action,
            occurredAt: Date(),
            sequence: flags.value("sequence").flatMap(Int.init)
        )
    }

    /// `aipulse claude-hook` — Claude Code hook entry point. Reads the hook
    /// JSON from stdin, maps it through ClaudeCodeAdapter, and publishes.
    /// Always exits 0 and prints nothing: a status pill must never block or
    /// clutter a Claude Code session, even when AI Pulse isn't running.
    private static func claudeHookCommand() async {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        // The Claude Code session process is our nearest non-shell ancestor
        // (hook commands may run under transient `sh -c` wrappers). Its
        // death is what "this agent is gone" means.
        let sessionPID = ProcessAncestry.stableAncestor(from: getppid())
        guard let input = try? JSONDecoder().decode(ClaudeCodeAdapter.HookInput.self, from: data),
              let mapped = ClaudeCodeAdapter.map(
                  input,
                  environment: ProcessInfo.processInfo.environment,
                  sourceProcessID: sessionPID
              )
        else { return }
        guard let flags = try? Flags([]),
              let client = try? client(from: flags, needsToken: true) else { return }

        switch mapped {
        case .publish(let payload):
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let body = try? encoder.encode(payload) else { return }
            _ = try? await client.post("/v1/agents/upsert", body: body)
        case .remove(let agentID):
            _ = try? await client.delete("/v1/agents/\(escapePathComponent(agentID))")
        }
    }

    /// Agent IDs routinely contain "/" (project paths) — `.urlPathAllowed`
    /// keeps "/" literal, which would splinter the ID across route segments.
    static func escapePathComponent(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }

    // MARK: - Connection

    private static func client(from flags: Flags, needsToken: Bool) throws -> HTTPClient {
        let handshake = CLIHandshakeFile.read(from: CLIHandshakeFile.defaultURL())
        let environment = ProcessInfo.processInfo.environment

        let port = flags.value("port").flatMap(Int.init)
            ?? environment["AIPULSE_PORT"].flatMap(Int.init)
            ?? handshake?.port
            ?? 7455
        let token = environment["AIPULSE_TOKEN"] ?? handshake?.token

        if needsToken, token == nil {
            throw CLIError("""
            no credentials found. Launch AI Pulse once so it writes \
            \(CLIHandshakeFile.defaultURL().path), or set AIPULSE_TOKEN.
            """)
        }
        return HTTPClient(port: port, token: token)
    }

    private static func print(response: (status: Int, body: String)) {
        Swift.print(response.body)
        if !(200..<300).contains(response.status) {
            exit(1)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("aipulse: \(message)\n".utf8))
        exit(1)
    }

    private static let usage = """
    usage:
      aipulse health
      aipulse agents
      aipulse agent upsert --id ID --name NAME --state STATE [options]
      aipulse agent update --id ID --state STATE [options]
      aipulse agent remove --id ID

    options:
      --provider P       --instance NAME    --icon SFSYMBOL
      --message TEXT     --project-name N   --project-path PATH
      --sequence N       --open-url URL     --open-label TEXT
      --activate-app BUNDLE_ID              --port N

    states: idle, working, waitingForInput, approvalRequired,
            completed, failed, disconnected, unknown
    """
}
