import XCTest
@testable import AIPulseKit

final class ClaudeCodeAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_753_900_000)

    private func input(
        _ event: String,
        sessionID: String? = "s1",
        cwd: String? = "/Users/leo/src/symphony",
        source: String? = nil,
        notificationType: String? = nil,
        message: String? = nil,
        toolName: String? = nil
    ) -> ClaudeCodeAdapter.HookInput {
        .init(
            hook_event_name: event,
            session_id: sessionID,
            cwd: cwd,
            source: source,
            notification_type: notificationType,
            message: message,
            tool_name: toolName
        )
    }

    private func published(_ mapped: ClaudeCodeAdapter.Mapped?) -> AgentEventPayload? {
        if case let .publish(payload) = mapped { return payload }
        return nil
    }

    func testAgentIDIsPerSessionPerProject() {
        let a = ClaudeCodeAdapter.map(input("Stop", sessionID: "s1"), now: now)
        let b = ClaudeCodeAdapter.map(input("Stop", sessionID: "s2"), now: now)
        let c = ClaudeCodeAdapter.map(input("Stop", sessionID: "s1", cwd: "/other"), now: now)
        XCTAssertNotEqual(published(a)?.agent.id, published(b)?.agent.id)
        XCTAssertNotEqual(published(a)?.agent.id, published(c)?.agent.id)
        XCTAssertEqual(published(a)?.agent.id, "claude-code:/Users/leo/src/symphony:s1")
    }

    func testLifecycleStateMapping() {
        XCTAssertEqual(published(ClaudeCodeAdapter.map(input("SessionStart"), now: now))?.state, .idle)
        XCTAssertEqual(published(ClaudeCodeAdapter.map(input("UserPromptSubmit"), now: now))?.state, .working)
        XCTAssertEqual(published(ClaudeCodeAdapter.map(input("PreToolUse", toolName: "Bash"), now: now))?.state, .working)
        XCTAssertEqual(published(ClaudeCodeAdapter.map(input("PermissionRequest", toolName: "Bash"), now: now))?.state, .approvalRequired)
        XCTAssertEqual(published(ClaudeCodeAdapter.map(input("Stop"), now: now))?.state, .completed)
        XCTAssertEqual(published(ClaudeCodeAdapter.map(input("StopFailure"), now: now))?.state, .failed)
    }

    func testSessionStartResume() {
        let mapped = ClaudeCodeAdapter.map(input("SessionStart", source: "resume"), now: now)
        XCTAssertEqual(published(mapped)?.message, "Session resumed")
    }

    func testNotificationTypeDistinguishesPermissionFromIdle() {
        let permission = ClaudeCodeAdapter.map(
            input("Notification", notificationType: "permission_prompt", message: "Claude needs your permission to use Bash"),
            now: now
        )
        XCTAssertEqual(published(permission)?.state, .approvalRequired)
        XCTAssertEqual(published(permission)?.message, "Claude needs your permission to use Bash")

        let idle = ClaudeCodeAdapter.map(
            input("Notification", notificationType: "idle_prompt"),
            now: now
        )
        XCTAssertEqual(published(idle)?.state, .waitingForInput)

        let auth = ClaudeCodeAdapter.map(
            input("Notification", notificationType: "auth_success"),
            now: now
        )
        XCTAssertNil(auth, "non-status notifications must be ignored")
    }

    func testSessionEndRemoves() {
        let mapped = ClaudeCodeAdapter.map(input("SessionEnd"), now: now)
        XCTAssertEqual(mapped, .remove(agentID: "claude-code:/Users/leo/src/symphony:s1"))
    }

    func testIrrelevantEventsIgnored() {
        for event in ["SubagentStop", "PreCompact", "MessageDisplay", "SomeFutureEvent"] {
            XCTAssertNil(ClaudeCodeAdapter.map(input(event), now: now), event)
        }
    }

    func testHostAppBecomesActivateAction() {
        let mapped = ClaudeCodeAdapter.map(
            input("UserPromptSubmit"),
            environment: ["__CFBundleIdentifier": "com.googlecode.iterm2"],
            now: now
        )
        XCTAssertEqual(published(mapped)?.action?.type, "activateApplication")
        XCTAssertEqual(published(mapped)?.action?.bundleIdentifier, "com.googlecode.iterm2")
    }

    func testIdentityAndProjectMetadata() {
        let payload = published(ClaudeCodeAdapter.map(input("UserPromptSubmit"), now: now))
        XCTAssertEqual(payload?.agent.name, "Claude Code")
        XCTAssertEqual(payload?.agent.provider, "anthropic")
        XCTAssertEqual(payload?.agent.instance, "symphony")
        XCTAssertEqual(payload?.project?.path, "/Users/leo/src/symphony")
        XCTAssertEqual(payload?.sequence, Int(now.timeIntervalSince1970 * 1000))
    }

    /// The privacy boundary: prompt content, tool inputs, and assistant
    /// output are not even decoded, so they can never be republished.
    func testPromptAndToolContentNeverCrossTheBoundary() throws {
        let raw = """
        {
          "hook_event_name": "UserPromptSubmit",
          "session_id": "s1",
          "cwd": "/tmp/proj",
          "user_prompt": "SECRET PROMPT CONTENT",
          "tool_input": {"command": "SECRET COMMAND"},
          "last_assistant_message": "SECRET RESPONSE"
        }
        """
        let input = try JSONDecoder().decode(ClaudeCodeAdapter.HookInput.self, from: Data(raw.utf8))
        guard let payload = published(ClaudeCodeAdapter.map(input, now: now)) else {
            return XCTFail("expected publish")
        }
        let encoded = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("SECRET"), "no prompt/tool/response content may be published")
    }

    /// Store-level integration: a full hook lifecycle drives one agent
    /// through the normalized states.
    @MainActor
    func testLifecycleThroughStore() {
        let store = AgentStore()
        var clock = now

        func fire(_ hookInput: ClaudeCodeAdapter.HookInput) {
            clock = clock.addingTimeInterval(1)
            switch ClaudeCodeAdapter.map(hookInput, now: clock) {
            case .publish(let payload): store.apply(payload)
            case .remove(let id): store.remove(id: id)
            case nil: break
            }
        }

        fire(input("SessionStart"))
        let id = "claude-code:/Users/leo/src/symphony:s1"
        XCTAssertEqual(store.agent(id: id)?.state, .idle)

        fire(input("UserPromptSubmit"))
        XCTAssertEqual(store.agent(id: id)?.state, .working)

        fire(input("Notification", notificationType: "permission_prompt", message: "Permission?"))
        XCTAssertEqual(store.agent(id: id)?.state, .approvalRequired)

        fire(input("PreToolUse", toolName: "Bash"))
        XCTAssertEqual(store.agent(id: id)?.state, .working)

        fire(input("Stop"))
        XCTAssertEqual(store.agent(id: id)?.state, .completed)
        XCTAssertEqual(store.agent(id: id)?.integrationLevel, .interactiveLifecycle)

        fire(input("SessionEnd"))
        XCTAssertNil(store.agent(id: id))
    }

    // MARK: - Source PID

    func testSourceProcessIDPublishedWhenKnown() {
        let mapped = ClaudeCodeAdapter.map(input("PreToolUse", toolName: "Bash"), sourceProcessID: 4321, now: now)
        XCTAssertEqual(published(mapped)?.pid, 4321)

        let without = ClaudeCodeAdapter.map(input("PreToolUse", toolName: "Bash"), now: now)
        XCTAssertNil(published(without)?.pid)
    }

    // MARK: - Ancestry resolution

    func testStableAncestorSkipsShellWrappers() {
        // hook (900) ← zsh wrapper (800) ← claude (700) ← Terminal (600)
        let table: [pid_t: ProcessAncestry.Info] = [
            900: .init(parentID: 800, command: "aipulse"),
            800: .init(parentID: 700, command: "zsh"),
            700: .init(parentID: 600, command: "claude"),
        ]
        XCTAssertEqual(ProcessAncestry.stableAncestor(from: 800, lookup: { table[$0] }), 700)
        XCTAssertEqual(ProcessAncestry.stableAncestor(from: 700, lookup: { table[$0] }), 700)
    }

    func testStableAncestorGivesUpRatherThanGuessing() {
        // Reparented to launchd, or a lookup dead-end: no PID at all.
        let orphaned: [pid_t: ProcessAncestry.Info] = [800: .init(parentID: 1, command: "zsh")]
        XCTAssertNil(ProcessAncestry.stableAncestor(from: 800, lookup: { orphaned[$0] }))
        XCTAssertNil(ProcessAncestry.stableAncestor(from: 800, lookup: { _ in nil }))
    }
}
