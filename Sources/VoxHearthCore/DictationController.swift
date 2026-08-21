import Foundation
import Observation

@MainActor
@Observable
public final class DictationController {
    public static let maximumExternalAudioDuration: TimeInterval = 10 * 60
    public static let defaultLivePreviewInterval: Duration = .milliseconds(600)
    public static let defaultLivePreviewWindow: TimeInterval = 8

    nonisolated static func defaultLivePreviewLatencyBudget(
        for interval: Duration
    ) -> Duration {
        max(.seconds(2), interval * 4)
    }

    public private(set) var state: DictationSessionState = .idle
    public private(set) var settings: AppSettings
    public private(set) var recordingStartedAt: Date?
    public private(set) var pendingTranscript: String?
    /// Approximate, memory-only text for the optional overlay. This is never
    /// used for insertion; the final full recording is transcribed separately.
    public private(set) var liveTranscriptPreview: String?

    @ObservationIgnored
    public var onOnboardingRequirement: (@MainActor @Sendable (OnboardingRequirement) -> Void)?

    /// Runs immediately after a dictation request is accepted and before the
    /// microphone starts. The app uses this for a short local acknowledgement
    /// tone so the cue itself is not included in captured audio.
    @ObservationIgnored
    public var onStartCue: (@MainActor @Sendable () async -> Void)?

    @ObservationIgnored
    public var onInputDeviceFallback: (@MainActor @Sendable () -> Void)?

    @ObservationIgnored
    public var onLiveTranscriptPreview: (@MainActor @Sendable (String?) -> Void)?

    @ObservationIgnored private let audioCapture: any AudioCapturing
    @ObservationIgnored private let transcriptionEngine: any LocalTranscriptionEngine
    @ObservationIgnored private let textInserter: any TextInserting
    @ObservationIgnored private let hotkeyService: any GlobalHotkeyRegistering
    @ObservationIgnored private let pointerButtonService: any GlobalPointerButtonRegistering
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var transcriptionTask: Task<String, Error>?
    @ObservationIgnored private var enginePreparationTask: Task<Void, Error>?
    @ObservationIgnored private var pendingTranscriptExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var activationStartTask: Task<Void, Never>?
    @ObservationIgnored private var activationStopTask: Task<Void, Never>?
    @ObservationIgnored private var livePreviewTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPreviewJoin: Task<Void, Never>?
    @ObservationIgnored private var livePreviewDismissTask: Task<Void, Never>?
    @ObservationIgnored private var modelMaintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var activationIsPressed = false
    @ObservationIgnored private var sessionEpoch = 0
    @ObservationIgnored private var currentSessionID: DictationSessionID?
    @ObservationIgnored private var pendingInsertableTranscript: InsertableTranscript?
    @ObservationIgnored private let pendingTranscriptLifetime: Duration
    @ObservationIgnored private let livePreviewInterval: Duration
    @ObservationIgnored private let livePreviewMinimumDuration: TimeInterval
    @ObservationIgnored private let livePreviewWindow: TimeInterval
    @ObservationIgnored private let livePreviewFinalVisibility: Duration
    @ObservationIgnored private let livePreviewLatencyBudget: Duration
    @ObservationIgnored private let activityScope: LifecycleActivityScope
    @ObservationIgnored private let recoveryPolicy = ModelRecoveryPolicy()
    @ObservationIgnored private let releasePooledBuffersWhenIdle: Bool
    @ObservationIgnored private let modelReloadOnStall: Bool
    @ObservationIgnored private var pathologicalPreviewCount = 0
    @ObservationIgnored private var modelRecoveryAttempted = false
    @ObservationIgnored private let logger = PrivacySafeLogger(category: "Dictation")
    @ObservationIgnored private let signposter = PrivacySafeSignposter(category: "Dictation")

