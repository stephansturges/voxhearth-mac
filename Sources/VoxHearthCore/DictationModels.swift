import Foundation

public struct AudioInputDevice: Identifiable, Equatable, Sendable {
    public let uid: String
    public let name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }

    public var id: String { uid }
}

public struct CapturedAudio: Equatable, Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

/// Whether an external, memory-only audio source was accepted for local
/// transcription. External sources include a future directly paired BLE audio
/// accessory; they never need to impersonate the Mac microphone.
public enum ExternalAudioSubmissionResult: Equatable, Sendable {
    case accepted
    case busy
    case invalidAudio
}

public enum DictationSessionState: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case transcribing
    case cleaning(CleanupFormat)
    case inserting
    case failed(DictationFailure)

    public var isBusy: Bool {
        switch self {
        case .preparing, .recording, .transcribing, .cleaning, .inserting: true
        case .idle, .failed: false
        }
    }
}

/// Content-free progress for passive UI surfaces. Transcript text continues to
/// travel only through the existing typed final/insertable callback boundary.
public enum DictationProgress: Equatable, Sendable {
    case finalizing
    case cleaning(CleanupFormat)
    case fallingBack(CleanupFormat, CleanupFallbackReason)
    case formattedTextReady(PendingInsertionReason)
}

public enum DictationFailure: String, Error, Equatable, Sendable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case modelUnavailable
    case recordingFailed
    case noAudioCaptured
    case transcriptionFailed
    case accessibilityPermissionRequired
    case insertionFailed
    case insertionUncertain
    case recoveryRequired
}

extension DictationFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access is required to dictate."
        case .microphoneUnavailable:
            "The selected microphone is unavailable."
        case .modelUnavailable:
            "The bundled local transcription model is unavailable."
        case .recordingFailed:
            "VoxHearth could not record audio."
        case .noAudioCaptured:
            "No speech was captured."
        case .transcriptionFailed:
            "Local transcription failed."
        case .accessibilityPermissionRequired:
            "Accessibility access is required to type into other apps."
        case .insertionFailed:
            "VoxHearth could not type the transcript into the active app."
        case .insertionUncertain:
            "VoxHearth could not confirm the transcript reached the app. Retry or discard it."
        case .recoveryRequired:
            "Resolve an earlier transcript before starting another dictation."
        }
    }
}

public enum OnboardingRequirement: Equatable, Sendable {
    case microphone
    case accessibility
}

public enum GlobalHotkeyPhase: Equatable, Sendable {
    case pressed
    case released
}

public enum TextInsertionMethod: Equatable, Sendable {
    case accessibility
    case unicodeEvents
    case clipboard
}

public enum AudioCaptureError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case invalidInputFormat
    case alreadyRecording
    case notRecording
    case engineStartFailed
    case noAudioCaptured
}

public enum AudioInputSelection: Equatable, Sendable {
    case systemDefault
    case requestedDevice
    case fellBackToSystemDefault
}

public enum ParakeetEngineError: Error, Equatable, Sendable {
    case unsupportedArchitecture
    case missingModelAsset(String)
    case invalidVocabulary
    case modelLoadFailed
    case emptyAudio
    case transcriptionFailed
}

public enum TextInsertionError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case unicodeEventCreationFailed
    case clipboardFallbackDisabled
    case clipboardSnapshotFailed
    case clipboardWriteFailed
    case pasteEventCreationFailed
    case insertionFailed
    case insertionUncertain
    case multilineClipboardFallbackDisabled
    case blockedMultilineDestination
}
