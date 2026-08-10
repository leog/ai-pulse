import XCTest
@testable import AIPulseKit

final class PersistenceTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aipulse-tests-\(UUID().uuidString)")
            .appendingPathComponent("agents.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    // Whole-second dates so the ISO 8601 round trip is exact.
    private func agent(_ id: String, _ state: AgentState, acknowledged: Bool = false) -> Agent {
        Agent(
            id: id,
            displayName: id,
            provider: "test",
            state: state,
            lastUpdatedAt: Date(timeIntervalSince1970: 5_000),
            stateChangedAt: Date(timeIntervalSince1970: 4_000),
            isAcknowledged: acknowledged,
            integrationLevel: .interactiveLifecycle,
            lastSequence: 7
        )
    }

    func testSaveLoadRoundTrip() {
        let store = PersistenceStore(fileURL: fileURL)
        let agents = [agent("a", .waitingForInput, acknowledged: true), agent("b", .failed)]
        store.save(agents)
        XCTAssertEqual(store.load(), agents)
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertEqual(PersistenceStore(fileURL: fileURL).load(), [])
    }

    func testCorruptFileLoadsEmpty() {
        let store = PersistenceStore(fileURL: fileURL)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data("not json{".utf8).write(to: fileURL)
        XCTAssertEqual(store.load(), [])
    }

    func testIncompatibleVersionLoadsEmpty() {
        let store = PersistenceStore(fileURL: fileURL)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let future = #"{"version": 99, "savedAt": "2026-07-31T00:00:00Z", "agents": []}"#
        try? Data(future.utf8).write(to: fileURL)
        XCTAssertEqual(store.load(), [])
    }

    // MARK: - Restore semantics

    func testRehydrateKeepsUnresolvedAttentionStates() {
        let now = Date(timeIntervalSince1970: 9_000)
        let restored = RestorePolicy.rehydrate(
            [agent("w", .waitingForInput, acknowledged: true), agent("f", .failed), agent("p", .approvalRequired)],
            at: now
        )
        XCTAssertEqual(restored.map(\.state), [.waitingForInput, .failed, .approvalRequired])
        XCTAssertTrue(restored[0].isAcknowledged, "acknowledgement survives restart")
        XCTAssertEqual(restored[0].stateChangedAt, Date(timeIntervalSince1970: 4_000), "original transition time kept")
    }

    func testRehydrateDowngradesLiveStatesToDisconnected() {
        let now = Date(timeIntervalSince1970: 9_000)
        let restored = RestorePolicy.rehydrate(
            [agent("w", .working), agent("i", .idle), agent("u", .unknown)],
            at: now
        )
        for a in restored {
            XCTAssertEqual(a.state, .disconnected)
            XCTAssertEqual(a.stateChangedAt, now)
        }
    }

    func testRehydrateKeepsCompletedForSweepToDecide() {
        let restored = RestorePolicy.rehydrate([agent("c", .completed)], at: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(restored[0].state, .completed)
    }

    // MARK: - End-to-end restart behavior

    @MainActor
    func testRestartRestoresUnresolvedStates() {
        let persistence = PersistenceStore(fileURL: fileURL)

        let first = AgentStore()
        first.upsert(agent("waiting", .waitingForInput))
        first.upsert(agent("working", .working))
        persistence.save(first.allSorted)

        let second = AgentStore()
        RestorePolicy.rehydrate(persistence.load(), at: Date(timeIntervalSince1970: 9_000))
            .forEach { second.upsert($0) }

        XCTAssertEqual(second.agent(id: "waiting")?.state, .waitingForInput)
        XCTAssertEqual(second.agent(id: "working")?.state, .disconnected)
    }
}
