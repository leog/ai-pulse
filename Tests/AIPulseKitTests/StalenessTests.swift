import XCTest
@testable import AIPulseKit

final class StalenessTests: XCTestCase {
    private let config = StalenessConfiguration(workingStaleAfter: 600, completedRemovalDelay: 60)
    private let epoch = Date(timeIntervalSince1970: 10_000)

    private func agent(
        _ id: String,
        _ state: AgentState,
        updatedAt: Date,
        expiresAt: Date? = nil,
        pid: Int32? = nil
    ) -> Agent {
        Agent(
            id: id,
            displayName: id,
            provider: "test",
            state: state,
            sourceProcessID: pid,
            lastUpdatedAt: updatedAt,
            stateChangedAt: updatedAt,
            expiresAt: expiresAt
        )
    }

    // MARK: - Stale (working, silent)

    func testWorkingAgentStaleAtThreshold() {
        let working = agent("a", .working, updatedAt: epoch)
        XCTAssertFalse(StalenessPolicy.isStale(working, at: epoch.addingTimeInterval(599), configuration: config))
        XCTAssertTrue(StalenessPolicy.isStale(working, at: epoch.addingTimeInterval(600), configuration: config))
    }

    func testNonWorkingStatesAreNeverStale() {
        let longAgo = epoch.addingTimeInterval(100_000)
        for state in AgentState.allCases where state != .working {
            let a = agent("a", state, updatedAt: epoch)
            XCTAssertFalse(StalenessPolicy.isStale(a, at: longAgo, configuration: config), "\(state)")
        }
    }

    // MARK: - Disconnection (working, silent too long)

    func testWorkingAgentDisconnectsAtThreshold() {
        let config = StalenessConfiguration(workingDisconnectAfter: 1800)
        let working = agent("a", .working, updatedAt: epoch)
        XCTAssertFalse(StalenessPolicy.shouldDisconnect(working, at: epoch.addingTimeInterval(1799), configuration: config))
        XCTAssertTrue(StalenessPolicy.shouldDisconnect(working, at: epoch.addingTimeInterval(1800), configuration: config))
    }

    func testNeverDisconnectsWhenThresholdIsNil() {
        let never = StalenessConfiguration(workingDisconnectAfter: nil)
        let working = agent("a", .working, updatedAt: epoch)
        XCTAssertFalse(StalenessPolicy.shouldDisconnect(working, at: epoch.addingTimeInterval(1_000_000), configuration: never))
    }

    func testNonWorkingStatesNeverDisconnectOnTimer() {
        let longAgo = epoch.addingTimeInterval(1_000_000)
        for state in AgentState.allCases where state != .working {
            let a = agent("a", state, updatedAt: epoch)
            XCTAssertFalse(StalenessPolicy.shouldDisconnect(a, at: longAgo, configuration: config), "\(state)")
        }
    }

    // MARK: - Expiration

    func testCompletedExpiresAfterDelay() {
        let completed = agent("a", .completed, updatedAt: epoch)
        XCTAssertFalse(StalenessPolicy.shouldExpire(completed, at: epoch.addingTimeInterval(59), configuration: config))
        XCTAssertTrue(StalenessPolicy.shouldExpire(completed, at: epoch.addingTimeInterval(60), configuration: config))
    }

    func testCompletedNeverExpiresWhenDelayIsNil() {
        let never = StalenessConfiguration(workingStaleAfter: 600, completedRemovalDelay: nil)
        let completed = agent("a", .completed, updatedAt: epoch)
        XCTAssertFalse(StalenessPolicy.shouldExpire(completed, at: epoch.addingTimeInterval(1_000_000), configuration: never))
    }

    func testAttentionStatesNeverExpireOnTimers() {
        let longAgo = epoch.addingTimeInterval(1_000_000)
        for state in [AgentState.waitingForInput, .approvalRequired, .failed] {
            let a = agent("a", state, updatedAt: epoch)
            XCTAssertFalse(StalenessPolicy.shouldExpire(a, at: longAgo, configuration: config), "\(state)")
        }
    }

    func testSourceProvidedExpirationHonored() {
        let expiry = epoch.addingTimeInterval(120)
        let waiting = agent("a", .waitingForInput, updatedAt: epoch, expiresAt: expiry)
        XCTAssertFalse(StalenessPolicy.shouldExpire(waiting, at: expiry.addingTimeInterval(-1), configuration: config))
        XCTAssertTrue(StalenessPolicy.shouldExpire(waiting, at: expiry, configuration: config))
    }

    // MARK: - Store sweep

