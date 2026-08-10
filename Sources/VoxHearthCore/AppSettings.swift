import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var hotkey: HotkeyConfiguration
    public var inputDeviceUID: String?
    public var language: DictationLanguage
    public var launchAtLogin: Bool
    public var clipboardCompatibilityEnabled: Bool

    public init(
        hotkey: HotkeyConfiguration = .controlOptionSpace,
        inputDeviceUID: String? = nil,
        language: DictationLanguage = .english,
        launchAtLogin: Bool = false,
        clipboardCompatibilityEnabled: Bool = false
    ) {
        self.hotkey = hotkey
        self.inputDeviceUID = inputDeviceUID
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.clipboardCompatibilityEnabled = clipboardCompatibilityEnabled
    }

    public static let `default` = AppSettings()
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
