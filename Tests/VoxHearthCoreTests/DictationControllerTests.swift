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

private actor GatedCancelAudioCapture: AudioCapturing {
    private(set) var cancelStartedCount = 0
    private var cancelContinuations: [CheckedContinuation<Void, Never>] = []
    private let result = CapturedAudio(samples: [0.1, -0.1, 0.2], sampleRate: 16_000)

    func availableInputDevices() async -> [AudioInputDevice] { [] }

    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws -> AudioInputSelection {
        _ = inputDeviceUID
        _ = maximumDurationReached
        return .systemDefault
    }

    func stop() async throws -> CapturedAudio { result }

    func snapshot(maximumDuration: TimeInterval) async -> CapturedAudio? {
        _ = maximumDuration
        return nil
    }

    func cancel() async {
        cancelStartedCount += 1
        await withCheckedContinuation { continuation in
            cancelContinuations.append(continuation)
        }
    }

    func releaseNextCancel() {
        guard !cancelContinuations.isEmpty else { return }
        cancelContinuations.removeFirst().resume()
    }
}

private actor GatedStopAndCancelAudioCapture: AudioCapturing {
    private(set) var stopStarted = false
    private(set) var cancelStarted = false
    private var stopCount = 0
    private var cancelContinuation: CheckedContinuation<Void, Never>?

    func availableInputDevices() async -> [AudioInputDevice] { [] }

    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws -> AudioInputSelection {
        _ = inputDeviceUID
        _ = maximumDurationReached
        return .systemDefault
    }

    func stop() async throws -> CapturedAudio {
        stopCount += 1
        if stopCount > 1 {
            return CapturedAudio(samples: [0.1, -0.1, 0.2], sampleRate: 16_000)
        }
        stopStarted = true
        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(1))
        }
        throw CancellationError()
    }

    func snapshot(maximumDuration: TimeInterval) async -> CapturedAudio? {
        _ = maximumDuration
        return nil
    }

    func cancel() async {
        cancelStarted = true
        await withCheckedContinuation { continuation in
            cancelContinuation = continuation
        }
    }

    func releaseCancel() {
        cancelContinuation?.resume()
        cancelContinuation = nil
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

private actor MockCleanupNormalizer: TranscriptNormalizing {
    enum Behavior: Sendable {
        case cleaned(String)
        case fallback(CleanupFallbackReason)
        case waitForCancellation
    }

    var behavior: Behavior
    private(set) var prepareCount = 0
    private(set) var unloadCount = 0
    private(set) var inputs: [NormalizationInput] = []
    private(set) var settings: [CleanupSettings] = []

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func prepare(
        modelURL: URL,
        selection: LlamaBackendSelection,
        warmUp: Bool,
        deadlineMilliseconds: Int
    ) async throws -> LlamaBackend {
        _ = modelURL
        _ = warmUp
        _ = deadlineMilliseconds
        prepareCount += 1
        return selection.selected
    }

    func normalize(
        _ input: NormalizationInput,
        settings: CleanupSettings,
        cancellation: S1MiniCancellationToken,
        deadlineMilliseconds: Int
    ) async -> DictationOutcome {
        _ = deadlineMilliseconds
        inputs.append(input)
        self.settings.append(settings)
        switch behavior {
        case let .cleaned(text):
            return .insert(CleanupPolicy().cleaned(for: input, text: text))
        case let .fallback(reason):
            return .recover(CleanupPolicy().fallback(for: input, reason: reason), reason)
        case .waitForCancellation:
            while !cancellation.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
            }
            return .cancelled(input.sessionID)
        }
    }

    func unload() async { unloadCount += 1 }
}

