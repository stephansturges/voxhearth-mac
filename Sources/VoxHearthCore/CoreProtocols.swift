import Foundation

public protocol AudioCapturing: Sendable {
    func availableInputDevices() async -> [AudioInputDevice]

    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws

    func stop() async throws -> CapturedAudio
    func cancel() async
}

public protocol LocalTranscriptionEngine: Sendable {
    func prepare() async throws
    func transcribe(_ audio: CapturedAudio, language: DictationLanguage) async throws -> String
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