    @MainActor
    func testSweepRemovesExpiredAndMarksStale() {
        let store = AgentStore()
        store.upsert(agent("stale-working", .working, updatedAt: epoch))
        store.upsert(agent("fresh-working", .working, updatedAt: epoch.addingTimeInterval(500)))
        store.upsert(agent("old-completed", .completed, updatedAt: epoch))
        store.upsert(agent("waiting", .waitingForInput, updatedAt: epoch))

        store.sweep(at: epoch.addingTimeInterval(700), configuration: config)

        XCTAssertNil(store.agent(id: "old-completed"), "completed past delay is removed")
        XCTAssertNotNil(store.agent(id: "waiting"), "waiting never auto-expires")
        XCTAssertEqual(store.staleAgentIDs, ["stale-working"])
    }

    @MainActor
    func testStaleClearsAfterFreshUpdate() {
        let store = AgentStore()
        store.upsert(agent("a", .working, updatedAt: epoch))
        store.sweep(at: epoch.addingTimeInterval(700), configuration: config)
        XCTAssertEqual(store.staleAgentIDs, ["a"])

        store.upsert(agent("a", .working, updatedAt: epoch.addingTimeInterval(700)))
        store.sweep(at: epoch.addingTimeInterval(710), configuration: config)
        XCTAssertTrue(store.staleAgentIDs.isEmpty)
    }

    @MainActor
    func testSweepDisconnectsAgentWithDeadProcessImmediately() {
        let store = AgentStore()
        store.upsert(agent("dead", .working, updatedAt: epoch, pid: 101))
        store.upsert(agent("alive", .working, updatedAt: epoch, pid: 102))

        store.sweep(at: epoch.addingTimeInterval(30), configuration: config, isProcessAlive: { $0 == 102 })

        XCTAssertEqual(store.agent(id: "dead")?.state, .disconnected)
        XCTAssertEqual(store.agent(id: "dead")?.stateChangedAt, epoch.addingTimeInterval(30))
        XCTAssertEqual(store.agent(id: "alive")?.state, .working)
    }

    @MainActor
    func testSweepLeavesAttentionStatesAloneWhenProcessDies() {
        let store = AgentStore()
        store.upsert(agent("waiting", .waitingForInput, updatedAt: epoch, pid: 101))
        store.upsert(agent("approval", .approvalRequired, updatedAt: epoch, pid: 101))
        store.upsert(agent("failed", .failed, updatedAt: epoch, pid: 101))

        store.sweep(at: epoch.addingTimeInterval(30), configuration: config, isProcessAlive: { _ in false })

        XCTAssertEqual(store.agent(id: "waiting")?.state, .waitingForInput)
        XCTAssertEqual(store.agent(id: "approval")?.state, .approvalRequired)
        XCTAssertEqual(store.agent(id: "failed")?.state, .failed)
    }

    @MainActor
    func testSweepDisconnectsSilentWorkingAgentWithoutPID() {
        let disconnectConfig = StalenessConfiguration(workingStaleAfter: 600, workingDisconnectAfter: 1800)
        let store = AgentStore()
        store.upsert(agent("silent", .working, updatedAt: epoch))

        store.sweep(at: epoch.addingTimeInterval(1799), configuration: disconnectConfig, isProcessAlive: { _ in true })
        XCTAssertEqual(store.agent(id: "silent")?.state, .working)
        XCTAssertEqual(store.staleAgentIDs, ["silent"])

        store.sweep(at: epoch.addingTimeInterval(1800), configuration: disconnectConfig, isProcessAlive: { _ in true })
        XCTAssertEqual(store.agent(id: "silent")?.state, .disconnected)
        XCTAssertTrue(store.staleAgentIDs.isEmpty, "disconnected agents are no longer stale-working")
    }

    @MainActor
    func testDisconnectedAgentRecoversOnFreshEvent() {
        let store = AgentStore()
        store.upsert(agent("a", .working, updatedAt: epoch, pid: 101))
        store.sweep(at: epoch.addingTimeInterval(30), configuration: config, isProcessAlive: { _ in false })
        XCTAssertEqual(store.agent(id: "a")?.state, .disconnected)

        store.apply(
            AgentEventPayload(
                agent: .init(id: "a", name: "a", provider: "test"),
                state: .working,
                occurredAt: epoch.addingTimeInterval(60),
                pid: 103
            )
        )
        XCTAssertEqual(store.agent(id: "a")?.state, .working)
        XCTAssertEqual(store.agent(id: "a")?.sourceProcessID, 103)
    }

    @MainActor
    func testRemoveClearsStaleMark() {
        let store = AgentStore()
        store.upsert(agent("a", .working, updatedAt: epoch))
        store.sweep(at: epoch.addingTimeInterval(700), configuration: config)
        store.remove(id: "a")
        XCTAssertTrue(store.staleAgentIDs.isEmpty)
    }
}
