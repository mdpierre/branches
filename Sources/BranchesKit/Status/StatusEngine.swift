import Foundation

/// Pure function from evidence to the five-word status. See docs/03-architecture.md §6.
public enum StatusEngine {
    public struct Tuning: Sendable {
        /// Transcript-only fallback (no live status file): an "instant" tool (Edit, Read…) still
        /// pending after this long probably means a permission prompt.
        public var permissionAfter: TimeInterval = 6
        /// Working inferred from transcript shape only; quiet longer than this → "No recent activity".
        public var inferredQuiet: TimeInterval = 180
        /// Working reported by the provider; quiet longer than this → "No recent activity".
        public var reportedQuiet: TimeInterval = 900
        /// Done becomes Idle after this long even if you never looked.
        public var doneToIdle: TimeInterval = 1800
        /// Sessions without a known process are considered over after this long.
        public var noProcessEnd: TimeInterval = 12 * 3600
        /// No turn information at all, but recent file activity counts as working.
        public var recentActivity: TimeInterval = 90

        public init() {}
    }

    /// - Parameters:
    ///   - processAlive: true/false when we know, nil when this session has no findable process.
    ///   - lastSeen: when the user last jumped to this session from Branches.
    public static func evaluate(
        _ e: SessionEvidence,
        processAlive: Bool?,
        lastSeen: Date?,
        now: Date,
        tuning t: Tuning = Tuning()
    ) -> StatusResult {
        // 1. Gone.
        if e.ended {
            return StatusResult(.ended, .reported, since: e.lastActivityAt, reason: "session replaced")
        }
        if processAlive == false {
            return StatusResult(.ended, .reported, since: e.lastActivityAt, reason: "process exited")
        }
        if processAlive == nil, now.timeIntervalSince(e.lastActivityAt) > t.noProcessEnd {
            return StatusResult(.ended, .inferred, since: e.lastActivityAt, reason: "no activity for 12h")
        }

        // 2. Explicit attention signals.
        if e.attention == .error {
            return StatusResult(.needsYou, .reported, since: e.lastActivityAt, reason: "turn ended with an error", attention: .error)
        }
        if e.attention == .permission {
            return StatusResult(.needsYou, .reported, since: e.pendingTool?.since ?? e.lastActivityAt, reason: "waiting for approval", attention: .permission)
        }

        // 3. Provider-reported live status (Claude), unless the transcript has newer news.
        if let live = e.liveStatus, let at = e.liveStatusAt, !transcriptIsNewer(e, than: at) {
            switch live {
            case .waiting:
                // Claude writes status "waiting" whenever a prompt is on screen, with the reason
                // in waitingFor ("permission prompt", "input needed", "dialog open", …).
                let why = e.waitingFor ?? "waiting"
                return StatusResult(.needsYou, .reported, since: at, reason: "provider: \(why)", attention: attention(for: e.waitingFor))
            case .busy:
                // The provider flips to busy when a turn starts, so its timestamp is the most accurate start.
                let since = at
                if now.timeIntervalSince(max(at, e.lastActivityAt)) > t.reportedQuiet {
                    return StatusResult(.working, .unknown, since: since, reason: "busy, but no recent activity")
                }
                return StatusResult(.working, .reported, since: since, reason: "provider: busy")
            case .idle:
                guard e.lastPrompt != nil || e.firstPrompt != nil || turnEnded(e) != nil else {
                    return StatusResult(.idle, .reported, since: at, reason: "provider: idle, no turns yet")
                }
                return doneOrIdle(finishedAt: turnEnded(e) ?? at, confidence: .reported, lastSeen: lastSeen, now: now, t)
            case .other(let raw):
                return fromTurn(e, lastSeen: lastSeen, now: now, t, note: "unknown provider status '\(raw)'")
            }
        }

        return fromTurn(e, lastSeen: lastSeen, now: now, t, note: nil)
    }

    static func attention(for waitingFor: String?) -> AttentionReason {
        let w = (waitingFor ?? "").lowercased()
        if w.isEmpty || w.contains("permission") || w.contains("sandbox") || w.contains("approval") { return .permission }
        return .input
    }

    private static func fromTurn(_ e: SessionEvidence, lastSeen: Date?, now: Date, _ t: Tuning, note: String?) -> StatusResult {
        switch e.turn {
        case .running(let since):
            let quietLimit = e.turnReported ? t.reportedQuiet : t.inferredQuiet
            if now.timeIntervalSince(e.lastActivityAt) > quietLimit {
                return StatusResult(.idle, .unknown, since: e.lastActivityAt, reason: note ?? "no recent activity")
            }
            if let tool = e.pendingTool, ClaudeTools.instant.contains(tool.name), e.key.provider == .claude,
               now.timeIntervalSince(tool.since) > t.permissionAfter {
                return StatusResult(.needsYou, .inferred, since: tool.since, reason: "\(tool.name) pending, probably awaiting approval", attention: .permission)
            }
            return StatusResult(.working, e.turnReported ? .reported : .inferred, since: since, reason: note ?? "turn in progress")
        case .ended(let at):
            return doneOrIdle(finishedAt: at, confidence: e.turnReported ? .reported : .inferred, lastSeen: lastSeen, now: now, t)
        case .unknown:
            if now.timeIntervalSince(e.lastActivityAt) < t.recentActivity {
                return StatusResult(.working, .inferred, since: e.lastActivityAt, reason: note ?? "recent file activity")
            }
            return StatusResult(.idle, .inferred, since: e.lastActivityAt, reason: note ?? "no turn information")
        }
    }

    private static func doneOrIdle(finishedAt: Date, confidence: Confidence, lastSeen: Date?, now: Date, _ t: Tuning) -> StatusResult {
        if let lastSeen, lastSeen >= finishedAt {
            return StatusResult(.idle, confidence, since: finishedAt, reason: "finished, seen")
        }
        if now.timeIntervalSince(finishedAt) > t.doneToIdle {
            return StatusResult(.idle, confidence, since: finishedAt, reason: "finished a while ago")
        }
        return StatusResult(.done, confidence, since: finishedAt, reason: "finished, not yet seen")
    }

    private static func turnEnded(_ e: SessionEvidence) -> Date? {
        if case .ended(let at) = e.turn { return at }
        return nil
    }

    /// The live file flips on every turn; if the transcript moved on well after the last
    /// flip, trust the transcript.
    private static func transcriptIsNewer(_ e: SessionEvidence, than liveAt: Date) -> Bool {
        switch e.turn {
        case .running(let since): return since.timeIntervalSince(liveAt) > 5 && e.liveStatus != .busy
        case .ended(let at): return at.timeIntervalSince(liveAt) > 5 && e.liveStatus != .idle
        case .unknown: return false
        }
    }
}
