import BranchesKit
import Foundation

/// Made-up sessions for `--demo` (screenshots, UI work without real agents running).
enum DemoData {
    static func snapshot(now: Date = Date()) -> StoreSnapshot {
        func session(
            _ provider: ProviderID, _ id: String, project: String, title: String,
            _ display: DisplayStatus, ago: TimeInterval, activity: String? = nil,
            attention: AttentionReason? = nil, host: HostKind = .terminal, tty: String? = nil,
            worktree: String? = nil
        ) -> SessionSnapshot {
            let path = "/Users/demo/code/\(project)"
            let hostName = host == .ghostty ? "Ghostty" : "Terminal"
            return SessionSnapshot(
                id: SessionKey(provider, id),
                projectName: project,
                projectPath: path,
                worktree: worktree,
                cwd: worktree.map { "\(path)/.claude/worktrees/\($0)" } ?? path,
                title: title,
                activity: activity,
                status: StatusResult(display, .reported, since: now - ago, reason: "demo", attention: attention),
                host: HostApp(kind: host, name: hostName),
                tty: tty,
                resumeCommand: provider == .claude ? "claude --resume \(id)" : "codex resume \(id)",
                // Quiet sessions stopped when their status began; live ones were active just now.
                lastActivityAt: display == .idle || display == .done ? now - ago : now - min(ago, 5)
            )
        }

        let sessions = [
            session(.claude, "a1", project: "personal-ai", title: "Build the authentication flow",
                    .working, ago: 102, activity: "Editing AuthController.swift", tty: "ttys003"),
            session(.codex, "a2", project: "personal-ai", title: "Fix Gmail parser",
                    .needsYou, ago: 12, activity: "Running a command", attention: .permission, host: .ghostty),
            session(.claude, "a3", project: "personal-ai", title: "Refactor settings screen",
                    .done, ago: 190, tty: "ttys005", worktree: "settings-redesign"),
            session(.codex, "b1", project: "portfolio", title: "Fix responsive nav on mobile",
                    .working, ago: 250, activity: "Editing files", tty: "ttys007"),
            session(.claude, "b2", project: "portfolio", title: "Add dark mode to case studies",
                    .idle, ago: 2 * 3600, tty: "ttys002"),
            session(.claude, "d1", project: "dotfiles", title: "Tidy zsh startup",
                    .done, ago: 25 * 60, tty: "ttys011"),
            session(.codex, "e1", project: "recipe-box", title: "Import recipes from CSV",
                    .idle, ago: 5 * 3600, tty: "ttys012"),
            session(.claude, "c1", project: "api-server", title: "Migrate to Postgres 17",
                    .needsYou, ago: 40, attention: .error, tty: "ttys009"),
            session(.claude, "c2", project: "api-server", title: "Write integration tests for billing",
                    .working, ago: 31, activity: "Run the test suite", tty: "ttys010"),
        ]
        let diagnostics = [
            ProviderDiagnostics(provider: .claude, root: "~/.claude"),
            ProviderDiagnostics(provider: .codex, root: "~/.codex"),
        ]
        return StoreSnapshot(sessions: sessions, diagnostics: diagnostics)
    }
}