@MainActor
private final class GatedFailingInserter: TextInserting {
    private(set) var attempted: [InsertableTranscript] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func insert(
        _ transcript: InsertableTranscript,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        _ = clipboardFallbackEnabled
        attempted.append(transcript)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        throw TextInsertionError.insertionFailed
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class RetryExpiryInserter: TextInserting {
    private(set) var attemptCount = 0
    private var retryContinuation: CheckedContinuation<Void, Never>?

    func insert(
        _ transcript: InsertableTranscript,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        _ = transcript
        _ = clipboardFallbackEnabled
        attemptCount += 1
        if attemptCount == 2 {
            await withCheckedContinuation { continuation in
                retryContinuation = continuation
            }
        }
        throw TextInsertionError.insertionFailed
    }

    func releaseRetry() {
        retryContinuation?.resume()
        retryContinuation = nil
    }
}

@MainActor
private final class GatedRecoverySuccessInserter: TextInserting {
    private let initialError: TextInsertionError
    private(set) var attemptCount = 0
    private var recoveryContinuation: CheckedContinuation<Void, Never>?

    init(initialError: TextInsertionError) {
        self.initialError = initialError
    }

    func insert(
        _ transcript: InsertableTranscript,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        _ = transcript
        _ = clipboardFallbackEnabled
        attemptCount += 1
        if attemptCount == 1 { throw initialError }
        if attemptCount == 2 {
            await withCheckedContinuation { continuation in
                recoveryContinuation = continuation
            }
        }
        return .accessibility
    }

    func releaseRecovery() {
        recoveryContinuation?.resume()
        recoveryContinuation = nil
    }
}

private actor GatedUnloadNormalizer: TranscriptNormalizing {
    private(set) var unloadStarted = false
    private(set) var unloadCompleted = false
    private var unloadContinuation: CheckedContinuation<Void, Never>?

    func prepare(
        modelURL: URL,
        selection: LlamaBackendSelection,
        warmUp: Bool,
        deadlineMilliseconds: Int
    ) async throws -> LlamaBackend {
        _ = modelURL
        _ = warmUp
        _ = deadlineMilliseconds
        return selection.selected
    }

    func normalize(
        _ input: NormalizationInput,
        settings: CleanupSettings,
        cancellation: S1MiniCancellationToken,
        deadlineMilliseconds: Int
    ) async -> DictationOutcome {
        _ = settings
        _ = cancellation
        _ = deadlineMilliseconds
        return .recover(CleanupPolicy().fallback(for: input, reason: .modelUnavailable), .modelUnavailable)
    }

    func unload() async {
        unloadStarted = true
        await withCheckedContinuation { continuation in
            unloadContinuation = continuation
        }
        unloadCompleted = true
    }

    func releaseUnload() {
        unloadContinuation?.resume()
        unloadContinuation = nil
    }
}

private actor GatedCleanupPreparationNormalizer: TranscriptNormalizing {
    private(set) var prepareStarted = false
    private(set) var unloadCount = 0
    private(set) var inputs: [NormalizationInput] = []
    private var prepareContinuation: CheckedContinuation<Void, Never>?

    func prepare(
        modelURL: URL,
        selection: LlamaBackendSelection,
        warmUp: Bool,
        deadlineMilliseconds: Int
    ) async throws -> LlamaBackend {
        _ = modelURL
        _ = warmUp
        _ = deadlineMilliseconds
        prepareStarted = true
        await withCheckedContinuation { continuation in
            prepareContinuation = continuation
        }
        return selection.selected
    }

    func normalize(
        _ input: NormalizationInput,
        settings: CleanupSettings,
        cancellation: S1MiniCancellationToken,
        deadlineMilliseconds: Int
    ) async -> DictationOutcome {
        _ = settings
        _ = cancellation
        _ = deadlineMilliseconds
        inputs.append(input)
        return .recover(CleanupPolicy().fallback(for: input, reason: .modelUnavailable), .modelUnavailable)
    }

    func unload() async { unloadCount += 1 }

    func releasePreparation() {
        prepareContinuation?.resume()
        prepareContinuation = nil
    }
}

private actor GatedCleanupCompletionNormalizer: TranscriptNormalizing {
    private(set) var normalizeStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func prepare(
        modelURL: URL,
        selection: LlamaBackendSelection,
        warmUp: Bool,
        deadlineMilliseconds: Int
    ) async throws -> LlamaBackend {
        _ = modelURL
        _ = warmUp
        _ = deadlineMilliseconds
        return selection.selected
    }

    func normalize(
        _ input: NormalizationInput,
        settings: CleanupSettings,
        cancellation: S1MiniCancellationToken,
        deadlineMilliseconds: Int
    ) async -> DictationOutcome {
        _ = settings
        _ = cancellation
        _ = deadlineMilliseconds
        normalizeStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return .insert(CleanupPolicy().cleaned(for: input, text: "cleaned"))
    }

    func unload() async {}

    func releaseNormalization() {
        continuation?.resume()
        continuation = nil
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

private actor GatedFinalTranscriptionEngine: LocalTranscriptionEngine {
    private(set) var transcribeCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

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
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            return "old session text"
        }
        return "new session text"
    }

    func releaseFirstTranscription() {
        continuation?.resume()
        continuation = nil
    }
}

/// Deliberately ignores cancellation during its first inference so the test
/// can detect actor reentrancy between a live preview and final transcription.
private actor NonCooperativePreviewEngine: LocalTranscriptionEngine {
    private(set) var transcribeCount = 0
    private(set) var maximumActiveTranscriptions = 0
    private(set) var firstTranscriptionStarted = false
    private var activeTranscriptions = 0
    private var firstTranscriptionContinuation: CheckedContinuation<Void, Never>?

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
            firstTranscriptionStarted = true
            await withCheckedContinuation { continuation in
                firstTranscriptionContinuation = continuation
            }
        }

        activeTranscriptions -= 1
        return callNumber == 1 ? "preview" : "final"
    }

