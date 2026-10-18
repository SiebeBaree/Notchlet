import AppKit
import Darwin

/// LaunchServices puts `__CFBundleIdentifier` in the environment of
/// everything a GUI app starts and children inherit it, so the hook script
/// reports it directly. When it is missing (ssh, a launchd job) the parent
/// chain is walked to the first running app, the way CodexBar does.
enum HostApp {
    static func resolve(bundleID: String?, pid: pid_t) -> String? {
        if let bundleID, !bundleID.isEmpty {
            return bundleID
        }
        var current = pid
        var seen = Set<pid_t>()
        while current > 1, seen.insert(current).inserted {
            if let app = NSRunningApplication(processIdentifier: current), let id = app.bundleIdentifier {
                return id
            }
            guard let parent = parentPID(of: current) else { return nil }
            current = parent
        }
        return nil
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }
}
