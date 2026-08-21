import Foundation

public struct CleanupDirectiveParser: Sendable {
    public init() {}

    public func parse(
        _ transcript: FinalTranscript,
        listEnabled: Bool,
        emailEnabled: Bool
    ) -> DirectiveParse {
        let text = transcript.text
        var index = text.unicodeScalars.startIndex
        while index < text.unicodeScalars.endIndex,
              text.unicodeScalars[index].properties.isWhitespace {
            index = text.unicodeScalars.index(after: index)
        }

        guard let match = recognizedWord(in: text, at: &index) else {
            return ordinary(transcript)
        }
        guard (match == .list && listEnabled) || (match == .email && emailEnabled) else {
            return ordinary(transcript)
        }

        if index < text.unicodeScalars.endIndex {
            let delimiter = text.unicodeScalars[index]
            if delimiter == ":" || delimiter == "," || delimiter == "." {
                index = text.unicodeScalars.index(after: index)
            }
        }

        guard index < text.unicodeScalars.endIndex,
              text.unicodeScalars[index].properties.isWhitespace else {
            return ordinary(transcript)
        }
        while index < text.unicodeScalars.endIndex,
              text.unicodeScalars[index].properties.isWhitespace {
            index = text.unicodeScalars.index(after: index)
        }
        guard index < text.unicodeScalars.endIndex else {
            return ordinary(transcript)
        }

        // A leading combining scalar is a valid scalar boundary but not a
        // Swift Character boundary. Treat that degenerate input as ordinary
        // prose instead of trapping the global hotkey path.
        guard let payloadIndex = index.samePosition(in: text) else {
            return ordinary(transcript)
        }
        let offset = text.utf8.distance(
            from: text.utf8.startIndex,
            to: payloadIndex.samePosition(in: text.utf8)!
        )
        let format: CleanupFormat = match == .list ? .listGeneral : .proseEmail
        return DirectiveParse(
            source: transcript,
            directive: match,
            format: format,
            payloadUTF8Offset: offset
        )
    }

    private func ordinary(_ transcript: FinalTranscript) -> DirectiveParse {
        DirectiveParse(
            source: transcript,
            directive: nil,
            format: .proseGeneral,
            payloadUTF8Offset: 0
        )
    }

    private func recognizedWord(
        in text: String,
        at index: inout String.UnicodeScalarView.Index
    ) -> RecognizedDirective? {
        let start = index
        if consumeASCII("list", in: text, at: &index) {
            return .list
        }
        index = start
        if consumeASCII("email", in: text, at: &index) {
            return .email
        }
        index = start
        return nil
    }

    private func consumeASCII(
        _ expected: StaticString,
        in text: String,
        at index: inout String.UnicodeScalarView.Index
    ) -> Bool {
        var cursor = index
        for expectedByte in expected.withUTF8Buffer({ Array($0) }) {
            guard cursor < text.unicodeScalars.endIndex else { return false }
            let value = text.unicodeScalars[cursor].value
            let folded = value >= 65 && value <= 90 ? value + 32 : value
            guard folded == UInt32(expectedByte) else { return false }
            cursor = text.unicodeScalars.index(after: cursor)
        }
        index = cursor
        return true
    }
}
