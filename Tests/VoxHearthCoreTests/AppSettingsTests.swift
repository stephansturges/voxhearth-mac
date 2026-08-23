import Foundation
import Testing
@testable import VoxHearthCore

@Test func appSettingsUsePrivacyPreservingDefaults() {
    let settings = AppSettings.default

    #expect(settings.hotkey == .controlOptionSpace)
    #expect(settings.pointerButton == nil)
    #expect(settings.inputDeviceUID == nil)
    #expect(settings.transcriptionModel == .multilingual)
    #expect(settings.language == .english)
    #expect(settings.launchAtLogin == false)
    #expect(settings.liveTranscriptOverlayEnabled == false)
    #expect(settings.clipboardCompatibilityEnabled == false)
    #expect(settings.cleanup == CleanupSettings())
    #expect(settings.cleanup.isEnabled)
    #expect(settings.cleanup.styling == .semiFormal)
    #expect(settings.cleanup.listDirectiveEnabled)
    #expect(settings.cleanup.emailDirectiveEnabled)
    #expect(settings.hotkey.displayName == "Control-Option-Space")
}

@Test func appSettingsRoundTripWithoutLosingHotkeyModifiers() throws {
    let settings = AppSettings(
        hotkey: HotkeyConfiguration(
            keyCode: 36,
            modifiers: [.control, .shift, .command]
        ),
        pointerButton: 4,
        inputDeviceUID: "local-device-uid",
        transcriptionModel: .multilingual,
        language: .ukrainian,
        launchAtLogin: true,
        liveTranscriptOverlayEnabled: true,
        clipboardCompatibilityEnabled: true,
        cleanup: CleanupSettings(
            isEnabled: false,
            styling: .formal,
            listDirectiveEnabled: false,
            emailDirectiveEnabled: true
        )
    )

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
    #expect(decoded == settings)
    #expect(decoded.pointerButton == 4)
    #expect(decoded.liveTranscriptOverlayEnabled)
}

@Test func legacySettingsWithoutModelRetainMultilingualBehavior() throws {
    let legacy = #"{"hotkey":{"keyCode":49,"modifiers":3},"language":"fr","launchAtLogin":false,"clipboardCompatibilityEnabled":false}"#
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
    #expect(decoded.transcriptionModel == .multilingual)
    #expect(decoded.language == .french)
    #expect(!decoded.liveTranscriptOverlayEnabled)
    #expect(decoded.cleanup == CleanupSettings())
}

@Test func partiallyWrittenCleanupSettingsReceiveOnlyMissingDefaults() throws {
    let payload = #"{"cleanup":{"isEnabled":false,"listDirectiveEnabled":false},"language":"fr","launchAtLogin":true}"#
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))
    #expect(!decoded.cleanup.isEnabled)
    #expect(!decoded.cleanup.listDirectiveEnabled)
    #expect(decoded.cleanup.emailDirectiveEnabled)
    #expect(decoded.cleanup.styling == .semiFormal)
    #expect(decoded.language == .french)
    #expect(decoded.launchAtLogin)
}

@Test func cleanupEnablementRequiresEveryStaticCondition() {
    let available = CleanupEnablement.resolve(
        settings: .default,
        disclosureVersion: CleanupDisclosure.requiredVersion,
        modelAssetVerified: true
    )
    #expect(available.isEffective)
    #expect(available.listDirectiveEnabled)
    #expect(available.emailDirectiveEnabled)
    #expect(available.ineffectiveReason == nil)

    var disabled = AppSettings.default
    disabled.cleanup.isEnabled = false
    #expect(CleanupEnablement.resolve(
        settings: disabled,
        disclosureVersion: 1,
        modelAssetVerified: true
    ).ineffectiveReason == .disabled)

    #expect(CleanupEnablement.resolve(
        settings: .default,
        disclosureVersion: 0,
        modelAssetVerified: true
    ).ineffectiveReason == .disclosureRequired)

    var nonEnglish = AppSettings.default
    nonEnglish.language = .french
    #expect(CleanupEnablement.resolve(
        settings: nonEnglish,
        disclosureVersion: 1,
        modelAssetVerified: true
    ).ineffectiveReason == .unsupportedLanguage)

    #expect(CleanupEnablement.resolve(
        settings: .default,
        disclosureVersion: 1,
        modelAssetVerified: false
    ).ineffectiveReason == .modelUnavailable)
}

@Test func disabledDirectiveTogglesStayDisabledWhenCleanupBecomesEffective() {
    var settings = AppSettings.default
    settings.cleanup.listDirectiveEnabled = false
    settings.cleanup.emailDirectiveEnabled = false
    let resolved = CleanupEnablement.resolve(
        settings: settings,
        disclosureVersion: 1,
        modelAssetVerified: true
    )
    #expect(resolved.isEffective)
    #expect(!resolved.listDirectiveEnabled)
    #expect(!resolved.emailDirectiveEnabled)
}

@Test func s1MiniAssetContractIsPinnedWithoutPerSessionHashing() {
    #expect(S1MiniModelAsset.bundleRoot == "s1-mini-gguf")
    #expect(S1MiniModelAsset.fileName == "s1-mini-q4_k_m.gguf")
    #expect(S1MiniModelAsset.byteCount == 484_219_808)
    #expect(S1MiniModelAsset.sha256 == "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634")
    #expect(S1MiniModelAsset.verifiedBundledURL(resourceURL: nil) == nil)
}

@Test func compactModelForcesItsOnlySupportedLanguage() {
    let settings = AppSettings(transcriptionModel: .compactEnglish, language: .french)
    #expect(settings.language == .english)
    #expect(TranscriptionModel.compactEnglish.supportedLanguages == [.english])
}

@Test func languageCatalogMatchesBundledModelContract() {
    #expect(DictationLanguage.allCases.count == 25)
    #expect(Set(DictationLanguage.allCases.map(\.rawValue)).count == 25)
    #expect(DictationLanguage.allCases.allSatisfy { !$0.displayName.isEmpty })
}

@Test func carbonModifierMappingCoversEveryPublicModifier() {
    let mapped = CarbonGlobalHotkeyService.carbonModifiers(
        for: [.control, .option, .shift, .command]
    )
    #expect(mapped != 0)
    #expect(CarbonGlobalHotkeyService.carbonModifiers(for: []) == 0)
}
