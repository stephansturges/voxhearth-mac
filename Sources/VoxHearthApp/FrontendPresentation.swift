import AppKit
import SwiftUI

enum SessionPresentationState: Equatable, Sendable {
    case idle
    case listening
    case transcribing
    case error(String)

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .listening:
            "Listening"
        case .transcribing:
            "Transcribing on this Mac"
        case .error:
            "Dictation unavailable"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "Hold ⌃⌥Space to dictate anywhere."
        case .listening:
            "Release the shortcut or choose Stop & Transcribe."
        case .transcribing:
            "Audio is being processed by the bundled local model."
        case let .error(message):
            message
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            "waveform"
        case .listening:
            "waveform.circle.fill"
        case .transcribing:
            "ellipsis.circle.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .voxWarmWhite
        case .listening:
            .voxHearthAmber
        case .transcribing:
            .voxHearthAmber
        case .error:
            .red
        }
    }

    var isBusy: Bool {
        if case .transcribing = self { return true }
        return false
    }

    var primaryActionTitle: String {
        switch self {
        case .listening:
            "Stop & Transcribe"
        case .transcribing:
            "Transcribing…"
        case .idle, .error:
            "Start Dictation"
        }
    }
}

struct HotkeyDescriptor: Codable, Equatable, Sendable {
    static let defaultHoldToTalk = HotkeyDescriptor(
        keyCode: 49,
        modifierRawValue: NSEvent.ModifierFlags([.control, .option]).rawValue
    )

    let keyCode: UInt16
    let modifierRawValue: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
            .intersection(.deviceIndependentFlagsMask)
    }

    var displayName: String {
        Self.modifierDisplay(modifiers) + Self.keyDisplay(keyCode)
    }

    var isSuitableGlobalShortcut: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    static func modifierDisplay(_ modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    static func keyDisplay(_ keyCode: UInt16) -> String {
        let knownKeys: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M", 36: "Return", 48: "Tab",
            49: "Space", 51: "Delete", 53: "Escape", 123: "←", 124: "→",
            125: "↓", 126: "↑",
        ]
        return knownKeys[keyCode] ?? "Key (keyCode)"
    }
}

struct MicrophoneChoice: Identifiable, Equatable, Sendable {
    static let systemDefault = MicrophoneChoice(
        id: "system-default",
        name: "System Default",
        detail: "Follow the input selected in System Settings"
    )

    let id: String
    let name: String
    let detail: String?
}

struct LanguageChoice: Identifiable, Equatable, Sendable {
    static let automatic = LanguageChoice(
        id: "auto",
        name: "Automatic",
        detail: "Detect among the bundled model’s supported languages"
    )

    let id: String
    let name: String
    let detail: String?
}

enum SettingsSection: Hashable {
    case dictation
    case privacy
    case about
    case licenses
}

enum LaunchPresentationPolicy {
    static func shouldPresentOnboarding(hasCompletedOnboarding: Bool) -> Bool {
        !hasCompletedOnboarding
    }
}

enum AppInstancePolicy {
    static func shouldTerminateNewInstance(
        currentProcessIdentifier: Int32,
        runningProcessIdentifiers: [Int32]
    ) -> Bool {
        runningProcessIdentifiers.contains {
            $0 != currentProcessIdentifier && $0 < currentProcessIdentifier
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case privacy
    case permissions
    case tryIt

    var title: String {
        switch self {
        case .privacy: "Private by construction"
        case .permissions: "Two permissions, clearly explained"
        case .tryIt: "Try local dictation"
        }
    }
}

extension Color {
    static let voxGraphite = Color(red: 21 / 255, green: 23 / 255, blue: 26 / 255)
    static let voxHearthAmber = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
    static let voxWarmWhite = Color(red: 247 / 255, green: 244 / 255, blue: 238 / 255)
}
