import Foundation
import Testing
@testable import VoxHearthApp
import VoxHearthCore

private actor CleanupSettingsEngine: LocalTranscriptionEngine {
    private(set) var prepareCount = 0

    func prepare(model: TranscriptionModel) async throws {
        _ = model
        prepareCount += 1
    }

    func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage,
        model: TranscriptionModel
    ) async throws -> String {
        _ = audio
        _ = language
        _ = model
        return ""
    }
}

private actor CleanupSettingsAudio: AudioCapturing {
    func availableInputDevices() async -> [AudioInputDevice] { [] }
    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws -> AudioInputSelection {
        _ = inputDeviceUID
        _ = maximumDurationReached
        return .systemDefault
    }
    func snapshot(maximumDuration: TimeInterval) async -> CapturedAudio? {
        _ = maximumDuration
        return nil
    }
    func stop() async throws -> CapturedAudio {
        CapturedAudio(samples: [0.1], sampleRate: 16_000)
    }
    func cancel() async {}
}

@MainActor
private final class CleanupSettingsInserter: TextInserting {
    func insert(
        _ transcript: InsertableTranscript,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        _ = transcript
        _ = clipboardFallbackEnabled
        return .accessibility
    }
}

@MainActor
private final class CleanupSettingsHotkey: GlobalHotkeyRegistering {
    func register(
        _ configuration: HotkeyConfiguration,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) throws {
        _ = configuration
        _ = onEvent
    }
    func unregister() {}
}

@MainActor
private final class CleanupSettingsPointer: GlobalPointerButtonRegistering {
    func register(
        buttonNumber: UInt32?,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) {
        _ = buttonNumber
        _ = onEvent
    }
    func unregister() {}
}

@Test @MainActor func cleanupDisclosureAndTogglesDoNotPrepareTheModel() async throws {
    let suite = "VoxHearth.CleanupSettingsFrontendTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "VoxHearth.completedOnboarding.v1")
    defaults.set("test-build", forKey: "VoxHearth.completedOnboardingBuild.v1")

    let engine = CleanupSettingsEngine()
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: .default,
        audioCapture: CleanupSettingsAudio(),
        textInserter: CleanupSettingsInserter(),
        hotkeyService: CleanupSettingsHotkey(),
        pointerButtonService: CleanupSettingsPointer()
    )
    let model = VoxHearthFrontendModel(
        controller: controller,
        defaults: defaults,
        currentBuildIdentity: "test-build"
    )
    #expect(model.onboardingLaunchReason == .cleanupDisclosureRequired)
    #expect(model.cleanupDisclosureVersion == 0)
    #expect(model.cleanupEnablement.ineffectiveReason == .disclosureRequired)

    for _ in 0..<100 {
        if await engine.prepareCount > 0 {
            break
        }
        try? await Task.sleep(for: .milliseconds(2))
    }
    let baselinePreparations = await engine.prepareCount
    #expect(baselinePreparations == 1)

    model.setCleanupEnabled(false)
    model.setCleanupStyling(.formal)
    model.setListDirectiveEnabled(false)
    model.setEmailDirectiveEnabled(false)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await engine.prepareCount == baselinePreparations)
    #expect(!model.settings.cleanup.isEnabled)
    #expect(model.settings.cleanup.styling == .formal)
    #expect(!model.settings.cleanup.listDirectiveEnabled)
    #expect(!model.settings.cleanup.emailDirectiveEnabled)

    model.completeCleanupDisclosure()
    #expect(model.cleanupDisclosureVersion == CleanupDisclosure.requiredVersion)
    #expect(defaults.integer(forKey: CleanupDisclosure.defaultsKey) == 1)
    #expect(await engine.prepareCount == baselinePreparations)

    let persisted = try #require(defaults.data(forKey: "VoxHearth.appSettings.v1"))
    let decoded = try JSONDecoder().decode(AppSettings.self, from: persisted)
    #expect(decoded.cleanup == model.settings.cleanup)
}
