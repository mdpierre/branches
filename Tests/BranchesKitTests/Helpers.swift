import Foundation
@testable import BranchesKit

/// A throwaway directory that mimics a user's home for provider fixtures.
final class TempHome {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("branches-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    @discardableResult
    func write(_ relative: String, _ content: String) -> URL {
        let file = path(relative)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.data(using: .utf8)!.write(to: file)
        return file
    }

    func append(_ relative: String, _ content: String) {
        let file = path(relative)
        guard let handle = try? FileHandle(forWritingTo: file) else { write(relative, content); return }
        handle.seekToEndOfFile()
        handle.write(content.data(using: .utf8)!)
        try? handle.close()
    }
}

/// JSON for a single JSONL line (with trailing newline).
func line(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self) + "\n"
}

func iso(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
}

struct FakeProcessTable: ProcessTable {
    var records: [Int32: ProcessRecord] = [:]
    var cwds: [Int32: String] = [:]

    func snapshot() -> [Int32: ProcessRecord] { records }
    func workingDirectory(of pid: Int32) -> String? { cwds[pid] }
}