    public init(
        transcriptionEngine: any LocalTranscriptionEngine,
        settings: AppSettings = .default,
        audioCapture: any AudioCapturing = AudioCaptureService(),
        textInserter: any TextInserting = TextInsertionService(),
        hotkeyService: any GlobalHotkeyRegistering = CarbonGlobalHotkeyService(),
        pointerButtonService: any GlobalPointerButtonRegistering = GlobalPointerButtonService(),
        pendingTranscriptLifetime: Duration = .seconds(120),
        livePreviewInterval: Duration = defaultLivePreviewInterval,
        livePreviewMinimumDuration: TimeInterval = 0.6,
        livePreviewWindow: TimeInterval = defaultLivePreviewWindow,
        livePreviewFinalVisibility: Duration = .seconds(2),
        livePreviewLatencyBudget: Duration? = nil,
        lifecycleActivityAsserter: (any LifecycleActivityAsserting)? = nil,
        releasePooledBuffersWhenIdle: Bool? = nil,
        modelReloadOnStall: Bool? = nil
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.settings = settings.normalizedForSelectedModel()
        self.audioCapture = audioCapture
        self.textInserter = textInserter
        self.hotkeyService = hotkeyService
        self.pointerButtonService = pointerButtonService
        self.pendingTranscriptLifetime = pendingTranscriptLifetime
        self.livePreviewInterval = livePreviewInterval
        self.livePreviewMinimumDuration = livePreviewMinimumDuration
        self.livePreviewWindow = livePreviewWindow
        self.livePreviewFinalVisibility = livePreviewFinalVisibility
        self.livePreviewLatencyBudget = livePreviewLatencyBudget
            ?? Self.defaultLivePreviewLatencyBudget(for: livePreviewInterval)
        activityScope = LifecycleActivityScope(asserter: lifecycleActivityAsserter)
        self.releasePooledBuffersWhenIdle = releasePooledBuffersWhenIdle
            ?? UserDefaults.standard.bool(
                forKey: "VoxHearth.diagnostics.releasePooledArrays"
            )
        self.modelReloadOnStall = modelReloadOnStall
            ?? UserDefaults.standard.bool(
                forKey: "VoxHearth.diagnostics.modelReloadOnStall"
            )
    }

    deinit {
        transcriptionTask?.cancel()
        enginePreparationTask?.cancel()
        pendingTranscriptExpiryTask?.cancel()
        activationStartTask?.cancel()
        activationStopTask?.cancel()
        enginePreparationTask?.cancel()
        livePreviewTask?.cancel()
        pendingPreviewJoin?.cancel()
        livePreviewDismissTask?.cancel()
        modelMaintenanceTask?.cancel()
    }

    public func activate() throws {
        guard !isActive else { return }
        try registerHotkey(settings.hotkey)
        registerPointerButton(settings.pointerButton)
        isActive = true
    }

    public func deactivate() {
        hotkeyService.unregister()
        pointerButtonService.unregister()
        activationIsPressed = false
        sessionEpoch &+= 1
        activationStartTask?.cancel()
        activationStopTask?.cancel()
        livePreviewTask?.cancel()
        pendingPreviewJoin?.cancel()
        activityScope.end()
        isActive = false
    }

    public func applySettings(_ settings: AppSettings) throws {
        let settings = settings.normalizedForSelectedModel()
        let previousSettings = self.settings
        if isActive, settings.hotkey != previousSettings.hotkey {
            do {
                try registerHotkey(settings.hotkey)
            } catch {
                try? registerHotkey(previousSettings.hotkey)
                throw error
            }
        }
        if isActive, settings.pointerButton != previousSettings.pointerButton {
            registerPointerButton(settings.pointerButton)
        }
        self.settings = settings
        if state == .recording,
           settings.liveTranscriptOverlayEnabled != previousSettings.liveTranscriptOverlayEnabled {
            if settings.liveTranscriptOverlayEnabled {
                beginLiveTranscriptPreview()
            } else {
                retainPreviewJoin(stopLiveTranscriptPreview(clearText: true))
            }
        } else if !settings.liveTranscriptOverlayEnabled {
            retainPreviewJoin(stopLiveTranscriptPreview(clearText: true))
        }
    }

