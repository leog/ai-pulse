import XCTest
@testable import AIPulseKit

final class StalenessTests: XCTestCase {
    private let config = StalenessConfiguration(workingStaleAfter: 600, completedRemovalDelay: 60)
    private let epoch = Date(timeIntervalSince1970: 10_000)

    private func agent(_ id: String, _ state: AgentState, updatedAt: Date, expiresAt: Date? = nil) -> Agent {
        Agent(
            id: id,
            displayName: id,
            provider: "test",
            state: state,
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
    func testRemoveClearsStaleMark() {
        let store = AgentStore()
        store.upsert(agent("a", .working, updatedAt: epoch))
        store.sweep(at: epoch.addingTimeInterval(700), configuration: config)
        store.remove(id: "a")
        XCTAssertTrue(store.staleAgentIDs.isEmpty)
    }
}