    func releaseFirstTranscription() {
        firstTranscriptionContinuation?.resume()
        firstTranscriptionContinuation = nil
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
private final class DictationPresentationRecorder {
    private(set) var progress: [DictationProgress] = []
    private(set) var selections: [(FinalTranscript, InsertableTranscript, RecognizedDirective?)] = []
    private(set) var overlayValues: [String?] = []

    func record(_ progress: DictationProgress) {
        self.progress.append(progress)
    }

    func record(
        original: FinalTranscript,
        selected: InsertableTranscript,
        directive: RecognizedDirective?
    ) {
        selections.append((original, selected, directive))
    }

    func recordOverlay(_ text: String?) {
        overlayValues.append(text)
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
    for _ in 0..<5_000 {
        if await engine.firstTranscriptionStarted { break }
        await Task.yield()
    }
    #expect(await engine.firstTranscriptionStarted)
    #expect(await engine.transcribeCount == 1)

    let stopTask = Task { await controller.stopDictation() }
    await waitUntil(attempts: 5_000) { controller.state == .transcribing }
    #expect(controller.state == .transcribing)
    await engine.releaseFirstTranscription()
    await stopTask.value

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
    for _ in 0..<5_000 {
        if await engine.firstTranscriptionStarted { break }
        await Task.yield()
    }
    #expect(await engine.firstTranscriptionStarted)
    #expect(await engine.transcribeCount == 1)

    try controller.applySettings(AppSettings(liveTranscriptOverlayEnabled: false))
    let stopTask = Task { await controller.stopDictation() }
    await waitUntil(attempts: 5_000) { controller.state == .transcribing }
    #expect(controller.state == .transcribing)
    await engine.releaseFirstTranscription()
    await stopTask.value

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
    #expect(recoveryReservationCount(controller) == 1)
    #expect(activity.liveTokens.count == 1)
    #expect(activity.beginCount - activity.endCount == 1)
    await controller.cancelDictation()
    #expect(recoveryReservationCount(controller) == 0)
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

@Test @MainActor func effectiveCleanupParsesOnceAndInsertsTheCleanedSessionValue() async throws {
    let engine = MockTranscriptionEngine()
    await engine.setTranscript("list milk eggs bread")
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("- Milk\n- Eggs\n- Bread"))
    let inserter = MockTextInserter()
    let controller = DictationController(
        transcriptionEngine: engine,
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    await controller.prepareCleanupModelIfEffective()

    await controller.startDictation()
    await controller.stopDictation()

    let inputs = await normalizer.inputs
    let input = try #require(inputs.first)
    #expect(inputs.count == 1)
    #expect(input.format == .listGeneral)
    #expect(String(input.text) == "milk eggs bread")
    #expect(inserter.insertedTexts == ["- Milk\n- Eggs\n- Bread"])
    #expect(inserter.attemptedSessionIDs == [input.sessionID])
    #expect(controller.state == .idle)
}

@Test @MainActor func unpreparedCleanupFallsBackImmediatelyWithoutQueueingNormalization() async {
    let engine = MockTranscriptionEngine()
    await engine.setTranscript("list milk eggs bread")
    let normalizer = GatedCleanupPreparationNormalizer()
    let inserter = MockTextInserter()
    let controller = DictationController(
        transcriptionEngine: engine,
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )

    await controller.startDictation()
    for _ in 0..<1_000 where !(await normalizer.prepareStarted) {
        await Task.yield()
    }
    #expect(await normalizer.prepareStarted)
    await controller.stopDictation()
    #expect(await normalizer.inputs.isEmpty)
    #expect(inserter.insertedTexts == ["milk eggs bread"])
    #expect(controller.state == .idle)
    await normalizer.releasePreparation()
}

@Test @MainActor func acceptedEmptyCleanupFinishesWithoutInsertionOrRecovery() async {
    let engine = MockTranscriptionEngine()
    await engine.setTranscript("um uh")
    let normalizer = MockCleanupNormalizer(behavior: .cleaned(""))
    let inserter = MockTextInserter()
    var settings = AppSettings.default
    settings.liveTranscriptOverlayEnabled = true
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        livePreviewMinimumDuration: 100,
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    var overlayValues: [String?] = []
    controller.onLiveTranscriptPreview = { overlayValues.append($0) }
    await controller.prepareCleanupModelIfEffective()

    await controller.startDictation()
    await controller.stopDictation()
    #expect(inserter.insertedTexts.isEmpty)
    #expect(inserter.attemptedSessionIDs.isEmpty)
    #expect(controller.pendingInsertions.entries.isEmpty)
    #expect(controller.state == .idle)
    #expect(overlayValues.count >= 2)
    #expect(overlayValues[overlayValues.count - 1] == nil)
}

@Test @MainActor func cleanupPublishesTypedProgressAndOnlyTheSelectedOverlayValue() async throws {
    let engine = MockTranscriptionEngine()
    await engine.setTranscript("list milk eggs bread")
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("- Milk\n- Eggs\n- Bread"))
    let recorder = DictationPresentationRecorder()
    var settings = AppSettings.default
    settings.liveTranscriptOverlayEnabled = true
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        livePreviewMinimumDuration: 100,
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    controller.onDictationProgress = { recorder.record($0) }
    controller.onFinalSelection = { original, selected, directive in
        recorder.record(original: original, selected: selected, directive: directive)
    }
    controller.onLiveTranscriptPreview = { recorder.recordOverlay($0) }
    await controller.prepareCleanupModelIfEffective()

    await controller.startDictation()
    await controller.stopDictation()

    #expect(recorder.progress == [.finalizing, .cleaning(.listGeneral)])
    let selection = try #require(recorder.selections.first)
    #expect(recorder.selections.count == 1)
    #expect(selection.0.sessionID == selection.1.sessionID)
    #expect(selection.0.text == "list milk eggs bread")
    #expect(selection.1.text == "- Milk\n- Eggs\n- Bread")
    #expect(selection.2 == .list)
    #expect(!recorder.overlayValues.contains("list milk eggs bread"))
    #expect(recorder.overlayValues.contains("- Milk\n- Eggs\n- Bread"))
}

@Test @MainActor func failedSelectedInsertionPublishesTypedFormattedReadyReason() async {
    let inserter = MockTextInserter()
    inserter.error = .insertionUncertain
    let recorder = DictationPresentationRecorder()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService()
    )
    controller.onDictationProgress = { recorder.record($0) }

    await controller.startDictation()
    await controller.stopDictation()

    #expect(recorder.progress == [.finalizing, .formattedTextReady(.insertionUncertain)])
    #expect(controller.pendingInsertions.entries.first?.reason == .insertionUncertain)
}

@Test @MainActor func inactiveCleanupDoesNotParseOrCallTheSecondModel() async {
    let engine = MockTranscriptionEngine()
    await engine.setTranscript("list milk eggs bread")
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("should not run"))
    let inserter = MockTextInserter()
    var settings = AppSettings.default
    settings.cleanup.isEnabled = false
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    await controller.prepareCleanupModelIfEffective()

    await controller.startDictation()
    await controller.stopDictation()

    #expect(await normalizer.inputs.isEmpty)
    #expect(inserter.insertedTexts == ["list milk eggs bread"])
}

@Test @MainActor func nonEnglishSessionMakesZeroCleanupCallsAndInsertsUnchangedText() async {
    let engine = MockTranscriptionEngine()
    await engine.setTranscript("list lait oeufs pain")
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("should not run"))
    let inserter = MockTextInserter()
    var settings = AppSettings.default
    settings.language = .french
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    await controller.prepareCleanupModelIfEffective()

