import XCTest
@testable import AIPulseKit

final class DockTileAggregatorTests: XCTestCase {
    private func agent(_ id: String, _ state: AgentState, acknowledged: Bool = false) -> Agent {
        Agent(id: id, displayName: id, provider: "test", state: state, isAcknowledged: acknowledged)
    }

    func testNoAgentsIsNeutral() {
        XCTAssertEqual(DockTileAggregator.summarize([]), DockTileSummary(emphasis: .neutral, urgentCount: 0))
    }

    func testIdleAndCompletedAreNeutral() {
        let summary = DockTileAggregator.summarize([agent("a", .idle), agent("b", .completed), agent("c", .disconnected)])
        XCTAssertEqual(summary.emphasis, .neutral)
        XCTAssertEqual(summary.urgentCount, 0)
    }

    func testWorkingEmphasis() {
        let summary = DockTileAggregator.summarize([agent("a", .working), agent("b", .idle)])
        XCTAssertEqual(summary.emphasis, .working)
    }

    func testAttentionBeatsWorking() {
        let summary = DockTileAggregator.summarize([agent("a", .working), agent("b", .waitingForInput)])
        XCTAssertEqual(summary.emphasis, .attention)
        XCTAssertEqual(summary.urgentCount, 1)
    }

    func testFailureBeatsAttention() {
        let summary = DockTileAggregator.summarize([
            agent("a", .waitingForInput), agent("b", .failed), agent("c", .approvalRequired),
        ])
        XCTAssertEqual(summary.emphasis, .failure)
        XCTAssertEqual(summary.urgentCount, 3)
    }

    func testAcknowledgedAgentsDoNotCount() {
        let summary = DockTileAggregator.summarize([
            agent("a", .failed, acknowledged: true),
            agent("b", .waitingForInput, acknowledged: true),
            agent("c", .working),
        ])
        XCTAssertEqual(summary.emphasis, .working)
        XCTAssertEqual(summary.urgentCount, 0)
    }
}