    public func prepareEngine() async {
        guard state == .idle || Self.isFailureState(state) else { return }
        let epoch = sessionEpoch
        transition(to: .preparing)
        let model = settings.transcriptionModel
        let task = Task {
            try await transcriptionEngine.prepare(model: model)
        }
        enginePreparationTask = task
        do {
            try await task.value
            enginePreparationTask = nil
            guard epoch == sessionEpoch else { return }
            transition(to: .idle)
        } catch is CancellationError {
            enginePreparationTask = nil
            guard epoch == sessionEpoch else { return }
            transition(to: .idle)
        } catch {
            enginePreparationTask = nil
            guard epoch == sessionEpoch else { return }
            logger.error(.operationFailed, error: error)
            transition(to: .failed(.modelUnavailable))
        }
    }

    public func startDictation() async {
        guard requestStart(), let task = activationStartTask else { return }
        await task.value
    }

    /// Accepts the start in the caller's current MainActor turn, before any
    /// preparation work is queued. This is the hotkey/UI control-plane seam.
    @discardableResult
    public func requestStart() -> Bool {
        let backgroundPreparationInProgress = state == .preparing
            && activationStartTask == nil
            && enginePreparationTask != nil
        guard state == .idle
            || Self.isFailureState(state)
            || backgroundPreparationInProgress else { return false }
        modelMaintenanceTask?.cancel()
        modelMaintenanceTask = nil
        let predecessorStart = activationStartTask
        let predecessorStop = activationStopTask
        let predecessorPreparation = enginePreparationTask
        predecessorStart?.cancel()
        sessionEpoch &+= 1
        let epoch = sessionEpoch
        currentSessionID = DictationSessionID()
        pathologicalPreviewCount = 0
        clearPendingTranscript()
        activityScope.beginAudioCritical()
        transition(to: .preparing)
        logger.info(.dictationStartAccepted)

        activationStartTask = Task(priority: .userInitiated) { [weak self] in
            await predecessorStart?.value
            await predecessorStop?.value
            _ = try? await predecessorPreparation?.value
            guard let self else { return }
            guard self.sessionEpoch == epoch else {
                self.logger.info(.dictationStartAbandoned)
                return
            }
            await self.runAcceptedStart(epoch: epoch)
        }
        return true
    }

    private func runAcceptedStart(epoch: Int) async {
        defer {
            if epoch == sessionEpoch {
                activationStartTask = nil
            }
        }
        do {
            logger.info(.startCueStarted)
            await onStartCue?()
            logger.info(.startCueCompleted)
            try Task.checkCancellation()
            guard epoch == sessionEpoch else {
                logger.info(.dictationStartAbandoned)
                return
            }
            logger.info(.modelPreparationStarted)
            let preparationInterval = signposter.begin(.modelPreparationStarted)
            do {
                try await transcriptionEngine.prepare(model: settings.transcriptionModel)
            } catch {
                signposter.end(.modelPreparationCompleted, preparationInterval)
                logger.info(.modelPreparationCompleted)
                throw error
            }
            signposter.end(.modelPreparationCompleted, preparationInterval)
            logger.info(.modelPreparationCompleted)
            try Task.checkCancellation()
            guard epoch == sessionEpoch else {
                logger.info(.dictationStartAbandoned)
                return
            }
            let inputSelection = try await audioCapture.start(
                inputDeviceUID: settings.inputDeviceUID,
                maximumDurationReached: { [weak self] in
                    await self?.stopDictation()
                }
            )
            try Task.checkCancellation()
            guard epoch == sessionEpoch, state == .preparing else {
                await audioCapture.cancel()
                logger.info(.dictationStartAbandoned)
                return
            }
            if inputSelection == .fellBackToSystemDefault {
                settings.inputDeviceUID = nil
                onInputDeviceFallback?()
            }
            recordingStartedAt = Date()
            transition(to: .recording)
            beginLiveTranscriptPreview()
        } catch is CancellationError {
            await audioCapture.cancel()
            guard epoch == sessionEpoch else {
                logger.info(.dictationStartAbandoned)
                return
            }
            recordingStartedAt = nil
            transition(to: .idle)
        } catch {
            await audioCapture.cancel()
            guard epoch == sessionEpoch else {
                logger.info(.dictationStartAbandoned)
                return
            }
            recordingStartedAt = nil
            if Task.isCancelled {
                transition(to: .idle)
            } else {
                handleStartError(error)
            }
        }
    }

