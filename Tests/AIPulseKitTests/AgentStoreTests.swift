import XCTest
@testable import AIPulseKit

@MainActor
final class AgentStoreTests: XCTestCase {
    private func agent(
        _ id: String,
        state: AgentState,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> Agent {
        Agent(
            id: id,
            displayName: id,
            provider: "test",
            state: state,
            lastUpdatedAt: updatedAt,
            stateChangedAt: updatedAt
        )
    }

    func testUpsertInsertsAndReplaces() {
        let store = AgentStore()
        store.upsert(agent("a", state: .working))
        XCTAssertEqual(store.allSorted.count, 1)

        store.upsert(agent("a", state: .completed))
        XCTAssertEqual(store.allSorted.count, 1)
        XCTAssertEqual(store.agent(id: "a")?.state, .completed)
    }

    func testStateChangeStampsTransitionAndResetsAcknowledgement() {
        let store = AgentStore()
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)

        store.upsert(agent("a", state: .working, updatedAt: t1))
        store.acknowledge(id: "a")
        XCTAssertTrue(store.agent(id: "a")!.isAcknowledged)

        var update = agent("a", state: .waitingForInput, updatedAt: t2)
        update.stateChangedAt = t2
        store.upsert(update)

        let stored = store.agent(id: "a")!
        XCTAssertEqual(stored.stateChangedAt, t2)
        XCTAssertFalse(stored.isAcknowledged, "new state must demand fresh attention")
    }

    func testSameStateUpdatePreservesTransitionTimeAndAcknowledgement() {
        let store = AgentStore()
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)

        store.upsert(agent("a", state: .working, updatedAt: t1))
        store.acknowledge(id: "a")
        store.upsert(agent("a", state: .working, updatedAt: t2))

        let stored = store.agent(id: "a")!
        XCTAssertEqual(stored.stateChangedAt, t1, "no transition on same-state refresh")
        XCTAssertTrue(stored.isAcknowledged)
        XCTAssertEqual(stored.lastUpdatedAt, t2)
    }

    func testMutedAgentsHiddenFromPillButKeptInList() {
        let store = AgentStore()
        store.upsert(agent("a", state: .working))
        store.upsert(agent("b", state: .failed))
        store.setMuted(id: "b", muted: true)

        XCTAssertEqual(store.pillAgents.map(\.id), ["a"])
        XCTAssertEqual(store.allSorted.count, 2)
    }

    func testMuteSurvivesUpsert() {
        let store = AgentStore()
        store.upsert(agent("a", state: .working))
        store.setMuted(id: "a", muted: true)
        store.upsert(agent("a", state: .failed))
        XCTAssertTrue(store.agent(id: "a")!.isMuted)
    }

    func testVisibleAgentsOverflow() {
        let store = AgentStore()
        for i in 0..<9 {
            store.upsert(agent("agent-\(i)", state: .working))
        }
        let slice = store.visibleAgents(maxCount: 6)
        XCTAssertEqual(slice.visible.count, 6)
        XCTAssertEqual(slice.overflow, 3)

        let noOverflow = store.visibleAgents(maxCount: 20)
        XCTAssertEqual(noOverflow.visible.count, 9)
        XCTAssertEqual(noOverflow.overflow, 0)
    }

    func testRemove() {
        let store = AgentStore()
        store.upsert(agent("a", state: .working))
        store.remove(id: "a")
        XCTAssertTrue(store.allSorted.isEmpty)
    }
}
