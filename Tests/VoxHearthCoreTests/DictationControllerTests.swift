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
    private(set) var snapshotMaximumDurations: [TimeInterval] = []
    private(set) var requestedInputDeviceUIDs: [String?] = []
    private(set) var startPriorities: [TaskPriority] = []

    func availableInputDevices() async -> [AudioInputDevice] { [] }

    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws -> AudioInputSelection {
        startCount += 1
        startPriorities.append(Task.currentPriority)
        requestedInputDeviceUIDs.append(inputDeviceUID)
        if let startError { throw startError }
        return startSelection
    }

    func stop() async throws -> CapturedAudio {
        stopCount += 1
        return result
    }

    func snapshot(maximumDuration: TimeInterval) async -> CapturedAudio? {
        snapshotCount += 1
        snapshotMaximumDurations.append(maximumDuration)
        let maximumSampleCount = max(
            1,
            Int((result.sampleRate * maximumDuration).rounded(.down))
        )
        return CapturedAudio(
            samples: Array(result.samples.suffix(maximumSampleCount)),
            sampleRate: result.sampleRate
        )
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
    private(set) var releasePooledBuffersCount = 0
    private(set) var recoveryCount = 0

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

    func releasePooledBuffers() async {
        releasePooledBuffersCount += 1
    }

    func recover(model: TranscriptionModel) async throws {
        recoveryCount += 1
        models.append(model)
    }
}

private actor GatedPrepareEngine: LocalTranscriptionEngine {
    private(set) var prepareCount = 0
    private var firstPrepareContinuation: CheckedContinuation<Void, Never>?

    func prepare(model: TranscriptionModel) async throws {
        _ = model
        prepareCount += 1
        if prepareCount == 1 {
            await withCheckedContinuation { continuation in
                firstPrepareContinuation = continuation
            }
        }
    }

    func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage,
        model: TranscriptionModel
    ) async throws -> String {
        _ = audio
        _ = language
        _ = model
        return "dictated locally"
    }

    func releaseFirstPrepare() {
        firstPrepareContinuation?.resume()
        firstPrepareContinuation = nil
    }
}

private actor TransientPreviewEngine: LocalTranscriptionEngine {
    private(set) var transcribeCount = 0

    func prepare(model: TranscriptionModel) async throws { _ = model }

    func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage,
        model: TranscriptionModel
    ) async throws -> String {
        _ = audio
        _ = language
        _ = model
        transcribeCount += 1
        if transcribeCount == 1 {
            throw ParakeetEngineError.transcriptionFailed
        }
        return "preview recovered"
    }
}

private actor PersistentPreviewFailureEngine: LocalTranscriptionEngine {
    private(set) var transcribeCount = 0

    func prepare(model: TranscriptionModel) async throws { _ = model }

    func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage,
        model: TranscriptionModel
    ) async throws -> String {
        _ = audio
        _ = language
        _ = model
        transcribeCount += 1
        throw ParakeetEngineError.transcriptionFailed
    }
}

/// Deliberately ignores cancellation during its first inference so the test
/// can detect actor reentrancy between a live preview and final transcription.
private actor NonCooperativePreviewEngine: LocalTranscriptionEngine {
    private(set) var transcribeCount = 0
    private(set) var maximumActiveTranscriptions = 0
    private var activeTranscriptions = 0

    func prepare(model: TranscriptionModel) async throws {}

    func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage,
        model: TranscriptionModel
    ) async throws -> String {
        transcribeCount += 1
        let callNumber = transcribeCount
        activeTranscriptions += 1
        maximumActiveTranscriptions = max(
            maximumActiveTranscriptions,
            activeTranscriptions
        )

        if callNumber == 1 {
            await Task.detached {
                try? await Task.sleep(for: .milliseconds(30))
            }.value
        }

        activeTranscriptions -= 1
        return callNumber == 1 ? "preview" : "final"
    }
}

@MainActor
private final class MockTextInserter: TextInserting {
    private(set) var insertedTexts: [String] = []
    private(set) var attemptedSessionIDs: [DictationSessionID] = []
    private(set) var clipboardFlags: [Bool] = []
    private(set) var priorities: [TaskPriority] = []
    var error: TextInsertionError?

