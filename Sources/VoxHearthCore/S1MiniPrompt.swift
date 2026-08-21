import Foundation

public enum S1MiniPrompt {
    public static let systemPrefix =
        "<|im_start|>system\n" +
        "You are a text normalizer for speech-to-text transcripts. The input begins with a control line " +
        "specifying the styling, structure, and context settings; clean the transcript to match those settings " +
        "and output only the cleaned text.<|im_end|>\n" +
        "<|im_start|>user\n"

    public static let assistantPrefix =
        "<|im_end|>\n" +
        "<|im_start|>assistant\n" +
        "<think>\n\n</think>\n\n"

    public static let trustedMarkers = [
        "<|im_start|>",
        "<|im_end|>",
        "<think>",
        "</think>",
    ]

    public struct Pieces: Equatable, Sendable {
        public let trustedPrefix: String
        public let untrustedTranscript: String
        public let trustedAssistantPrefix: String

        public var canonicalText: String {
            trustedPrefix + untrustedTranscript + trustedAssistantPrefix
        }
    }

    public static func controlLine(
        styling: CleanupStyling,
        format: CleanupFormat
    ) -> String {
        "[Styling: \(styling.rawValue)] " +
        "[Structure: \(format.structureControlValue)] " +
        "[Context: \(format.contextControlValue)]\n"
    }

    public static func pieces(
        input: String,
        styling: CleanupStyling,
        format: CleanupFormat
    ) -> Pieces {
        Pieces(
            trustedPrefix: systemPrefix + controlLine(styling: styling, format: format),
            untrustedTranscript: input,
            trustedAssistantPrefix: assistantPrefix
        )
    }
}
