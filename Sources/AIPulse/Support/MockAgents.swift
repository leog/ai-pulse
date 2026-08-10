import Foundation
import AIPulseKit

/// Milestone 1 mock data: three agent instances in distinct states.
@MainActor
enum MockAgents {
    static func seed(into store: AgentStore) {
        let now = Date()

        store.upsert(Agent(
            id: "claude-code:ai-pulse:session-1",
            displayName: "Claude Code",
            provider: "anthropic",
            instanceName: "ai-pulse",
            iconSystemName: "terminal",
            state: .working,
            taskSummary: "Implementing Dock placement",
            projectName: "ai-pulse",
            projectPath: NSHomeDirectory() + "/Developer/_workvane/ai-pulse",
            sourceApplicationBundleID: "com.apple.Terminal",
            lastUpdatedAt: now.addingTimeInterval(-15),
            stateChangedAt: now.addingTimeInterval(-180),
            integrationLevel: .interactiveLifecycle
        ))

        store.upsert(Agent(
            id: "codex:symphony:session-7",
            displayName: "Codex",
            provider: "openai",
            instanceName: "symphony",
            iconSystemName: "chevron.left.forwardslash.chevron.right",
            state: .waitingForInput,
            taskSummary: "Waiting for permission to run the test suite",
            projectName: "Symphony",
            sourceApplicationBundleID: "com.microsoft.VSCode",
            lastUpdatedAt: now.addingTimeInterval(-60),
            stateChangedAt: now.addingTimeInterval(-60),
            deepLink: URL(string: "aipulse://agent/codex:symphony:session-7"),
            integrationLevel: .interactiveLifecycle
        ))

        store.upsert(Agent(
            id: "openclaw:home:session-3",
            displayName: "OpenClaw",
            provider: "openclaw",
            instanceName: "home",
            iconSystemName: "pawprint",
            state: .failed,
            taskSummary: "Build failed: exit code 1",
            lastUpdatedAt: now.addingTimeInterval(-600),
            stateChangedAt: now.addingTimeInterval(-600),
            integrationLevel: .activityLifecycle
        ))
    }
}
