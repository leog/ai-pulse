import XCTest
@testable import AIPulseKit

final class LightAggregatorTests: XCTestCase {
    private func agent(_ id: String, _ state: AgentState, acknowledged: Bool = false) -> Agent {
        Agent(id: id, displayName: id, provider: "test", state: state, isAcknowledged: acknowledged)
    }

    func testOffWhenNoAgents() {
        XCTAssertEqual(LightAggregator.signal(for: []), .off)
    }

    func testIdleWhenAgentsPresentButInactive() {
        XCTAssertEqual(
            LightAggregator.signal(for: [agent("a", .idle), agent("b", .disconnected), agent("c", .unknown)]),
            .idle
        )
    }

    func testWorkingBeatsIdleAndSuccess() {
        XCTAssertEqual(
            LightAggregator.signal(for: [agent("a", .completed), agent("b", .working), agent("c", .idle)]),
            .working
        )
    }

    func testSuccessWhenCompletedAndNothingActive() {
        XCTAssertEqual(
            LightAggregator.signal(for: [agent("a", .completed), agent("b", .idle)]),
            .success
        )
    }

    func testAttentionBeatsWorking() {
        XCTAssertEqual(
            LightAggregator.signal(for: [agent("a", .working), agent("b", .waitingForInput)]),
            .attention
        )
        XCTAssertEqual(
            LightAggregator.signal(for: [agent("a", .working), agent("b", .approvalRequired)]),
            .attention
        )
    }

    func testFailureBeatsEverything() {
        XCTAssertEqual(
            LightAggregator.signal(for: [
                agent("a", .working), agent("b", .waitingForInput), agent("c", .failed),
            ]),
            .failure
        )
    }

    func testAcknowledgedAttentionAndFailureDoNotSignal() {
        XCTAssertEqual(
            LightAggregator.signal(for: [
                agent("a", .failed, acknowledged: true),
                agent("b", .waitingForInput, acknowledged: true),
                agent("c", .working),
            ]),
            .working
        )
    }

    @MainActor
    func testAcknowledgeAllClearsAttention() {
        let store = AgentStore()
        store.upsert(agent("a", .waitingForInput))
        store.upsert(agent("b", .failed))
        store.upsert(agent("c", .working))
        XCTAssertEqual(LightAggregator.signal(for: store.allSorted), .failure)

        store.acknowledgeAll()
        XCTAssertEqual(LightAggregator.signal(for: store.allSorted), .working)
        XCTAssertTrue(store.allSorted.allSatisfy(\.isAcknowledged))
    }
}