    await controller.startDictation()
    await controller.stopDictation()

    #expect(await normalizer.inputs.isEmpty)
    #expect(inserter.insertedTexts == ["list lait oeufs pain"])
}

@Test @MainActor func directiveFallbackNeverReinsertsTheCommand() async {
    let engine = MockTranscriptionEngine()
    await engine.setTranscript("email Hi John all the best Stephen")
    let normalizer = MockCleanupNormalizer(behavior: .fallback(.modelUnavailable))
    let inserter = MockTextInserter()
    let controller = DictationController(
        transcriptionEngine: engine,
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    await controller.prepareCleanupModelIfEffective()

    await controller.startDictation()
    await controller.stopDictation()

    #expect(inserter.insertedTexts == ["Hi John all the best Stephen"])
}

@Test @MainActor func wholeSessionCancelDuringCleanupProducesNoInsertion() async {
    let normalizer = MockCleanupNormalizer(behavior: .waitForCancellation)
    let inserter = MockTextInserter()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    await controller.prepareCleanupModelIfEffective()

    let session = Task { @MainActor in
        await controller.startDictation()
        await controller.stopDictation()
    }
    await waitUntil(attempts: 1_000) {
        if case .cleaning = controller.state { return true }
        return false
    }
    await controller.cancelDictation()
    await session.value

    #expect(inserter.insertedTexts.isEmpty)
    #expect(controller.pendingInsertions.entries.isEmpty)
    #expect(controller.state == .idle)
}

@Test @MainActor func expeditedPressStartsCaptureWhilePriorInsertionRemainsSessionKeyed() async throws {
    let audio = MockAudioCapture()
    let normalizer = MockCleanupNormalizer(behavior: .waitForCancellation)
    let inserter = GatedFailingInserter()
    let hotkey = MockHotkeyService()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: hotkey,
        expediteRestartDelay: .milliseconds(10),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    try controller.activate()
    await controller.prepareCleanupModelIfEffective()

    hotkey.emit(.pressed)
    await waitUntil(attempts: 1_000) { controller.state == .recording }
    hotkey.emit(.released)
    await waitUntil(attempts: 1_000) {
        if case .cleaning = controller.state { return true }
        return false
    }
    hotkey.emit(.pressed)
    await waitUntil(attempts: 5_000) { inserter.attempted.count == 1 }
    await waitUntil(attempts: 5_000) {
        controller.state == .recording
    }
    #expect(await audio.startCount == 2)
    let previousSessionID = try #require(inserter.attempted.first?.sessionID)

    inserter.release()
    await waitUntil(attempts: 5_000) { controller.pendingInsertions.entries.count == 1 }
    #expect(controller.state == .recording)
    #expect(controller.pendingInsertions.entries.first?.id == previousSessionID)
    #expect(controller.pendingInsertions.entries.first?.text == "dictated locally")

    await controller.cancelDictation()
}

@Test @MainActor func threeUnresolvedSessionsRefuseAnotherCaptureWithoutDroppingText() async {
    let inserter = MockTextInserter()
    inserter.error = .insertionFailed
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService()
    )

    for _ in 0..<3 {
        await controller.startDictation()
        await controller.stopDictation()
    }
    #expect(controller.pendingInsertions.entries.count == 3)
    let retainedIDs = controller.pendingInsertions.entries.map(\.id)

    #expect(!controller.requestStart())
    #expect(controller.state == .failed(.recoveryRequired))
    #expect(controller.pendingInsertions.entries.map(\.id) == retainedIDs)
}