    public func stopDictation() async {
        guard requestStop(), let task = activationStopTask else { return }
        await task.value
    }

    /// Accepts the stop synchronously so the UI and duplicate-event guard no
    /// longer wait behind preview or overlay MainActor work.
    @discardableResult
    public func requestStop() -> Bool {
        guard state == .recording, let sessionID = currentSessionID else { return false }
        sessionEpoch &+= 1
        let epoch = sessionEpoch
        logger.info(.dictationStopAccepted)
        transition(to: .transcribing)
        recordingStartedAt = nil
        let cancelledPreviewTask = mergePreviewJoins(
            pendingPreviewJoin,
            stopLiveTranscriptPreview(clearText: false)
        )
        pendingPreviewJoin = nil

        activationStopTask = Task(priority: .userInitiated) { [weak self] in
            await self?.runAcceptedStop(
                epoch: epoch,
                sessionID: sessionID,
                joining: cancelledPreviewTask
            )
        }
        return true
    }

    private func runAcceptedStop(
        epoch: Int,
        sessionID: DictationSessionID,
        joining cancelledPreviewTask: Task<Void, Never>?
    ) async {
        defer {
            if epoch == sessionEpoch {
                activationStopTask = nil
            }
        }
        do {
            // Release the tap and AVAudioEngine before waiting for an in-flight
            // preview. The microphone indicator should react immediately even
            // when Core ML takes time to acknowledge cancellation.
            let audio = try await audioCapture.stop()
            guard epoch == sessionEpoch else {
                logger.info(.dictationStopAbandoned)
                return
            }
            activityScope.narrowToUserInitiated()
            // A Parakeet actor can re-enter while awaiting Core ML. Joining the
            // cancelled preview prevents final inference from overlapping it.
            if let cancelledPreviewTask {
                await cancelledPreviewTask.value
                guard epoch == sessionEpoch else {
                    logger.info(.dictationStopAbandoned)
                    return
                }
                logger.info(.livePreviewCancellationJoined)
            }
            await transcribeAndInsert(audio, sessionID: sessionID)
        } catch is CancellationError {
            guard epoch == sessionEpoch else {
                logger.info(.dictationStopAbandoned)
                return
            }
            transcriptionTask = nil
            transition(to: .idle)
        } catch {
            guard epoch == sessionEpoch else {
                logger.info(.dictationStopAbandoned)
                return
            }
            transcriptionTask = nil
            handleCompletionError(error)
        }
    }

    /// Accepts PCM captured by a directly connected local accessory, without
    /// opening the Mac microphone or playing the microphone-start cue.
    ///
    /// The caller remains responsible for authenticating the accessory,
    /// bounding the transfer, validating packet integrity, and releasing its
    /// transport buffers. Once accepted, audio follows the same in-memory
    /// transcription and insertion path as microphone dictation.
    @discardableResult
    public func submitExternalAudio(
        _ audio: CapturedAudio
    ) async -> ExternalAudioSubmissionResult {
        guard state == .idle || Self.isFailureState(state) else { return .busy }
        guard audio.sampleRate.isFinite,
              audio.sampleRate > 0,
              audio.sampleRate <= 192_000,
              !audio.samples.isEmpty,
              audio.duration <= Self.maximumExternalAudioDuration,
              audio.samples.allSatisfy(\.isFinite) else {
            return .invalidAudio
        }

        clearPendingTranscript()
        let sessionID = DictationSessionID()
        currentSessionID = sessionID
        recordingStartedAt = nil
        activityScope.beginUserInitiated()
        transition(to: .transcribing)
        await transcribeAndInsert(audio, sessionID: sessionID)
        return .accepted
    }

