import Dispatch
import Foundation

public enum CleanupMemoryPressureLevel: Equatable, Sendable {
    case warning
    case critical
}

/// A process-local signal only. It never samples transcript data or writes
/// diagnostics payloads; it merely asks the cleanup owner to release residency.
final class CleanupMemoryPressureMonitor: @unchecked Sendable {
    private let source: DispatchSourceMemoryPressure

    init(handler: @escaping @Sendable (CleanupMemoryPressureLevel) -> Void) {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue(
                label: "com.stephansturges.voxhearth.cleanup-memory-pressure",
                qos: .utility
            )
        )
        self.source = source
        source.setEventHandler { [weak source] in
            guard let source else { return }
            let data = source.data
            handler(data.contains(.critical) ? .critical : .warning)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
