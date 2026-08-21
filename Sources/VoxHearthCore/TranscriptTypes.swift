import Foundation

public struct DictationSessionID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

public struct FinalTranscript: Equatable, Sendable {
    public let sessionID: DictationSessionID
    public let text: String

    public init(sessionID: DictationSessionID, text: String) {
        self.sessionID = sessionID
        self.text = text
    }
}

public struct DirectiveParse: Equatable, Sendable {
    public let source: FinalTranscript
    public let directive: RecognizedDirective?
    public let format: CleanupFormat
    public let payloadUTF8Offset: Int

    init(
        source: FinalTranscript,
        directive: RecognizedDirective?,
        format: CleanupFormat,
        payloadUTF8Offset: Int
    ) {
        precondition(payloadUTF8Offset >= 0)
        precondition(payloadUTF8Offset <= source.text.utf8.count)
        let utf8Index = source.text.utf8.index(
            source.text.utf8.startIndex,
            offsetBy: payloadUTF8Offset
        )
        precondition(String.Index(utf8Index, within: source.text) != nil)
        self.source = source
        self.directive = directive
        self.format = format
        self.payloadUTF8Offset = payloadUTF8Offset
    }

    public var effectiveText: Substring {
        let utf8Index = source.text.utf8.index(
            source.text.utf8.startIndex,
            offsetBy: payloadUTF8Offset
        )
        let index = String.Index(utf8Index, within: source.text)!
        return source.text[index...]
    }
}

public struct NormalizationInput: Equatable, Sendable {
    public let parse: DirectiveParse

    public init(parse: DirectiveParse) {
        self.parse = parse
    }

    public var sessionID: DictationSessionID { parse.source.sessionID }
    public var format: CleanupFormat { parse.format }
    public var text: Substring { parse.effectiveText }
}

public struct InsertableTranscript: Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        case original
        case directiveStrippedFallback(CleanupFallbackReason)
        case cleaned
    }

    public let sessionID: DictationSessionID
    public let text: String
    public let origin: Origin

    init(sessionID: DictationSessionID, text: String, origin: Origin) {
        self.sessionID = sessionID
        self.text = text
        self.origin = origin
    }
}

public enum DictationOutcome: Equatable, Sendable {
    case insert(InsertableTranscript)
    case cancelled(DictationSessionID)
    case recover(InsertableTranscript, CleanupFallbackReason)
}
