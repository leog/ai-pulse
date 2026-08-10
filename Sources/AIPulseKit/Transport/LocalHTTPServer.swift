import Foundation
import Network
import os

/// Loopback-only HTTP service for local agent integrations.
///
/// Security posture:
/// - binds to the loopback interface only (`requiredInterfaceType = .loopback`)
///   and additionally rejects any connection whose remote endpoint is not
///   loopback,
/// - requires `Authorization: Bearer <token>` on every route except
///   `GET /v1/health`,
/// - caps header and body sizes,
/// - never logs tokens or event message content,
/// - passes payloads through `RequestValidator` + `AgentReducer`; nothing in
///   a payload is ever interpreted as a command.
public final class LocalHTTPServer: @unchecked Sendable {
    public struct Handlers: Sendable {
        public var applyEvent: @Sendable (AgentEventPayload) async -> AgentReducer.Outcome
        public var removeAgent: @Sendable (String) async -> Bool
        public var listAgents: @Sendable () async -> [Agent]

        public init(
            applyEvent: @escaping @Sendable (AgentEventPayload) async -> AgentReducer.Outcome,
            removeAgent: @escaping @Sendable (String) async -> Bool,
            listAgents: @escaping @Sendable () async -> [Agent]
        ) {
            self.applyEvent = applyEvent
            self.removeAgent = removeAgent
            self.listAgents = listAgents
        }
    }

    public struct Configuration: Sendable {
        /// 0 requests an ephemeral port; `start()` returns the bound port.
        public var port: UInt16
        public var token: String
        public var maxBodyBytes: Int

        public init(port: UInt16, token: String, maxBodyBytes: Int = RequestValidator.maxBodyBytes) {
            self.port = port
            self.token = token
            self.maxBodyBytes = maxBodyBytes
        }
    }

    private let configuration: Configuration
    private let handlers: Handlers
    private let queue = DispatchQueue(label: "me.leog.aipulse.server")
    private let logger = Logger(subsystem: "me.leog.aipulse", category: "server")
    private var listener: NWListener?
    /// Keeps in-flight connections alive; queue-confined.
    private var activeHandlers: [ObjectIdentifier: ConnectionHandler] = [:]

    public init(configuration: Configuration, handlers: Handlers) {
        self.configuration = configuration
        self.handlers = handlers
    }

