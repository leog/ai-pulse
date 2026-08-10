import Foundation

/// Maps Claude Code hook events (delivered as JSON on stdin to a command
/// hook) into normalized AI Pulse protocol events.
///
/// Built against the documented hook lifecycle (code.claude.com/docs/en/
/// hooks.md, July 2026):
/// - `SessionStart` (`source`: new/resume/…) → idle
/// - `UserPromptSubmit` → working (turn started)
/// - `PreToolUse`/`PostToolUse` (`tool_name`) → working
/// - `PermissionRequest` → approvalRequired
/// - `Notification` with `notification_type == "permission_prompt"` →
///   approvalRequired; `"idle_prompt"` → waitingForInput; other
///   notification types are ignored
/// - `Stop` → completed; `StopFailure` (turn ended on API error) → failed
/// - `SessionEnd` (`session_end_reason`) → remove the agent
///
/// Privacy: only Claude-Code-generated metadata crosses this boundary —
/// event name, tool *name*, and notification text. Prompt content
/// (`user_prompt`), tool inputs/outputs, and assistant messages are never
/// decoded, so they can never be published.
public enum ClaudeCodeAdapter {
    /// Subset of hook stdin fields the adapter consumes. Unknown fields are
    /// ignored by Codable, which is the privacy boundary described above.
    public struct HookInput: Codable, Sendable {
        public var hook_event_name: String
        public var session_id: String?
        public var cwd: String?
        public var source: String?
        public var notification_type: String?
        public var message: String?
        public var tool_name: String?
        public var session_end_reason: String?

        public init(
            hook_event_name: String,
            session_id: String? = nil,
            cwd: String? = nil,
            source: String? = nil,
            notification_type: String? = nil,
            message: String? = nil,
            tool_name: String? = nil,
            session_end_reason: String? = nil
        ) {
            self.hook_event_name = hook_event_name
            self.session_id = session_id
            self.cwd = cwd
            self.source = source
            self.notification_type = notification_type
            self.message = message
            self.tool_name = tool_name
            self.session_end_reason = session_end_reason
        }
    }

    public enum Mapped: Sendable, Equatable {
        case publish(AgentEventPayload)
        case remove(agentID: String)
    }

    /// One agent per session per project: two Claude Code sessions in
    /// different repositories are distinct pill entries.
    public static func agentID(sessionID: String?, cwd: String?) -> String {
        "claude-code:\(cwd ?? "unknown"):\(sessionID ?? "unknown")"
    }

    public static func map(
        _ input: HookInput,
        environment: [String: String] = [:],
        sourceProcessID: Int32? = nil,
        now: Date = Date()
    ) -> Mapped? {
        let id = agentID(sessionID: input.session_id, cwd: input.cwd)

        let state: AgentState
        let message: String?
        switch input.hook_event_name {
        case "SessionStart":
            state = .idle
            message = input.source == "resume" ? "Session resumed" : "Session started"
        case "UserPromptSubmit":
            state = .working
            message = "Working on a prompt"
        case "PreToolUse":
            state = .working
            message = input.tool_name.map { "Running \($0)" } ?? "Running a tool"
        case "PostToolUse":
            state = .working
            message = input.tool_name.map { "Finished \($0)" } ?? "Working"
        case "PermissionRequest":
            state = .approvalRequired
            message = input.tool_name.map { "Approval required: \($0)" } ?? "Approval required"
        case "Notification":
            switch input.notification_type {
            case "permission_prompt":
                state = .approvalRequired
                message = input.message ?? "Approval required"
            case "idle_prompt":
                state = .waitingForInput
                message = input.message ?? "Waiting for your input"
            default:
                // auth_success and friends are not agent status.
                return nil
            }
        case "Stop":
            state = .completed
            message = "Turn finished"
        case "StopFailure":
            state = .failed
            message = "Turn failed"
        case "SessionEnd":
            return .remove(agentID: id)
        default:
            // SubagentStop, PreCompact, and future events carry no
            // top-level status the pill should reflect.
            return nil
        }

        let instance = input.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }

        // GUI-launched processes carry the host app's bundle identifier;
        // it gives the pill a safe "bring my terminal forward" action.
        var action: AgentEventPayload.ActionDescriptor?
        if let bundleID = environment["__CFBundleIdentifier"], !bundleID.isEmpty {
            action = .init(type: "activateApplication", bundleIdentifier: bundleID)
        }

        let payload = AgentEventPayload(
            agent: .init(
                id: id,
                name: "Claude Code",
                provider: "anthropic",
                instance: instance
            ),
            state: state,
            message: message,
            project: input.cwd.map { .init(name: instance, path: $0) },
            action: action,
            occurredAt: now,
            sequence: Int(now.timeIntervalSince1970 * 1000),
            pid: sourceProcessID.map(Int.init)
        )
        return .publish(payload)
    }
}
