import AppKit
import ApplicationServices
@preconcurrency import AVFoundation
import Foundation
import Observation
import ServiceManagement
import VoxHearthCore

enum PermissionPresentation: Equatable {
    case notDetermined
    case granted
    case denied

    var title: String {
        switch self {
        case .notDetermined: "Not requested"
        case .granted: "Allowed"
        case .denied: "Needs attention"
        }
    }

    var symbolName: String {
        switch self {
        case .notDetermined: "circle.dashed"
        case .granted: "checkmark.circle.fill"
        case .denied: "exclamationmark.circle.fill"
        }
    }
}

@Observable
@MainActor
final class VoxHearthFrontendModel {
    private enum DefaultsKey {
        static let appSettings = "VoxHearth.appSettings.v1"
        static let completedOnboarding = "VoxHearth.completedOnboarding.v1"
    }

    let controller: DictationController

    private(set) var availableMicrophones: [AudioInputDevice] = []
    private(set) var microphonePermission: PermissionPresentation = .notDetermined
    private(set) var accessibilityPermission: PermissionPresentation = .notDetermined
    private(set) var interfaceError: String?
    private(set) var microphoneFallbackNotice: String?

    var onboardingStep: OnboardingStep = .privacy
    var selectedSettingsSection: SettingsSection = .dictation
    var hasCompletedOnboarding: Bool

    private let defaults: UserDefaults
    private let audioCapture: AudioCaptureService
    private let startCuePlayer: DictationStartCuePlayer

    init(
        controller: DictationController? = nil,
        defaults: UserDefaults = .standard,
        audioCapture: AudioCaptureService = AudioCaptureService()
    ) {
        self.defaults = defaults
        self.audioCapture = audioCapture
        let startCuePlayer = DictationStartCuePlayer()
        self.startCuePlayer = startCuePlayer
        hasCompletedOnboarding = defaults.bool(forKey: DefaultsKey.completedOnboarding)

        let settings = Self.loadSettings(from: defaults)
        if let controller {
            self.controller = controller
        } else {
            let engine = ParakeetEngine(
                multilingualModelDirectoryURL: Self.bundledModelDirectoryURL(for: .multilingual),
                compactEnglishModelDirectoryURL: Self.bundledModelDirectoryURL(for: .compactEnglish)
            )
            self.controller = DictationController(
                transcriptionEngine: engine,
                settings: settings,
                audioCapture: audioCapture
            )
        }

        self.controller.onOnboardingRequirement = { [weak self] requirement in
            guard let self else { return }
            switch requirement {
            case .microphone:
                self.microphonePermission = .denied
            case .accessibility:
                self.accessibilityPermission = .denied
            }
        }
        self.controller.onStartCue = { [weak startCuePlayer] in
            await startCuePlayer?.play()
        }
        self.controller.onInputDeviceFallback = { [weak self] in
            self?.handleInputDeviceFallback()
        }

        do {
            try self.controller.activate()
        } catch {
            interfaceError = Self.userFacingMessage(for: error)
        }

        refreshPermissionStatus()
        Task {
            await refreshMicrophones()
            await self.controller.prepareEngine()
        }
    }

    var sessionState: SessionPresentationState {
        if let interfaceError {
            return .error(interfaceError)
        }

        switch controller.state {
        case .idle:
            return .idle
        case .recording:
            return .listening
        case .preparing, .transcribing, .inserting:
            return .transcribing
        case let .failed(failure):
            return .error(Self.userFacingMessage(for: failure))
        }
    }

    var settings: AppSettings {
        controller.settings
    }

    var hasPendingTranscript: Bool {
        controller.pendingTranscript != nil
    }

    var onboardingCanAdvance: Bool {
        switch onboardingStep {
        case .privacy, .tryIt:
            true
        case .permissions:
            microphonePermission == .granted && accessibilityPermission == .granted
        }
    }

    func primaryDictationAction() {
        interfaceError = nil
        switch controller.state {
        case .recording:
            Task { await controller.stopDictation() }
        case .preparing, .transcribing, .inserting:
            break
        case .idle, .failed:
            Task { await controller.startDictation() }
        }
    }

    func cancelDictation() {
        Task { await controller.cancelDictation() }
    }

    func retryPendingInsertion() {
        Task { await controller.retryPendingInsertion() }
    }

    func discardPendingTranscript() {
        controller.discardPendingTranscript()
    }

    func advanceOnboarding() {
        guard onboardingCanAdvance else { return }
        guard let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        onboardingStep = next
    }

