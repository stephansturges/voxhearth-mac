import Foundation
import OSLog

enum PrivacyLogSubsystem {
    static let current = resolved(
        processName: ProcessInfo.processInfo.processName,
        environment: ProcessInfo.processInfo.environment
    )

    static func resolved(
        processName: String,
        environment: [String: String]
    ) -> String {
        if processName == "swiftpm-testing-helper"
            || processName.contains("VoxHearthPackageTests")
            || environment["XCTestConfigurationFilePath"] != nil
        {
            return AppIdentity.bundleIdentifier + ".tests"
        }
        return AppIdentity.bundleIdentifier
    }
}

public enum PrivacyLogEvent: String, CaseIterable, Sendable {
    case hotkeyDispatchDelayed = "hotkey_dispatch_delayed"
    case hotkeyDispatchStalled = "hotkey_dispatch_stalled"
    case hotkeyPressed = "hotkey_pressed"
    case hotkeyReleased = "hotkey_released"
    case activationHandlingStarted = "activation_handling_started"
    case activationHandlingCompleted = "activation_handling_completed"
    case lifecycleActivityBegan = "lifecycle_activity_began"
    case lifecycleActivityNarrowed = "lifecycle_activity_narrowed"
    case lifecycleActivityEnded = "lifecycle_activity_ended"
    case dictationStartAccepted = "dictation_start_accepted"
    case dictationStartAbandoned = "dictation_start_abandoned"
    case dictationStopAccepted = "dictation_stop_accepted"
    case dictationStopAbandoned = "dictation_stop_abandoned"
    case startCueStarted = "start_cue_started"
    case startCueCompleted = "start_cue_completed"
    case startCuePlayEntered = "start_cue_play_entered"
    case startCuePlayReturned = "start_cue_play_returned"
    case startCueDelayResumed = "start_cue_delay_resumed"
    case modelPreparationStarted = "model_preparation_started"
    case modelPreparationCompleted = "model_preparation_completed"
    case audioCaptureStartEntered = "audio_capture_start_entered"
    case audioCaptureStarted = "audio_capture_started"
    case audioCaptureStopEntered = "audio_capture_stop_entered"
    case audioCaptureStopped = "audio_capture_stopped"
    case audioCaptureCancelled = "audio_capture_cancelled"
    case audioDurationLimitReached = "audio_duration_limit_reached"
    case livePreviewSnapshotStarted = "live_preview_snapshot_started"
    case livePreviewSnapshotCompleted = "live_preview_snapshot_completed"
    case audioSnapshotLockEntered = "audio_snapshot_lock_entered"
    case audioSnapshotCopyCompleted = "audio_snapshot_copy_completed"
    case livePreviewInferenceStarted = "live_preview_inference_started"
    case livePreviewInferenceCompleted = "live_preview_inference_completed"
    case livePreviewPublishRequested = "live_preview_publish_requested"
    case livePreviewActorEntered = "live_preview_actor_entered"
    case livePreviewPublished = "live_preview_published"
    case livePreviewBudgetExceeded = "live_preview_budget_exceeded"
    case livePreviewCircuitOpened = "live_preview_circuit_opened"
    case livePreviewCancellationRequested = "live_preview_cancellation_requested"
    case livePreviewCancellationJoined = "live_preview_cancellation_joined"
    case overlayTextApplied = "overlay_text_applied"
    case overlayScreenQueryStarted = "overlay_screen_query_started"
    case overlayScreenQueryCompleted = "overlay_screen_query_completed"
    case overlayPositionApplied = "overlay_position_applied"
    case overlayOrderFrontStarted = "overlay_order_front_started"
    case overlayOrderFrontCompleted = "overlay_order_front_completed"
    case overlayHidden = "overlay_hidden"
    case localModelLoadStarted = "local_model_load_started"
    case localModelLoadCompleted = "local_model_load_completed"
    case localTranscriptionStarted = "local_transcription_started"
    case localInferenceReturned = "local_inference_returned"
    case localTranscriptionCompleted = "local_transcription_completed"
    case pooledBuffersReleaseRequested = "pooled_buffers_release_requested"
    case modelRecoveryConsidered = "model_recovery_considered"
    case modelRecoverySkipped = "model_recovery_skipped"
    case modelRecoveryStarted = "model_recovery_started"
    case modelRecoveryCompleted = "model_recovery_completed"
    case audioResampleStarted = "audio_resample_started"
    case audioResampleCompleted = "audio_resample_completed"
    case finalTranscriptionStarted = "final_transcription_started"
    case finalTranscriptionCompleted = "final_transcription_completed"
    case cleanupPreparationStarted = "cleanup_preparation_started"
    case cleanupPreparationCompleted = "cleanup_preparation_completed"
    case cleanupGenerationStarted = "cleanup_generation_started"
    case cleanupQueueSubmitted = "cleanup_queue_submitted"
    case cleanupQueueEntered = "cleanup_queue_entered"
    case cleanupGenerationCompleted = "cleanup_generation_completed"
    case cleanupSelectionCompleted = "cleanup_selection_completed"
    case cleanupFallback = "cleanup_fallback"
    case cleanupCancelled = "cleanup_cancelled"
    case cleanupBackendDemoted = "cleanup_backend_demoted"
    case cleanupExpediteRequested = "cleanup_expedite_requested"
    case cleanupExpediteRestarted = "cleanup_expedite_restarted"
    case pendingInsertionRetained = "pending_insertion_retained"
    case pendingInsertionExpired = "pending_insertion_expired"
    case pendingInsertionRemoved = "pending_insertion_removed"
    case multilineInsertionBlocked = "multiline_insertion_blocked"
    case multilineRecoveryOverride = "multiline_recovery_override"
    case textInsertionStarted = "text_insertion_started"
    case textInsertionCompleted = "text_insertion_completed"
    case accessibilityFocusQueryStarted = "accessibility_focus_query_started"
    case accessibilityFocusQueryCompleted = "accessibility_focus_query_completed"
    case accessibilitySettableQueryStarted = "accessibility_settable_query_started"
    case accessibilitySettableQueryCompleted = "accessibility_settable_query_completed"
    case accessibilitySetValueStarted = "accessibility_set_value_started"
    case accessibilitySetValueCompleted = "accessibility_set_value_completed"
    case accessibilitySetValueTimedOut = "accessibility_set_value_timed_out"
    case accessibilitySetValueRefused = "accessibility_set_value_refused"
    case accessibilityInsertionUnavailable = "accessibility_insertion_unavailable"
    case accessibilityInsertionUncertain = "accessibility_insertion_uncertain"
    case unicodeInsertionStarted = "unicode_insertion_started"
    case unicodeInsertionDispatched = "unicode_insertion_dispatched"
    case clipboardInsertionStarted = "clipboard_insertion_started"
    case clipboardInsertionCompleted = "clipboard_insertion_completed"
    case sessionReturnedToIdle = "session_returned_to_idle"
    case operationFailed = "operation_failed"
}