    /// Starts listening; returns the bound port.
    public func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: configuration.port) else {
            throw ServerError.invalidPort
        }
        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            @Sendable func resumeOnce(_ body: () -> Void) {
                let first = resumed.withLock { alreadyResumed in
                    if alreadyResumed { return false }
                    alreadyResumed = true
                    return true
                }
                if first { body() }
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    resumeOnce { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    self?.logger.error("listener failed: \(error.localizedDescription, privacy: .public)")
                    resumeOnce { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    public enum ServerError: Error {
        case invalidPort
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        guard Self.isLoopback(connection.endpoint) else {
            logger.warning("rejected non-loopback connection")
            connection.cancel()
            return
        }
        let handler = ConnectionHandler(
            connection: connection,
            queue: queue,
            maxBodyBytes: configuration.maxBodyBytes
        ) { [weak self] request, respond in
            guard let self else {
                respond(HTTPResponseBuilder.response(status: 503, reason: "Service Unavailable", jsonBody: nil))
                return
            }
            Task {
                respond(await self.route(request))
            }
        }
        handler.onFinish = { [weak self] finished in
            self?.activeHandlers.removeValue(forKey: ObjectIdentifier(finished))
        }
        // accept() and onFinish both run on `queue`.
        activeHandlers[ObjectIdentifier(handler)] = handler
        handler.begin()
    }

    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback || address.asIPv4?.isLoopback == true
        case .name(let name, _): return name == "localhost"
        @unknown default: return false
        }
    }

    // MARK: - Routing

    private func route(_ request: HTTPRequest) async -> Data {
        let segments = request.path.split(separator: "/").map(String.init)

        if request.method == "GET", request.path == "/v1/health" {
            return Self.json(200, "OK", ["status": "ok", "protocolVersion": "\(AgentReducer.supportedVersion)"])
        }

        guard isAuthorized(request) else {
            return Self.json(401, "Unauthorized", ["error": "unauthorized"])
        }

        switch (request.method, segments.count) {
        case ("GET", 2) where segments == ["v1", "agents"]:
            let agents = await handlers.listAgents()
            return Self.encode(200, "OK", AgentsResponse(agents: agents))

        case ("POST", 3) where segments[0] == "v1" && segments[1] == "agents" && segments[2] == "upsert":
            return await handleEvent(request, pathAgentID: nil)

        case ("POST", 4) where segments[0] == "v1" && segments[1] == "agents" && segments[3] == "event":
            let id = segments[2].removingPercentEncoding ?? segments[2]
            return await handleEvent(request, pathAgentID: id)

        case ("DELETE", 3) where segments[0] == "v1" && segments[1] == "agents":
            let id = segments[2].removingPercentEncoding ?? segments[2]
            let removed = await handlers.removeAgent(id)
            return Self.json(200, "OK", ["removed": removed ? "true" : "false"])

        default:
            return Self.json(404, "Not Found", ["error": "unknownRoute"])
        }
    }

    private func handleEvent(_ request: HTTPRequest, pathAgentID: String?) async -> Data {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(AgentEventPayload.self, from: request.body) else {
            return Self.json(400, "Bad Request", ["error": "invalidJSON"])
        }
        if let reason = RequestValidator.validate(payload, pathAgentID: pathAgentID) {
            return Self.json(400, "Bad Request", ["error": reason])
        }

        switch await handlers.applyEvent(payload) {
        case .applied:
            logger.info("event applied agent=\(payload.agent.id, privacy: .public) state=\(payload.state.rawValue, privacy: .public)")
            return Self.json(200, "OK", ["applied": "true"])
        case .rejected(let rejection):
            switch rejection {
            case .unsupportedVersion, .invalidAgentID:
                return Self.json(400, "Bad Request", ["error": rejection.rawValue])
            case .duplicateSequence, .outdatedSequence, .outdatedTimestamp:
                // Not client errors — duplicates and stragglers are normal.
                return Self.json(200, "OK", ["applied": "false", "reason": rejection.rawValue])
            }
        }
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard let header = request.headers["authorization"],
              header.hasPrefix("Bearer ") else { return false }
        let presented = String(header.dropFirst("Bearer ".count))
        // Constant-time-ish comparison; both sides are fixed-length tokens.
        guard presented.utf8.count == configuration.token.utf8.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(presented.utf8, configuration.token.utf8) {
            difference |= a ^ b
        }
        return difference == 0
    }

    // MARK: - Encoding helpers

    struct AgentsResponse: Codable {
        var agents: [Agent]
    }

    private static func json(_ status: Int, _ reason: String, _ fields: [String: String]) -> Data {
        let body = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return HTTPResponseBuilder.response(status: status, reason: reason, jsonBody: body)
    }

    private static func encode(_ status: Int, _ reason: String, _ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let body = try? encoder.encode(value)
        return HTTPResponseBuilder.response(status: status, reason: reason, jsonBody: body)
    }
}

/// Reads one HTTP request off a connection, hands it to the router, writes
/// the response, and closes. State is confined to the server's serial queue.
private final class ConnectionHandler: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let maxBodyBytes: Int
    private let onRequest: (HTTPRequest, @escaping @Sendable (Data) -> Void) -> Void

    private var buffer = Data()
    private var finished = false
    /// Called exactly once, on the server queue, when the connection closes.
    var onFinish: ((ConnectionHandler) -> Void)?

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        maxBodyBytes: Int,
        onRequest: @escaping (HTTPRequest, @escaping @Sendable (Data) -> Void) -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.maxBodyBytes = maxBodyBytes
        self.onRequest = onRequest
    }

    func begin() {
        connection.start(queue: queue)
        // Slow-client guard: a request must complete within 15 seconds.
        queue.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
            self.connection.cancel()
        }
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data {
                self.buffer.append(data)
            }
            if error != nil {
                self.finish()
                return
            }
            switch HTTPMessageParser.parse(self.buffer, maxBodyBytes: self.maxBodyBytes) {
            case .incomplete:
                if isComplete {
                    self.finish()
                } else if self.buffer.count > HTTPMessageParser.maxHeaderBytes + self.maxBodyBytes {
                    self.respond(HTTPResponseBuilder.response(status: 413, reason: "Payload Too Large", jsonBody: nil))
                } else {
                    self.receive()
                }
            case .invalid:
                // Includes declared bodies beyond the cap.
                self.respond(HTTPResponseBuilder.response(status: 413, reason: "Payload Too Large", jsonBody: nil))
            case .request(let request):
                self.onRequest(request) { [weak self] response in
                    self?.queue.async {
                        self?.respond(response)
                    }
                }
            }
        }
    }

    private func respond(_ data: Data) {
        guard !finished else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.finish()
        })
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        connection.cancel()
        onFinish?(self)
        onFinish = nil
    }
}
