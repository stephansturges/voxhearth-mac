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

        #expect(SessionPresentationState.finalizing.title == "Transcribing on this Mac")
        #expect(SessionPresentationState.finalizing.isBusy)

        let cleaning = SessionPresentationState.cleaning(.listGeneral)
        #expect(cleaning.title == "Cleaning up on this Mac")
        #expect(cleaning.detail.contains("Formatting list"))
        #expect(cleaning.isBusy)
        #expect(cleaning.canCancelCurrentSession)

        #expect(SessionPresentationState.inserting.title == "Inserting text")
        #expect(SessionPresentationState.inserting.isBusy)

        let error = SessionPresentationState.error("Microphone unavailable")
        #expect(error.title == "Dictation unavailable")
        #expect(error.detail == "Microphone unavailable")
    }

    @Test("Cleanup copy exposes exact formats, dynamic payload size, and safe fallback states")
    func cleanupPresentationCopy() {
        #expect(CleanupSettingsPresentation.modelPayloadSize.contains("484"))
        #expect(CleanupSettingsPresentation.modelPayloadSize.contains("462 MiB"))
        #expect(
            CleanupSettingsPresentation.ineffectiveReason(.disclosureRequired)
                == "Cleanup is off until the new model disclosure is completed."
        )
        #expect(
            CleanupProgressPresentation.cleaningDetail(for: .proseGeneral)
                == "Cleaning up with S1-mini by Superwhisper…"
        )
        #expect(
            CleanupProgressPresentation.cleaningDetail(for: .listGeneral)
                == "Formatting list with S1-mini by Superwhisper…"
        )
        #expect(
            CleanupProgressPresentation.cleaningDetail(for: .proseEmail)
                == "Formatting email with S1-mini by Superwhisper…"
        )
        #expect(
            CleanupProgressPresentation.fallbackDetail(
                format: .listGeneral,
                reason: .inputTooLong
            ) == "Too long to format — inserted without the command"
        )
    }

    @Test("Static cleanup examples cover commands and near misses without a runtime seam")
    func cleanupExamplesAreFixedData() {
        #expect(CleanupExamples.all.map(\.id) == ["ordinary", "list", "email", "near-misses"])
        #expect(CleanupExamples.all.first { $0.id == "list" }?.cleaned.contains("\n") == true)
        #expect(CleanupExamples.all.first { $0.id == "email" }?.cleaned.contains("\n\n") == true)
        let nearMiss = CleanupExamples.all.first { $0.id == "near-misses" }
        #expect(nearMiss?.original == nearMiss?.cleaned)
    }

    @Test("Every pending reason exposes only its safe recovery actions")
    func pendingInsertionPresentation() {
        let sessionID = DictationSessionID()
        let ordinary = PendingInsertionPresentation(
            id: sessionID,
            position: 1,
            total: 1,
            reason: .insertionFailed
        )
        #expect(ordinary.allowsRetry)
        #expect(!ordinary.allowsInsertAnyway)

        let uncertain = PendingInsertionPresentation(
            id: sessionID,
            position: 1,
            total: 2,
            reason: .insertionUncertain
        )
        #expect(uncertain.retryNeedsConfirmation)
        #expect(uncertain.detail.contains("avoid a duplicate"))

        let terminal = PendingInsertionPresentation(
            id: sessionID,
            position: 2,
            total: 2,
            reason: .blockedTerminal
        )
        #expect(!terminal.allowsRetry)
        #expect(terminal.allowsInsertAnyway)
        #expect(terminal.insertAnywayWarning.contains("run pasted lines as commands"))
        #expect(terminal.insertAnywayWarning.contains("remove trailing line breaks"))

        let disabled = PendingInsertionPresentation(
            id: sessionID,
            position: 1,
            total: 1,
            reason: .multilineClipboardDisabled
        )
        #expect(disabled.allowsInsertAnyway)
        #expect(disabled.insertAnywayWarning.contains("setting will remain off"))
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
        #expect(!settings.liveTranscriptOverlayEnabled)
        #expect(!settings.clipboardCompatibilityEnabled)
    }

    @Test("Live preview presentation is bounded and has a listening placeholder")
    func livePreviewPresentation() {
        #expect(
            LiveTranscriptOverlayPresentation.displayText(for: "  ")
                == "Listening for speech…"
        )
        let longTranscript = (1...30).map { "word\($0)" }.joined(separator: " ")
        let displayed = LiveTranscriptOverlayPresentation.displayText(for: longTranscript)
        #expect(displayed == "… word21 word22 word23 word24 word25 word26 word27 word28 word29 word30")
        #expect(displayed.hasSuffix("word30"))
        #expect(displayed.split(separator: " ").count == 11)
    }

    @Test("Menu-bar window keeps a stable nonzero content height")
    func menuBarWindowSizing() throws {
        #expect(MenuBarLayoutPresentation.mainMenuMinimumHeight >= 400)
        #expect(
            MenuBarLayoutPresentation.mainMenuIdealHeight
                >= MenuBarLayoutPresentation.mainMenuMinimumHeight
        )
        #expect(
            MenuBarLayoutPresentation.mainMenuMaximumHeight
                >= MenuBarLayoutPresentation.mainMenuIdealHeight
        )

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menu = try String(contentsOf: repository.appendingPathComponent(
            "Sources/VoxHearthApp/MenuBarContentView.swift"
        ))
        #expect(menu.contains(
            "minHeight: MenuBarLayoutPresentation.mainMenuMinimumHeight"
        ))
        #expect(menu.contains(
            "idealHeight: MenuBarLayoutPresentation.mainMenuIdealHeight"
        ))
    }

    @Test("Onboarding appears once for every installed build")
    func launchPresentationPolicy() {
        #expect(
            LaunchPresentationPolicy.reason(
                previouslyCompleted: false,
                completedBuildIdentity: nil,
                currentBuildIdentity: "0.2.1 (10)"
            ) == .firstInstall
        )
        #expect(OnboardingStep.allCases == [.privacy, .cleanup, .permissions, .tryIt])
        #expect(
            LaunchPresentationPolicy.reason(
                previouslyCompleted: true,
                completedBuildIdentity: "0.2.1 (9)",
                currentBuildIdentity: "0.2.1 (10)"
            ) == .updatedBuild
        )
        #expect(
            LaunchPresentationPolicy.reason(
                previouslyCompleted: true,
                completedBuildIdentity: "0.2.1 (10)",
                currentBuildIdentity: "0.2.1 (10)"
            ) == nil
        )
        #expect(
            LaunchPresentationPolicy.reason(
                previouslyCompleted: true,
                completedBuildIdentity: "0.2.1 (10)",
                currentBuildIdentity: "0.2.1 (10)",
                cleanupDisclosureVersion: 0
            ) == .cleanupDisclosureRequired
        )
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
        #expect(AccessibilityRecoveryGuidance.updateExplanation.contains("cannot add"))
        #expect(AccessibilityRecoveryGuidance.recoverySteps.joined().contains("press −"))
        #expect(AccessibilityRecoveryGuidance.recoverySteps.joined().contains("press +"))
        #expect(AccessibilityRecoveryGuidance.recoverySteps.joined().contains("Applications"))
    }

    @Test("Cleanup length, privacy, attribution, and fallback copy stay explicit")
    func cleanupDisclosureAndAttributionCopy() {
        #expect(CleanupSettingsPresentation.lengthDisclosure.contains("Longer"))
        #expect(CleanupSettingsPresentation.lengthDisclosure.contains("inserted unchanged"))
        #expect(PrivacySettingsPresentation.localPreferences.contains("cleanup choice/style"))
        #expect(PrivacySettingsPresentation.localPreferences.contains("list/email prefix choices"))
        #expect(PrivacySettingsPresentation.localPreferences.contains("live-preview choice"))
        #expect(ThirdPartyLicensePresentation.cleanupDependencies.map(\.name) == [
            "S1-mini by Superwhisper", "Qwen3-0.6B", "llama.cpp",
        ])
        #expect(ThirdPartyLicensePresentation.cleanupDependencies[0].terms.contains("Naming-Clause"))
        #expect(
            CleanupProgressPresentation.fallbackDetail(
                format: .proseGeneral,
                reason: .inputTooLong
            ) == "Too long to clean up — using original transcript"
        )
    }

    @Test("Settings and onboarding both render the shared cleanup disclosure")
    func cleanupDisclosureSurfaces() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(contentsOf: repository.appendingPathComponent(
            "Sources/VoxHearthApp/SettingsRootView.swift"
        ))
        let onboarding = try String(contentsOf: repository.appendingPathComponent(
            "Sources/VoxHearthApp/OnboardingView.swift"
        ))
        let privacy = try String(contentsOf: repository.appendingPathComponent(
            "Documentation/PRIVACY.md"
        ))
        #expect(settings.contains("Text(CleanupSettingsPresentation.lengthDisclosure)"))
        #expect(onboarding.contains("Text(CleanupSettingsPresentation.lengthDisclosure)"))
        #expect(settings.contains("PrivacySettingsPresentation.localPreferences"))
        #expect(settings.contains("ThirdPartyLicensePresentation.cleanupDependencies"))
        #expect(privacy.contains(PrivacySettingsPresentation.localPreferences))
    }

    @Test("Recovery insertion controls are inert only while the session is busy")
    func recoveryActionEnablement() {
        #expect(RecoveryActionPresentation.insertionIsEnabled(for: .idle))
        #expect(RecoveryActionPresentation.insertionIsEnabled(for: .failed(.insertionFailed)))
        #expect(!RecoveryActionPresentation.insertionIsEnabled(for: .preparing))
        #expect(!RecoveryActionPresentation.insertionIsEnabled(for: .recording))
        #expect(!RecoveryActionPresentation.insertionIsEnabled(for: .transcribing))
        #expect(!RecoveryActionPresentation.insertionIsEnabled(for: .cleaning(.proseGeneral)))
        #expect(!RecoveryActionPresentation.insertionIsEnabled(for: .inserting))
        #expect(RecoveryActionPresentation.busyHint.contains("current dictation"))
    }
}
