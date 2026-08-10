import XCTest
@testable import AIPulseKit

final class AgentReducerTests: XCTestCase {
    private func payload(
        id: String = "claude-code:proj:s1",
        state: AgentState = .working,
        message: String? = nil,
        sequence: Int? = nil,
        occurredAt: Date = Date(timeIntervalSince1970: 1_000),
        version: Int = 1,
        action: AgentEventPayload.ActionDescriptor? = nil
    ) -> AgentEventPayload {
        AgentEventPayload(
            version: version,
            agent: .init(id: id, name: "Claude Code", provider: "anthropic", instance: "proj"),
            state: state,
            message: message,
            action: action,
            occurredAt: occurredAt,
            sequence: sequence
        )
    }

    private func applied(_ outcome: AgentReducer.Outcome) -> Agent? {
        if case let .applied(agent) = outcome { return agent }
        return nil
    }

    // MARK: - Sequencing

    func testHigherSequenceApplied() {
        let first = applied(AgentReducer.reduce(existing: nil, event: payload(sequence: 1)))!
        let outcome = AgentReducer.reduce(existing: first, event: payload(state: .completed, sequence: 2))
        XCTAssertEqual(applied(outcome)?.state, .completed)
        XCTAssertEqual(applied(outcome)?.lastSequence, 2)
    }

    func testDuplicateSequenceRejected() {
        let first = applied(AgentReducer.reduce(existing: nil, event: payload(sequence: 5)))!
        let outcome = AgentReducer.reduce(existing: first, event: payload(state: .failed, sequence: 5))
        XCTAssertEqual(outcome, .rejected(.duplicateSequence))
    }

    func testLowerSequenceRejected() {
        let first = applied(AgentReducer.reduce(existing: nil, event: payload(sequence: 5)))!
        let outcome = AgentReducer.reduce(existing: first, event: payload(state: .failed, sequence: 3))
        XCTAssertEqual(outcome, .rejected(.outdatedSequence))
    }

    func testOlderTimestampRejectedWithoutSequences() {
        let t1 = Date(timeIntervalSince1970: 2_000)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let first = applied(AgentReducer.reduce(existing: nil, event: payload(occurredAt: t1)))!
        let outcome = AgentReducer.reduce(existing: first, event: payload(state: .failed, occurredAt: t0))
        XCTAssertEqual(outcome, .rejected(.outdatedTimestamp))
    }

    func testSequencedEventAcceptedWhenExistingHasNoSequence() {
        // Adopting sequences mid-stream must not be treated as out-of-order.
        let old = Date(timeIntervalSince1970: 2_000)
        let first = applied(AgentReducer.reduce(existing: nil, event: payload(occurredAt: old)))!
        let outcome = AgentReducer.reduce(
            existing: first,
            event: payload(state: .completed, sequence: 1, occurredAt: Date(timeIntervalSince1970: 1_500))
        )
        XCTAssertEqual(applied(outcome)?.state, .completed)
    }

    // MARK: - Validation

    func testUnsupportedVersionRejected() {
        let outcome = AgentReducer.reduce(existing: nil, event: payload(version: 2))
        XCTAssertEqual(outcome, .rejected(.unsupportedVersion))
    }

    func testInvalidAgentIDsRejected() {
        XCTAssertEqual(AgentReducer.reduce(existing: nil, event: payload(id: "")), .rejected(.invalidAgentID))
        XCTAssertEqual(
            AgentReducer.reduce(existing: nil, event: payload(id: String(repeating: "x", count: 300))),
            .rejected(.invalidAgentID)
        )
        XCTAssertEqual(
            AgentReducer.reduce(existing: nil, event: payload(id: "bad\u{0000}id")),
            .rejected(.invalidAgentID)
        )
    }

    func testOverlongStringsAreCapped() {
        let long = String(repeating: "m", count: 900)
        let agent = applied(AgentReducer.reduce(existing: nil, event: payload(message: long)))!
        XCTAssertEqual(agent.taskSummary?.count, AgentReducer.maxMessageLength)
    }

    // MARK: - Action mapping

    func testUnsafeActionURLDroppedButEventApplied() {
        let action = AgentEventPayload.ActionDescriptor(type: "openURL", label: "Open", url: "file:///etc/passwd")
        let agent = applied(AgentReducer.reduce(existing: nil, event: payload(action: action)))
        XCTAssertNotNil(agent, "event itself is valid")
        XCTAssertNil(agent?.action, "unsafe action must be dropped")
    }

    func testSafeActionMapped() {
        let action = AgentEventPayload.ActionDescriptor(type: "openURL", label: "Open", url: "aipulse://agent/x")
        let agent = applied(AgentReducer.reduce(existing: nil, event: payload(action: action)))!
        guard case let .openURL(url, label)? = agent.action else { return XCTFail("expected openURL") }
        XCTAssertEqual(url.absoluteString, "aipulse://agent/x")
        XCTAssertEqual(label, "Open")
    }

    func testUnknownActionTypeDropped() {
        let action = AgentEventPayload.ActionDescriptor(type: "runShellCommand", label: "rm -rf /", url: nil)
        let agent = applied(AgentReducer.reduce(existing: nil, event: payload(action: action)))!
        XCTAssertNil(agent.action)
    }

    // MARK: - Integration level

    func testIntegrationLevelInferredAndNeverDowngraded() {
        let waiting = applied(AgentReducer.reduce(existing: nil, event: payload(state: .waitingForInput, sequence: 1)))!
        XCTAssertEqual(waiting.integrationLevel, .interactiveLifecycle)

        let laterWorking = applied(AgentReducer.reduce(existing: waiting, event: payload(state: .working, sequence: 2)))!
        XCTAssertEqual(laterWorking.integrationLevel, .interactiveLifecycle, "level must not downgrade")
    }

    // MARK: - Store integration

    @MainActor
    func testStoreApplyRespectsSequencingAndAcknowledgement() {
        let store = AgentStore()
        store.apply(payload(state: .waitingForInput, sequence: 1))
        store.acknowledge(id: "claude-code:proj:s1")

        // Duplicate: no change, acknowledgement intact.
        let dup = store.apply(payload(state: .failed, sequence: 1))
        XCTAssertEqual(dup, .rejected(.duplicateSequence))
        XCTAssertEqual(store.agent(id: "claude-code:proj:s1")?.state, .waitingForInput)
        XCTAssertTrue(store.agent(id: "claude-code:proj:s1")!.isAcknowledged)

        // Real transition: state moves, acknowledgement resets.
        store.apply(payload(state: .working, sequence: 2))
        let agent = store.agent(id: "claude-code:proj:s1")!
        XCTAssertEqual(agent.state, .working)
        XCTAssertFalse(agent.isAcknowledged)
    }
}
