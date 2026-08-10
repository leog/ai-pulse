import XCTest
@testable import AIPulseKit

/// End-to-end integration tests: real loopback listener, real URLSession
/// requests, real AgentStore behind main-actor handlers.
final class LocalHTTPServerTests: XCTestCase {
    private static let token = "test-token-1234567890"

    private var server: LocalHTTPServer!
    private var store: AgentStore!
    private var port: UInt16 = 0

    @MainActor
    override func setUp() async throws {
        // No super.setUp() call: awaiting the nonisolated async variant from
        // @MainActor sends non-Sendable `self` across executors, which newer
        // Swift 6 toolchains reject; XCTest's default implementation is empty.
        let store = AgentStore()
        self.store = store
        server = LocalHTTPServer(
            configuration: .init(port: 0, token: Self.token),
            handlers: .init(
                applyEvent: { payload in
                    await MainActor.run { store.apply(payload) }
                },
                removeAgent: { id in
                    await MainActor.run {
                        guard store.agent(id: id) != nil else { return false }
                        store.remove(id: id)
                        return true
                    }
                },
                listAgents: {
                    await MainActor.run { store.allSorted }
                }
            )
        )
        port = try await server.start()
        XCTAssertGreaterThan(port, 0)
    }

    override func tearDown() {
        server?.stop()
        super.tearDown()
    }

    // MARK: - Helpers

    private func request(
        _ method: String,
        _ path: String,
        token: String? = LocalHTTPServerTests.token,
        body: Data? = nil
    ) async throws -> (status: Int, json: [String: Any]) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 5
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (status, json)
    }

    private func eventBody(
        id: String = "test:agent:1",
        state: AgentState = .working,
        sequence: Int? = nil,
        action: AgentEventPayload.ActionDescriptor? = nil,
        version: Int = 1
    ) throws -> Data {
        let payload = AgentEventPayload(
            version: version,
            agent: .init(id: id, name: "Test Agent", provider: "test"),
            state: state,
            message: "hello",
            action: action,
            occurredAt: Date(),
            sequence: sequence
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    // MARK: - Tests

    func testHealthRequiresNoAuth() async throws {
        let (status, json) = try await request("GET", "/v1/health", token: nil)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["status"] as? String, "ok")
    }

    func testMissingTokenRejected() async throws {
        let (status, json) = try await request("GET", "/v1/agents", token: nil)
        XCTAssertEqual(status, 401)
        XCTAssertEqual(json["error"] as? String, "unauthorized")
    }

    func testWrongTokenRejected() async throws {
        let (status, _) = try await request("GET", "/v1/agents", token: "wrong-token-000000000")
        XCTAssertEqual(status, 401)
    }

    func testUpsertUpdatesStore() async throws {
        let (status, json) = try await request("POST", "/v1/agents/upsert", body: eventBody(state: .waitingForInput))
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["applied"] as? String, "true")
        let store = self.store!
        let state = await MainActor.run { store.agent(id: "test:agent:1")?.state }
        XCTAssertEqual(state, .waitingForInput)
    }

    func testEventRouteMatchesPathID() async throws {
        let (okStatus, _) = try await request(
            "POST", "/v1/agents/test:agent:1/event",
            body: eventBody(id: "test:agent:1")
        )
        XCTAssertEqual(okStatus, 200)

        let (mismatch, json) = try await request(
            "POST", "/v1/agents/other:agent/event",
            body: eventBody(id: "test:agent:1", sequence: 99)
        )
        XCTAssertEqual(mismatch, 400)
        XCTAssertEqual(json["error"] as? String, "agentIDMismatch")
    }

    func testDuplicateSequenceReportedNotApplied() async throws {
        _ = try await request("POST", "/v1/agents/upsert", body: eventBody(state: .working, sequence: 5))
        let (status, json) = try await request("POST", "/v1/agents/upsert", body: eventBody(state: .failed, sequence: 5))
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["applied"] as? String, "false")
        XCTAssertEqual(json["reason"] as? String, "duplicateSequence")
        let store = self.store!
        let state = await MainActor.run { store.agent(id: "test:agent:1")?.state }
        XCTAssertEqual(state, .working, "duplicate must not change state")
    }

    func testInvalidJSONRejected() async throws {
        let (status, json) = try await request("POST", "/v1/agents/upsert", body: Data("{not json".utf8))
        XCTAssertEqual(status, 400)
        XCTAssertEqual(json["error"] as? String, "invalidJSON")
    }

    func testUnsafeActionURLRejected() async throws {
        let action = AgentEventPayload.ActionDescriptor(type: "openURL", label: "x", url: "file:///etc/passwd")
        let (status, json) = try await request("POST", "/v1/agents/upsert", body: eventBody(action: action))
        XCTAssertEqual(status, 400)
        XCTAssertEqual(json["error"] as? String, "unsafeActionURL")
        let store = self.store!
        let missing = await MainActor.run { store.agent(id: "test:agent:1") == nil }
        XCTAssertTrue(missing)
    }

    func testUnsupportedVersionRejected() async throws {
        let (status, json) = try await request("POST", "/v1/agents/upsert", body: eventBody(version: 9))
        XCTAssertEqual(status, 400)
        XCTAssertEqual(json["error"] as? String, "unsupportedVersion")
    }

    func testListAgents() async throws {
        _ = try await request("POST", "/v1/agents/upsert", body: eventBody())
        let (status, json) = try await request("GET", "/v1/agents")
        XCTAssertEqual(status, 200)
        let agents = json["agents"] as? [[String: Any]]
        XCTAssertEqual(agents?.count, 1)
        XCTAssertEqual(agents?.first?["id"] as? String, "test:agent:1")
    }

    func testDeleteAgent() async throws {
        _ = try await request("POST", "/v1/agents/upsert", body: eventBody())
        let (status, json) = try await request("DELETE", "/v1/agents/test:agent:1")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["removed"] as? String, "true")

        let (again, json2) = try await request("DELETE", "/v1/agents/test:agent:1")
        XCTAssertEqual(again, 200)
        XCTAssertEqual(json2["removed"] as? String, "false")
    }

    func testDeleteAgentWithSlashesInID() async throws {
        // Real agent IDs embed project paths: "claude-code:/Users/x/proj:s1".
        let id = "claude-code:/Users/leo/src/proj:s1"
        _ = try await request("POST", "/v1/agents/upsert", body: eventBody(id: id))
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let escaped = id.addingPercentEncoding(withAllowedCharacters: allowed)!
        let (status, json) = try await request("DELETE", "/v1/agents/\(escaped)")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["removed"] as? String, "true")
    }

    func testOversizedBodyRejected() async throws {
        let huge = Data(repeating: 0x61, count: RequestValidator.maxBodyBytes + 1024)
        do {
            let (status, _) = try await request("POST", "/v1/agents/upsert", body: huge)
            XCTAssertEqual(status, 413)
        } catch {
            // Acceptable: server may cut the connection while URLSession is
            // still streaming the oversized body.
        }
    }

    func testUnknownRouteIs404() async throws {
        let (status, _) = try await request("GET", "/v1/nonsense")
        XCTAssertEqual(status, 404)
    }
}