/// Logs only fixed event identifiers and error types. It deliberately has no
/// API that accepts transcripts, clipboard contents, audio, paths, or freeform strings.
public struct PrivacySafeLogger: Sendable {
    private let logger: Logger

    public init(category: String) {
        logger = Logger(subsystem: PrivacyLogSubsystem.current, category: category)
    }

    public func info(_ event: PrivacyLogEvent) {
        logger.info("\(event.rawValue, privacy: .public)")
    }

    public func info(_ event: PrivacyLogEvent, sessionID: DictationSessionID) {
        logger.info(
            "\(event.rawValue, privacy: .public) session_id=\(sessionID.description, privacy: .public)"
        )
    }

    public func info(_ event: PrivacyLogEvent, format: CleanupFormat) {
        logger.info(
            "\(event.rawValue, privacy: .public) format=\(format.rawValue, privacy: .public)"
        )
    }

    public func info(_ event: PrivacyLogEvent, reason: CleanupFallbackReason) {
        logger.info(
            "\(event.rawValue, privacy: .public) reason=\(reason.rawValue, privacy: .public)"
        )
    }

    public func error(_ event: PrivacyLogEvent, error: any Error) {
        let errorType = String(reflecting: type(of: error))
        logger.error(
            "\(event.rawValue, privacy: .public) error_type=\(errorType, privacy: .public)"
        )
    }
}

/// Paired timing intervals carry only the same closed event identifiers as the
/// privacy-safe logger. They deliberately expose no arbitrary payload API.
public struct PrivacySafeSignposter: Sendable {
    private let signposter: OSSignposter

    public init(category: String) {
        signposter = OSSignposter(
            subsystem: PrivacyLogSubsystem.current,
            category: category
        )
    }

    public func begin(_ event: PrivacyLogEvent) -> OSSignpostIntervalState {
        signposter.beginInterval(
            "phase",
            id: signposter.makeSignpostID(),
            "\(event.rawValue, privacy: .public)"
        )
    }

    public func end(
        _ event: PrivacyLogEvent,
        _ state: OSSignpostIntervalState
    ) {
        signposter.endInterval("phase", state, "\(event.rawValue, privacy: .public)")
    }
}
