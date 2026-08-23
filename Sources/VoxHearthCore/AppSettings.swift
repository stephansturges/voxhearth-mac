import Foundation

/// The immutable local speech models bundled inside VoxHearth.
public enum TranscriptionModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case multilingual = "parakeet-tdt-0.6b-v3-coreml"
    case compactEnglish = "parakeet-tdt-ctc-110m-coreml"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .multilingual: "Multilingual (600M)"
        case .compactEnglish: "Compact English (110M)"
        }
    }

    public var detail: String {
        switch self {
        case .multilingual: "Best accuracy and 25 languages"
        case .compactEnglish: "Lower memory use and faster startup"
        }
    }

    public var supportedLanguages: [DictationLanguage] {
        switch self {
        case .multilingual: DictationLanguage.allCases
        case .compactEnglish: [.english]
        }
    }

    public func supports(_ language: DictationLanguage) -> Bool {
        supportedLanguages.contains(language)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var hotkey: HotkeyConfiguration
    /// An optional NSEvent button number (2 is middle click; 3+ are extra
    /// mouse/accessory buttons). The keyboard shortcut remains available.
    public var pointerButton: UInt32?
    public var inputDeviceUID: String?
    public var transcriptionModel: TranscriptionModel
    public var language: DictationLanguage
    public var launchAtLogin: Bool
    public var liveTranscriptOverlayEnabled: Bool
    public var clipboardCompatibilityEnabled: Bool
    public var cleanup: CleanupSettings

    public init(
        hotkey: HotkeyConfiguration = .controlOptionSpace,
        pointerButton: UInt32? = nil,
        inputDeviceUID: String? = nil,
        transcriptionModel: TranscriptionModel = .multilingual,
        language: DictationLanguage = .english,
        launchAtLogin: Bool = false,
        liveTranscriptOverlayEnabled: Bool = false,
        clipboardCompatibilityEnabled: Bool = false,
        cleanup: CleanupSettings = CleanupSettings()
    ) {
        self.hotkey = hotkey
        self.pointerButton = pointerButton
        self.inputDeviceUID = inputDeviceUID
        self.transcriptionModel = transcriptionModel
        self.language = transcriptionModel.supports(language) ? language : .english
        self.launchAtLogin = launchAtLogin
        self.liveTranscriptOverlayEnabled = liveTranscriptOverlayEnabled
        self.clipboardCompatibilityEnabled = clipboardCompatibilityEnabled
        self.cleanup = cleanup
    }

    public static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case hotkey
        case pointerButton
        case inputDeviceUID
        case transcriptionModel
        case language
        case launchAtLogin
        case liveTranscriptOverlayEnabled
        case clipboardCompatibilityEnabled
        case cleanup
    }

    /// Keeps settings written by the first preview compatible: the model field
    /// did not exist there, so those users retain the multilingual model.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hotkey: try values.decodeIfPresent(HotkeyConfiguration.self, forKey: .hotkey)
                ?? .controlOptionSpace,
            pointerButton: try values.decodeIfPresent(UInt32.self, forKey: .pointerButton),
            inputDeviceUID: try values.decodeIfPresent(String.self, forKey: .inputDeviceUID),
            transcriptionModel: try values.decodeIfPresent(
                TranscriptionModel.self,
                forKey: .transcriptionModel
            ) ?? .multilingual,
            language: try values.decodeIfPresent(DictationLanguage.self, forKey: .language)
                ?? .english,
            launchAtLogin: try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
                ?? false,
            liveTranscriptOverlayEnabled: try values.decodeIfPresent(
                Bool.self,
                forKey: .liveTranscriptOverlayEnabled
            ) ?? false,
            clipboardCompatibilityEnabled: try values.decodeIfPresent(
                Bool.self,
                forKey: .clipboardCompatibilityEnabled
            ) ?? false,
            cleanup: try values.decodeIfPresent(CleanupSettings.self, forKey: .cleanup)
                ?? CleanupSettings()
        )
    }

    public func normalizedForSelectedModel() -> AppSettings {
        guard transcriptionModel.supports(language) else {
            var copy = self
            copy.language = .english
            return copy
        }
        return self
    }
}

public struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let control = HotkeyModifiers(rawValue: 1 << 0)
    public static let option = HotkeyModifiers(rawValue: 1 << 1)
    public static let shift = HotkeyModifiers(rawValue: 1 << 2)
    public static let command = HotkeyModifiers(rawValue: 1 << 3)
}

public struct HotkeyConfiguration: Codable, Hashable, Sendable {
    /// A hardware-independent macOS virtual key code.
    public var keyCode: UInt32
    public var modifiers: HotkeyModifiers

    public init(keyCode: UInt32, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Control-Option-Space. Space is virtual key code 49 on macOS.
    public static let controlOptionSpace = HotkeyConfiguration(
        keyCode: 49,
        modifiers: [.control, .option]
    )

    public var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "-")
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: "Space"
        case 36: "Return"
        case 48: "Tab"
        case 53: "Escape"
        case 105: "F13"
        case 107: "F14"
        case 113: "F15"
        case 106: "F16"
        case 64: "F17"
        case 79: "F18"
        case 80: "F19"
        case 90: "F20"
        default: "Key \(keyCode)"
        }
    }
}

/// The 25 languages supported by the bundled Parakeet TDT v3 model.
public enum DictationLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case bulgarian = "bg"
    case croatian = "hr"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case english = "en"
    case estonian = "et"
    case finnish = "fi"
    case french = "fr"
    case german = "de"
    case greek = "el"
    case hungarian = "hu"
    case italian = "it"
    case latvian = "lv"
    case lithuanian = "lt"
    case maltese = "mt"
    case polish = "pl"
    case portuguese = "pt"
    case romanian = "ro"
    case russian = "ru"
    case slovak = "sk"
    case slovenian = "sl"
    case spanish = "es"
    case swedish = "sv"
    case ukrainian = "uk"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bulgarian: "Bulgarian"
        case .croatian: "Croatian"
        case .czech: "Czech"
        case .danish: "Danish"
        case .dutch: "Dutch"
        case .english: "English"
        case .estonian: "Estonian"
        case .finnish: "Finnish"
        case .french: "French"
        case .german: "German"
        case .greek: "Greek"
        case .hungarian: "Hungarian"
        case .italian: "Italian"
        case .latvian: "Latvian"
        case .lithuanian: "Lithuanian"
        case .maltese: "Maltese"
        case .polish: "Polish"
        case .portuguese: "Portuguese"
        case .romanian: "Romanian"
        case .russian: "Russian"
        case .slovak: "Slovak"
        case .slovenian: "Slovenian"
        case .spanish: "Spanish"
        case .swedish: "Swedish"
        case .ukrainian: "Ukrainian"
        }
    }
}
