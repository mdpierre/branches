import Foundation

/// Incrementally reads complete lines appended to a JSONL file.
///
/// - Only new bytes are read after the first call.
/// - A trailing line without `\n` is held back until it is completed.
/// - Truncation or replacement (new inode, or size < offset) resets to the start.
/// - The first read can start near the end of a large file (`initialTail`).
public final class JSONLTailReader {
    public let url: URL
    public private(set) var offset: UInt64 = 0
    private var inode: UInt64?
    private var partial = Data()

    /// Never read more than this in one go; if a file grew more than this while we
    /// weren't looking, skip to its tail instead.
    private let maxChunk: UInt64

    public init(url: URL, maxChunk: UInt64 = 16 << 20) {
        self.url = url
        self.maxChunk = maxChunk
    }

    public var hasRead: Bool { inode != nil }

    public func readNewLines(initialTail: UInt64? = nil) -> [Data] {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return [] }
        let fileID = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0

        var dropFirstLine = false
        if let inode, inode != fileID || size < offset {
            offset = 0
            partial.removeAll()
        }
        if inode == nil, let tail = initialTail, size > tail {
            offset = size - tail
            dropFirstLine = true
        }
        inode = fileID
        if size - offset > maxChunk {
            offset = size - maxChunk
            partial.removeAll()
            dropFirstLine = true
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: Int(size - offset)), !data.isEmpty else { return [] }
            offset += UInt64(data.count)
            var buffer = partial
            buffer.append(data)
            return split(&buffer, dropFirst: dropFirstLine)
        } catch {
            return []
        }
    }

    private func split(_ buffer: inout Data, dropFirst: Bool) -> [Data] {
        var lines: [Data] = []
        var start = buffer.startIndex
        var skip = dropFirst
        while let nl = buffer[start...].firstIndex(of: 0x0A) {
            let line = buffer[start..<nl]
            start = buffer.index(after: nl)
            if skip { skip = false; continue }
            if !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) {
                lines.append(Data(line))
            }
        }
        partial = skip ? Data() : Data(buffer[start...])
        return lines
    }

    /// Reads the first line of a file (e.g. Codex `session_meta`), up to `maxBytes`.
    public static func firstLine(of url: URL, maxBytes: Int = 8 << 20) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var buffer = Data()
        while buffer.count < maxBytes {
            guard let chunk = try? handle.read(upToCount: 64 << 10), !chunk.isEmpty else { break }
            if let nl = chunk.firstIndex(of: 0x0A) {
                buffer.append(chunk[chunk.startIndex..<nl])
                return buffer
            }
            buffer.append(chunk)
        }
        return buffer.isEmpty ? nil : buffer
    }
}
