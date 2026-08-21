import AppKit
import SwiftUI
import VoxHearthCore

enum SessionPresentationState: Equatable, Sendable {
    case idle
    case listening
    case finalizing
    case cleaning(CleanupFormat)
    case inserting
    case error(String)

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .listening:
            "Listening"
        case .finalizing:
            "Transcribing on this Mac"
        case .cleaning:
            "Cleaning up on this Mac"
        case .inserting:
            "Inserting text"
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
        case .finalizing:
            "Audio is being processed by the bundled local model."
        case let .cleaning(format):
            CleanupProgressPresentation.cleaningDetail(for: format)
        case .inserting:
            "The selected text is being placed in the focused field."
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
        case .finalizing, .cleaning, .inserting:
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
        case .finalizing, .cleaning, .inserting:
            .voxHearthAmber
        case .error:
            .red
        }
    }

    var isBusy: Bool {
        switch self {
        case .finalizing, .cleaning, .inserting: true
        case .idle, .listening, .error: false
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .listening:
            "Stop & Transcribe"
        case .finalizing:
            "Finishing transcription…"
        case .cleaning:
            "Cleaning up…"
        case .inserting:
            "Inserting…"
        case .idle, .error:
            "Start Dictation"
        }
    }

    var canCancelCurrentSession: Bool {
        switch self {
        case .listening, .cleaning:
            true
        case .idle, .finalizing, .inserting, .error:
            false
        }
    }
}

enum CleanupProgressPresentation {
    static func cleaningDetail(for format: CleanupFormat) -> String {
        switch format {
        case .proseGeneral:
            "Cleaning up with S1-mini by Superwhisper…"
        case .listGeneral:
            "Formatting list with S1-mini by Superwhisper…"
        case .proseEmail:
            "Formatting email with S1-mini by Superwhisper…"
        }
    }

    static func fallbackDetail(
        format: CleanupFormat,
        reason: CleanupFallbackReason
    ) -> String {
        if reason == .inputTooLong, format != .proseGeneral {
            return "Too long to format — inserted without the command"
        }
        switch format {
        case .proseGeneral:
            return "Cleanup skipped — using original transcript"
        case .listGeneral:
            return "Formatting skipped — inserted without the “list” command"
        case .proseEmail:
            return "Formatting skipped — inserted without the “email” command"
        }
    }
}

enum CleanupSettingsPresentation {
    static var modelPayloadSize: String {
        let bytes = Int64(S1MiniModelAsset.byteCount)
        let decimal = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let mebibytes = Double(bytes) / 1_048_576
        return "\(decimal) (\(String(format: "%.0f", mebibytes)) MiB)"
    }

    static func ineffectiveReason(_ reason: CleanupIneffectiveReason?) -> String? {
        switch reason {
        case .disabled?:
            "Cleanup is turned off."
        case .disclosureRequired?:
            "Cleanup is off until the new model disclosure is completed."
        case .unsupportedLanguage?:
            "Cleanup currently runs only for English dictation."
        case .modelUnavailable?:
            "The bundled S1-mini model is unavailable, so VoxHearth will use the original transcript."
        case nil:
            nil
        }
    }
}

struct PendingInsertionPresentation: Identifiable, Equatable, Sendable {
    let id: DictationSessionID
    let position: Int
    let total: Int
    let reason: PendingInsertionReason

    var title: String {
        total == 1 ? "Previous dictation" : "Previous dictation \(position) of \(total)"
    }

    var detail: String {
        switch reason {
        case .insertionFailed:
            "The destination refused the text. Choose a text field, then retry, copy, or discard it. Available for 2 minutes."
        case .insertionUncertain:
            "VoxHearth could not confirm whether the destination received the text. Check it before retrying to avoid a duplicate. Available for 2 minutes."
        case .multilineClipboardDisabled:
            "The formatted text needs multiline paste, but clipboard compatibility is off. Copy it, insert it once with confirmation, or discard it. Available for 2 minutes."
        case .blockedTerminal:
            "This terminal may run pasted lines as commands. Copy the formatted text, insert it once with confirmation, or discard it. Available for 2 minutes."
        }
    }

    var allowsRetry: Bool {
        reason == .insertionFailed || reason == .insertionUncertain
    }

    var retryNeedsConfirmation: Bool { reason == .insertionUncertain }

    var allowsInsertAnyway: Bool {
        reason == .multilineClipboardDisabled || reason == .blockedTerminal
    }

    var insertAnywayWarning: String {
        switch reason {
        case .blockedTerminal:
            "This destination may run pasted lines as commands. Insert anyway? VoxHearth will remove trailing line breaks, but the destination may still execute earlier lines."
        case .multilineClipboardDisabled:
            "Insert this formatted text once using a temporary clipboard paste? Your clipboard-compatibility setting will remain off."
        case .insertionFailed, .insertionUncertain:
            ""
        }
    }
}

extension CleanupStyling {
    var displayName: String {
        switch self {
        case .casual: "Casual"
        case .semiCasual: "Semi-casual"
        case .semiFormal: "Semi-formal"
        case .formal: "Formal"
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
            || Self.unmodifiedAccessoryKeys.contains(keyCode)
    }

    /// F13-F20 are intentionally accepted without modifiers. They are rarely
    /// present on compact keyboards and are conventional safe targets for USB
    /// macro buttons, headset utilities, and mouse remapping software.
    private static let unmodifiedAccessoryKeys: Set<UInt16> = [
        105, 107, 113, 106, 64, 79, 80, 90,
    ]

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
            125: "↓", 126: "↑", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
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

enum AccessibilityRecoveryGuidance {
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    static let updateExplanation =
        "After replacing VoxHearth with a new build, macOS may keep the previous build’s Accessibility record instead of asking again. Apps cannot add or approve themselves in this protected list."

    static let recoverySteps = [
        "Click Set Up Accessibility to request access and open macOS Settings.",
        "If an old VoxHearth entry remains, select it and press −.",
        "If VoxHearth is not listed, press +, choose VoxHearth from Applications, then turn it on.",
        "Quit and reopen VoxHearth.",
    ]
}

enum OnboardingLaunchReason: Equatable {
    case firstInstall
    case updatedBuild
    case cleanupDisclosureRequired
    case manualReview
}

enum LaunchPresentationPolicy {
    static func reason(
        previouslyCompleted: Bool,
        completedBuildIdentity: String?,
        currentBuildIdentity: String,
        cleanupDisclosureVersion: Int = CleanupDisclosure.requiredVersion
    ) -> OnboardingLaunchReason? {
        guard previouslyCompleted else { return .firstInstall }
        guard completedBuildIdentity == currentBuildIdentity else { return .updatedBuild }
        guard cleanupDisclosureVersion >= CleanupDisclosure.requiredVersion else {
            return .cleanupDisclosureRequired
        }
        return nil
    }
}

enum AppBuildIdentity {
    static var current: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "development"
        let build = info?["CFBundleVersion"] as? String ?? "unversioned"
        return "\(version) (\(build))"
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
    case cleanup
    case permissions
    case tryIt

    var title: String {
        switch self {
        case .privacy: "Private by construction"
        case .cleanup: "Optional transcript cleanup"
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
