import Foundation

/// Owns the provider adapters, merges in process information, runs the status engine and
/// publishes immutable snapshots for the UI.
///
/// Event-driven: file events trigger ingestion. A single light tick (2 s while anything is
/// working or waiting, 15 s otherwise) catches process exits and time-based transitions.
public actor SessionStore {
    public nonisolated let updates: AsyncStream<StoreSnapshot>
    private let continuation: AsyncStream<StoreSnapshot>.Continuation

    private let adapters: [any ProviderAdapter]
    private let processes: any ProcessTable
    private let watcher = FileWatcher()
    private let defaults: UserDefaults?
    private let tuning: StatusEngine.Tuning

    private var procs: [Int32: ProcessRecord] = [:]
    private var hosts: [Int32: HostApp?] = [:]
    private var gitRoots: [String: String] = [:]
    private var lastSeen: [String: Date] = [:]
    private var watchedRoots: [String] = []
    private var latest: StoreSnapshot = .empty
    private var tasks: [Task<Void, Never>] = []

    private static let lastSeenKey = "lastSeen"

    public init(
        roots: ProviderRoots = .current(),
        processes: any ProcessTable = DarwinProcessTable(),
        defaults: UserDefaults? = .standard,
        tuning: StatusEngine.Tuning = .init()
    ) {
        adapters = [ClaudeAdapter(home: roots.claudeHome), CodexAdapter(home: roots.codexHome)]
        self.processes = processes
        self.defaults = defaults
        self.tuning = tuning
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        if let stored = defaults?.dictionary(forKey: Self.lastSeenKey) as? [String: Double] {
            lastSeen = stored.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    // MARK: Lifecycle

    public func start() {
        guard tasks.isEmpty else { return }
        let now = Date()
        for adapter in adapters { adapter.bootstrap(now: now) }
        rewatchIfNeeded(force: true)
        publish()

        let events = watcher.events
        tasks.append(Task { [weak self] in
            for await batch in events {
                await self?.handle(batch)
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                let interval = await self?.tick() ?? 15
                try? await Task.sleep(for: .seconds(interval))
            }
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        watcher.stop()
    }

    /// Full rescan, e.g. after the Mac wakes.
    public func rescan() {
        let now = Date()
        for adapter in adapters { adapter.ingest(paths: [FileWatcher.rescanAll], now: now) }
        rewatchIfNeeded(force: true)
        publish()
    }

    /// The user jumped to this session: a Done session becomes Idle.
    public func markSeen(_ key: SessionKey) {
        lastSeen[key.description] = Date()
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        lastSeen = lastSeen.filter { $0.value > cutoff }
        defaults?.set(lastSeen.mapValues(\.timeIntervalSince1970), forKey: Self.lastSeenKey)
        publish()
    }

    public var snapshot: StoreSnapshot { latest }

    // MARK: Events

    func handle(_ paths: [String]) {
        let now = Date()
        for adapter in adapters { adapter.ingest(paths: paths, now: now) }
        publish()
    }

    /// Returns the delay until the next tick.
    func tick() -> Double {
        rewatchIfNeeded(force: false)
        publish()
        let active = latest.sessions.contains { $0.status.display == .working || $0.status.display == .needsYou }
        return active ? 2 : 15
    }

    private func rewatchIfNeeded(force: Bool) {
        let roots = adapters.flatMap(\.watchRoots).filter { FileManager.default.fileExists(atPath: $0.path) }
        let paths = roots.map(\.path)
        guard force || paths != watchedRoots else { return }
        watchedRoots = paths
        watcher.watch(roots)
    }

    // MARK: Snapshot

    func publish() {
        let now = Date()
        procs = processes.snapshot()
        hosts = hosts.filter { procs[$0.key] != nil }

        let all = adapters.flatMap(\.sessions)
        let codexMatches = matchCodexProcesses(all.filter { $0.key.provider == .codex && $0.expectsProcess && !$0.ended }, now: now)

        var sessions: [SessionSnapshot] = []
        for e in all {
            var pid = e.pid
            let alive: Bool?
            if let known = e.pid {
                alive = isAlive(pid: known, notAfter: e.pidNotAfter)
            } else if e.key.provider == .codex, e.expectsProcess {
                let match = codexMatches[e.key] ?? .none
                switch match {
                case .pid(let p): pid = p; alive = true
                case .alive: alive = true
                case .none: alive = now.timeIntervalSince(e.lastActivityAt) < 60 ? nil : false
                }
            } else {
                alive = e.expectsProcess ? false : nil
            }

            let status = StatusEngine.evaluate(e, processAlive: alive, lastSeen: lastSeen[e.key.description], now: now, tuning: tuning)
            if status.display == .ended, now.timeIntervalSince(status.since) > tuning.noProcessEnd { continue }
            if e.cwd.isEmpty, e.lastPrompt == nil, e.firstPrompt == nil, e.customTitle == nil { continue }

            var host: HostApp?
            if let pid, alive == true { host = resolveHost(pid) }
            if host == nil, let hint = e.hostHint { host = HostApp(kind: hint, name: hint == .vscode ? "VS Code" : "ChatGPT") }

            let root = projectRoot(for: e.cwd)
            sessions.append(SessionSnapshot(
                id: e.key,
                projectName: projectName(root),
                projectPath: root,
                cwd: e.cwd,
                title: e.title,
                activity: status.display == .working || status.display == .needsYou ? e.activity : nil,
                lastPrompt: e.lastPrompt,
                status: status,
                host: host,
                tty: pid.flatMap { procs[$0]?.tty },
                pid: alive == true ? pid : nil,
                parent: e.parent,
                resumeCommand: e.resumeCommand,
                lastActivityAt: e.lastActivityAt
            ))
        }
        sessions.sort { ($0.status.display, $1.lastActivityAt) < ($1.status.display, $0.lastActivityAt) }

        let next = StoreSnapshot(sessions: sessions, diagnostics: adapters.map(\.diagnostics))
        if next != latest {
            latest = next
            continuation.yield(next)
        }
    }

    private func isAlive(pid: Int32, notAfter: Date?) -> Bool {
        guard let record = procs[pid] else { return false }
        // A process that started after the session registered is a reused PID.
        if let notAfter, record.startedAt.timeIntervalSince(notAfter) > 5 { return false }
        return true
    }

    private enum CodexMatch { case pid(Int32), alive, none }

    /// Codex doesn't tell us its PID. Match running `codex` processes to sessions by working
    /// directory; when several sessions share a directory, the newest ones win.
    private func matchCodexProcesses(_ sessions: [SessionEvidence], now: Date) -> [SessionKey: CodexMatch] {
        let me = getuid()
        let candidates = procs.values.filter { $0.command == "codex" && $0.uid == me }
        guard !candidates.isEmpty else { return [:] }
        var byCwd: [String: [ProcessRecord]] = [:]
        for c in candidates {
            if let cwd = processes.workingDirectory(of: c.pid) { byCwd[cwd, default: []].append(c) }
        }
        var result: [SessionKey: CodexMatch] = [:]
        for (cwd, group) in Dictionary(grouping: sessions, by: \.cwd) {
            let running = (byCwd[cwd] ?? []).sorted { $0.startedAt > $1.startedAt }
            let newest = group.sorted { $0.lastActivityAt > $1.lastActivityAt }
            for (i, e) in newest.prefix(running.count).enumerated() {
                result[e.key] = running.count == 1 ? .pid(running[i].pid) : .alive
            }
        }
        return result
    }

    private func resolveHost(_ pid: Int32) -> HostApp? {
        if let cached = hosts[pid] { return cached }
        let host = HostResolver.host(of: pid, in: procs)
        hosts[pid] = host
        return host
    }

    private func projectRoot(for cwd: String) -> String {
        guard !cwd.isEmpty else { return "" }
        if let cached = gitRoots[cwd] { return cached }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var dir = cwd
        var root = cwd
        while dir != "/" && dir != home && !dir.isEmpty {
            if fm.fileExists(atPath: dir + "/.git") { root = dir; break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        gitRoots[cwd] = root
        return root
    }

    private func projectName(_ root: String) -> String {
        if root.isEmpty { return "Unknown project" }
        if root == FileManager.default.homeDirectoryForCurrentUser.path { return "~" }
        return (root as NSString).lastPathComponent
    }
}
