import Darwin
import Foundation

/// Cheap local-process liveness via `kill(pid, 0)`. Signal 0 delivers
/// nothing; it only performs the existence/permission check.
public enum ProcessLiveness {
    /// True when a process with `pid` exists. EPERM still means "exists" —
    /// only ESRCH proves the process is gone, so any other failure counts
    /// as alive and never demotes an agent on shaky evidence.
    public static func isAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }
}