@Test @MainActor func supersededCancelsDoNotConsumeRecoveryCapacity() async throws {
    let audio = GatedCancelAudioCapture()
    let hotkey = MockHotkeyService()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: hotkey,
        expediteRestartDelay: .zero
    )
    try controller.activate()

    for cycle in 1...3 {
        hotkey.emit(.pressed)
        await waitUntil(attempts: 1_000) { controller.state == .recording }

        let cancellation = Task { @MainActor in
            await controller.cancelDictation()
        }
        for _ in 0..<1_000 where await audio.cancelStartedCount != cycle {
            await Task.yield()
        }
        #expect(await audio.cancelStartedCount == cycle)

        hotkey.emit(.released)
        hotkey.emit(.pressed)
        await waitUntil(attempts: 5_000) { controller.state == .recording }
        await audio.releaseNextCancel()
        await cancellation.value

        hotkey.emit(.released)
        await waitUntil(attempts: 5_000) { controller.state == .idle }
        #expect(recoveryReservationCount(controller) == 0)
    }

    hotkey.emit(.pressed)
    await waitUntil(attempts: 5_000) { controller.state == .recording }
    #expect(controller.state == .recording)
    hotkey.emit(.released)
    await waitUntil(attempts: 5_000) { controller.state == .idle }
    #expect(controller.state == .idle)
}

