import Foundation
import Darwin

/// Lightweight process info extracted via libproc.
struct TerminalProcessInfo {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let cpuUsage: Double       // percentage (0-100+)
    let memoryBytes: UInt64    // resident memory
    let startTime: Date?
    var children: [TerminalProcessInfo] = []
}

/// Inspects the process tree rooted at a given PID using libproc.
/// All calls work on the current user's processes — no entitlements needed.
final class ProcessMonitor {
    /// Get info for a single process.
    static func info(for pid: pid_t) -> TerminalProcessInfo? {
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(size))
        guard ret == size else { return nil }

        var bsdInfo = proc_bsdinfo()
        let bsdSize = MemoryLayout<proc_bsdinfo>.size
        let bsdRet = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(bsdSize))

        let name = processName(pid: pid)
        let ppid: pid_t = bsdRet == bsdSize ? pid_t(bsdInfo.pbi_ppid) : 0

        let cpuTime = Double(taskInfo.pti_total_user + taskInfo.pti_total_system) / 1_000_000_000.0
        let residentMem = UInt64(taskInfo.pti_resident_size)

        var startDate: Date?
        if bsdRet == bsdSize {
            let sec = Double(bsdInfo.pbi_start_tvsec) + Double(bsdInfo.pbi_start_tvusec) / 1_000_000.0
            if sec > 0 { startDate = Date(timeIntervalSince1970: sec) }
        }

        return TerminalProcessInfo(
            pid: pid, ppid: ppid, name: name,
            cpuUsage: cpuTime, memoryBytes: residentMem,
            startTime: startDate
        )
    }

    /// Build the full process tree rooted at `rootPID`.
    static func processTree(rootPID: pid_t) -> TerminalProcessInfo? {
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return nil }

        var pids = [pid_t](repeating: 0, count: Int(bufferSize))
        let actual = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard actual > 0 else { return nil }
        pids = Array(pids.prefix(Int(actual)))

        var parentMap: [pid_t: [pid_t]] = [:]
        var infoMap: [pid_t: TerminalProcessInfo] = [:]

        for pid in pids {
            guard let pi = info(for: pid) else { continue }
            infoMap[pid] = pi
            parentMap[pi.ppid, default: []].append(pid)
        }

        func buildTree(_ pid: pid_t) -> TerminalProcessInfo? {
            guard var node = infoMap[pid] else { return nil }
            let childPIDs = parentMap[pid] ?? []
            node.children = childPIDs.compactMap { buildTree($0) }
            return node
        }

        return buildTree(rootPID)
    }

    /// Flat list of all descendant PIDs (inclusive).
    static func allDescendants(of rootPID: pid_t) -> [pid_t] {
        guard let tree = processTree(rootPID: rootPID) else { return [rootPID] }
        var result: [pid_t] = []
        func collect(_ node: TerminalProcessInfo) {
            result.append(node.pid)
            for child in node.children { collect(child) }
        }
        collect(tree)
        return result
    }

    /// Public accessor for process name.
    static func processName(for pid: pid_t) -> String {
        processName(pid: pid)
    }

    /// Get the process name for a PID.
    private static func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_name(pid, &buffer, UInt32(buffer.count))
        if ret > 0 {
            return String(cString: buffer)
        }
        return kernProcName(pid: pid) ?? "Unknown"
    }

    private static func kernProcName(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        guard size > MemoryLayout<Int32>.size else { return nil }
        let pathStart = MemoryLayout<Int32>.size
        let pathBytes = buffer[pathStart...]
        guard let nullIdx = pathBytes.firstIndex(of: 0) else { return nil }
        let path = String(bytes: buffer[pathStart..<nullIdx], encoding: .utf8) ?? ""
        return (path as NSString).lastPathComponent
    }

    /// Get the current working directory for a process.
    static func workingDirectory(for pid: pid_t) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, Int32(size))
        guard ret == size else { return nil }
        return withUnsafePointer(to: vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    /// Format bytes as human-readable string.
    static func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.2f GB", gb)
    }

    /// Format a duration from a start date to now.
    static func formatUptime(from start: Date?) -> String {
        guard let start else { return "\u{2014}" }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 60 { return String(format: "%.0fs", elapsed) }
        if elapsed < 3600 { return String(format: "%.0fm", elapsed / 60) }
        return String(format: "%.1fh", elapsed / 3600)
    }
}
