import Foundation
import Observation

private final class BoundedDrainReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func finish() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}

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
    public private(set) var pendingInsertions = PendingInsertionStore()
    public private(set) var cleanupStatus: CleanupStatus = .disabled
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

    @ObservationIgnored
    public var onDictationProgress: (@MainActor @Sendable (DictationProgress) -> Void)?

    /// A transient, memory-only UI seam used by onboarding to compare the raw
    /// final transcript with the exact typed value selected for insertion.
    @ObservationIgnored
    public var onFinalSelection: (@MainActor @Sendable (
        FinalTranscript,
        InsertableTranscript,
        RecognizedDirective?
    ) -> Void)?

    @ObservationIgnored private let audioCapture: any AudioCapturing
    @ObservationIgnored private let transcriptionEngine: any LocalTranscriptionEngine
    @ObservationIgnored private let textInserter: any TextInserting
    @ObservationIgnored private let hotkeyService: any GlobalHotkeyRegistering
    @ObservationIgnored private let pointerButtonService: any GlobalPointerButtonRegistering
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var transcriptionTasks: [DictationSessionID: Task<String, Error>] = [:]
    @ObservationIgnored private var enginePreparationTask: Task<Void, Error>?
    @ObservationIgnored private var pendingTranscriptExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var activationStartTask: Task<Void, Never>?
    @ObservationIgnored private var activationStopTask: Task<Void, Never>?
    @ObservationIgnored private var deferredStartTask: Task<Void, Never>?
    @ObservationIgnored private var livePreviewTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPreviewJoin: Task<Void, Never>?
    @ObservationIgnored private var livePreviewDismissTask: Task<Void, Never>?
    @ObservationIgnored private var modelMaintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupIdleUnloadTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupPressureRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var activationIsPressed = false
    @ObservationIgnored private var sessionEpoch = 0
    @ObservationIgnored private var currentSessionID: DictationSessionID?
    @ObservationIgnored private var cleanupCancellationTokens: [DictationSessionID: S1MiniCancellationToken] = [:]
    @ObservationIgnored private var explicitlyCancelledSessions: Set<DictationSessionID> = []
    @ObservationIgnored private var automaticInsertionSessions: Set<DictationSessionID> = []
    @ObservationIgnored private var automaticInsertionOrder: [DictationSessionID] = []
    @ObservationIgnored private var retryingSessions: Set<DictationSessionID> = []
    @ObservationIgnored private var recoveryReservations: Set<DictationSessionID> = []
    @ObservationIgnored private let pendingTranscriptLifetime: Duration
    @ObservationIgnored private let pendingTranscriptLifetimeSeconds: TimeInterval
    @ObservationIgnored private let expediteRestartDelay: Duration
    @ObservationIgnored private let livePreviewInterval: Duration
    @ObservationIgnored private let livePreviewMinimumDuration: TimeInterval
    @ObservationIgnored private let livePreviewWindow: TimeInterval
    @ObservationIgnored private let livePreviewFinalVisibility: Duration
    @ObservationIgnored private let livePreviewLatencyBudget: Duration
    @ObservationIgnored private let activityScope: LifecycleActivityScope
    @ObservationIgnored private let recoveryPolicy = ModelRecoveryPolicy()
    @ObservationIgnored private let releasePooledBuffersWhenIdle: Bool
    @ObservationIgnored private let modelReloadOnStall: Bool
    @ObservationIgnored private let cleanupNormalizer: (any TranscriptNormalizing)?
    @ObservationIgnored private var cleanupModelURL: URL?
    @ObservationIgnored private var cleanupDisclosureVersion: Int
    @ObservationIgnored private let cleanupDeadlineMilliseconds: Int
    @ObservationIgnored private let cleanupIdleUnloadDelay: Duration
    @ObservationIgnored private let cleanupPressureCooldown: Duration
    @ObservationIgnored private var cleanupIsPrepared = false
    @ObservationIgnored private var cleanupPreparationEpoch = 0
    @ObservationIgnored private var cleanupPreparationInFlight = false
    @ObservationIgnored private var cleanupUnloadPending = false
    @ObservationIgnored private var cleanupPreparationSuppressedUntil: ContinuousClock.Instant?
    @ObservationIgnored private var cleanupMemoryPressureMonitor: CleanupMemoryPressureMonitor?
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
        expediteRestartDelay: Duration = .milliseconds(100),
        livePreviewInterval: Duration = defaultLivePreviewInterval,
        livePreviewMinimumDuration: TimeInterval = 0.6,
        livePreviewWindow: TimeInterval = defaultLivePreviewWindow,
        livePreviewFinalVisibility: Duration = .seconds(2),
        livePreviewLatencyBudget: Duration? = nil,
        lifecycleActivityAsserter: (any LifecycleActivityAsserting)? = nil,
        releasePooledBuffersWhenIdle: Bool? = nil,
        modelReloadOnStall: Bool? = nil,
        cleanupNormalizer: (any TranscriptNormalizing)? = nil,
        cleanupModelURL: URL? = nil,
        cleanupDisclosureVersion: Int = 0,
        cleanupDeadlineMilliseconds: Int = CleanupRuntimeLimits.productionDeadlineMilliseconds,
        cleanupIdleUnloadDelay: Duration = .seconds(15 * 60),
        cleanupPressureCooldown: Duration = .seconds(5 * 60),
        monitorCleanupMemoryPressure: Bool = true
    ) {
        precondition(cleanupDeadlineMilliseconds > 0)
        self.transcriptionEngine = transcriptionEngine
        self.settings = settings.normalizedForSelectedModel()
        self.audioCapture = audioCapture
        self.textInserter = textInserter
        self.hotkeyService = hotkeyService
        self.pointerButtonService = pointerButtonService
        self.pendingTranscriptLifetime = pendingTranscriptLifetime
        pendingTranscriptLifetimeSeconds = Self.seconds(pendingTranscriptLifetime)
        self.expediteRestartDelay = expediteRestartDelay
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
        self.cleanupNormalizer = cleanupNormalizer
        self.cleanupModelURL = cleanupModelURL
        self.cleanupDisclosureVersion = cleanupDisclosureVersion
        self.cleanupDeadlineMilliseconds = cleanupDeadlineMilliseconds
        self.cleanupIdleUnloadDelay = cleanupIdleUnloadDelay
        self.cleanupPressureCooldown = cleanupPressureCooldown
        cleanupStatus = cleanupEnablement.isEffective ? .preparing : .disabled
        if cleanupNormalizer != nil, monitorCleanupMemoryPressure {
            cleanupMemoryPressureMonitor = CleanupMemoryPressureMonitor { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.handleCleanupMemoryPressure(level)
                }
            }
        }
    }

    deinit {
        transcriptionTasks.values.forEach { $0.cancel() }
        cleanupCancellationTokens.values.forEach { $0.cancel() }
        enginePreparationTask?.cancel()
        pendingTranscriptExpiryTask?.cancel()
        activationStartTask?.cancel()
        activationStopTask?.cancel()
        deferredStartTask?.cancel()
        enginePreparationTask?.cancel()
        livePreviewTask?.cancel()
        pendingPreviewJoin?.cancel()
        livePreviewDismissTask?.cancel()
        modelMaintenanceTask?.cancel()
        cleanupIdleUnloadTask?.cancel()
        cleanupPressureRecoveryTask?.cancel()
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
        deferredStartTask?.cancel()
        cleanupCancellationTokens.values.forEach { $0.cancel() }
        transcriptionTasks.values.forEach { $0.cancel() }
        livePreviewTask?.cancel()
        pendingPreviewJoin?.cancel()
        activityScope.end()
        isActive = false
    }

    public func applySettings(_ settings: AppSettings) throws {
        let settings = settings.normalizedForSelectedModel()
        let previousSettings = self.settings
        let wasCleanupEffective = cleanupEnablement.isEffective
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
        let enablement = cleanupEnablement
        if !enablement.isEffective {
            cleanupIdleUnloadTask?.cancel()
            cleanupPressureRecoveryTask?.cancel()
            cleanupPreparationSuppressedUntil = nil
            cleanupPreparationEpoch &+= 1
            cleanupIsPrepared = false
            if !Self.isCleanupActive(cleanupStatus) {
                cleanupStatus = .disabled
            }
            if wasCleanupEffective, let cleanupNormalizer {
                Task(priority: .utility) { await cleanupNormalizer.unload() }
            }
        }
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

    public var cleanupEnablement: CleanupEnablement {
        CleanupEnablement.resolve(
            settings: settings,
            disclosureVersion: cleanupDisclosureVersion,
            modelAssetVerified: cleanupNormalizer != nil && cleanupModelURL != nil
        )
    }

    public func configureCleanup(
        modelURL: URL?,
        disclosureVersion: Int
    ) {
        if cleanupModelURL != modelURL {
            cleanupIsPrepared = false
            cleanupPreparationEpoch &+= 1
        }
        cleanupModelURL = modelURL
        cleanupDisclosureVersion = disclosureVersion
        if !cleanupEnablement.isEffective, !Self.isCleanupActive(cleanupStatus) {
            cleanupStatus = .disabled
        }
    }

    public func prepareCleanupModelIfEffective() async {
        await prepareCleanupModelIfEffective(allowDuringRecording: false)
    }

    private func prepareCleanupModelIfEffective(allowDuringRecording: Bool) async {
        guard cleanupEnablement.isEffective,
              let cleanupNormalizer,
              let cleanupModelURL else {
            cleanupStatus = .disabled
            return
        }
        guard !cleanupPreparationInFlight else { return }
        guard state == .idle
                || Self.isFailureState(state)
                || (allowDuringRecording && state == .recording) else { return }
        let preparationEpoch = cleanupPreparationEpoch
        cleanupPreparationInFlight = true
        defer { cleanupPreparationInFlight = false }
        cleanupStatus = .preparing
        do {
            _ = try await cleanupNormalizer.prepare(
                modelURL: cleanupModelURL,
                selection: .production(),
                warmUp: true,
                deadlineMilliseconds: 30_000
            )
            guard preparationEpoch == cleanupPreparationEpoch,
                  cleanupEnablement.isEffective else {
                cleanupIsPrepared = false
                if !cleanupEnablement.isEffective { cleanupStatus = .disabled }
                return
            }
            cleanupIsPrepared = true
            if !Self.isCleanupActive(cleanupStatus) {
                cleanupStatus = .ready
            }
            scheduleCleanupIdleUnloadIfNeeded()
        } catch {
            cleanupIsPrepared = false
            logger.error(.operationFailed, error: error)
            cleanupStatus = .disabled
        }
    }

    public func handleCleanupMemoryPressure(_ level: CleanupMemoryPressureLevel) {
        guard let cleanupNormalizer else { return }
        if level == .critical, let currentSessionID {
            cleanupCancellationTokens[currentSessionID]?.cancel()
        }
        let now = ContinuousClock.now
        cleanupPreparationEpoch &+= 1
        cleanupPreparationSuppressedUntil = now + cleanupPressureCooldown
        cleanupPressureRecoveryTask?.cancel()
        cleanupPressureRecoveryTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.cleanupPressureCooldown)
            guard !Task.isCancelled else { return }
            self.cleanupPreparationSuppressedUntil = nil
            await self.prepareCleanupModelIfEffective()
        }
        let shouldUnload = !cleanupUnloadPending
            && (cleanupIsPrepared
                || cleanupStatus == .preparing
                || Self.isCleanupActive(cleanupStatus))
        guard shouldUnload else { return }
        cleanupUnloadPending = true
        cleanupIsPrepared = false
        if !Self.isCleanupActive(cleanupStatus) {
            cleanupStatus = cleanupEnablement.isEffective ? .preparing : .disabled
        }
        Task(priority: .utility) { [weak self] in
            await cleanupNormalizer.unload()
            self?.cleanupUnloadPending = false
        }
    }

    /// Drains cleanup work on application termination, but never makes Quit
    /// wait indefinitely for a non-cooperative native call.
    public func shutdownCleanup(deadline: Duration = .seconds(2)) async {
        cleanupIdleUnloadTask?.cancel()
        cleanupPressureRecoveryTask?.cancel()
        cleanupCancellationTokens.values.forEach { $0.cancel() }
        cleanupPreparationEpoch &+= 1
        cleanupIsPrepared = false
        guard let cleanupNormalizer else { return }
        await withCheckedContinuation { continuation in
            let reply = BoundedDrainReply(continuation)
            Task(priority: .utility) {
                await cleanupNormalizer.unload()
                reply.finish()
            }
            Task(priority: .utility) {
                try? await Task.sleep(for: deadline)
                reply.finish()
            }
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
        expirePendingInsertions()
        if Self.isFinalizingState(state) {
            guard activationIsPressed else { return false }
            requestExpeditedStart()
            return true
        }
        return acceptStart(waitForPriorStop: true, skipPreparation: false)
    }

    private func acceptStart(
        waitForPriorStop: Bool,
        skipPreparation: Bool
    ) -> Bool {
        let backgroundPreparationInProgress = state == .preparing
            && activationStartTask == nil
            && enginePreparationTask != nil
        let concurrentFinalization = !waitForPriorStop && Self.isFinalizingState(state)
        guard state == .idle
            || Self.isFailureState(state)
            || backgroundPreparationInProgress
            || concurrentFinalization else { return false }
        guard pendingInsertions.entries.count + recoveryReservations.count
                < pendingInsertions.capacity else {
            transition(to: .failed(.recoveryRequired))
            return false
        }
        modelMaintenanceTask?.cancel()
        modelMaintenanceTask = nil
        cleanupIdleUnloadTask?.cancel()
        cleanupIdleUnloadTask = nil
        let predecessorStart = activationStartTask
        let predecessorStop = activationStopTask
        let predecessorPreparation = enginePreparationTask
        predecessorStart?.cancel()
        sessionEpoch &+= 1
        let epoch = sessionEpoch
        let sessionID = DictationSessionID()
        currentSessionID = sessionID
        recoveryReservations.insert(sessionID)
        pathologicalPreviewCount = 0
        activityScope.beginAudioCritical()
        transition(to: .preparing)
        logger.info(.dictationStartAccepted)

        activationStartTask = Task(priority: .userInitiated) { [weak self] in
            await predecessorStart?.value
            if waitForPriorStop {
                await predecessorStop?.value
            }
            if !skipPreparation {
                _ = try? await predecessorPreparation?.value
            }
            guard let self else { return }
            guard self.sessionEpoch == epoch else {
                self.recoveryReservations.remove(sessionID)
                self.logger.info(.dictationStartAbandoned)
                return
            }
            await self.runAcceptedStart(
                epoch: epoch,
                sessionID: sessionID,
                skipPreparation: skipPreparation
            )
        }
        return true
    }

    private func requestExpeditedStart() {
        guard deferredStartTask == nil else { return }
        logger.info(.cleanupExpediteRequested)
        if let currentSessionID {
            cleanupCancellationTokens[currentSessionID]?.cancel()
            if case let .cleaning(format) = state {
                let fallback = CleanupFallbackReason.cancelled
                cleanupStatus = .fallingBack(currentSessionID, fallback)
                publishProgress(.fallingBack(format, fallback), for: currentSessionID)
            }
        }
        let delay = expediteRestartDelay
        deferredStartTask = Task(priority: .userInitiated) { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.deferredStartTask = nil
            guard self.activationIsPressed else { return }
            self.logger.info(.cleanupExpediteRestarted)
            _ = self.acceptStart(waitForPriorStop: false, skipPreparation: true)
        }
    }

    private func runAcceptedStart(
        epoch: Int,
        sessionID: DictationSessionID,
        skipPreparation: Bool
    ) async {
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
                recoveryReservations.remove(sessionID)
                logger.info(.dictationStartAbandoned)
                return
            }
            if !skipPreparation {
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
            }
            try Task.checkCancellation()
            guard epoch == sessionEpoch else {
                recoveryReservations.remove(sessionID)
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
                recoveryReservations.remove(sessionID)
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
            scheduleCleanupPreparationForActiveCaptureIfNeeded()
        } catch is CancellationError {
            await audioCapture.cancel()
            recoveryReservations.remove(sessionID)
            guard epoch == sessionEpoch else {
                logger.info(.dictationStartAbandoned)
                return
            }
            recordingStartedAt = nil
            currentSessionID = nil
            transition(to: .idle)
        } catch {
            await audioCapture.cancel()
            recoveryReservations.remove(sessionID)
            guard epoch == sessionEpoch else {
                logger.info(.dictationStartAbandoned)
                return
            }
            recordingStartedAt = nil
            if Task.isCancelled {
                currentSessionID = nil
                transition(to: .idle)
            } else {
                currentSessionID = nil
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
        publishProgress(.finalizing, for: sessionID)
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
            if currentSessionID == sessionID {
                activityScope.narrowToUserInitiated()
            }
            // A Parakeet actor can re-enter while awaiting Core ML. Joining the
            // cancelled preview prevents final inference from overlapping it.
            if let cancelledPreviewTask {
                await cancelledPreviewTask.value
                logger.info(.livePreviewCancellationJoined)
            }
            await transcribeAndInsert(audio, sessionID: sessionID)
        } catch is CancellationError {
            transcriptionTasks[sessionID] = nil
            recoveryReservations.remove(sessionID)
            if currentSessionID == sessionID {
                transition(to: .idle)
            }
        } catch {
            transcriptionTasks[sessionID] = nil
            recoveryReservations.remove(sessionID)
            handleCompletionError(error, for: sessionID)
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
        expirePendingInsertions()
        guard state == .idle || Self.isFailureState(state) else { return .busy }
        guard pendingInsertions.entries.count + recoveryReservations.count
                < pendingInsertions.capacity else {
            transition(to: .failed(.recoveryRequired))
            return .busy
        }
        guard audio.sampleRate.isFinite,
              audio.sampleRate > 0,
              audio.sampleRate <= 192_000,
              !audio.samples.isEmpty,
              audio.duration <= Self.maximumExternalAudioDuration,
              audio.samples.allSatisfy(\.isFinite) else {
            return .invalidAudio
        }

        let sessionID = DictationSessionID()
        currentSessionID = sessionID
        recoveryReservations.insert(sessionID)
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
        guard let sessionID = pendingInsertions.entries.first?.id else { return }
        await retryPendingInsertion(sessionID: sessionID)
    }

    public func retryPendingInsertion(sessionID: DictationSessionID) async {
        guard state == .idle || Self.isFailureState(state) else { return }
        expirePendingInsertions()
        guard let entry = pendingInsertions.entry(for: sessionID),
              retryingSessions.insert(sessionID).inserted else { return }
        recoveryReservations.insert(sessionID)
        removePendingInsertion(sessionID: sessionID)
        defer {
            retryingSessions.remove(sessionID)
            recoveryReservations.remove(sessionID)
        }
        activityScope.beginUserInitiated()
        transition(to: .inserting)
        do {
            _ = try await textInserter.insert(
                entry.transcript,
                clipboardFallbackEnabled: settings.clipboardCompatibilityEnabled
            )
            removePendingInsertion(sessionID: sessionID)
            if currentSessionID == nil, state == .inserting {
                transition(to: .idle)
            }
        } catch {
            retainPendingTranscript(entry.transcript, reason: pendingReason(for: error))
            handleCompletionError(error, for: sessionID)
        }
    }

    public func discardPendingTranscript() {
        guard let sessionID = pendingInsertions.entries.first?.id else { return }
        discardPendingInsertion(sessionID: sessionID)
    }

    public func discardPendingInsertion(sessionID: DictationSessionID) {
        removePendingInsertion(sessionID: sessionID)
        if Self.isFailureState(state) {
            transition(to: .idle)
        }
    }

    public func copyPendingInsertion(sessionID: DictationSessionID) throws {
        expirePendingInsertions()
        guard let entry = pendingInsertions.entry(for: sessionID) else { return }
        try textInserter.copyToClipboard(entry.transcript)
        removePendingInsertion(sessionID: sessionID)
        if Self.isFailureState(state) {
            transition(to: .idle)
        }
    }

    public func insertPendingAnyway(sessionID: DictationSessionID) async {
        guard state == .idle || Self.isFailureState(state) else { return }
        expirePendingInsertions()
        guard let entry = pendingInsertions.entry(for: sessionID),
              entry.reason == .blockedTerminal
                || entry.reason == .multilineClipboardDisabled,
              retryingSessions.insert(sessionID).inserted else { return }
        recoveryReservations.insert(sessionID)
        removePendingInsertion(sessionID: sessionID)
        defer {
            retryingSessions.remove(sessionID)
            recoveryReservations.remove(sessionID)
        }
        activityScope.beginUserInitiated()
        transition(to: .inserting)
        do {
            _ = try await textInserter.insertConfirmedMultiline(entry.transcript)
            removePendingInsertion(sessionID: sessionID)
            if currentSessionID == nil, state == .inserting {
                transition(to: .idle)
            }
        } catch {
            retainPendingTranscript(entry.transcript, reason: entry.reason)
            handleCompletionError(error, for: sessionID)
        }
    }

    public func cancelDictation() async {
        sessionEpoch &+= 1
        let epoch = sessionEpoch
        let cancelledSessionID = currentSessionID
        let cancelledSessionHasNoCompletionWork = state == .preparing || state == .recording
        if state == .recording {
            // Close the preview publication gate before awaiting cancellation;
            // an in-flight snapshot must not repopulate an overlay already
            // cleared by this whole-session cancel.
            transition(to: .transcribing)
        }
        if let cancelledSessionID {
            explicitlyCancelledSessions.insert(cancelledSessionID)
            cleanupCancellationTokens[cancelledSessionID]?.cancel()
            transcriptionTasks[cancelledSessionID]?.cancel()
        }
        let cancelledStartTask = activationStartTask
        let cancelledStopTask = activationStopTask
        cancelledStartTask?.cancel()
        cancelledStopTask?.cancel()
        deferredStartTask?.cancel()
        deferredStartTask = nil
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
            if cancelledSessionHasNoCompletionWork, let cancelledSessionID {
                recoveryReservations.remove(cancelledSessionID)
                cleanupCancellationTokens[cancelledSessionID] = nil
                explicitlyCancelledSessions.remove(cancelledSessionID)
            } else if let cancelledSessionID,
                      transcriptionTasks[cancelledSessionID] == nil,
                      cleanupCancellationTokens[cancelledSessionID] == nil,
                      !automaticInsertionSessions.contains(cancelledSessionID),
                      !retryingSessions.contains(cancelledSessionID) {
                // The stop/start tasks have been joined, so a marker with no
                // remaining keyed completion work cannot be observed again.
                explicitlyCancelledSessions.remove(cancelledSessionID)
            }
            logger.info(.dictationStopAbandoned)
            return
        }
        recordingStartedAt = nil
        if let cancelledSessionID {
            recoveryReservations.remove(cancelledSessionID)
            cleanupCancellationTokens[cancelledSessionID] = nil
            transcriptionTasks[cancelledSessionID] = nil
            explicitlyCancelledSessions.remove(cancelledSessionID)
        }
        currentSessionID = nil
        cleanupStatus = cleanupEnablement.isEffective
            ? (cleanupIsPrepared ? .ready : .preparing)
            : .disabled
        transition(to: .idle)
    }

    private func retainPendingTranscript(
        _ transcript: InsertableTranscript,
        reason: PendingInsertionReason
    ) {
        let retained = pendingInsertions.retain(
            transcript,
            reason: reason,
            lifetime: pendingTranscriptLifetimeSeconds
        )
        precondition(retained, "recovery reservation must prevent pending text loss")
        logger.info(.pendingInsertionRetained, sessionID: transcript.sessionID)
        recoveryReservations.remove(transcript.sessionID)
        synchronizePendingPresentation()
        schedulePendingExpiry()
    }

    private func removePendingInsertion(sessionID: DictationSessionID) {
        if pendingInsertions.remove(sessionID: sessionID) != nil {
            logger.info(.pendingInsertionRemoved, sessionID: sessionID)
        }
        synchronizePendingPresentation()
        schedulePendingExpiry()
        scheduleCleanupIdleUnloadIfNeeded()
    }

    private func expirePendingInsertions(now: Date = Date()) {
        let expired = pendingInsertions.expire(at: now)
        guard !expired.isEmpty else { return }
        for entry in expired {
            logger.info(.pendingInsertionExpired, sessionID: entry.id)
        }
        synchronizePendingPresentation()
        schedulePendingExpiry()
        if pendingInsertions.entries.isEmpty, Self.isFailureState(state) {
            transition(to: .idle)
        }
        scheduleCleanupIdleUnloadIfNeeded()
    }

    private func synchronizePendingPresentation() {
        pendingTranscript = pendingInsertions.entries.first?.text
    }

    private func schedulePendingExpiry() {
        pendingTranscriptExpiryTask?.cancel()
        pendingTranscriptExpiryTask = nil
        guard let expiry = pendingInsertions.entries.map(\.expiresAt).min() else { return }
        let delay = max(0, expiry.timeIntervalSinceNow)
        pendingTranscriptExpiryTask = Task { [weak self, delay] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.expirePendingInsertions()
        }
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
            transcriptionTasks[sessionID] = task
            let transcript = try await task.value
            transcriptionTasks[sessionID] = nil
            logger.info(.finalTranscriptionCompleted)

            guard !explicitlyCancelledSessions.contains(sessionID) else {
                finishSessionReturningToIdle(sessionID: sessionID)
                return
            }

            guard !transcript.isEmpty else {
                let ownsPresentation = currentSessionID == sessionID
                finishSessionReturningToIdle(sessionID: sessionID)
                if ownsPresentation { scheduleLiveTranscriptPreviewDismissal() }
                return
            }
            let finalTranscript = FinalTranscript(sessionID: sessionID, text: transcript)
            let policy = CleanupPolicy()
            let enablement = cleanupEnablement
            let insertableTranscript: InsertableTranscript
            let recognizedDirective: RecognizedDirective?
            if enablement.isEffective {
                let parse = CleanupDirectiveParser().parse(
                    finalTranscript,
                    listEnabled: enablement.listDirectiveEnabled,
                    emailEnabled: enablement.emailDirectiveEnabled
                )
                let input = NormalizationInput(parse: parse)
                if cleanupIsPrepared, let cleanupNormalizer {
                    let cancellation = S1MiniCancellationToken()
                    cleanupCancellationTokens[sessionID] = cancellation
                    transition(to: .cleaning(parse.format), for: sessionID)
                    publishProgress(.cleaning(parse.format), for: sessionID)
                    logger.info(.cleanupGenerationStarted, format: parse.format)
                    setCleanupStatus(.cleaning(sessionID), for: sessionID)
                    let outcome = await cleanupNormalizer.normalize(
                        input,
                        settings: settings.cleanup,
                        cancellation: cancellation,
                        deadlineMilliseconds: cleanupDeadlineMilliseconds
                    )
                    cleanupCancellationTokens[sessionID] = nil
                    guard !explicitlyCancelledSessions.contains(sessionID) else {
                        finishSessionReturningToIdle(sessionID: sessionID)
                        return
                    }
                    switch outcome {
                    case let .insert(selected):
                        insertableTranscript = selected
                    case let .recover(fallback, reason):
                        setCleanupStatus(.fallingBack(sessionID, reason), for: sessionID)
                        publishProgress(.fallingBack(parse.format, reason), for: sessionID)
                        insertableTranscript = fallback
                    case .cancelled:
                        let reason = CleanupFallbackReason.cancelled
                        setCleanupStatus(.fallingBack(sessionID, reason), for: sessionID)
                        publishProgress(.fallingBack(parse.format, reason), for: sessionID)
                        insertableTranscript = policy.fallback(for: input, reason: reason)
                    }
                } else {
                    let reason = CleanupFallbackReason.modelUnavailable
                    setCleanupStatus(.fallingBack(sessionID, reason), for: sessionID)
                    publishProgress(.fallingBack(parse.format, reason), for: sessionID)
                    insertableTranscript = policy.fallback(for: input, reason: reason)
                }
                recognizedDirective = parse.directive
            } else {
                insertableTranscript = policy.passthrough(finalTranscript)
                recognizedDirective = nil
            }
            transcriptForRecovery = insertableTranscript
            if currentSessionID == sessionID {
                onFinalSelection?(finalTranscript, insertableTranscript, recognizedDirective)
            }
            if currentSessionID == sessionID, settings.liveTranscriptOverlayEnabled {
                publishLiveTranscriptPreview(
                    insertableTranscript.text.isEmpty ? nil : insertableTranscript.text
                )
            }

            guard beginAutomaticInsertion(for: sessionID) else {
                finishSessionReturningToIdle(sessionID: sessionID)
                return
            }
            if insertableTranscript.text.isEmpty {
                removePendingInsertion(sessionID: sessionID)
                let ownsPresentation = currentSessionID == sessionID
                finishSessionReturningToIdle(sessionID: sessionID)
                if ownsPresentation { scheduleLiveTranscriptPreviewDismissal() }
                return
            }
            transition(to: .inserting, for: sessionID)
            logger.info(.textInsertionStarted)
            _ = try await textInserter.insert(
                insertableTranscript,
                clipboardFallbackEnabled: settings.clipboardCompatibilityEnabled
            )
            removePendingInsertion(sessionID: sessionID)
            let ownsPresentation = currentSessionID == sessionID
            finishSessionReturningToIdle(sessionID: sessionID)
            if ownsPresentation { scheduleLiveTranscriptPreviewDismissal() }
        } catch is CancellationError {
            transcriptionTasks[sessionID] = nil
            recoveryReservations.remove(sessionID)
            let ownsPresentation = currentSessionID == sessionID
            finishSessionReturningToIdle(sessionID: sessionID)
            if ownsPresentation { scheduleLiveTranscriptPreviewDismissal() }
        } catch {
            transcriptionTasks[sessionID] = nil
            if let transcriptForRecovery {
                let reason = pendingReason(for: error)
                retainPendingTranscript(
                    transcriptForRecovery,
                    reason: reason
                )
                publishProgress(.formattedTextReady(reason), for: sessionID)
            } else {
                recoveryReservations.remove(sessionID)
            }
            let ownsPresentation = currentSessionID == sessionID
            handleCompletionError(error, for: sessionID)
            if ownsPresentation { scheduleLiveTranscriptPreviewDismissal() }
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
        case .preparing, .transcribing, .cleaning, .inserting:
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
            case .idle, .transcribing, .cleaning, .inserting, .failed:
                deferredStartTask?.cancel()
                deferredStartTask = nil
                break
            }
        }
    }

    private func cancelAcceptedStart() {
        guard activationStartTask != nil else { return }
        sessionEpoch &+= 1
        activationStartTask?.cancel()
        if let currentSessionID {
            recoveryReservations.remove(currentSessionID)
        }
        recordingStartedAt = nil
        currentSessionID = nil
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

    private func handleCompletionError(
        _ error: any Error,
        for sessionID: DictationSessionID
    ) {
        logger.error(.operationFailed, error: error)
        let ownsPresentation = currentSessionID == sessionID
            || (currentSessionID == nil && state == .inserting)
        guard ownsPresentation else { return }
        if currentSessionID == sessionID {
            currentSessionID = nil
        }
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
        case .preparing, .recording, .transcribing, .cleaning, .inserting:
            break
        }
    }

    private func transition(
        to newState: DictationSessionState,
        for sessionID: DictationSessionID
    ) {
        guard currentSessionID == sessionID else { return }
        transition(to: newState)
    }

    private func finishSessionReturningToIdle(sessionID: DictationSessionID) {
        recoveryReservations.remove(sessionID)
        cleanupCancellationTokens[sessionID] = nil
        explicitlyCancelledSessions.remove(sessionID)
        guard currentSessionID == sessionID else { return }
        currentSessionID = nil
        cleanupStatus = cleanupEnablement.isEffective
            ? (cleanupIsPrepared ? .ready : .preparing)
            : .disabled
        transition(to: .idle)
        logger.info(.sessionReturnedToIdle)
        scheduleIdleModelMaintenance()
        scheduleCleanupPreparationIfNeeded()
        scheduleCleanupIdleUnloadIfNeeded()
    }

    private func beginAutomaticInsertion(for sessionID: DictationSessionID) -> Bool {
        guard automaticInsertionSessions.insert(sessionID).inserted else { return false }
        automaticInsertionOrder.append(sessionID)
        if automaticInsertionOrder.count > 64 {
            let expired = automaticInsertionOrder.removeFirst()
            automaticInsertionSessions.remove(expired)
        }
        return true
    }

    private func setCleanupStatus(
        _ status: CleanupStatus,
        for sessionID: DictationSessionID
    ) {
        guard currentSessionID == sessionID else { return }
        cleanupStatus = status
    }

    private func publishProgress(
        _ progress: DictationProgress,
        for sessionID: DictationSessionID
    ) {
        guard currentSessionID == sessionID else { return }
        onDictationProgress?(progress)
    }

    private func pendingReason(for error: any Error) -> PendingInsertionReason {
        switch error {
        case TextInsertionError.insertionUncertain:
            .insertionUncertain
        case TextInsertionError.multilineClipboardFallbackDisabled:
            .multilineClipboardDisabled
        case TextInsertionError.blockedMultilineDestination:
            .blockedTerminal
        default:
            .insertionFailed
        }
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

    private func scheduleCleanupPreparationIfNeeded() {
        guard cleanupEnablement.isEffective, !cleanupIsPrepared else { return }
        if let suppressedUntil = cleanupPreparationSuppressedUntil,
           ContinuousClock.now < suppressedUntil {
            return
        }
        Task(priority: .utility) { [weak self] in
            await Task.yield()
            guard let self, self.state == .idle else { return }
            await self.prepareCleanupModelIfEffective()
        }
    }

    private func scheduleCleanupPreparationForActiveCaptureIfNeeded() {
        guard cleanupEnablement.isEffective,
              !cleanupIsPrepared,
              !cleanupPreparationInFlight else { return }
        if let suppressedUntil = cleanupPreparationSuppressedUntil,
           ContinuousClock.now < suppressedUntil {
            return
        }
        Task(priority: .utility) { [weak self] in
            await Task.yield()
            guard let self, self.state == .recording else { return }
            await self.prepareCleanupModelIfEffective(allowDuringRecording: true)
        }
    }

    private func scheduleCleanupIdleUnloadIfNeeded() {
        cleanupIdleUnloadTask?.cancel()
        cleanupIdleUnloadTask = nil
        guard cleanupEnablement.isEffective,
              cleanupIsPrepared,
              pendingInsertions.entries.isEmpty,
              let cleanupNormalizer else { return }
        let delay = cleanupIdleUnloadDelay
        cleanupIdleUnloadTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  let self,
                  self.state == .idle,
                  self.pendingInsertions.entries.isEmpty,
                  self.cleanupEnablement.isEffective,
                  self.cleanupIsPrepared else { return }
            self.cleanupIsPrepared = false
            self.cleanupStatus = .preparing
            await cleanupNormalizer.unload()
            self.cleanupIdleUnloadTask = nil
        }
    }

    private static func isFailureState(_ state: DictationSessionState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private static func isFinalizingState(_ state: DictationSessionState) -> Bool {
        switch state {
        case .transcribing, .cleaning, .inserting: true
        case .idle, .preparing, .recording, .failed: false
        }
    }

    private static func isCleanupActive(_ status: CleanupStatus) -> Bool {
        switch status {
        case .cleaning, .fallingBack: true
        case .disabled, .preparing, .ready: false
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return max(
            0,
            TimeInterval(components.seconds)
                + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }
}
