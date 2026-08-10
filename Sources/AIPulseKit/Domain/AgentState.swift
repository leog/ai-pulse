import Foundation

/// Normalized state for any AI agent instance, regardless of vendor.
public enum AgentState: String, Codable, Sendable, CaseIterable, Hashable {
    case idle
    case working
    case waitingForInput
    case approvalRequired
    case completed
    case failed
    case disconnected
    case unknown
}

public extension AgentState {
    /// True for states that should remain visible until resolved or acknowledged.
    var requiresAttention: Bool {
        switch self {
        case .waitingForInput, .approvalRequired, .failed: true
        default: false
        }
    }

    /// Human-readable label, also used for VoiceOver.
    var displayLabel: String {
        switch self {
        case .idle: "idle"
        case .working: "working"
        case .waitingForInput: "waiting for input"
        case .approvalRequired: "approval required"
        case .completed: "completed"
        case .failed: "failed"
        case .disconnected: "disconnected"
        case .unknown: "state unknown"
        }
    }
}