    func insert(
        _ transcript: InsertableTranscript,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        attemptedSessionIDs.append(transcript.sessionID)
        if let error { throw error }
        priorities.append(Task.currentPriority)
        insertedTexts.append(transcript.text)
        clipboardFlags.append(clipboardFallbackEnabled)
        return .accessibility
    }
}

@MainActor
private final class BlockingRetryInserter: TextInserting {
    private(set) var insertCount = 0
    private var shouldFail = true
    private var continuation: CheckedContinuation<Void, Never>?

    func insert(
        _ transcript: InsertableTranscript,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        _ = transcript
        _ = clipboardFallbackEnabled
        if shouldFail {
            shouldFail = false
            throw TextInsertionError.insertionFailed
        }
        insertCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return .accessibility
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class CountingLifecycleActivityAsserter: LifecycleActivityAsserting {
    private final class Token: NSObject {}

    private(set) var beginOptions: [ProcessInfo.ActivityOptions] = []
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var liveTokens: Set<ObjectIdentifier> = []
    private(set) var maximumLiveTokenCount = 0

    func beginActivity(
        options: ProcessInfo.ActivityOptions,
        reason: String
    ) -> any NSObjectProtocol {
        _ = reason
        let token = Token()
        beginOptions.append(options)
        beginCount += 1
        liveTokens.insert(ObjectIdentifier(token))
        maximumLiveTokenCount = max(maximumLiveTokenCount, liveTokens.count)
        return token
    }

    func endActivity(_ activity: any NSObjectProtocol) {
        endCount += 1
        if let token = activity as? Token {
            liveTokens.remove(ObjectIdentifier(token))
        }
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
    #expect(await audio.snapshotMaximumDurations.allSatisfy {
        $0 == DictationController.defaultLivePreviewWindow
    })
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

@Test @MainActor func finalTranscriptionDoesNotOverlapCancelledPreview() async {
    let audio = MockAudioCapture()
    let engine = NonCooperativePreviewEngine()
    let inserter = MockTextInserter()
    let recorder = LivePreviewRecorder()
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: AppSettings(liveTranscriptOverlayEnabled: true),
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        livePreviewInterval: .milliseconds(1),
        livePreviewMinimumDuration: 0
    )
    controller.onLiveTranscriptPreview = { recorder.values.append($0) }

    await controller.startDictation()
    for _ in 0..<500 {
        if await engine.transcribeCount == 1 { break }
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(await engine.transcribeCount == 1)

    await controller.stopDictation()

    #expect(await audio.stopCount == 1)
    #expect(await engine.transcribeCount == 2)
    #expect(await engine.maximumActiveTranscriptions == 1)
    #expect(inserter.insertedTexts == ["final"])
    #expect(!recorder.values.contains("preview"))
    #expect(recorder.values.contains("final"))
}

@Test func defaultPreviewLatencyBudgetHasAnAbsoluteFloor() {
    #expect(
        DictationController.defaultLivePreviewLatencyBudget(for: .milliseconds(100))
            == .seconds(2)
    )
    #expect(
        DictationController.defaultLivePreviewLatencyBudget(for: .seconds(1))
            == .seconds(4)
    )
}

@Test @MainActor func disablingPreviewStillJoinsBeforeFinalTranscription() async throws {
    let audio = MockAudioCapture()
    let engine = NonCooperativePreviewEngine()
    let inserter = MockTextInserter()
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: AppSettings(liveTranscriptOverlayEnabled: true),
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        livePreviewInterval: .milliseconds(1),
        livePreviewMinimumDuration: 0
    )

    await controller.startDictation()
    for _ in 0..<500 {
        if await engine.transcribeCount == 1 { break }
        await Task.yield()
    }
    #expect(await engine.transcribeCount == 1)

    try controller.applySettings(AppSettings(liveTranscriptOverlayEnabled: false))
    await controller.stopDictation()

    #expect(await engine.transcribeCount == 2)
    #expect(await engine.maximumActiveTranscriptions == 1)
    #expect(inserter.insertedTexts == ["final"])
}

