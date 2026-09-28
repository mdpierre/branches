import Foundation

// MARK: - Activity tiers

/// Where a project sits in the list: what you're driving now, what you touched lately, and the rest.
public enum ActivityTier: Int, Sendable, Comparable, CaseIterable {
    /// Something is working or needs you.
    case active = 0
    /// Nothing running, but there was activity within `recentWindow`.
    case recent
    /// Quiet for longer than that.
    case background

    /// How long a quiet project counts as recent.
    public static let recentWindow: TimeInterval = 3600

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .active: "Active"
        case .recent: "Recent"
        case .background: "Background"
        }
    }

    /// The tier of a project, from all of its sessions.
    public static func of(_ sessions: [SessionSnapshot], now: Date) -> ActivityTier {
        if sessions.contains(where: { $0.status.display == .working || $0.status.display == .needsYou }) { return .active }
        let latest = sessions.map(\.lastActivityAt).max() ?? .distantPast
        return now.timeIntervalSince(latest) < recentWindow ? .recent : .background
    }
}

// MARK: - Project roots

public enum ProjectRoot {
    /// The folder a session belongs to: the nearest git root above `cwd` (stopping at `home`),
    /// or `cwd` itself. A linked worktree resolves to its main repository, and `worktree` names
    /// the worktree's folder. Submodules stay their own project.
    public static func resolve(cwd: String, home: String) -> (root: String, worktree: String?) {
        guard !cwd.isEmpty else { return ("", nil) }
        let fm = FileManager.default
        var dir = cwd
        while dir != "/" && dir != home && !dir.isEmpty {
            let git = dir + "/.git"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git, isDirectory: &isDir) {
                if !isDir.boolValue, let main = mainRepository(gitFile: git, in: dir) {
                    return (main, (dir as NSString).lastPathComponent)
                }
                return (dir, nil)
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return (cwd, nil)
    }

    /// A worktree's `.git` is a file: `gitdir: <main>/.git/worktrees/<name>`.
    private static func mainRepository(gitFile: String, in dir: String) -> String? {
        guard let text = try? String(contentsOfFile: gitFile, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first,
              line.hasPrefix("gitdir:")
        else { return nil }
        var gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitdir.hasPrefix("/") { gitdir = (dir as NSString).appendingPathComponent(gitdir) }
        gitdir = (gitdir as NSString).standardizingPath
        guard let range = gitdir.range(of: "/.git/worktrees/") else { return nil }
        let main = String(gitdir[..<range.lowerBound])
        return FileManager.default.fileExists(atPath: main + "/.git") ? main : nil
    }
}