@Test @MainActor func supersededTranscribingCancelDoesNotRetainItsMarker() async throws {
    let audio = GatedStopAndCancelAudioCapture()
    let hotkey = MockHotkeyService()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: audio,
        textInserter: MockTextInserter(),
        hotkeyService: hotkey,
        expediteRestartDelay: .zero
    )
    try controller.activate()

    hotkey.emit(.pressed)
    await waitUntil(attempts: 1_000) { controller.state == .recording }
    hotkey.emit(.released)
    for _ in 0..<1_000 where !(await audio.stopStarted) {
        await Task.yield()
    }

    let cancellation = Task { @MainActor in
        await controller.cancelDictation()
    }
    for _ in 0..<1_000 where !(await audio.cancelStarted) {
        await Task.yield()
    }
    await waitUntil(attempts: 1_000) { controller.state == .idle }

    hotkey.emit(.pressed)
    await waitUntil(attempts: 5_000) { controller.state == .recording }
    await audio.releaseCancel()
    await cancellation.value

    #expect(controller.state == .recording)
    #expect(recoveryReservationCount(controller) == 1)
    #expect(explicitCancellationMarkerCount(controller) == 0)
    hotkey.emit(.released)
    await waitUntil(attempts: 5_000) { controller.state == .idle }
    #expect(controller.state == .idle)
}

@Test @MainActor func supersededCleaningCancelKeepsSafetyStateUntilCompletionJoins() async throws {
    let normalizer = GatedCleanupCompletionNormalizer()
    let inserter = MockTextInserter()
    let hotkey = MockHotkeyService()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: hotkey,
        expediteRestartDelay: .zero,
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    try controller.activate()
    await controller.prepareCleanupModelIfEffective()

    hotkey.emit(.pressed)
    await waitUntil(attempts: 1_000) { controller.state == .recording }
    hotkey.emit(.released)
    for _ in 0..<1_000 where !(await normalizer.normalizeStarted) {
        await Task.yield()
    }

    let cancellation = Task { @MainActor in
        await controller.cancelDictation()
    }
    await waitUntil(attempts: 1_000) {
        explicitCancellationMarkerCount(controller) == 1
    }
    hotkey.emit(.pressed)
    await waitUntil(attempts: 5_000) { controller.state == .recording }

    #expect(controller.state == .recording)
    #expect(recoveryReservationCount(controller) == 2)
    #expect(explicitCancellationMarkerCount(controller) == 1)
    await normalizer.releaseNormalization()
    await cancellation.value

    #expect(controller.state == .recording)
    #expect(recoveryReservationCount(controller) == 1)
    #expect(explicitCancellationMarkerCount(controller) == 0)
    #expect(inserter.insertedTexts.isEmpty)
    await controller.cancelDictation()
    #expect(controller.state == .idle)
}

@MainActor
private func recoveryReservationCount(_ controller: DictationController) -> Int {
    let value = Mirror(reflecting: controller).children.first {
        $0.label == "recoveryReservations"
    }?.value
    return (value as? Set<DictationSessionID>)?.count ?? -1
}

@MainActor
private func explicitCancellationMarkerCount(_ controller: DictationController) -> Int {
    let value = Mirror(reflecting: controller).children.first {
        $0.label == "explicitlyCancelledSessions"
    }?.value
    return (value as? Set<DictationSessionID>)?.count ?? -1
}

@Test @MainActor func retryReservationSurvivesExpiryAndConcurrentFailuresWithoutLoss() async throws {
    let inserter = RetryExpiryInserter()
    let hotkey = MockHotkeyService()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: hotkey,
        pendingTranscriptLifetime: .milliseconds(50),
        expediteRestartDelay: .zero
    )
    try controller.activate()

    await controller.startDictation()
    await controller.stopDictation()
    let retryID = try #require(controller.pendingInsertions.entries.first?.id)
    let retry = Task { @MainActor in
        await controller.retryPendingInsertion(sessionID: retryID)
    }
    await waitUntil(attempts: 1_000) { inserter.attemptCount == 2 }
    try? await Task.sleep(for: .milliseconds(70))

    hotkey.emit(.pressed)
    await waitUntil(attempts: 1_000) { controller.state == .recording }
    hotkey.emit(.released)
    await waitUntil(attempts: 1_000) { controller.pendingInsertions.entries.count == 1 }
    await controller.startDictation()
    await controller.stopDictation()
    #expect(controller.pendingInsertions.entries.count == 2)

    inserter.releaseRetry()
    await retry.value
    #expect(controller.pendingInsertions.entries.count == 3)
    #expect(controller.pendingInsertions.entry(for: retryID) != nil)
}

@Test @MainActor func successfulRetryCannotClobberAnExpeditedRecording() async throws {
    try await assertSuccessfulRecoveryCannotClobberRecording(insertAnyway: false)
}

@Test @MainActor func successfulInsertAnywayCannotClobberAnExpeditedRecording() async throws {
    try await assertSuccessfulRecoveryCannotClobberRecording(insertAnyway: true)
}