@Test @MainActor func transientPreviewFailureRetriesWithinRecording() async {
    let engine = TransientPreviewEngine()
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: AppSettings(liveTranscriptOverlayEnabled: true),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        livePreviewInterval: .zero,
        livePreviewMinimumDuration: 0,
        livePreviewLatencyBudget: .seconds(60)
    )

    await controller.startDictation()
    await waitUntil(attempts: 500) {
        controller.liveTranscriptPreview == "preview recovered"
    }

    #expect(await engine.transcribeCount >= 2)
    #expect(controller.state == .recording)
    await controller.cancelDictation()
}

@Test @MainActor func persistentPreviewFailuresOpenBoundedCircuit() async {
    let engine = PersistentPreviewFailureEngine()
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: AppSettings(liveTranscriptOverlayEnabled: true),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        livePreviewInterval: .zero,
        livePreviewMinimumDuration: 0,
        livePreviewLatencyBudget: .seconds(60)
    )

    await controller.startDictation()
    for _ in 0..<500 {
        if await engine.transcribeCount == 3 { break }
        await Task.yield()
    }
    for _ in 0..<50 { await Task.yield() }

    #expect(await engine.transcribeCount == 3)
    #expect(controller.state == .recording)
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
    #expect(inserter.attemptedSessionIDs.count == 2)
    #expect(Set(inserter.attemptedSessionIDs).count == 1)
}

@Test @MainActor func concurrentRetryRequestsInsertOnlyOnce() async {
    let inserter = BlockingRetryInserter()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService()
    )

    await controller.startDictation()
    await controller.stopDictation()
    #expect(controller.pendingTranscript == "dictated locally")

    let first = Task { @MainActor in await controller.retryPendingInsertion() }
    await waitUntil { controller.state == .inserting }
    let second = Task { @MainActor in await controller.retryPendingInsertion() }
    await Task.yield()
    inserter.release()
    await first.value
    await second.value

    #expect(inserter.insertCount == 1)
    #expect(controller.pendingTranscript == nil)
    #expect(controller.state == .idle)
}

@Test @MainActor func uncertainInsertionRequiresExplicitRetry() async {
    let inserter = MockTextInserter()
    inserter.error = .insertionUncertain
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService()
    )

    await controller.startDictation()
    await controller.stopDictation()
    #expect(controller.state == .failed(.insertionUncertain))
    #expect(controller.pendingTranscript == "dictated locally")
    #expect(inserter.insertedTexts.isEmpty)

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

@Test @MainActor func staleCancelledStartCannotClobberNewPress() async throws {
    let hotkey = MockHotkeyService()
    let audio = MockAudioCapture()
    let engine = GatedPrepareEngine()
    let activity = CountingLifecycleActivityAsserter()
    let controller = DictationController(
        transcriptionEngine: engine,
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: hotkey,
        lifecycleActivityAsserter: activity
    )
    try controller.activate()

    hotkey.emit(.pressed)
    for _ in 0..<500 {
        if await engine.prepareCount == 1 { break }
        await Task.yield()
    }
    #expect(await engine.prepareCount == 1)
    hotkey.emit(.released)
    #expect(controller.state == .idle)
    hotkey.emit(.pressed)
    #expect(controller.state == .preparing)
    await engine.releaseFirstPrepare()
    await waitUntil { controller.state == .recording }

    #expect(controller.state == .recording)
    #expect(activity.liveTokens.count == 1)
    #expect(activity.beginCount - activity.endCount == 1)
    #expect(await audio.cancelCount == 1)
    await controller.cancelDictation()
}

