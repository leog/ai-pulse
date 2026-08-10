import XCTest
@testable import AIPulseKit

final class StatusPriorityTests: XCTestCase {
    private func agent(
        _ id: String,
        _ state: AgentState,
        changedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> Agent {
        Agent(id: id, displayName: id, provider: "test", state: state, stateChangedAt: changedAt)
    }

    func testUrgencyRankOrder() {
        let expected: [AgentState] = [
            .approvalRequired, .waitingForInput, .failed, .working,
            .completed, .disconnected, .idle, .unknown,
        ]
        for (index, state) in expected.enumerated() {
            XCTAssertEqual(StatusPriority.rank(state), index, "rank(\(state))")
        }
    }

    func testSortOrdersAllStatesByUrgency() {
        let shuffled: [Agent] = [
            agent("a", .idle), agent("b", .completed), agent("c", .approvalRequired),
            agent("d", .unknown), agent("e", .working), agent("f", .failed),
            agent("g", .disconnected), agent("h", .waitingForInput),
        ]
        let sorted = StatusPriority.sort(shuffled).map(\.state)
        XCTAssertEqual(sorted, [
            .approvalRequired, .waitingForInput, .failed, .working,
            .completed, .disconnected, .idle, .unknown,
        ])
    }

    func testSamePrioritySortsByMostRecentTransition() {
        let older = agent("older", .working, changedAt: Date(timeIntervalSince1970: 100))
        let newer = agent("newer", .working, changedAt: Date(timeIntervalSince1970: 200))
        let sorted = StatusPriority.sort([older, newer])
        XCTAssertEqual(sorted.map(\.id), ["newer", "older"])
    }

    func testEqualPriorityAndTimestampIsStableByID() {
        let ts = Date(timeIntervalSince1970: 500)
        let agents = [agent("charlie", .working, changedAt: ts),
                      agent("alpha", .working, changedAt: ts),
                      agent("bravo", .working, changedAt: ts)]
        let once = StatusPriority.sort(agents)
        let twice = StatusPriority.sort(once.shuffled())
        XCTAssertEqual(once.map(\.id), ["alpha", "bravo", "charlie"])
        XCTAssertEqual(once.map(\.id), twice.map(\.id), "sort must be deterministic")
    }
}