@Test @MainActor func latePriorTranscriptionCannotClobberANewRecording() async throws {
    let audio = MockAudioCapture()
    let engine = GatedFinalTranscriptionEngine()
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("old cleaned"))
    let inserter = MockTextInserter()
    inserter.error = .insertionFailed
    let hotkey = MockHotkeyService()
    var settings = AppSettings.default
    settings.liveTranscriptOverlayEnabled = true
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: hotkey,
        expediteRestartDelay: .milliseconds(10),
        livePreviewMinimumDuration: 100,
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion
    )
    try controller.activate()
    await controller.prepareCleanupModelIfEffective()

    hotkey.emit(.pressed)
    await waitUntil(attempts: 1_000) { controller.state == .recording }
    hotkey.emit(.released)
    await waitUntil(attempts: 1_000) { controller.state == .transcribing }

    let clock = ContinuousClock()
    let press = clock.now
    hotkey.emit(.pressed)
    await waitUntil(attempts: 5_000) { controller.state == .recording }
    #expect(clock.now - press < .milliseconds(200))
    #expect(await audio.startCount == 2)

    await engine.releaseFirstTranscription()
    await waitUntil(attempts: 5_000) { controller.pendingInsertions.entries.count == 1 }
    #expect(controller.state == .recording)
    #expect(controller.liveTranscriptPreview == "")
    #expect(controller.pendingInsertions.entries.first?.text == "old cleaned")

    await controller.cancelDictation()
}

@Test @MainActor func cleanupMemoryPressureReleasesTheResidentNormalizer() async {
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("cleaned"))
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion,
        monitorCleanupMemoryPressure: false
    )
    await controller.prepareCleanupModelIfEffective()
    #expect(controller.cleanupStatus == .ready)

    controller.handleCleanupMemoryPressure(.warning)
    for _ in 0..<1_000 {
        if await normalizer.unloadCount == 1 { break }
        await Task.yield()
    }
    #expect(await normalizer.unloadCount == 1)
    #expect(controller.cleanupStatus == .preparing)
}

@Test @MainActor func cleanupModelUnloadsAfterTheConfiguredLongIdleInterval() async {
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("cleaned"))
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion,
        cleanupIdleUnloadDelay: .milliseconds(10),
        monitorCleanupMemoryPressure: false
    )
    await controller.prepareCleanupModelIfEffective()
    for _ in 0..<5_000 where await normalizer.unloadCount != 1 {
        await Task.yield()
    }
    #expect(await normalizer.unloadCount == 1)
    #expect(controller.cleanupStatus == .preparing)
}

@Test @MainActor func captureAfterIdleUnloadWarmsInBackgroundAndStillCleans() async {
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("cleaned after idle"))
    let inserter = MockTextInserter()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion,
        cleanupIdleUnloadDelay: .milliseconds(10),
        monitorCleanupMemoryPressure: false
    )
    await controller.prepareCleanupModelIfEffective()
    for _ in 0..<5_000 where await normalizer.unloadCount != 1 {
        await Task.yield()
    }

    await controller.startDictation()
    for _ in 0..<5_000 where await normalizer.prepareCount != 2 {
        await Task.yield()
    }
    await controller.stopDictation()
    #expect(await normalizer.inputs.count == 1)
    #expect(inserter.insertedTexts == ["cleaned after idle"])

    for _ in 0..<2 {
        await controller.startDictation()
        await controller.stopDictation()
    }
    #expect(await normalizer.prepareCount == 2)
}

@Test @MainActor func resolvingRecoveryRearmsIdleCleanupUnload() async throws {
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("cleaned"))
    let inserter = MockTextInserter()
    inserter.error = .insertionFailed
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: inserter,
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion,
        cleanupIdleUnloadDelay: .milliseconds(10),
        monitorCleanupMemoryPressure: false
    )
    await controller.prepareCleanupModelIfEffective()
    await controller.startDictation()
    await controller.stopDictation()
    let pendingID = try #require(controller.pendingInsertions.entries.first?.id)
    controller.discardPendingInsertion(sessionID: pendingID)
    for _ in 0..<5_000 where await normalizer.unloadCount != 1 {
        await Task.yield()
    }
    #expect(await normalizer.unloadCount == 1)
}

