import Foundation

/// Status changes worth telling the user about (used for notifications).
public enum StatusTransitions {
    public enum Kind: Sendable, Equatable {
        /// Started needing you (approval, a question, an error).
        case startedNeedingYou
        /// A working turn finished. `workingSince` is when that turn started.
        case finished(workingSince: Date)
        /// Stopped needing you (so a stale "needs you" banner can be cleared).
        case stoppedNeedingYou
    }

    public struct Event: Sendable, Equatable {
        public var session: SessionKey
        public var kind: Kind
    }

    public struct Seen: Sendable, Equatable {
        public var display: DisplayStatus
        public var since: Date

        public init(display: DisplayStatus, since: Date) {
            self.display = display
            self.since = since
        }
    }

    /// Compares the previous statuses with the current snapshot. Subagents are ignored;
    /// sessions seen for the first time never produce events.
    public static func detect(previous: [SessionKey: Seen], current: [SessionSnapshot]) -> [Event] {
        var events: [Event] = []
        for s in current where s.parent == nil {
            guard let before = previous[s.id] else { continue }
            let now = s.status.display
            if now == .needsYou, before.display != .needsYou {
                events.append(Event(session: s.id, kind: .startedNeedingYou))
            } else if now == .done, before.display == .working {
                events.append(Event(session: s.id, kind: .finished(workingSince: before.since)))
            }
            if before.display == .needsYou, now != .needsYou {
                events.append(Event(session: s.id, kind: .stoppedNeedingYou))
            }
        }
        return events
    }

    public static func seen(_ sessions: [SessionSnapshot]) -> [SessionKey: Seen] {
        Dictionary(
            sessions.filter { $0.parent == nil }.map { ($0.id, Seen(display: $0.status.display, since: $0.status.since)) },
            uniquingKeysWith: { a, _ in a }
        )
    }
}
