import Foundation

/// Observes OpenAI Codex.
///
/// Sources (verified against Codex CLI 0.139, see docs/02-feasibility.md):
/// - `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`: one file per session.
///   Line envelope `{timestamp, type, payload}`. First line is `session_meta`.
///   `event_msg` `task_started` / `task_complete` mark turn boundaries.
/// - `~/.codex/session_index.jsonl`: `{id, thread_name, updated_at}` titles.
public final class CodexAdapter: ProviderAdapter {
    public let id = ProviderID.codex
    public let capabilities: ProviderCapabilities = [
        .sessionDiscovery, .transcriptReading, .turnBoundaries, .toolActivity, .waitingDetection, .resumeCommand, .subagents,
    ]

    let home: URL
    let sessionsDir: URL
    let indexURL: URL
    private var evidence: [String: SessionEvidence] = [:]
    private var fileToSession: [String: String] = [:]
    private var readers: [String: JSONLTailReader] = [:]
    private var indexReader: JSONLTailReader
    private var threadNames: [String: String] = [:]
    private var diag: ProviderDiagnostics

    public init(home: URL) {
        self.home = home
        sessionsDir = home.appendingPathComponent("sessions")
        indexURL = home.appendingPathComponent("session_index.jsonl")
        indexReader = JSONLTailReader(url: indexURL)
        diag = ProviderDiagnostics(provider: .codex, root: home.path)
    }

    public var watchRoots: [URL] { [sessionsDir] }
    public var sessions: [SessionEvidence] { Array(evidence.values) }
    public var diagnostics: ProviderDiagnostics {
        var d = diag
        d.rootExists = FileManager.default.fileExists(atPath: sessionsDir.path)
        d.filesTracked = readers.count
        return d
    }

    // MARK: Scanning

