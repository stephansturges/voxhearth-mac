import Foundation
import OSLog

public enum PrivacyLogEvent: String, Sendable {
    case audioCaptureStarted = "audio_capture_started"
    case audioCaptureStopped = "audio_capture_stopped"
    case audioCaptureCancelled = "audio_capture_cancelled"
    case audioDurationLimitReached = "audio_duration_limit_reached"
    case localModelLoadStarted = "local_model_load_started"
    case localModelLoadCompleted = "local_model_load_completed"
    case localTranscriptionStarted = "local_transcription_started"
    case localTranscriptionCompleted = "local_transcription_completed"
    case textInsertionCompleted = "text_insertion_completed"
    case operationFailed = "operation_failed"
}

/// Logs only fixed event identifiers and error types. It deliberately has no
/// API that accepts transcripts, clipboard contents, audio, paths, or freeform strings.
public struct PrivacySafeLogger: Sendable {
    private let logger: Logger

    public init(category: String) {
        logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: category)
    }

    public func info(_ event: PrivacyLogEvent) {
        logger.info("\(event.rawValue, privacy: .public)")
    }

    public func error(_ event: PrivacyLogEvent, error: any Error) {
        let errorType = String(reflecting: type(of: error))
        logger.error(
            "\(event.rawValue, privacy: .public) error_type=\(errorType, privacy: .public)"
        )
    }
}