    /// Retries insertion of an in-memory transcript retained after a destination
    /// app rejected it. Nothing is written to disk and the value remains subject
    /// to the same two-minute expiry.
    public func retryPendingInsertion() async {
        guard state == .idle || Self.isFailureState(state) else { return }
        guard let pending = pendingInsertableTranscript else { return }
        activityScope.beginUserInitiated()
        transition(to: .inserting)
        do {
            _ = try await textInserter.insert(
                pending,
                clipboardFallbackEnabled: settings.clipboardCompatibilityEnabled
            )
            clearPendingTranscript()
            transition(to: .idle)
        } catch {
            retainPendingTranscript(pending)
            handleCompletionError(error)
        }
    }

    public func discardPendingTranscript() {
        clearPendingTranscript()
        if Self.isFailureState(state) {
            transition(to: .idle)
        }
    }

    public func cancelDictation() async {
        sessionEpoch &+= 1
        let epoch = sessionEpoch
        let cancelledStartTask = activationStartTask
        let cancelledStopTask = activationStopTask
        cancelledStartTask?.cancel()
        cancelledStopTask?.cancel()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        let cancelledPreviewTask = mergePreviewJoins(
            pendingPreviewJoin,
            stopLiveTranscriptPreview(clearText: true)
        )
        pendingPreviewJoin = nil
        await audioCapture.cancel()
        await cancelledPreviewTask?.value
        await cancelledStartTask?.value
        await cancelledStopTask?.value
        guard epoch == sessionEpoch else {
            logger.info(.dictationStopAbandoned)
            return
        }
        recordingStartedAt = nil
        currentSessionID = nil
        transition(to: .idle)
    }

    private func retainPendingTranscript(_ transcript: InsertableTranscript) {
        pendingTranscriptExpiryTask?.cancel()
        pendingInsertableTranscript = transcript
        pendingTranscript = transcript.text
        let lifetime = pendingTranscriptLifetime
        pendingTranscriptExpiryTask = Task { [weak self, lifetime] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            self?.discardPendingTranscript()
        }
    }

    private func clearPendingTranscript() {
        pendingTranscriptExpiryTask?.cancel()
        pendingTranscriptExpiryTask = nil
        pendingInsertableTranscript = nil
        pendingTranscript = nil
    }

    private func transcribeAndInsert(
        _ audio: CapturedAudio,
        sessionID: DictationSessionID
    ) async {
        var transcriptForRecovery: InsertableTranscript?
        do {
            let selectedLanguage = settings.language
            let selectedModel = settings.transcriptionModel
            logger.info(.finalTranscriptionStarted)
            let task = Task(priority: .userInitiated) {
                try await transcriptionEngine.transcribe(
                    audio,
                    language: selectedLanguage,
                    model: selectedModel
                )
            }
            transcriptionTask = task
            let transcript = try await task.value
            transcriptionTask = nil
            logger.info(.finalTranscriptionCompleted)

            guard !transcript.isEmpty else {
                scheduleLiveTranscriptPreviewDismissal()
                finishSessionReturningToIdle()
                return
            }
            let finalTranscript = FinalTranscript(sessionID: sessionID, text: transcript)
            let insertableTranscript = CleanupPolicy().passthrough(finalTranscript)
            transcriptForRecovery = insertableTranscript
            if settings.liveTranscriptOverlayEnabled {
                publishLiveTranscriptPreview(transcript)
            }

            transition(to: .inserting)
            logger.info(.textInsertionStarted)
            _ = try await textInserter.insert(
                insertableTranscript,
                clipboardFallbackEnabled: settings.clipboardCompatibilityEnabled
            )
            clearPendingTranscript()
            finishSessionReturningToIdle()
            scheduleLiveTranscriptPreviewDismissal()
        } catch is CancellationError {
            transcriptionTask = nil
            transition(to: .idle)
            logger.info(.sessionReturnedToIdle)
            scheduleLiveTranscriptPreviewDismissal()
        } catch {
            transcriptionTask = nil
            if let transcriptForRecovery {
                retainPendingTranscript(transcriptForRecovery)
            }
            handleCompletionError(error)
            scheduleLiveTranscriptPreviewDismissal()
        }
    }

