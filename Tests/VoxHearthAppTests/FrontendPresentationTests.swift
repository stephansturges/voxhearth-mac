import AppKit
import Testing
@testable import VoxHearthApp
import VoxHearthCore

@Suite("Frontend presentation")
struct FrontendPresentationTests {
    @Test("Every dictation state has an actionable, privacy-conscious presentation")
    func sessionStatePresentation() {
        #expect(SessionPresentationState.idle.title == "Ready")
        #expect(SessionPresentationState.idle.primaryActionTitle == "Start Dictation")

        #expect(SessionPresentationState.listening.title == "Listening")
        #expect(SessionPresentationState.listening.primaryActionTitle == "Stop & Transcribe")

        #expect(SessionPresentationState.transcribing.title == "Transcribing on this Mac")
        #expect(SessionPresentationState.transcribing.isBusy)

        let error = SessionPresentationState.error("Microphone unavailable")
        #expect(error.title == "Dictation unavailable")
        #expect(error.detail == "Microphone unavailable")
    }

    @Test("Default hold-to-talk shortcut is Control-Option-Space")
    func defaultHotkey() {
        let hotkey = HotkeyDescriptor.defaultHoldToTalk

        #expect(hotkey.displayName == "⌃⌥Space")
        #expect(hotkey.modifiers.contains(.control))
        #expect(hotkey.modifiers.contains(.option))
        #expect(hotkey.isSuitableGlobalShortcut)
    }

    @Test("A bare key cannot become a global dictation shortcut")
    func rejectsBareShortcut() {
        let bareSpace = HotkeyDescriptor(keyCode: 49, modifierRawValue: 0)
        #expect(!bareSpace.isSuitableGlobalShortcut)
    }

    @Test("Accessory function keys can be bound without modifiers")
    func acceptsAccessoryFunctionKeys() {
        let f13 = HotkeyDescriptor(keyCode: 105, modifierRawValue: 0)
        let f20 = HotkeyDescriptor(keyCode: 90, modifierRawValue: 0)

        #expect(f13.isSuitableGlobalShortcut)
        #expect(f13.displayName == "F13")
        #expect(f20.isSuitableGlobalShortcut)
        #expect(f20.displayName == "F20")
    }

    @Test("Start cue is a tiny in-memory PCM wave")
    func startCueWaveData() {
        let data = DictationStartCuePlayer.makeToneData()

        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self) == "WAVE")
        #expect(data.count > 44)
        #expect(data.count < 5_000)
    }

    @Test("Privacy-sensitive settings start conservative")
    func privacyDefaults() {
        let settings = AppSettings.default

        #expect(settings.hotkey == .controlOptionSpace)
        #expect(settings.pointerButton == nil)
        #expect(settings.inputDeviceUID == nil)
        #expect(settings.transcriptionModel == .multilingual)
        #expect(settings.language == .english)
        #expect(!settings.launchAtLogin)
        #expect(!settings.clipboardCompatibilityEnabled)
    }

    @Test("First launch presents onboarding and later launches stay menu-bar only")
    func launchPresentationPolicy() {
        #expect(LaunchPresentationPolicy.shouldPresentOnboarding(hasCompletedOnboarding: false))
        #expect(!LaunchPresentationPolicy.shouldPresentOnboarding(hasCompletedOnboarding: true))
    }

    @Test("A second process yields to an older VoxHearth instance")
    func singleInstancePolicy() {
        #expect(
            AppInstancePolicy.shouldTerminateNewInstance(
                currentProcessIdentifier: 200,
                runningProcessIdentifiers: [200, 100]
            )
        )
        #expect(
            !AppInstancePolicy.shouldTerminateNewInstance(
                currentProcessIdentifier: 100,
                runningProcessIdentifiers: [100]
            )
        )
    }

    @Test("Accessibility recovery opens the precise privacy pane and explains replacement")
    func accessibilityRecoveryGuidance() {
        #expect(AccessibilityRecoveryGuidance.settingsURL.scheme == "x-apple.systempreferences")
        #expect(
            AccessibilityRecoveryGuidance.settingsURL.absoluteString
                .contains("Privacy_Accessibility")
        )
        #expect(AccessibilityRecoveryGuidance.updateExplanation.contains("new build"))
        #expect(AccessibilityRecoveryGuidance.recoverySteps.count == 4)
        #expect(AccessibilityRecoveryGuidance.recoverySteps.joined().contains("press −"))
        #expect(AccessibilityRecoveryGuidance.recoverySteps.joined().contains("Applications"))
    }
}
