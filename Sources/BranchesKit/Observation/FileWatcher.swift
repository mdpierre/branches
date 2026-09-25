import CoreServices
import Foundation

/// A thin FSEvents wrapper that emits batches of changed file paths.
/// A batch containing `FileWatcher.rescanAll` means "events were dropped; rescan everything".
public final class FileWatcher: @unchecked Sendable {
    public static let rescanAll = "*"

    public let events: AsyncStream<[String]>
    private let continuation: AsyncStream<[String]>.Continuation
    private let queue = DispatchQueue(label: "app.branches.fsevents")
    private var stream: FSEventStreamRef?

    public init() {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
    }

    deinit {
        stop()
        continuation.finish()
    }

    /// (Re)starts watching the given directories. Directories that don't exist are skipped.
    public func watch(_ directories: [URL], latency: TimeInterval = 0.2) {
        stop()
        let paths = directories.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(paths, to: NSArray.self)
            var batch: [String] = []
            batch.reserveCapacity(count)
            for i in 0..<count {
                let f = eventFlags[i]
                if f & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 {
                    batch.append(FileWatcher.rescanAll)
                } else if let p = cfPaths[i] as? String {
                    batch.append(p)
                }
            }
            if !batch.isEmpty { watcher.continuation.yield(batch) }
        }
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else {
            Log.fs.error("FSEventStreamCreate failed")
            return
        }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
        Log.fs.info("Watching \(paths.count) directories")
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }
}
