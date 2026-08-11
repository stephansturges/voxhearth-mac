import Foundation

public protocol AudioCapturing: Sendable {
    func availableInputDevices() async -> [AudioInputDevice]

    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws -> AudioInputSelection

    /// Returns a copy of the active in-memory capture for an optional local
    /// preview. Implementations must not persist the snapshot.
    func snapshot() async -> CapturedAudio?

    func stop() async throws -> CapturedAudio
    func cancel() async
}

public protocol LocalTranscriptionEngine: Sendable {
    func prepare(model: TranscriptionModel) async throws
    func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage,
        model: TranscriptionModel
    ) async throws -> String
}

@MainActor
public protocol TextInserting: AnyObject {
    func insert(
        _ text: String,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod
}

@MainActor
public protocol GlobalHotkeyRegistering: AnyObject {
    func register(
        _ configuration: HotkeyConfiguration,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) throws

    func unregister()
}

@MainActor
public protocol GlobalPointerButtonRegistering: AnyObject {
    func register(
        buttonNumber: UInt32?,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    )

    func unregister()
}
