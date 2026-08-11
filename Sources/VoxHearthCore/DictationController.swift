import Foundation
import Observation

@MainActor
@Observable
public final class DictationController {
    public static let maximumExternalAudioDuration: TimeInterval = 10 * 60
    public static let defaultLivePreviewInterval: Duration = .seconds(2)
    public static let defaultLivePreviewWindow: TimeInterval = 30

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
    @ObservationIgnored private var pendingTranscriptExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var activationStartTask: Task<Void, Never>?
    @ObservationIgnored private var livePreviewTask: Task<Void, Never>?
    @ObservationIgnored private var livePreviewDismissTask: Task<Void, Never>?
    @ObservationIgnored private var activationIsPressed = false
    @ObservationIgnored private let pendingTranscriptLifetime: Duration
    @ObservationIgnored private let livePreviewInterval: Duration
    @ObservationIgnored private let livePreviewMinimumDuration: TimeInterval
    @ObservationIgnored private let livePreviewWindow: TimeInterval
    @ObservationIgnored private let livePreviewFinalVisibility: Duration
    @ObservationIgnored private let logger = PrivacySafeLogger(category: "Dictation")

    public init(
        transcriptionEngine: any LocalTranscriptionEngine,
        settings: AppSettings = .default,
        audioCapture: any AudioCapturing = AudioCaptureService(),
        textInserter: any TextInserting = TextInsertionService(),
        hotkeyService: any GlobalHotkeyRegistering = CarbonGlobalHotkeyService(),
        pointerButtonService: any GlobalPointerButtonRegistering = GlobalPointerButtonService(),
        pendingTranscriptLifetime: Duration = .seconds(120),
        livePreviewInterval: Duration = defaultLivePreviewInterval,
        livePreviewMinimumDuration: TimeInterval = 0.8,
        livePreviewWindow: TimeInterval = defaultLivePreviewWindow,
        livePreviewFinalVisibility: Duration = .seconds(2)
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
    }

