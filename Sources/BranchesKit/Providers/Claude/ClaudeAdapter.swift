import Foundation

/// Observes Claude Code.
///
/// Sources (verified against Claude Code 2.1.x, see docs/02-feasibility.md):
/// - `~/.claude/sessions/<pid>.json`: live registry: pid, sessionId, cwd, status busy/idle.
///   Undocumented. We never read the sibling `*.key` files.
/// - `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`: the transcript.
public final class ClaudeAdapter: ProviderAdapter {
    public let id = ProviderID.claude
    public let capabilities: ProviderCapabilities = [
        .sessionDiscovery, .transcriptReading, .liveStatus, .toolActivity, .processCorrelation, .resumeCommand,
    ]

    let sessionsDir: URL
    let projectsDir: URL
    private var evidence: [String: SessionEvidence] = [:]
    private var readers: [String: JSONLTailReader] = [:]
    private var liveByPID: [Int32: String] = [:]
    private var diag: ProviderDiagnostics

    public init(home: URL) {
        sessionsDir = home.appendingPathComponent("sessions")
        projectsDir = home.appendingPathComponent("projects")
        diag = ProviderDiagnostics(provider: .claude, root: home.path)
    }

    public var watchRoots: [URL] { [sessionsDir, projectsDir] }
    public var sessions: [SessionEvidence] { Array(evidence.values) }
    public var diagnostics: ProviderDiagnostics {
        var d = diag
        d.rootExists = FileManager.default.fileExists(atPath: projectsDir.path)
        d.filesTracked = readers.count
        return d
    }

    // MARK: Scanning

    public func bootstrap(now: Date) {
        rescanLiveFiles(now: now)
        let cutoff = now.addingTimeInterval(-Self.recentWindow)
        let live = Set(liveByPID.values)
        for url in allTranscripts() {
            let sid = url.deletingPathExtension().lastPathComponent
            let mtime = modificationDate(url) ?? .distantPast
            if live.contains(sid) || mtime > cutoff {
                ingestTranscript(url, now: now)
            }
        }
    }

    public func ingest(paths: [String], now: Date) {
        var liveChanged = false
        for path in paths {
            if path == FileWatcher.rescanAll { bootstrap(now: now); return }
            if path.hasPrefix(sessionsDir.path) {
                liveChanged = true
            } else if path.hasPrefix(projectsDir.path), path.hasSuffix(".jsonl"), !path.contains("/subagents/") {
                ingestTranscript(URL(fileURLWithPath: path), now: now)
            }
        }
        if liveChanged { rescanLiveFiles(now: now) }
    }

