import Foundation

/// Transport-level payload checks, applied before the reducer. The reducer
/// silently drops unsafe actions for defense in depth, but the API rejects
/// them loudly so integration authors notice.
public enum RequestValidator {
    public static let maxBodyBytes = 131_072

    /// Returns a machine-readable error reason, or nil when acceptable.
    public static func validate(_ payload: AgentEventPayload, pathAgentID: String? = nil) -> String? {
        if let pathAgentID, payload.agent.id != pathAgentID {
            return "agentIDMismatch"
        }
        if let action = payload.action, action.type == "openURL" {
            guard let raw = action.url, let url = URL(string: raw), URLSafety.isSafe(url) else {
                return "unsafeActionURL"
            }
        }
        return nil
    }
}