@Test @MainActor func backgroundPreparationCannotClobberQueuedHotkeyStart() async throws {
    let hotkey = MockHotkeyService()
    let audio = MockAudioCapture()
    let engine = GatedPrepareEngine()
    let activity = CountingLifecycleActivityAsserter()
    let controller = DictationController(
        transcriptionEngine: engine,
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: hotkey,
        lifecycleActivityAsserter: activity
    )
    try controller.activate()

    let backgroundPreparation = Task { @MainActor in
        await controller.prepareEngine()
    }
    for _ in 0..<500 {
        if await engine.prepareCount == 1 { break }
        await Task.yield()
    }
    #expect(controller.state == .preparing)

    hotkey.emit(.released)
    #expect(controller.state == .preparing)

    hotkey.emit(.pressed)
    #expect(controller.state == .preparing)
    hotkey.emit(.released)
    #expect(controller.state == .idle)
    hotkey.emit(.pressed)
    #expect(controller.state == .preparing)

    await engine.releaseFirstPrepare()
    await backgroundPreparation.value
    await waitUntil(attempts: 500) { controller.state == .recording }

    #expect(controller.state == .recording)
    #expect(await engine.prepareCount == 2)
    #expect(await audio.startCount == 1)
    #expect(activity.liveTokens.count == 1)
    #expect(activity.beginCount - activity.endCount == 1)
    await controller.cancelDictation()
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

@Test @MainActor func hotkeyAcceptsPressAndReleaseSynchronously() throws {
    let hotkey = MockHotkeyService()
    let activity = CountingLifecycleActivityAsserter()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: hotkey,
        lifecycleActivityAsserter: activity
    )
    try controller.activate()

    hotkey.emit(.pressed)
    #expect(controller.state == .preparing)
    #expect(activity.beginCount == 1)
    #expect(activity.liveTokens.count == 1)

    hotkey.emit(.pressed)
    #expect(activity.beginCount == 1)

    hotkey.emit(.released)
    #expect(controller.state == .idle)
    #expect(activity.beginCount == activity.endCount)
    #expect(activity.liveTokens.isEmpty)

    hotkey.emit(.released)
    #expect(activity.beginCount == activity.endCount)
}

@Test @MainActor func successfulSessionNarrowsAndBalancesLifecycleActivity() async {
    let activity = CountingLifecycleActivityAsserter()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        lifecycleActivityAsserter: activity
    )

    await controller.startDictation()
    #expect(controller.state == .recording)
    #expect(activity.liveTokens.count == 1)
    await controller.stopDictation()

    #expect(controller.state == .idle)
    #expect(activity.beginCount == 2)
    #expect(activity.endCount == 2)
    #expect(activity.maximumLiveTokenCount == 2)
    #expect(activity.liveTokens.isEmpty)
    #expect(activity.beginOptions[0].contains(.latencyCritical))
    #expect(activity.beginOptions[0].contains(.userInitiatedAllowingIdleSystemSleep))
    #expect(!activity.beginOptions[1].contains(.latencyCritical))
    #expect(activity.beginOptions[1].contains(.userInitiatedAllowingIdleSystemSleep))
}

@Test @MainActor func lifecycleActivityBalancesOnStartAndInsertionFailures() async {
    let startActivity = CountingLifecycleActivityAsserter()
    let failedCapture = MockAudioCapture()
    await failedCapture.setStartError(.microphoneUnavailable)
    let startController = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: failedCapture,
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        lifecycleActivityAsserter: startActivity
    )
    await startController.startDictation()
    #expect(startController.state == .failed(.microphoneUnavailable))
    #expect(startActivity.beginCount == startActivity.endCount)
    #expect(startActivity.liveTokens.isEmpty)

    let insertionActivity = CountingLifecycleActivityAsserter()
    let failedInserter = MockTextInserter()
    failedInserter.error = .insertionUncertain
    let insertionController = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: failedInserter,
        hotkeyService: MockHotkeyService(),
        lifecycleActivityAsserter: insertionActivity
    )
    await insertionController.startDictation()
    await insertionController.stopDictation()
    #expect(insertionController.state == .failed(.insertionUncertain))
    #expect(insertionActivity.beginCount == insertionActivity.endCount)
    #expect(insertionActivity.liveTokens.isEmpty)
}

@Test @MainActor func userVisiblePipelineRunsAtUserInitiatedPriority() async {
    let audio = MockAudioCapture()
    let inserter = MockTextInserter()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: MockHotkeyService()
    )

    await controller.startDictation()
    await controller.stopDictation()

    #expect(await audio.startPriorities == [.userInitiated])
    #expect(inserter.priorities == [.userInitiated])
}