@Test @MainActor func repeatedPressureWarningsCoalesceAndDelayRepreparation() async {
    let normalizer = MockCleanupNormalizer(behavior: .cleaned("cleaned"))
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion,
        cleanupIdleUnloadDelay: .seconds(60),
        cleanupPressureCooldown: .milliseconds(500),
        monitorCleanupMemoryPressure: false
    )
    await controller.prepareCleanupModelIfEffective()
    controller.handleCleanupMemoryPressure(.warning)
    controller.handleCleanupMemoryPressure(.warning)
    for _ in 0..<1_000 where await normalizer.unloadCount != 1 {
        await Task.yield()
    }
    #expect(await normalizer.unloadCount == 1)
    #expect(await normalizer.prepareCount == 1)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(await normalizer.prepareCount == 1)
    try? await Task.sleep(for: .milliseconds(550))
    for _ in 0..<1_000 where await normalizer.prepareCount != 2 {
        await Task.yield()
    }
    #expect(await normalizer.prepareCount == 2)
}

@Test @MainActor func pressureDuringPreparationCannotPublishAStaleReadyState() async {
    let normalizer = GatedCleanupPreparationNormalizer()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion,
        cleanupPressureCooldown: .seconds(60),
        monitorCleanupMemoryPressure: false
    )
    let preparation = Task { @MainActor in
        await controller.prepareCleanupModelIfEffective()
    }
    for _ in 0..<1_000 where !(await normalizer.prepareStarted) {
        await Task.yield()
    }
    controller.handleCleanupMemoryPressure(.warning)
    await normalizer.releasePreparation()
    await preparation.value
    for _ in 0..<1_000 where await normalizer.unloadCount != 1 {
        await Task.yield()
    }
    #expect(await normalizer.unloadCount == 1)
    #expect(controller.cleanupStatus == .preparing)
}

@Test @MainActor func cleanupShutdownDrainReturnsAtItsDeadline() async {
    let normalizer = GatedUnloadNormalizer()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: MockAudioCapture(),
        textInserter: MockTextInserter(),
        hotkeyService: MockHotkeyService(),
        cleanupNormalizer: normalizer,
        cleanupModelURL: URL(fileURLWithPath: "/tmp/s1-mini-test.gguf"),
        cleanupDisclosureVersion: CleanupDisclosure.requiredVersion,
        monitorCleanupMemoryPressure: false
    )
    await controller.prepareCleanupModelIfEffective()
    let shutdown = Task { @MainActor in
        await controller.shutdownCleanup(deadline: .milliseconds(20))
    }
    for _ in 0..<1_000 where !(await normalizer.unloadStarted) {
        await Task.yield()
    }
    #expect(await normalizer.unloadStarted)
    await shutdown.value
    #expect(!(await normalizer.unloadCompleted))
    await normalizer.releaseUnload()
    for _ in 0..<1_000 where !(await normalizer.unloadCompleted) {
        await Task.yield()
    }
    #expect(await normalizer.unloadCompleted)
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

@MainActor
private func assertSuccessfulRecoveryCannotClobberRecording(
    insertAnyway: Bool
) async throws {
    let audio = MockAudioCapture()
    let inserter = GatedRecoverySuccessInserter(
        initialError: insertAnyway ? .blockedMultilineDestination : .insertionFailed
    )
    let hotkey = MockHotkeyService()
    let controller = DictationController(
        transcriptionEngine: MockTranscriptionEngine(),
        audioCapture: audio,
        textInserter: inserter,
        hotkeyService: hotkey,
        expediteRestartDelay: .zero
    )
    try controller.activate()
    await controller.startDictation()
    await controller.stopDictation()
    let pendingID = try #require(controller.pendingInsertions.entries.first?.id)
    let baselineStopCount = await audio.stopCount

    let recovery = Task { @MainActor in
        if insertAnyway {
            await controller.insertPendingAnyway(sessionID: pendingID)
        } else {
            await controller.retryPendingInsertion(sessionID: pendingID)
        }
    }
    await waitUntil(attempts: 1_000) { inserter.attemptCount == 2 }
    hotkey.emit(.pressed)
    await waitUntil(attempts: 1_000) { controller.state == .recording }
    inserter.releaseRecovery()
    await recovery.value
    #expect(controller.state == .recording)

    hotkey.emit(.released)
    for _ in 0..<5_000 where await audio.stopCount != baselineStopCount + 1 {
        await Task.yield()
    }
    #expect(await audio.stopCount == baselineStopCount + 1)
    await waitUntil(attempts: 5_000) { controller.state == .idle }
}

private extension MockAudioCapture {
    func setStartError(_ error: AudioCaptureError?) {
        startError = error
    }

    func setStartSelection(_ selection: AudioInputSelection) {
        startSelection = selection
    }
}

private extension MockTranscriptionEngine {
    func setTranscript(_ value: String) {
        transcript = value
    }
}
