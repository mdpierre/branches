import Foundation

/// What a provider can (maybe) tell us. Adapters declare this honestly.
public struct ProviderCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let sessionDiscovery   = Self(rawValue: 1 << 0)
    public static let transcriptReading  = Self(rawValue: 1 << 1)
    /// Provider-reported busy/idle (Claude's sessions/<pid>.json).
    public static let liveStatus         = Self(rawValue: 1 << 2)
    /// Explicit turn start/end events (Codex task_started/task_complete).
    public static let turnBoundaries     = Self(rawValue: 1 << 3)
    public static let toolActivity       = Self(rawValue: 1 << 4)
    public static let waitingDetection   = Self(rawValue: 1 << 5)
    /// The provider tells us the PID directly.
    public static let processCorrelation = Self(rawValue: 1 << 6)
    public static let resumeCommand      = Self(rawValue: 1 << 7)
    public static let subagents          = Self(rawValue: 1 << 8)
}

/// The contract every provider implements. It is the only code that knows a provider's
/// file formats. See `Providers/README.md`.
///
/// Adapters are owned by `SessionStore` and only ever called from it, so they can keep
/// plain mutable parse state (cursors, per-session evidence).
public protocol ProviderAdapter: AnyObject {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }

    /// Directories to watch. Missing ones are fine (provider not installed).
    var watchRoots: [URL] { get }

    /// Initial scan: discover sessions active recently, reading only file tails.
    func bootstrap(now: Date)

    /// Changed paths from the file watcher. Must be incremental and must never throw:
    /// malformed input becomes a diagnostic.
    func ingest(paths: [String], now: Date)

    /// Current evidence for every session this provider knows about.
    var sessions: [SessionEvidence] { get }

    var diagnostics: ProviderDiagnostics { get }
}

extension ProviderAdapter {
    /// How far back to look for sessions at launch.
    static var recentWindow: TimeInterval { 12 * 3600 }
    /// How much of an existing transcript to read at launch.
    static var initialTailBytes: UInt64 { 512 << 10 }
}
