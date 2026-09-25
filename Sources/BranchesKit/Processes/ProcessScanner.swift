import AppKit
import Darwin
import Foundation

public struct ProcessRecord: Sendable, Equatable {
    public var pid: Int32
    public var ppid: Int32
    public var startedAt: Date
    public var tty: String?
    public var uid: uid_t
    public var command: String
}

/// Abstracts the OS process table so status logic can be tested with fakes.
public protocol ProcessTable: Sendable {
    func snapshot() -> [Int32: ProcessRecord]
    func workingDirectory(of pid: Int32) -> String?
}

/// Reads the process table with `sysctl` + `libproc`. Needs no special permission for
/// the user's own processes (the app is not sandboxed).
public struct DarwinProcessTable: ProcessTable {
    public init() {}

    public func snapshot() -> [Int32: ProcessRecord] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [:] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = procs.count * stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [:] }

        var result: [Int32: ProcessRecord] = [:]
        result.reserveCapacity(size / stride)
        for p in procs.prefix(size / stride) {
            let pid = p.kp_proc.p_pid
            let tv = p.kp_proc.p_un.__p_starttime
            let dev = p.kp_eproc.e_tdev
            var tty: String?
            if dev != -1, let name = devname(dev, S_IFCHR) {
                tty = String(cString: name)
            }
            let command = withUnsafeBytes(of: p.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            result[pid] = ProcessRecord(
                pid: pid,
                ppid: p.kp_eproc.e_ppid,
                startedAt: Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1e6),
                tty: tty,
                uid: p.kp_eproc.e_ucred.cr_uid,
                command: command
            )
        }
        return result
    }

    public func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Finds the GUI app a process runs inside by walking up its parents.
public enum HostResolver {
    public static func host(of pid: Int32, in table: [Int32: ProcessRecord]) -> HostApp? {
        var current = table[pid]?.ppid ?? 0
        var sawTmux = false
        for _ in 0..<32 where current > 1 {
            if let record = table[current] {
                if record.command.hasPrefix("tmux") { sawTmux = true }
            }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return HostApp(
                    kind: HostKind.from(bundleID: app.bundleIdentifier),
                    name: app.localizedName ?? app.bundleIdentifier ?? "App",
                    bundleID: app.bundleIdentifier,
                    pid: current
                )
            }
            guard let next = table[current]?.ppid, next != current else { break }
            current = next
        }
        // A tmux server is reparented to launchd, so there's no terminal above it.
        return sawTmux ? HostApp(kind: .tmux, name: "tmux") : nil
    }
}