    public func bootstrap(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.recentWindow)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: sessionsDir, includingPropertiesForKeys: keys) else { return }
        var recent: [URL] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mtime, mtime > cutoff { recent.append(url) }
        }
        for url in recent { ingestRollout(url, now: now) }
        refreshIndex()
    }

    public func ingest(paths: [String], now: Date) {
        var touched = false
        for path in paths {
            if path == FileWatcher.rescanAll { bootstrap(now: now); return }
            let name = (path as NSString).lastPathComponent
            if path.hasPrefix(sessionsDir.path), name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") {
                ingestRollout(URL(fileURLWithPath: path), now: now)
                touched = true
            }
        }
        // session_index.jsonl lives outside the watched folder (next to noisy sqlite files),
        // so pick up title changes whenever a rollout moves.
        if touched { refreshIndex() }
    }

    private func refreshIndex() {
        for line in indexReader.readNewLines(initialTail: 1 << 20) {
            guard let o = JSONLine.object(line), let id = o.str("id"), let name = o.str("thread_name"), !name.isEmpty else { continue }
            threadNames[id] = PromptText.shorten(name, limit: 80)
        }
        for (id, name) in threadNames where evidence[id] != nil {
            evidence[id]?.providerTitle = name
        }
    }

    private func ingestRollout(_ url: URL, now: Date) {
        let reader = readers[url.path] ?? JSONLTailReader(url: url)
        let isNew = !reader.hasRead
        readers[url.path] = reader

        var sid = fileToSession[url.path] ?? Self.sessionID(fromFileName: url.lastPathComponent)
        var e = evidence[sid] ?? SessionEvidence(key: SessionKey(.codex, sid), lastActivityAt: now)
        if isNew {
            // session_meta is the first line, which a tail read would skip.
            if let first = JSONLTailReader.firstLine(of: url) { apply(first, to: &e, sid: &sid) }
            e.lastActivityAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
        }
        for line in reader.readNewLines(initialTail: isNew ? Self.initialTailBytes : nil) {
            apply(line, to: &e, sid: &sid)
        }
        e.transcriptPath = url
        if let name = threadNames[sid] { e.providerTitle = name }
        e.resumeCommand = e.cwd.isEmpty ? "codex resume \(sid)" : "cd \(shellQuote(e.cwd)) && codex resume \(sid)"
        fileToSession[url.path] = sid
        evidence[sid] = e
    }

    // MARK: Record parsing

    func apply(_ line: Data, to e: inout SessionEvidence, sid: inout String) {
        guard let o = JSONLine.object(line) else { diag.linesSkipped += 1; return }
        diag.linesParsed += 1
        let type = o.str("type") ?? "?"
        let ts = Timestamps.parse(o.str("timestamp")) ?? e.lastActivityAt
        let p = o.obj("payload") ?? [:]

        switch type {
        case "session_meta":
            if let id = p.str("id") ?? p.str("session_id"), id != sid {
                e = SessionEvidence(key: SessionKey(.codex, id), cwd: e.cwd, lastActivityAt: e.lastActivityAt)
                sid = id
            }
            if let cwd = p.str("cwd") { e.cwd = cwd }
            e.startedAt = Timestamps.parse(p.str("timestamp")) ?? ts
            if let parent = p.str("parent_thread_id"), !parent.isEmpty { e.parent = SessionKey(.codex, parent) }
            if let v = p.str("cli_version") { e.formatVersion = v; diag.formatVersions.insert(v) }
            let origin = (p.str("originator") ?? "").lowercased()
            // Only terminal sessions have a codex process we can find; app-hosted ones
            // (ChatGPT app, IDE extensions) fall back to time-based status.
            let isTerminal = ["cli", "exec", "tui"].contains(where: origin.contains) || origin.isEmpty
            e.expectsProcess = isTerminal && e.parent == nil
            if origin.contains("vscode") { e.hostHint = .vscode }
            else if !isTerminal { e.hostHint = .chatGPT }
        case "turn_context":
            if let cwd = p.str("cwd") { e.cwd = cwd }
        case "event_msg":
            e.touch(ts)
            applyEvent(p, at: ts, to: &e)
        case "response_item":
            e.touch(ts)
            applyItem(p, at: ts, to: &e)
        default:
            diag.ignoredTypes[type, default: 0] += 1
        }
    }

    private func applyEvent(_ p: JSONObject, at ts: Date, to e: inout SessionEvidence) {
        let kind = p.str("type") ?? "?"
        switch kind {
        case "task_started", "turn_started":
            e.turn = .running(since: ts)
            e.turnReported = true
            e.activity = "Thinking…"
            e.attention = nil
            e.pendingTool = nil
        case "task_complete", "turn_complete", "turn_aborted":
            e.turn = .ended(at: ts)
            e.turnReported = true
            e.activity = nil
            e.pendingTool = nil
            if kind != "turn_aborted" { e.attention = nil }
        case "error":
            e.turn = .ended(at: ts)
            e.turnReported = true
            e.attention = .error
            e.activity = nil
        case "user_message":
            if let text = p.str("message").flatMap({ PromptText.clean($0) }) {
                e.lastPrompt = text
                if e.firstPrompt == nil { e.firstPrompt = text }
            }
        case "exec_command_begin":
            e.activity = "Running a command"
            e.pendingTool = PendingTool(name: "exec", since: ts)
        case "exec_command_end", "patch_apply_end":
            e.pendingTool = nil
            e.activity = "Thinking…"
        case "patch_apply_begin":
            e.activity = "Editing files"
        case let k where k.contains("approval_request"):
            e.attention = .permission
        default:
            diag.ignoredTypes["event_msg." + kind, default: 0] += 1
        }
    }

    private func applyItem(_ p: JSONObject, at ts: Date, to e: inout SessionEvidence) {
        switch p.str("type") ?? "?" {
        case "function_call", "custom_tool_call", "local_shell_call":
            let name = p.str("name") ?? "shell"
            e.activity = Self.describe(tool: name)
            e.pendingTool = PendingTool(name: name, since: ts)
            if case .running = e.turn {} else if !e.turnReported { e.turn = .running(since: ts) }
        case "function_call_output", "custom_tool_call_output", "local_shell_call_output":
            e.pendingTool = nil
            if e.attention == .permission { e.attention = nil }
        case "message":
            guard p.str("role") == "user" else { return }
            let text = p.objects("content").compactMap { $0.str("text") }.joined(separator: "\n")
            if let prompt = PromptText.clean(text) {
                e.lastPrompt = prompt
                if e.firstPrompt == nil { e.firstPrompt = prompt }
            }
        default:
            break
        }
    }

    static func describe(tool: String) -> String {
        switch tool {
        case "shell", "exec_command", "local_shell", "container.exec", "unified_exec": "Running a command"
        case "apply_patch": "Editing files"
        case "update_plan": "Planning"
        case "view_image": "Looking at an image"
        case "web_search": "Searching the web"
        default: "Using \(tool)"
        }
    }

    /// `rollout-2026-09-21T01-12-20-<uuid>.jsonl` → `<uuid>`
    static func sessionID(fromFileName name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        if let r = stem.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) {
            return String(stem[r])
        }
        return stem
    }
}