    private func beginLiveTranscriptPreview() {
        guard settings.liveTranscriptOverlayEnabled, state == .recording else { return }
        let predecessor = mergePreviewJoins(
            pendingPreviewJoin,
            stopLiveTranscriptPreview(clearText: false)
        )
        pendingPreviewJoin = nil
        livePreviewDismissTask?.cancel()
        livePreviewDismissTask = nil
        publishLiveTranscriptPreview("")

        let session = LivePreviewSession(
            audioCapture: audioCapture,
            transcriptionEngine: transcriptionEngine,
            interval: livePreviewInterval,
            maximumWindow: livePreviewWindow,
            minimumDuration: livePreviewMinimumDuration,
            language: settings.language,
            model: settings.transcriptionModel,
            latencyBudget: livePreviewLatencyBudget,
            publish: { [weak self] text in
                guard let self,
                      self.state == .recording,
                      self.settings.liveTranscriptOverlayEnabled else { return }
                self.logger.info(.livePreviewActorEntered)
                self.publishLiveTranscriptPreview(text)
                self.logger.info(.livePreviewPublished)
            },
            circuitOpened: { [weak self] in
                self?.pathologicalPreviewCount += 1
            }
        )
        livePreviewTask = Task(priority: .medium) {
            await predecessor?.value
            guard !Task.isCancelled else { return }
            await session.run()
        }
    }

    @discardableResult
    private func stopLiveTranscriptPreview(clearText: Bool) -> Task<Void, Never>? {
        let task = livePreviewTask
        if task != nil {
            logger.info(.livePreviewCancellationRequested)
        }
        task?.cancel()
        livePreviewTask = nil
        if clearText {
            livePreviewDismissTask?.cancel()
            livePreviewDismissTask = nil
            publishLiveTranscriptPreview(nil)
        }
        return task
    }

    private func retainPreviewJoin(_ task: Task<Void, Never>?) {
        pendingPreviewJoin = mergePreviewJoins(pendingPreviewJoin, task)
    }

    private func mergePreviewJoins(
        _ first: Task<Void, Never>?,
        _ second: Task<Void, Never>?
    ) -> Task<Void, Never>? {
        guard first != nil || second != nil else { return nil }
        return Task(priority: .medium) {
            await first?.value
            await second?.value
        }
    }

    private func publishLiveTranscriptPreview(_ text: String?) {
        liveTranscriptPreview = text
        onLiveTranscriptPreview?(text)
    }

