import Foundation

/// Per-recording preview scheduler. It shares the production capture and model
/// actors and enters MainActor only through the publish callbacks.
actor LivePreviewSession {
    private let audioCapture: any AudioCapturing
    private let transcriptionEngine: any LocalTranscriptionEngine
    private let interval: Duration
    private let maximumWindow: TimeInterval
    private let minimumDuration: TimeInterval
    private let language: DictationLanguage
    private let model: TranscriptionModel
    private let latencyBudget: Duration
    private let publish: @MainActor @Sendable (String) -> Void
    private let circuitOpened: @MainActor @Sendable () -> Void
    private let logger = PrivacySafeLogger(category: "LivePreview")
    private let signposter = PrivacySafeSignposter(category: "LivePreview")
    private static let maximumConsecutiveFailures = 3

    init(
        audioCapture: any AudioCapturing,
        transcriptionEngine: any LocalTranscriptionEngine,
        interval: Duration,
        maximumWindow: TimeInterval,
        minimumDuration: TimeInterval,
        language: DictationLanguage,
        model: TranscriptionModel,
        latencyBudget: Duration,
        publish: @escaping @MainActor @Sendable (String) -> Void,
        circuitOpened: @escaping @MainActor @Sendable () -> Void
    ) {
        self.audioCapture = audioCapture
        self.transcriptionEngine = transcriptionEngine
        self.interval = interval
        self.maximumWindow = maximumWindow
        self.minimumDuration = minimumDuration
        self.language = language
        self.model = model
        self.latencyBudget = latencyBudget
        self.publish = publish
        self.circuitOpened = circuitOpened
    }

    func run() async {
        let clock = ContinuousClock()
        var consecutiveFailures = 0
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
                try Task.checkCancellation()
                let cycleStart = clock.now

                logger.info(.livePreviewSnapshotStarted)
                let snapshotInterval = signposter.begin(.livePreviewSnapshotStarted)
                let snapshot = await audioCapture.snapshot(maximumDuration: maximumWindow)
                signposter.end(.livePreviewSnapshotCompleted, snapshotInterval)
                logger.info(.livePreviewSnapshotCompleted)

                guard let audio = snapshot, audio.duration >= minimumDuration else {
                    continue
                }

                logger.info(.livePreviewInferenceStarted)
                let inferenceInterval = signposter.begin(.livePreviewInferenceStarted)
                let text: String
                do {
                    text = try await transcriptionEngine.transcribe(
                        audio,
                        language: language,
                        model: model
                    )
                } catch {
                    signposter.end(.livePreviewInferenceCompleted, inferenceInterval)
                    logger.info(.livePreviewInferenceCompleted)
                    throw error
                }
                signposter.end(.livePreviewInferenceCompleted, inferenceInterval)
                logger.info(.livePreviewInferenceCompleted)

                try Task.checkCancellation()
                logger.info(.livePreviewPublishRequested)
                await publish(text)
                consecutiveFailures = 0

                if clock.now - cycleStart > latencyBudget {
                    logger.info(.livePreviewBudgetExceeded)
                    logger.info(.livePreviewCircuitOpened)
                    await circuitOpened()
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                logger.error(.operationFailed, error: error)
                consecutiveFailures += 1
                guard consecutiveFailures < Self.maximumConsecutiveFailures else {
                    logger.info(.livePreviewCircuitOpened)
                    await circuitOpened()
                    return
                }
                // Preview is optional: retry a bounded number of transient
                // failures without allowing an error loop to compete with the
                // final transcription for the remainder of the recording.
            }
        }
    }
}