@Test @MainActor func lifecycleActivityBalancesForCancelExternalRetryAndDeactivate() async {
    let cancelActivity = CountingLifecycleActivityAsserter()
    let cancelController = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        lifecycleActivityAsserter: cancelActivity
    )
    await cancelController.startDictation()
    await cancelController.cancelDictation()
    #expect(cancelActivity.beginCount == cancelActivity.endCount)
    #expect(cancelActivity.liveTokens.isEmpty)

    let externalActivity = CountingLifecycleActivityAsserter()
    let externalController = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        lifecycleActivityAsserter: externalActivity
    )
    let externalResult = await externalController.submitExternalAudio(
        CapturedAudio(samples: [0.1], sampleRate: 16_000)
    )
    #expect(externalResult == .accepted)
    #expect(externalActivity.beginCount == externalActivity.endCount)
    #expect(externalActivity.liveTokens.isEmpty)

    let retryActivity = CountingLifecycleActivityAsserter()
    let retryInserter = MockTextInserter()
    retryInserter.error = .insertionFailed
    let retryController = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: retryInserter,
        hotkeyService: MockHotkeyService(),
        lifecycleActivityAsserter: retryActivity
    )
    await retryController.startDictation()
    await retryController.stopDictation()
    retryController.discardPendingTranscript()
    #expect(retryActivity.beginCount == retryActivity.endCount)
    #expect(retryActivity.liveTokens.isEmpty)

    retryInserter.error = .insertionFailed
    await retryController.startDictation()
    await retryController.stopDictation()
    retryInserter.error = nil
    await retryController.retryPendingInsertion()
    #expect(retryActivity.beginCount == retryActivity.endCount)
    #expect(retryActivity.liveTokens.isEmpty)

    let deactivateActivity = CountingLifecycleActivityAsserter()
    let deactivateController = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        lifecycleActivityAsserter: deactivateActivity
    )
    await deactivateController.startDictation()
    deactivateController.deactivate()
    #expect(deactivateActivity.beginCount == deactivateActivity.endCount)
    #expect(deactivateActivity.liveTokens.isEmpty)
    await deactivateController.cancelDictation()
}

@Test @MainActor func pathologicalPreviewOpensPerRecordingCircuitWithoutBlockingFinal() async {
    let audio = MockAudioCapture()
    let engine = MockTranscriptionEngine()
    let inserter = MockTextInserter()
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: AppSettings(liveTranscriptOverlayEnabled: true),
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        livePreviewInterval: .zero,
        livePreviewMinimumDuration: 0,
        livePreviewLatencyBudget: .nanoseconds(-1)
    )

    await controller.startDictation()
    await waitUntil(attempts: 500) { controller.liveTranscriptPreview == "dictated locally" }
    let firstRecordingPreviewCount = await engine.transcribeCount
    for _ in 0..<50 { await Task.yield() }
    #expect(await engine.transcribeCount == firstRecordingPreviewCount)

    await controller.stopDictation()
    #expect(controller.state == .idle)
    #expect(inserter.insertedTexts == ["dictated locally"])

    await controller.startDictation()
    await waitUntil(attempts: 500) {
        controller.liveTranscriptPreview == "dictated locally"
    }
    #expect(await engine.transcribeCount > firstRecordingPreviewCount + 1)
    await controller.cancelDictation()
}

@Test @MainActor func diagnosticPoolReleaseRunsOnlyAfterReturningIdle() async {
    let engine = MockTranscriptionEngine()
    let controller = DictationController(
        transcriptionEngine: engine,
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        releasePooledBuffersWhenIdle: true
    )

    await controller.startDictation()
    #expect(await engine.releasePooledBuffersCount == 0)
    await controller.stopDictation()
    await waitUntil(attempts: 500) {
        controller.state == .idle
    }
    for _ in 0..<20 where await engine.releasePooledBuffersCount == 0 {
        await Task.yield()
    }
    #expect(await engine.releasePooledBuffersCount == 1)
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
