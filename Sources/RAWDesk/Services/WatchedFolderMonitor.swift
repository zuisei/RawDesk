import Darwin
import Foundation

/// A lightweight directory-change signal. The caller still re-enumerates and
/// validates every file; filesystem events are never treated as import truth.
public final class WatchedFolderMonitor:
    @unchecked Sendable {

    public enum MonitorError: LocalizedError {
        case unavailable

        public var errorDescription: String? {
            "The watched folder could not be monitored."
        }
    }

    private let queue = DispatchQueue(
        label: "rawdesk.auto-import.watcher",
        qos: .utility
    )
    private var source: DispatchSourceFileSystemObject?

    public init() {}

    deinit {
        stop()
    }

    public func start(
        folderURL: URL,
        onChange: @escaping @Sendable () -> Void
    ) throws {
        stop()
        let descriptor = open(folderURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw MonitorError.unavailable
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [
                .write,
                .extend,
                .attrib,
                .rename,
                .delete,
            ],
            queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
    }
}
