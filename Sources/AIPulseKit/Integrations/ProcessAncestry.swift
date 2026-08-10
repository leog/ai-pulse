import Darwin
import Foundation

/// Resolves which ancestor process actually *is* the agent. Hook commands
/// may run under transient `sh -c` wrappers whose PIDs die with the hook;
/// publishing one of those as the agent's PID would demote a healthy agent
/// on the next liveness sweep.
public enum ProcessAncestry {
    /// Shell basenames that indicate a wrapper, not the agent itself.
    static let shellNames: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "csh", "tcsh"]

    public struct Info: Sendable, Equatable {
        public var parentID: pid_t
        public var command: String

        public init(parentID: pid_t, command: String) {
            self.parentID = parentID
            self.command = command
        }
    }

    /// Parent PID and command name via sysctl; nil when the process is gone.
    public static func info(for pid: pid_t) -> Info? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &proc, &size, nil, 0) == 0, size > 0 else { return nil }
        let command = withUnsafeBytes(of: proc.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return Info(parentID: proc.kp_eproc.e_ppid, command: command)
    }

    /// Nearest ancestor of `pid` (inclusive) that is not a shell wrapper.
    /// Returns nil rather than guessing when the walk dead-ends — no PID is
    /// safer than a transient one. `lookup` is injectable for tests.
    public static func stableAncestor(
        from pid: pid_t,
        maxHops: Int = 5,
        lookup: (pid_t) -> Info? = info(for:)
    ) -> pid_t? {
        var current = pid
        for _ in 0..<maxHops {
            guard current > 1, let info = lookup(current) else { return nil }
            if !shellNames.contains(info.command) { return current }
            current = info.parentID
        }
        return nil
    }
}
