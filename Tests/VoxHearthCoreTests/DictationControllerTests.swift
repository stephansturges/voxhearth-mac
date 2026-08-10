import Foundation
import Testing
@testable import VoxHearthCore

private actor MockAudioCapture: AudioCapturing {
    var result = CapturedAudio(samples: [0.1, -0.1, 0.2], sampleRate: 16_000)
    var startError: AudioCaptureError?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    func availableInputDevices() async -> [AudioInputDevice] { [] }

    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws {
        startCount += 1
        if let startError { throw startError }
    }

    func stop() async throws -> CapturedAudio {
        stopCount += 1
        return result
    }

    func cancel() async {
        cancelCount += 1
    }
}

private actor MockTranscriptionEngine: LocalTranscriptionEngine {
    var transcript = "dictated locally"
    var prepareError: ParakeetEngineError?
    private(set) var prepareCount = 0
    private(set) var transcribeCount = 0
    private(set) var languages: [DictationLanguage] = []

    func prepare() async throws {
        prepareCount += 1
        if let prepareError { throw prepareError }
    }

    func transcribe(_ audio: CapturedAudio, language: DictationLanguage) async throws -> String {
        transcribeCount += 1
        languages.append(language)
        return transcript
    }
}

@MainActor
private final class MockTextInserter: TextInserting {
    private(set) var insertedTexts: [String] = []
    private(set) var clipboardFlags: [Bool] = []
    var error: TextInsertionError?

    func insert(
        _ text: String,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        if let error { throw error }
        insertedTexts.append(text)
        clipboardFlags.append(clipboardFallbackEnabled)
        return .accessibility
    }
}

@MainActor
private final class MockHotkeyService: GlobalHotkeyRegistering {
    private(set) var registeredConfiguration: HotkeyConfiguration?
    private var handler: (@MainActor @Sendable (GlobalHotkeyPhase) -> Void)?

    func register(
        _ configuration: HotkeyConfiguration,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) throws {
        registeredConfiguration = configuration
        handler = onEvent
    }

    func unregister() {
        registeredConfiguration = nil
        handler = nil
    }

    func emit(_ phase: GlobalHotkeyPhase) {
        handler?(phase)
    }
}

@MainActor
private final class OnboardingRecorder: @unchecked Sendable {
    var requirements: [OnboardingRequirement] = []
}

@Test @MainActor func controllerRunsMemoryOnlyDictationPipeline() async {
    let audio = MockAudioCapture()
    let engine = MockTranscriptionEngine()
    let inserter = MockTextInserter()
    let hotkey = MockHotkeyService()
    var settings = AppSettings.default
    settings.language = .french
    settings.clipboardCompatibilityEnabled = true
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: hotkey
    )

    await controller.startDictation()
    #expect(controller.state == .recording)
    #expect(controller.recordingStartedAt != nil)

    await controller.stopDictation()
    #expect(controller.state == .idle)
    #expect(controller.recordingStartedAt == nil)
    #expect(inserter.insertedTexts == ["dictated locally"])
    #expect(inserter.clipboardFlags == [true])
    #expect(await engine.languages == [.french])
    #expect(await audio.startCount == 1)
    #expect(await audio.stopCount == 1)
}

@Test @MainActor func microphoneDenialSurfacesOnboardingRequirement() async {
    let audio = MockAudioCapture()
    await audio.setStartError(.microphonePermissionDenied)
    let recorder = OnboardingRecorder()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService()
    )
    controller.onOnboardingRequirement = { requirement in
        recorder.requirements.append(requirement)
    }

    await controller.startDictation()
    #expect(controller.state == .failed(.microphonePermissionDenied))
    #expect(recorder.requirements == [.microphone])
}

@Test @MainActor func accessibilityFailureSurfacesOnboardingRequirement() async {
    let inserter = MockTextInserter()
    inserter.error = .accessibilityPermissionRequired
    let recorder = OnboardingRecorder()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService()
    )
    controller.onOnboardingRequirement = { requirement in
        recorder.requirements.append(requirement)
    }

    await controller.startDictation()
    await controller.stopDictation()
    #expect(controller.state == .failed(.accessibilityPermissionRequired))
    #expect(controller.pendingTranscript == "dictated locally")
    #expect(recorder.requirements == [.accessibility])
}

@Test @MainActor func failedInsertionCanRetryWithoutPersistingTranscript() async {
    let inserter = MockTextInserter()
    inserter.error = .insertionFailed
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService()
    )

    await controller.startDictation()
    await controller.stopDictation()
    #expect(controller.pendingTranscript == "dictated locally")

    inserter.error = nil
    await controller.retryPendingInsertion()
    #expect(controller.pendingTranscript == nil)
    #expect(controller.state == .idle)
    #expect(inserter.insertedTexts == ["dictated locally"])
}

@Test @MainActor func pendingTranscriptExpiresFromMemory() async {
    let inserter = MockTextInserter()
    inserter.error = .insertionFailed
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        pendingTranscriptLifetime: .zero
    )

    await controller.startDictation()
    await controller.stopDictation()
    await waitUntil { controller.pendingTranscript == nil }
    #expect(controller.pendingTranscript == nil)
    #expect(controller.state == .idle)
}

@Test @MainActor func hotkeyRegistersHoldToTalkPhases() async throws {
    let hotkey = MockHotkeyService()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: hotkey
    )
    try controller.activate()
    #expect(hotkey.registeredConfiguration == .controlOptionSpace)

    hotkey.emit(.pressed)
    await waitUntil { controller.state == .recording }
    hotkey.emit(.released)
    await waitUntil { controller.state == .idle }
    #expect(controller.state == .idle)
}

@MainActor
private func waitUntil(
    attempts: Int = 100,
    _ predicate: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<attempts {
        if predicate() { return }
        await Task.yield()
    }
}

private extension MockAudioCapture {
    func setStartError(_ error: AudioCaptureError?) {
        startError = error
    }
}
