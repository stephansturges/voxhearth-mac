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

    @Test("Privacy-sensitive settings start conservative")
    func privacyDefaults() {
        let settings = AppSettings.default

        #expect(settings.hotkey == .controlOptionSpace)
        #expect(settings.inputDeviceUID == nil)
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
}
