import Foundation
import os

public enum Log {
    public static let fs = Logger(subsystem: "app.branches", category: "fs")
    public static let claude = Logger(subsystem: "app.branches", category: "claude")
    public static let codex = Logger(subsystem: "app.branches", category: "codex")
    public static let process = Logger(subsystem: "app.branches", category: "process")
    public static let focus = Logger(subsystem: "app.branches", category: "focus")
}

/// Where providers keep their state. Overridable for tests and for unusual setups.
public struct ProviderRoots: Sendable {
    public var claudeHome: URL
    public var codexHome: URL

    public init(claudeHome: URL, codexHome: URL) {
        self.claudeHome = claudeHome
        self.codexHome = codexHome
    }

    public static func current() -> ProviderRoots {
        let env = ProcessInfo.processInfo.environment
        let home = env["BRANCHES_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let claude = env["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        let codex = env["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        return ProviderRoots(claudeHome: claude.resolvingSymlinksInPath(), codexHome: codex.resolvingSymlinksInPath())
    }
}

// MARK: - JSON helpers (tolerant: unknown fields are simply never looked at)

typealias JSONObject = [String: Any]

enum JSONLine {
    static func object(_ data: Data) -> JSONObject? {
        (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? JSONObject
    }
}

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? { self[key] as? String }
    func obj(_ key: String) -> JSONObject? { self[key] as? JSONObject }
    func objects(_ key: String) -> [JSONObject] { (self[key] as? [Any])?.compactMap { $0 as? JSONObject } ?? [] }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
    func number(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
}

enum Timestamps {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return (try? fractional.parse(string)) ?? (try? plain.parse(string))
    }

    static func fromMillis(_ value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        // Accept seconds or milliseconds.
        return Date(timeIntervalSince1970: value > 1e11 ? value / 1000 : value)
    }
}

enum PromptText {
    /// Returns a short, single-line version of a human prompt, or nil when the text is
    /// synthetic (slash-command wrappers, injected context, caveats).
    static func clean(_ raw: String, limit: Int = 80) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let syntheticPrefixes = ["<", "Caveat:", "# AGENTS.md", "[Request interrupted", "This session is being continued"]
        if syntheticPrefixes.contains(where: trimmed.hasPrefix) { return nil }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func shorten(_ s: String, limit: Int = 60) -> String {
        let one = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        return one.count <= limit ? one : String(one.prefix(limit - 1)) + "…"
    }
}

func fileName(_ path: String?) -> String? {
    guard let path, !path.isEmpty else { return nil }
    return (path as NSString).lastPathComponent
}