final class HTTPMessageParserTests: XCTestCase {
    func testParsesPostWithBody() {
        let raw = "POST /v1/agents/upsert HTTP/1.1\r\nContent-Length: 5\r\nAuthorization: Bearer abc\r\n\r\nhello"
        guard case let .request(request) = HTTPMessageParser.parse(Data(raw.utf8), maxBodyBytes: 1024) else {
            return XCTFail("expected parsed request")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/agents/upsert")
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), "hello")
    }

    func testIncompleteBodyWaits() {
        let raw = "POST /x HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"
        XCTAssertEqual(HTTPMessageParser.parse(Data(raw.utf8), maxBodyBytes: 1024), .incomplete)
    }

    func testDeclaredBodyOverCapIsInvalid() {
        let raw = "POST /x HTTP/1.1\r\nContent-Length: 999999\r\n\r\n"
        XCTAssertEqual(HTTPMessageParser.parse(Data(raw.utf8), maxBodyBytes: 1024), .invalid)
    }

    func testGarbageRequestLineIsInvalid() {
        let raw = "NOT-HTTP\r\n\r\n"
        XCTAssertEqual(HTTPMessageParser.parse(Data(raw.utf8), maxBodyBytes: 1024), .invalid)
    }

    func testHandshakeFileRoundTripWithPermissions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aipulse-hs-\(UUID().uuidString)")
            .appendingPathComponent("cli.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let handshake = CLIHandshake(port: 7455, token: "secret")
        try CLIHandshakeFile.write(handshake, to: url)
        XCTAssertEqual(CLIHandshakeFile.read(from: url), handshake)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.int16Value, 0o600)
    }
}