    private func rescanLiveFiles(now: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)) ?? []
        var seen: [Int32: String] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let o = JSONLine.object(data),
                  let sid = o.str("sessionId"), let pidValue = o.number("pid") else {
                diag.linesSkipped += 1
                continue
            }
            let pid = Int32(pidValue)
            let statusAt = Timestamps.fromMillis(o.number("statusUpdatedAt") ?? o.number("updatedAt")) ?? now
            let startedAt = Timestamps.fromMillis(o.number("startedAt"))
            var e = evidence[sid] ?? SessionEvidence(key: SessionKey(.claude, sid), lastActivityAt: startedAt ?? statusAt)
            if let cwd = o.str("cwd") { e.cwd = cwd }
            e.pid = pid
            e.pidNotAfter = startedAt
            e.startedAt = e.startedAt ?? startedAt
            e.expectsProcess = true
            e.ended = false
            if let status = o.str("status") {
                e.liveStatus = LiveStatus(raw: status)
                e.liveStatusAt = statusAt
                e.waitingFor = o.str("waitingFor")
            }
            if let name = o.str("name"), !Self.isAutoName(name, source: o.str("nameSource")) { e.providerTitle = name }
            if let v = o.str("version") { e.formatVersion = v; diag.formatVersions.insert(v) }
            e.resumeCommand = Self.resumeCommand(sid: sid, cwd: e.cwd)
            e.touch(statusAt)
            evidence[sid] = e
            seen[pid] = sid
            if e.transcriptPath == nil, let url = locateTranscript(sid) {
                ingestTranscript(url, now: now)
            }
        }
        // A PID that now hosts a different session (e.g. after /clear) ended its old one.
        for (pid, oldSid) in liveByPID where seen[pid] != nil && seen[pid] != oldSid {
            evidence[oldSid]?.ended = true
            evidence[oldSid]?.pid = nil
        }
        liveByPID = seen
    }

    private func ingestTranscript(_ url: URL, now: Date) {
        let sid = url.deletingPathExtension().lastPathComponent
        let reader = readers[url.path] ?? JSONLTailReader(url: url)
        readers[url.path] = reader
        let lines = reader.readNewLines(initialTail: reader.hasRead ? nil : Self.initialTailBytes)

        var e = evidence[sid] ?? SessionEvidence(key: SessionKey(.claude, sid), lastActivityAt: modificationDate(url) ?? now)
        e.transcriptPath = url
        for line in lines { apply(line, to: &e) }
        e.resumeCommand = Self.resumeCommand(sid: sid, cwd: e.cwd)
        evidence[sid] = e
    }

    // MARK: Record parsing

    func apply(_ line: Data, to e: inout SessionEvidence) {
        guard let o = JSONLine.object(line) else { diag.linesSkipped += 1; return }
        diag.linesParsed += 1
        let type = o.str("type") ?? "?"
        let ts = Timestamps.parse(o.str("timestamp"))
        if let cwd = o.str("cwd"), !cwd.isEmpty { e.cwd = cwd }
        if o.bool("isSidechain") == true { return }

        switch type {
        case "user":
            e.touch(ts)
            applyUser(o, at: ts ?? e.lastActivityAt, to: &e)
        case "assistant":
            e.touch(ts)
            applyAssistant(o, at: ts ?? e.lastActivityAt, to: &e)
        case "custom-title":
            if let t = o.str("customTitle"), !t.isEmpty { e.customTitle = PromptText.shorten(t, limit: 80) }
        case "summary":
            if e.customTitle == nil, let s = o.str("summary") { e.providerTitle = e.providerTitle ?? PromptText.shorten(s, limit: 80) }
        case "last-prompt":
            if let p = o.str("lastPrompt").flatMap({ PromptText.clean($0) }) { e.lastPrompt = p }
        default:
            diag.ignoredTypes[type, default: 0] += 1
        }
    }

    private func applyUser(_ o: JSONObject, at ts: Date, to e: inout SessionEvidence) {
        if o.bool("isMeta") == true { return }
        let content = o.obj("message")?["content"]
        if let text = content as? String {
            applyPrompt(text, at: ts, to: &e)
            return
        }
        let blocks = o.obj("message")?.objects("content") ?? []
        if blocks.contains(where: { $0.str("type") == "tool_result" }) {
            e.pendingTool = nil
            if e.attention == .permission { e.attention = nil }
            let interrupted = blocks.contains { block in
                (block["content"] as? String)?.hasPrefix("[Request interrupted") == true
            }
            if interrupted {
                endTurn(at: ts, to: &e)
            } else {
                e.activity = "Thinking…"
                if case .ended = e.turn { e.turn = .running(since: ts) }
            }
            return
        }
        let text = blocks.compactMap { $0.str("type") == "text" ? $0.str("text") : nil }.joined(separator: "\n")
        applyPrompt(text, at: ts, to: &e)
    }

    private func applyPrompt(_ text: String, at ts: Date, to e: inout SessionEvidence) {
        if text.hasPrefix("[Request interrupted") { endTurn(at: ts, to: &e); return }
        guard let prompt = PromptText.clean(text) else { return }
        e.lastPrompt = prompt
        if e.firstPrompt == nil { e.firstPrompt = prompt }
        e.turn = .running(since: ts)
        e.turnReported = false
        e.activity = "Thinking…"
        e.pendingTool = nil
        e.attention = nil
    }

    private func applyAssistant(_ o: JSONObject, at ts: Date, to e: inout SessionEvidence) {
        if o.bool("isApiErrorMessage") == true {
            endTurn(at: ts, to: &e)
            e.attention = .error
            return
        }
        if case .running = e.turn {} else { e.turn = .running(since: ts) }
        let message = o.obj("message")
        for block in message?.objects("content") ?? [] where block.str("type") == "tool_use" {
            let name = block.str("name") ?? "tool"
            e.pendingTool = PendingTool(name: name, since: ts)
            e.activity = ClaudeTools.describe(name: name, input: block.obj("input"))
        }
        if let stop = message?.str("stop_reason"), stop == "end_turn" || stop == "stop_sequence" {
            endTurn(at: ts, to: &e)
        }
    }

    private func endTurn(at ts: Date, to e: inout SessionEvidence) {
        e.turn = .ended(at: ts)
        e.pendingTool = nil
        e.activity = nil
    }

    // MARK: Helpers

    private func allTranscripts() -> [URL] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        return dirs.flatMap { dir in
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
    }

    private func locateTranscript(_ sid: String) -> URL? {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        return dirs.lazy.map { $0.appendingPathComponent("\(sid).jsonl") }.first { fm.fileExists(atPath: $0.path) }
    }

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Claude auto-names sessions like "myproject-3b"; those aren't useful titles.
    static func isAutoName(_ name: String, source: String? = nil) -> Bool {
        if source == "auto" || source == "collision" { return true }
        return name.range(of: #"^[a-z0-9._-]+-[0-9a-f]{2,4}$"#, options: .regularExpression) != nil
    }

    static func resumeCommand(sid: String, cwd: String) -> String {
        cwd.isEmpty ? "claude --resume \(sid)" : "cd \(shellQuote(cwd)) && claude --resume \(sid)"
    }
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

/// Turns a Claude tool call into a short activity line. Only file names and the
/// model-written Bash `description` are used, never command text or file contents.
enum ClaudeTools {
    static func describe(name: String, input: JSONObject?) -> String {
        let file = fileName(input?.str("file_path") ?? input?.str("notebook_path") ?? input?.str("path"))
        switch name {
        case "Edit", "MultiEdit": return file.map { "Editing \($0)" } ?? "Editing files"
        case "Write": return file.map { "Writing \($0)" } ?? "Writing a file"
        case "NotebookEdit": return file.map { "Editing \($0)" } ?? "Editing a notebook"
        case "Read": return file.map { "Reading \($0)" } ?? "Reading files"
        case "Bash", "BashOutput":
            if let d = input?.str("description"), !d.isEmpty { return PromptText.shorten(d, limit: 60) }
            return "Running a command"
        case "Grep", "Glob", "LS": return "Searching the codebase"
        case "WebFetch", "WebSearch": return "Searching the web"
        case "Task", "Agent": return "Running a subagent"
        case "TodoWrite", "TaskCreate", "TaskUpdate": return "Planning"
        case "AskUserQuestion": return "Asking you a question"
        case "ExitPlanMode": return "Proposing a plan"
        default:
            if name.hasPrefix("mcp__") {
                let server = name.split(separator: "_", omittingEmptySubsequences: true).dropFirst().first.map(String.init) ?? "MCP"
                return "Using \(server)"
            }
            return "Using \(name)"
        }
    }

    /// Tools that complete instantly when auto-approved. If one stays pending, Claude is
    /// almost certainly showing a permission prompt.
    static let instant: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit", "Read", "Grep", "Glob", "LS", "AskUserQuestion", "ExitPlanMode"]
}
