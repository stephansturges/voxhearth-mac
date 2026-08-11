import Foundation
import Testing
@testable import VoxHearthCore

private actor MockAudioCapture: AudioCapturing {
    var result = CapturedAudio(samples: [0.1, -0.1, 0.2], sampleRate: 16_000)
    var startError: AudioCaptureError?
    var startSelection = AudioInputSelection.systemDefault
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var snapshotCount = 0
    private(set) var requestedInputDeviceUIDs: [String?] = []

    func availableInputDevices() async -> [AudioInputDevice] { [] }

    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws -> AudioInputSelection {
        startCount += 1
        requestedInputDeviceUIDs.append(inputDeviceUID)
        if let startError { throw startError }
        return startSelection
    }

    func stop() async throws -> CapturedAudio {
        stopCount += 1
        return result
    }

    func snapshot() async -> CapturedAudio? {
        snapshotCount += 1
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
    private(set) var models: [TranscriptionModel] = []

    func prepare(model: TranscriptionModel) async throws {
        prepareCount += 1
        models.append(model)
        if let prepareError { throw prepareError }
    }

    func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage,
        model: TranscriptionModel
    ) async throws -> String {
        transcribeCount += 1
        languages.append(language)
        models.append(model)
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
private final class MockPointerButtonService: GlobalPointerButtonRegistering {
    private(set) var registeredButtonNumber: UInt32?
    private var handler: (@MainActor @Sendable (GlobalHotkeyPhase) -> Void)?

    func register(
        buttonNumber: UInt32?,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) {
        registeredButtonNumber = buttonNumber
        handler = buttonNumber == nil ? nil : onEvent
    }

    func unregister() {
        registeredButtonNumber = nil
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

@MainActor
private final class StartCueRecorder: @unchecked Sendable {
    var count = 0
}

@MainActor
private final class InputFallbackRecorder: @unchecked Sendable {
    var count = 0
}

@MainActor
private final class LivePreviewRecorder: @unchecked Sendable {
    var values: [String?] = []
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
    #expect(await engine.models == [.multilingual, .multilingual])
    #expect(await audio.startCount == 1)
    #expect(await audio.stopCount == 1)
}

@Test @MainActor func optionalLivePreviewUsesSnapshotsAndClearsOnCancel() async {
    let audio = MockAudioCapture()
    let engine = MockTranscriptionEngine()
    let recorder = LivePreviewRecorder()
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: AppSettings(liveTranscriptOverlayEnabled: true),
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        livePreviewInterval: .milliseconds(1),
        livePreviewMinimumDuration: 0
    )
    controller.onLiveTranscriptPreview = { recorder.values.append($0) }

    await controller.startDictation()
    await waitUntil(attempts: 500) { controller.liveTranscriptPreview == "dictated locally" }

    #expect(controller.state == .recording)
    #expect(controller.liveTranscriptPreview == "dictated locally")
    #expect(await audio.snapshotCount > 0)
    #expect(await engine.transcribeCount > 0)
    #expect(recorder.values.first == "")

    await controller.cancelDictation()
    #expect(controller.liveTranscriptPreview == nil)
    #expect(recorder.values.count >= 2)
    #expect(recorder.values[recorder.values.count - 1] == nil)
}

@Test @MainActor func livePreviewIsDisabledByDefault() async {
    let audio = MockAudioCapture()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        livePreviewInterval: .milliseconds(1),
        livePreviewMinimumDuration: 0
    )

    await controller.startDictation()
    try? await Task.sleep(for: .milliseconds(5))

    #expect(controller.liveTranscriptPreview == nil)
    #expect(await audio.snapshotCount == 0)
    await controller.cancelDictation()
}

@Test @MainActor func controllerPreparesSelectedCompactModelInEnglish() async {
    let engine = MockTranscriptionEngine()
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: AppSettings(
            transcriptionModel: .compactEnglish,
            language: .french
        ),
        hotkeyService: MockHotkeyService()
    )

    await controller.prepareEngine()

    #expect(controller.state == .idle)
    #expect(controller.settings.transcriptionModel == .compactEnglish)
    #expect(controller.settings.language == .english)
    #expect(await engine.models == [.compactEnglish])
}

@Test @MainActor func externalAudioUsesLocalPipelineWithoutOpeningMicrophone() async {
    let audio = MockAudioCapture()
    let engine = MockTranscriptionEngine()
    let inserter = MockTextInserter()
    let cue = StartCueRecorder()
    var settings = AppSettings.default
    settings.language = .german
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: MockHotkeyService()
    )
    controller.onStartCue = { cue.count += 1 }

    let result = await controller.submitExternalAudio(
        CapturedAudio(samples: [0.25, -0.25], sampleRate: 16_000)
    )

    #expect(result == .accepted)
    #expect(controller.state == .idle)
    #expect(inserter.insertedTexts == ["dictated locally"])
    #expect(await engine.languages == [.german])
    #expect(await audio.startCount == 0)
    #expect(await audio.stopCount == 0)
    #expect(cue.count == 0)
}

@Test @MainActor func externalAudioRejectsInvalidOrConcurrentSubmission() async {
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService()
    )

    let invalid = await controller.submitExternalAudio(
        CapturedAudio(samples: [], sampleRate: 16_000)
    )
    #expect(invalid == .invalidAudio)

    let tooLong = await controller.submitExternalAudio(
        CapturedAudio(
            samples: Array(
                repeating: 0.1,
                count: Int(DictationController.maximumExternalAudioDuration) + 1
            ),
            sampleRate: 1
        )
    )
    #expect(tooLong == .invalidAudio)

    await controller.startDictation()
    let busy = await controller.submitExternalAudio(
        CapturedAudio(samples: [0.1], sampleRate: 16_000)
    )
    #expect(busy == .busy)
    await controller.cancelDictation()
}

@Test @MainActor func startCueRunsBeforeMicrophoneCapture() async {
    let audio = MockAudioCapture()
    let cue = StartCueRecorder()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService()
    )
    controller.onStartCue = {
        #expect(await audio.startCount == 0)
        cue.count += 1
    }

    await controller.startDictation()

    #expect(cue.count == 1)
    #expect(await audio.startCount == 1)
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

@Test @MainActor func unavailableSelectedMicrophoneFallsBackAndClearsSelection() async {
    let audio = MockAudioCapture()
    await audio.setStartSelection(.fellBackToSystemDefault)
    let fallback = InputFallbackRecorder()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        settings: AppSettings(inputDeviceUID: "disconnected-device"),
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService()
    )
    controller.onInputDeviceFallback = { fallback.count += 1 }

    await controller.startDictation()

    #expect(controller.state == .recording)
    #expect(controller.settings.inputDeviceUID == nil)
    #expect(fallback.count == 1)
    #expect(await audio.requestedInputDeviceUIDs == ["disconnected-device"])
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

@Test @MainActor func pointerButtonRegistersHoldToTalkPhases() async throws {
    let pointer = MockPointerButtonService()
    var settings = AppSettings.default
    settings.pointerButton = 4
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        settings: settings,
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        pointerButtonService: pointer
    )
    try controller.activate()
    #expect(pointer.registeredButtonNumber == 4)

    pointer.emit(.pressed)
    await waitUntil { controller.state == .recording }
    pointer.emit(.released)
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

    func setStartSelection(_ selection: AudioInputSelection) {
        startSelection = selection
    }
}