    private func scheduleLiveTranscriptPreviewDismissal() {
        retainPreviewJoin(stopLiveTranscriptPreview(clearText: false))
        guard liveTranscriptPreview != nil else { return }
        livePreviewDismissTask?.cancel()
        let visibility = livePreviewFinalVisibility
        livePreviewDismissTask = Task { [weak self, visibility] in
            do {
                try await Task.sleep(for: visibility)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.publishLiveTranscriptPreview(nil)
            self?.livePreviewDismissTask = nil
        }
    }

    public func toggleDictation() {
        switch state {
        case .idle, .failed:
            requestStart()
        case .recording:
            requestStop()
        case .preparing, .transcribing, .inserting:
            break
        }
    }

    private func registerHotkey(_ configuration: HotkeyConfiguration) throws {
        try hotkeyService.register(configuration) { [weak self] phase in
            self?.handleActivation(phase)
        }
    }

    private func registerPointerButton(_ buttonNumber: UInt32?) {
        pointerButtonService.register(buttonNumber: buttonNumber) { [weak self] phase in
            self?.handleActivation(phase)
        }
    }

    private func handleActivation(_ phase: GlobalHotkeyPhase) {
        logger.info(.activationHandlingStarted)
        let activationInterval = signposter.begin(.activationHandlingStarted)
        defer {
            signposter.end(.activationHandlingCompleted, activationInterval)
            logger.info(.activationHandlingCompleted)
        }
        switch phase {
        case .pressed:
            guard !activationIsPressed else { return }
            activationIsPressed = true
            requestStart()
        case .released:
            guard activationIsPressed else { return }
            activationIsPressed = false
            switch state {
            case .preparing:
                cancelAcceptedStart()
            case .recording:
                requestStop()
            case .idle, .transcribing, .inserting, .failed:
                break
            }
        }
    }

    private func cancelAcceptedStart() {
        guard activationStartTask != nil else { return }
        sessionEpoch &+= 1
        activationStartTask?.cancel()
        recordingStartedAt = nil
        transition(to: .idle)
    }

    private func handleStartError(_ error: any Error) {
        logger.error(.operationFailed, error: error)
        switch error {
        case AudioCaptureError.microphonePermissionDenied:
            transition(to: .failed(.microphonePermissionDenied))
            onOnboardingRequirement?(.microphone)
        case AudioCaptureError.microphoneUnavailable,
             AudioCaptureError.invalidInputFormat:
            transition(to: .failed(.microphoneUnavailable))
        case is ParakeetEngineError:
            transition(to: .failed(.modelUnavailable))
        default:
            transition(to: .failed(.recordingFailed))
        }
    }

    private func handleCompletionError(_ error: any Error) {
        logger.error(.operationFailed, error: error)
        switch error {
        case AudioCaptureError.noAudioCaptured:
            transition(to: .failed(.noAudioCaptured))
        case TextInsertionError.accessibilityPermissionRequired:
            transition(to: .failed(.accessibilityPermissionRequired))
            onOnboardingRequirement?(.accessibility)
        case TextInsertionError.insertionUncertain:
            transition(to: .failed(.insertionUncertain))
        case is TextInsertionError:
            transition(to: .failed(.insertionFailed))
        case is ParakeetEngineError:
            transition(to: .failed(.transcriptionFailed))
        default:
            transition(to: .failed(.transcriptionFailed))
        }
    }

    private func transition(to newState: DictationSessionState) {
        state = newState
        switch newState {
        case .idle, .failed:
            activityScope.end()
        case .preparing, .recording, .transcribing, .inserting:
            break
        }
    }

    private func finishSessionReturningToIdle() {
        currentSessionID = nil
        transition(to: .idle)
        logger.info(.sessionReturnedToIdle)
        scheduleIdleModelMaintenance()
    }

    private func scheduleIdleModelMaintenance() {
        let shouldRecover = recoveryPolicy.shouldAttemptRecovery(
            state: state,
            pathologicalEventCount: pathologicalPreviewCount,
            alreadyAttempted: modelRecoveryAttempted
        )
        if pathologicalPreviewCount > 0 {
            logger.info(.modelRecoveryConsidered)
            if !modelReloadOnStall || !shouldRecover {
                logger.info(.modelRecoverySkipped)
            }
        }

        let performRecovery = modelReloadOnStall && shouldRecover
        guard releasePooledBuffersWhenIdle || performRecovery else { return }
        if performRecovery {
            modelRecoveryAttempted = true
        }
        let selectedModel = settings.transcriptionModel
        let engine = transcriptionEngine
        let logger = logger
        let releasePooledBuffersWhenIdle = releasePooledBuffersWhenIdle
        modelMaintenanceTask?.cancel()
        modelMaintenanceTask = Task(priority: .utility) { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.state == .idle else {
                if performRecovery { logger.info(.modelRecoverySkipped) }
                return
            }
            if releasePooledBuffersWhenIdle {
                await engine.releasePooledBuffers()
            }
            guard performRecovery, !Task.isCancelled, self.state == .idle else { return }
            logger.info(.modelRecoveryStarted)
            do {
                try await engine.recover(model: selectedModel)
                logger.info(.modelRecoveryCompleted)
            } catch {
                logger.error(.operationFailed, error: error)
            }
        }
    }

    private static func isFailureState(_ state: DictationSessionState) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
