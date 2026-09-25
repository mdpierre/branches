import AppKit
import BranchesKit
import Observation
import SwiftUI

struct ProjectGroup: Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var rows: [Row]
    var endedCount: Int

    /// A session plus its visual depth (subagents are indented under their parent).
    struct Row: Identifiable {
        var session: SessionSnapshot
        var depth: Int
        var id: SessionKey { session.id }
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: StoreSnapshot = .empty
    var selection: SessionKey?
    var filter = ""
    var toast: String?
    var expandedEnded: Set<String> = []
    var showEnded: Bool {
        didSet { UserDefaults.standard.set(showEnded, forKey: "showEnded") }
    }

    let store = SessionStore()
    private var toastTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        showEnded = UserDefaults.standard.bool(forKey: "showEnded")
    }

    func start() {
        let store = store
        Task {
            await store.start()
            for await next in store.updates {
                self.snapshot = next
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { await store.rescan() }
        })
    }

    // MARK: Derived

    var groups: [ProjectGroup] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = snapshot.sessions.filter { s in
            needle.isEmpty || s.projectName.lowercased().contains(needle) || s.title.lowercased().contains(needle)
        }
        let byProject = Dictionary(grouping: visible, by: \.projectPath)
        var groups: [ProjectGroup] = byProject.map { path, sessions in
            let live = sessions.filter { $0.status.display != .ended }
            let ended = sessions.filter { $0.status.display == .ended }
            let showAll = showEnded || expandedEnded.contains(path)
            let recentEnded = ended.filter { Date().timeIntervalSince($0.status.since) < 30 * 60 }
            let shown = live + (showAll ? ended : recentEnded)
            return ProjectGroup(
                name: sessions.first?.projectName ?? "Unknown",
                path: path,
                rows: Self.tree(shown.sorted(by: Self.order)),
                endedCount: ended.count - (showAll ? ended.count : recentEnded.count)
            )
        }
        // A project whose sessions all ended a while ago is noise; hide it entirely.
        groups.removeAll { $0.rows.isEmpty }
        // Two different folders with the same name: add the parent folder to tell them apart.
        let names = Dictionary(grouping: groups.indices, by: { groups[$0].name })
        for (_, indices) in names where indices.count > 1 {
            for i in indices {
                let parent = ((groups[i].path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                if !parent.isEmpty { groups[i].name += " (\(parent))" }
            }
        }
        groups.sort { a, b in
            let ra = a.rows.map(\.session.status.display).min() ?? .ended
            let rb = b.rows.map(\.session.status.display).min() ?? .ended
            if ra != rb { return ra < rb }
            let la = a.rows.map(\.session.lastActivityAt).max() ?? .distantPast
            let lb = b.rows.map(\.session.lastActivityAt).max() ?? .distantPast
            return la > lb
        }
        return groups
    }

    var flatRows: [SessionSnapshot] { groups.flatMap { $0.rows.map(\.session) } }

    var needsYouCount: Int { snapshot.sessions.filter { $0.status.display == .needsYou }.count }
    var workingCount: Int { snapshot.sessions.filter { $0.status.display == .working }.count }

    private static func order(_ a: SessionSnapshot, _ b: SessionSnapshot) -> Bool {
        if a.status.display != b.status.display { return a.status.display < b.status.display }
        return (a.status.since, a.id.id) > (b.status.since, b.id.id)
    }

    /// Places each child directly under its parent. Children only show while active.
    private static func tree(_ sessions: [SessionSnapshot]) -> [ProjectGroup.Row] {
        let keys = Set(sessions.map(\.id))
        let children = Dictionary(grouping: sessions.filter { $0.parent.map(keys.contains) == true }, by: { $0.parent! })
        var rows: [ProjectGroup.Row] = []
        for s in sessions where s.parent.map(keys.contains) != true {
            rows.append(.init(session: s, depth: 0))
            for c in children[s.id] ?? [] where c.status.display == .working || c.status.display == .needsYou {
                rows.append(.init(session: c, depth: 1))
            }
        }
        return rows
    }

    // MARK: Actions

    func jump(_ session: SessionSnapshot) {
        selection = session.id
        let outcome = FocusService.jump(to: session)
        if let message = outcome.message { show(message) }
        let store = store
        Task { await store.markSeen(session.id) }
    }

    func openFolder(_ session: SessionSnapshot) { FocusService.openFolder(session) }

    func copyResume(_ session: SessionSnapshot) {
        if FocusService.copyResume(session) == .copiedResume { show("Resume command copied.") }
    }

    func copySessionID(_ session: SessionSnapshot) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.id.id, forType: .string)
        show("Session ID copied.")
    }

    var selectedSession: SessionSnapshot? {
        flatRows.first { $0.id == selection }
    }

    func moveSelection(_ delta: Int) {
        let rows = flatRows
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : rows.count)
        selection = rows[max(0, min(rows.count - 1, index + delta))].id
    }

    func cycleNeedsYou() {
        let waiting = flatRows.filter { $0.status.display == .needsYou }
        guard !waiting.isEmpty else { return }
        let index = waiting.firstIndex { $0.id == selection } ?? -1
        selection = waiting[(index + 1) % waiting.count].id
    }

    func jumpToNeedsYou(_ n: Int) {
        let waiting = flatRows.filter { $0.status.display == .needsYou }
        if n < waiting.count { jump(waiting[n]) }
    }

    private func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled { toast = nil }
        }
    }
}