    func moveBackInOnboarding() {
        guard let previous = OnboardingStep(rawValue: onboardingStep.rawValue - 1) else { return }
        onboardingStep = previous
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: DefaultsKey.completedOnboarding)
    }

    func restartOnboarding() {
        onboardingStep = .privacy
        hasCompletedOnboarding = false
        defaults.set(false, forKey: DefaultsKey.completedOnboarding)
    }

    func requestMicrophonePermission() {
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            microphonePermission = allowed ? .granted : .denied
            if allowed { await refreshMicrophones() }
        }
    }

    func requestAccessibilityPermission() {
        // Use the documented key value directly. The SDK declares the matching
        // global as mutable, which Swift 6 correctly rejects across actors.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityPermission = AXIsProcessTrustedWithOptions(options) ? .granted : .denied

        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshPermissionStatus()
        }
    }

    func openAccessibilitySettings() {
        // Ask macOS to register/prompt for the current executable if it has no
        // TCC record, then show the only supported place where the user can
        // remove a stale build and approve this one. VoxHearth never edits the
        // TCC database directly.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        guard ApplicationPresentation.openAccessibilitySettings() else {
            interfaceError = "System Settings could not be opened. Go to Privacy & Security → Accessibility."
            return
        }
        interfaceError = nil

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            refreshPermissionStatus()
        }
    }

    func refreshPermissionStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .granted
        case .denied, .restricted:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .denied
        }
        accessibilityPermission = AXIsProcessTrusted() ? .granted : .notDetermined
    }

    func refreshMicrophones() async {
        let devices = await audioCapture.availableInputDevices()
        availableMicrophones = devices
        if let selectedUID = settings.inputDeviceUID,
           !devices.contains(where: { $0.uid == selectedUID }) {
            var next = settings
            next.inputDeviceUID = nil
            apply(next)
            microphoneFallbackNotice = Self.microphoneFallbackMessage
        }
    }

    func setHotkey(_ descriptor: HotkeyDescriptor) {
        var next = settings
        next.hotkey = HotkeyConfiguration(
            keyCode: UInt32(descriptor.keyCode),
            modifiers: Self.coreModifiers(from: descriptor.modifiers)
        )
        apply(next)
    }

    func setPointerButton(_ buttonNumber: UInt32?) {
        var next = settings
        next.pointerButton = buttonNumber
        apply(next)
    }

    func setInputDevice(uid: String?) {
        var next = settings
        next.inputDeviceUID = uid
        apply(next)
        microphoneFallbackNotice = nil
    }

    func setLanguage(_ language: DictationLanguage) {
        var next = settings
        next.language = language
        apply(next)
    }

    func setTranscriptionModel(_ transcriptionModel: TranscriptionModel) {
        guard controller.state == .idle || isFailureState else { return }
        var next = settings
        next.transcriptionModel = transcriptionModel
        if !transcriptionModel.supports(next.language) {
            next.language = .english
        }
        apply(next)
        Task { await controller.prepareEngine() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        Task {
            do {
                let service = SMAppService.mainApp
                if enabled {
                    if service.status == .notRegistered || service.status == .notFound {
                        try service.register()
                    }
                } else if service.status != .notRegistered {
                    try await service.unregister()
                }

                var next = settings
                next.launchAtLogin = enabled
                apply(next)
            } catch {
                interfaceError = "Launch at login could not be updated: \(error.localizedDescription)"
            }
        }
    }

    func setClipboardCompatibility(_ enabled: Bool) {
        var next = settings
        next.clipboardCompatibilityEnabled = enabled
        apply(next)
    }

    var hotkeyDescriptor: HotkeyDescriptor {
        HotkeyDescriptor(
            keyCode: UInt16(clamping: settings.hotkey.keyCode),
            modifierRawValue: Self.appKitModifiers(from: settings.hotkey.modifiers).rawValue
        )
    }

    var pointerButtonDisplayName: String {
        guard let buttonNumber = settings.pointerButton else { return "Not configured" }
        switch buttonNumber {
        case 2: return "Middle mouse button"
        default: return "Mouse/accessory button \(buttonNumber + 1)"
        }
    }

    private func apply(_ settings: AppSettings) {
        do {
            try controller.applySettings(settings)
            try Self.persist(settings, to: defaults)
            interfaceError = nil
        } catch {
            interfaceError = Self.userFacingMessage(for: error)
        }
    }

    private func handleInputDeviceFallback() {
        do {
            try Self.persist(controller.settings, to: defaults)
            microphoneFallbackNotice = Self.microphoneFallbackMessage
            interfaceError = nil
        } catch {
            interfaceError = Self.userFacingMessage(for: error)
        }
    }

    private static let microphoneFallbackMessage =
        "The selected microphone became unavailable. VoxHearth switched to System Default."

    private static func loadSettings(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: DefaultsKey.appSettings),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    private static func persist(_ settings: AppSettings, to defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: DefaultsKey.appSettings)
    }

    private var isFailureState: Bool {
        if case .failed = controller.state { return true }
        return false
    }

    private static func bundledModelDirectoryURL(for model: TranscriptionModel) -> URL {
        if let explicitURL = Bundle.main.url(
            forResource: model.rawValue,
            withExtension: nil
        ) {
            return explicitURL
        }
        return (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(model.rawValue, isDirectory: true)
    }

    private static func appKitModifiers(from modifiers: HotkeyModifiers) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    private static func coreModifiers(from modifiers: NSEvent.ModifierFlags) -> HotkeyModifiers {
        var result: HotkeyModifiers = []
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let failure = error as? DictationFailure {
            return userFacingMessage(for: failure)
        }
        return error.localizedDescription
    }

    private static func userFacingMessage(for failure: DictationFailure) -> String {
        switch failure {
        case .microphonePermissionDenied:
            "Allow microphone access to begin dictating."
        case .microphoneUnavailable:
            "No usable microphone is available."
        case .modelUnavailable:
            "The bundled local speech model could not be loaded."
        case .recordingFailed:
            "VoxHearth could not start recording from this microphone."
        case .noAudioCaptured:
            "No speech was captured. Try holding the shortcut a little longer."
        case .transcriptionFailed:
            "The local speech model could not transcribe that recording."
        case .accessibilityPermissionRequired:
            "Allow Accessibility access so VoxHearth can insert text."
        case .insertionFailed:
            "The destination app did not accept the transcription."
        }
    }
}
