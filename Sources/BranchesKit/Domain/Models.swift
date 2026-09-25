import Foundation

// MARK: - Identity

public enum ProviderID: String, Sendable, Codable, CaseIterable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

public struct SessionKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let provider: ProviderID
    public let id: String

    public init(_ provider: ProviderID, _ id: String) {
        self.provider = provider
        self.id = id
    }

    public var description: String { "\(provider.rawValue):\(id)" }
}

// MARK: - Status vocabulary

/// The five words the UI uses. Ordered by urgency.
public enum DisplayStatus: Int, Sendable, Comparable, CaseIterable {
    case needsYou = 0, working, done, idle, ended

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .done: "Done"
        case .idle: "Idle"
        case .ended: "Ended"
        }
    }
}

/// How much we trust a status. Never present `inferred` as `reported` internally.
public enum Confidence: String, Sendable {
    /// The provider itself said so (state file, turn event).
    case reported
    /// Derived from transcript shape, timing or process liveness.
    case inferred
    /// Not enough recent evidence.
    case unknown
}

public enum AttentionReason: Sendable, Equatable {
    case permission
    case error
}

public struct StatusResult: Sendable, Equatable {
    public var display: DisplayStatus
    public var confidence: Confidence
    public var attention: AttentionReason?
    /// Short machine-ish explanation, shown in tooltips.
    public var reason: String
    /// When the session entered this state.
    public var since: Date

    public init(_ display: DisplayStatus, _ confidence: Confidence, since: Date, reason: String, attention: AttentionReason? = nil) {
        self.display = display
        self.confidence = confidence
        self.since = since
        self.reason = reason
        self.attention = attention
    }
}

// MARK: - Evidence (what adapters produce)

/// Provider-reported live state (Claude's ~/.claude/sessions/<pid>.json).
public enum LiveStatus: Sendable, Equatable {
    case busy, idle, waiting
    case other(String)

    public init(raw: String) {
        let r = raw.lowercased()
        switch r {
        case "busy", "working", "running": self = .busy
        case "idle": self = .idle
        default:
            if ["wait", "permission", "input", "attention", "blocked"].contains(where: r.contains) {
                self = .waiting
            } else {
                self = .other(raw)
            }
        }
    }
}

public enum TurnState: Sendable, Equatable {
    case unknown
    case running(since: Date)
    case ended(at: Date)
}

public struct PendingTool: Sendable, Equatable {
    public var name: String
    public var since: Date
}

/// Everything an adapter knows about one session. Provider-neutral.
public struct SessionEvidence: Sendable, Equatable {
    public var key: SessionKey
    public var cwd: String
    public var startedAt: Date?
    public var lastActivityAt: Date

    // Titles, in priority order (see `title`)
    public var customTitle: String?
    public var providerTitle: String?
    public var firstPrompt: String?
    public var lastPrompt: String?

    public var activity: String?
    public var parent: SessionKey?

    // Liveness
    public var pid: Int32?
    /// The session registered at this time; a process that started later is a reused PID.
    public var pidNotAfter: Date?
    /// True when a live process should exist (so "no process" means Ended).
    public var expectsProcess: Bool = true
    /// The provider told us this session is over (e.g. its PID now belongs to a new session).
    public var ended: Bool = false

    // Status signals
    public var liveStatus: LiveStatus?
    public var liveStatusAt: Date?
    public var turn: TurnState = .unknown
    /// True when `turn` comes from explicit provider events rather than transcript shape.
    public var turnReported: Bool = false
    public var pendingTool: PendingTool?
    public var attention: AttentionReason?

    // Provider details, for navigation and diagnostics only
    public var hostHint: HostKind?
    public var transcriptPath: URL?
    public var formatVersion: String?
    public var resumeCommand: String?

    public init(key: SessionKey, cwd: String = "", lastActivityAt: Date) {
        self.key = key
        self.cwd = cwd
        self.lastActivityAt = lastActivityAt
    }

    public var title: String {
        customTitle ?? providerTitle ?? firstPrompt ?? lastPrompt ?? "New session"
    }

    mutating func touch(_ date: Date?) {
        if let date, date > lastActivityAt { lastActivityAt = date }
    }
}

// MARK: - Host application

public enum HostKind: String, Sendable, Equatable {
    case terminal, iTerm, ghostty, warp, vscode, cursor, claudeDesktop, chatGPT, tmux, other

    public static func from(bundleID: String?) -> HostKind {
        switch bundleID ?? "" {
        case "com.apple.Terminal": .terminal
        case "com.googlecode.iterm2": .iTerm
        case "com.mitchellh.ghostty": .ghostty
        case let b where b.hasPrefix("dev.warp."): .warp
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders": .vscode
        case let b where b.hasPrefix("com.todesktop."): .cursor
        case "com.anthropic.claudefordesktop": .claudeDesktop
        case "com.openai.chat", "com.openai.codex": .chatGPT
        default: .other
        }
    }
}

public struct HostApp: Sendable, Equatable {
    public var kind: HostKind
    public var name: String
    public var bundleID: String?
    public var pid: Int32?

    public init(kind: HostKind, name: String, bundleID: String? = nil, pid: Int32? = nil) {
        self.kind = kind
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
    }
}

// MARK: - What the UI receives

public struct SessionSnapshot: Identifiable, Sendable, Equatable {
    public var id: SessionKey
    public var provider: ProviderID { id.provider }
    public var projectName: String
    public var projectPath: String
    public var cwd: String
    public var title: String
    public var activity: String?
    public var lastPrompt: String?
    public var status: StatusResult
    public var host: HostApp?
    public var tty: String?
    public var pid: Int32?
    public var parent: SessionKey?
    public var resumeCommand: String?
    public var lastActivityAt: Date

    public init(
        id: SessionKey, projectName: String, projectPath: String, cwd: String, title: String,
        activity: String? = nil, lastPrompt: String? = nil, status: StatusResult, host: HostApp? = nil,
        tty: String? = nil, pid: Int32? = nil, parent: SessionKey? = nil, resumeCommand: String? = nil,
        lastActivityAt: Date
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.cwd = cwd
        self.title = title
        self.activity = activity
        self.lastPrompt = lastPrompt
        self.status = status
        self.host = host
        self.tty = tty
        self.pid = pid
        self.parent = parent
        self.resumeCommand = resumeCommand
        self.lastActivityAt = lastActivityAt
    }
}

public struct ProviderDiagnostics: Sendable, Equatable {
    public var provider: ProviderID
    public var root: String
    public var rootExists: Bool = false
    public var filesTracked: Int = 0
    public var linesParsed: Int = 0
    public var linesSkipped: Int = 0
    public var ignoredTypes: [String: Int] = [:]
    public var formatVersions: Set<String> = []

    public init(provider: ProviderID, root: String) {
        self.provider = provider
        self.root = root
    }
}

public struct StoreSnapshot: Sendable, Equatable {
    public var sessions: [SessionSnapshot]
    public var diagnostics: [ProviderDiagnostics]

    public init(sessions: [SessionSnapshot], diagnostics: [ProviderDiagnostics]) {
        self.sessions = sessions
        self.diagnostics = diagnostics
    }

    public static let empty = StoreSnapshot(sessions: [], diagnostics: [])
}
