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
    #expect(settings.clipboardCompatibilityEnabled == false)
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
        clipboardCompatibilityEnabled: true
    )

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
    #expect(decoded == settings)
    #expect(decoded.pointerButton == 4)
}

@Test func legacySettingsWithoutModelRetainMultilingualBehavior() throws {
    let legacy = #"{"hotkey":{"keyCode":49,"modifiers":3},"language":"fr","launchAtLogin":false,"clipboardCompatibilityEnabled":false}"#
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
    #expect(decoded.transcriptionModel == .multilingual)
    #expect(decoded.language == .french)
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