    deinit {
        transcriptionTask?.cancel()
        pendingTranscriptExpiryTask?.cancel()
        activationStartTask?.cancel()
        livePreviewTask?.cancel()
        livePreviewDismissTask?.cancel()
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
                stopLiveTranscriptPreview(clearText: true)
            }
        } else if !settings.liveTranscriptOverlayEnabled {
            stopLiveTranscriptPreview(clearText: true)
        }
    }

    public func prepareEngine() async {
        guard state == .idle || Self.isFailureState(state) else { return }
        state = .preparing
        do {
            try await transcriptionEngine.prepare(model: settings.transcriptionModel)
            state = .idle
        } catch is CancellationError {
            state = .idle
        } catch {
            logger.error(.operationFailed, error: error)
            state = .failed(.modelUnavailable)
        }
    }

    public func startDictation() async {
        guard state == .idle || Self.isFailureState(state) else { return }
        clearPendingTranscript()
        state = .preparing

        do {
            await onStartCue?()
            try Task.checkCancellation()
            try await transcriptionEngine.prepare(model: settings.transcriptionModel)
            try Task.checkCancellation()
            let inputSelection = try await audioCapture.start(
                inputDeviceUID: settings.inputDeviceUID,
                maximumDurationReached: { [weak self] in
                    await self?.stopDictation()
                }
            )
            if inputSelection == .fellBackToSystemDefault {
                settings.inputDeviceUID = nil
                onInputDeviceFallback?()
            }
            recordingStartedAt = Date()
            state = .recording
            beginLiveTranscriptPreview()
        } catch is CancellationError {
            await audioCapture.cancel()
            recordingStartedAt = nil
            state = .idle
        } catch {
            await audioCapture.cancel()
            recordingStartedAt = nil
            handleStartError(error)
        }
    }

    public func stopDictation() async {
        guard state == .recording else { return }
        // Transition before the actor hop so simultaneous hotkey/limit stops
        // cannot both consume the same capture session.
        state = .transcribing
        recordingStartedAt = nil
        stopLiveTranscriptPreview(clearText: false)

        do {
            let audio = try await audioCapture.stop()
            await transcribeAndInsert(audio)
        } catch is CancellationError {
            transcriptionTask = nil
            state = .idle
        } catch {
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
        recordingStartedAt = nil
        state = .transcribing
        await transcribeAndInsert(audio)
        return .accepted
    }

    /// Retries insertion of an in-memory transcript retained after a destination
    /// app rejected it. Nothing is written to disk and the value remains subject
    /// to the same two-minute expiry.
    public func retryPendingInsertion() async {
        guard let pendingTranscript else { return }
        state = .inserting
        do {
            _ = try await textInserter.insert(
                pendingTranscript,
                clipboardFallbackEnabled: settings.clipboardCompatibilityEnabled
            )
            clearPendingTranscript()
            state = .idle
        } catch {
            retainPendingTranscript(pendingTranscript)
            handleCompletionError(error)
        }
    }

    public func discardPendingTranscript() {
        clearPendingTranscript()
        if Self.isFailureState(state) {
            state = .idle
        }
    }

    public func cancelDictation() async {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        stopLiveTranscriptPreview(clearText: true)
        await audioCapture.cancel()
        recordingStartedAt = nil
        state = .idle
    }

    private func retainPendingTranscript(_ transcript: String) {
        pendingTranscriptExpiryTask?.cancel()
        pendingTranscript = transcript
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
        pendingTranscript = nil
    }

    private func transcribeAndInsert(_ audio: CapturedAudio) async {
        var transcriptForRecovery: String?
        do {
            let selectedLanguage = settings.language
            let selectedModel = settings.transcriptionModel
            let task = Task {
                try await transcriptionEngine.transcribe(
                    audio,
                    language: selectedLanguage,
                    model: selectedModel
                )
            }
            transcriptionTask = task
            let transcript = try await task.value
            transcriptionTask = nil

            guard !transcript.isEmpty else {
                scheduleLiveTranscriptPreviewDismissal()
                state = .idle
                return
            }
            transcriptForRecovery = transcript
            if settings.liveTranscriptOverlayEnabled {
                publishLiveTranscriptPreview(transcript)
            }

            state = .inserting
            _ = try await textInserter.insert(
                transcript,
                clipboardFallbackEnabled: settings.clipboardCompatibilityEnabled
            )
            clearPendingTranscript()
            state = .idle
            scheduleLiveTranscriptPreviewDismissal()
        } catch is CancellationError {
            transcriptionTask = nil
            state = .idle
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
        livePreviewTask?.cancel()
        livePreviewDismissTask?.cancel()
        livePreviewDismissTask = nil
        publishLiveTranscriptPreview("")

        let interval = livePreviewInterval
        livePreviewTask = Task { [weak self, interval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.refreshLiveTranscriptPreview()
            }
        }
    }

    private func refreshLiveTranscriptPreview() async {
        guard state == .recording, settings.liveTranscriptOverlayEnabled,
              let audio = await audioCapture.snapshot(),
              audio.duration >= livePreviewMinimumDuration else { return }

        let selectedLanguage = settings.language
        let selectedModel = settings.transcriptionModel
        let boundedAudio = Self.trailingPreviewWindow(audio, maximumDuration: livePreviewWindow)
        do {
            let text = try await transcriptionEngine.transcribe(
                boundedAudio,
                language: selectedLanguage,
                model: selectedModel
            )
            guard !Task.isCancelled, state == .recording,
                  settings.liveTranscriptOverlayEnabled else { return }
            publishLiveTranscriptPreview(text)
        } catch is CancellationError {
            return
        } catch {
            // Preview is optional and must never disrupt final transcription.
            return
        }
    }

    private static func trailingPreviewWindow(
        _ audio: CapturedAudio,
        maximumDuration: TimeInterval
    ) -> CapturedAudio {
        let maximumSamples = max(1, Int((audio.sampleRate * maximumDuration).rounded(.down)))
        guard audio.samples.count > maximumSamples else { return audio }
        return CapturedAudio(
            samples: Array(audio.samples.suffix(maximumSamples)),
            sampleRate: audio.sampleRate
        )
    }

    private func stopLiveTranscriptPreview(clearText: Bool) {
        livePreviewTask?.cancel()
        livePreviewTask = nil
        if clearText {
            livePreviewDismissTask?.cancel()
            livePreviewDismissTask = nil
            publishLiveTranscriptPreview(nil)
        }
    }

    private func publishLiveTranscriptPreview(_ text: String?) {
        liveTranscriptPreview = text
        onLiveTranscriptPreview?(text)
    }

    private func scheduleLiveTranscriptPreviewDismissal() {
        livePreviewTask?.cancel()
        livePreviewTask = nil
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
            Task { await startDictation() }
        case .recording:
            Task { await stopDictation() }
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
        switch phase {
        case .pressed:
            guard !activationIsPressed else { return }
            activationIsPressed = true
            guard state == .idle || Self.isFailureState(state) else { return }
            activationStartTask?.cancel()
            activationStartTask = Task { [weak self] in
                guard let self else { return }
                await self.startDictation()
                if !self.activationIsPressed, self.state == .recording {
                    await self.stopDictation()
                }
            }
        case .released:
            guard activationIsPressed else { return }
            activationIsPressed = false
            switch state {
            case .preparing:
                activationStartTask?.cancel()
                Task { await cancelDictation() }
            case .recording:
                Task { await stopDictation() }
            case .idle, .transcribing, .inserting, .failed:
                break
            }
        }
    }

    private func handleStartError(_ error: any Error) {
        logger.error(.operationFailed, error: error)
        switch error {
        case AudioCaptureError.microphonePermissionDenied:
            state = .failed(.microphonePermissionDenied)
            onOnboardingRequirement?(.microphone)
        case AudioCaptureError.microphoneUnavailable,
             AudioCaptureError.invalidInputFormat:
            state = .failed(.microphoneUnavailable)
        case is ParakeetEngineError:
            state = .failed(.modelUnavailable)
        default:
            state = .failed(.recordingFailed)
        }
    }

    private func handleCompletionError(_ error: any Error) {
        logger.error(.operationFailed, error: error)
        switch error {
        case AudioCaptureError.noAudioCaptured:
            state = .failed(.noAudioCaptured)
        case TextInsertionError.accessibilityPermissionRequired:
            state = .failed(.accessibilityPermissionRequired)
            onOnboardingRequirement?(.accessibility)
        case is TextInsertionError:
            state = .failed(.insertionFailed)
        case is ParakeetEngineError:
            state = .failed(.transcriptionFailed)
        default:
            state = .failed(.transcriptionFailed)
        }
    }

    private static func isFailureState(_ state: DictationSessionState) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
