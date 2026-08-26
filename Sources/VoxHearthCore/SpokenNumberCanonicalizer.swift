import Foundation

protocol CleanupOutputCanonicalizing: AnyObject {
    func canonicalize(_ text: String, source: String) -> CleanupCanonicalizationResult
}

struct CleanupCanonicalizationResult: Equatable {
    let text: String
    let parseAttempts: Int
    let isOperational: Bool
}

/// Deterministic English number canonicalization confined to S1MiniQueueState's
/// existing serial queue. NumberFormatter is intentionally not Sendable and
/// this type must never escape that queue.
final class SpokenNumberCanonicalizer: CleanupOutputCanonicalizing {
    struct Options: Equatable {
        let isEnabled: Bool
        let maximumParseAttempts: Int
        let maximumValue: Int64

        static let v1 = Options(
            isEnabled: true,
            maximumParseAttempts: 4,
            maximumValue: 1_000_000_000_000
        )
        static let disabled = Options(
            isEnabled: false,
            maximumParseAttempts: 0,
            maximumValue: 1_000_000_000_000
        )
    }

    struct SelfCheckProbe: Equatable {
        let input: String
        let expected: String

        static let production = [
            SelfCheckProbe(input: "seven thousand and twelve", expected: "7012"),
            SelfCheckProbe(input: "eleventy", expected: "eleventy"),
            SelfCheckProbe(input: "one two three", expected: "one two three"),
            SelfCheckProbe(input: "twenty twenty-four", expected: "twenty twenty-four"),
        ]
    }

    private struct WordToken {
        let range: Range<String.Index>
        let lowercased: String
    }

    private struct SpokenCandidate {
        let range: Range<String.Index>
        let currencySymbol: String?
        let currencyRange: Range<String.Index>?
    }

    private struct SourceAnchor {
        let integer: Int64
        let currencySymbol: String?
    }

    private struct NumericSlot {
        let range: Range<String.Index>
        let integer: Int64
        let digits: String
        let currencySymbol: String?
    }

    private struct CoreResult {
        let text: String
        let parseAttempts: Int
        let exceededAttemptLimit: Bool
    }

    private struct Replacement {
        let range: Range<String.Index>
        let text: String
    }

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
        "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
        "billion", "trillion",
    ]

    private static let valuesAtOrBelowTen: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    ]

    private static let ordinalWords: Set<String> = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth",
        "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth",
        "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth", "thirtieth",
        "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth", "ninetieth",
        "hundredth", "thousandth", "millionth", "billionth", "trillionth",
    ]

    private static let currencyWords = [
        "dollar": "$", "dollars": "$", "euro": "€", "euros": "€", "yen": "¥",
    ]
    private static let currencySymbols: Set<Character> = ["$", "€", "¥"]
    private static let semanticGuards: Set<String> = [
        "point", "percent", "percentage", "percentages", "cent", "cents",
        "half", "halves", "quarter", "quarters",
    ]
    private static let negativeGuards: Set<String> = ["minus", "negative"]
    private static let identifierGuards: Set<String> = [
        "build", "chapter", "code", "extension", "highway", "id", "model",
        "number", "pin", "room", "route", "section", "version", "zip",
    ]
    private static let addressSuffixes: Set<String> = [
        "avenue", "boulevard", "court", "drive", "highway", "lane", "parkway",
        "place", "road", "street", "terrace", "trail", "way",
    ]

    private let options: Options
    private let formatter: NumberFormatter
    private(set) var isOperational: Bool

    init(
        options: Options = .v1,
        selfCheckProbes: [SelfCheckProbe] = SelfCheckProbe.production
    ) {
        self.options = options
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .spellOut
        formatter.isLenient = false
        self.formatter = formatter
        isOperational = options.isEnabled

        if isOperational {
            isOperational = selfCheckProbes.allSatisfy {
                canonicalizeCore($0.input).text == $0.expected
            }
        }
    }

    func canonicalize(_ text: String) -> CleanupCanonicalizationResult {
        guard isOperational else {
            return CleanupCanonicalizationResult(
                text: text,
                parseAttempts: 0,
                isOperational: false
            )
        }
        let result = canonicalizeCore(text)
        return CleanupCanonicalizationResult(
            text: result.exceededAttemptLimit ? text : result.text,
            parseAttempts: result.exceededAttemptLimit ? 0 : result.parseAttempts,
            isOperational: true
        )
    }

    func canonicalize(_ text: String, source: String) -> CleanupCanonicalizationResult {
        guard isOperational else {
            return CleanupCanonicalizationResult(
                text: text,
                parseAttempts: 0,
                isOperational: false
            )
        }
        let direct = canonicalizeCore(text)
        guard !direct.exceededAttemptLimit else {
            return CleanupCanonicalizationResult(
                text: text,
                parseAttempts: 0,
                isOperational: true
            )
        }
        let result = sourceAnchoredCorrection(
            of: direct,
            source: source
        )
        return CleanupCanonicalizationResult(
            text: result.text,
            parseAttempts: result.parseAttempts,
            isOperational: true
        )
    }

    private func canonicalizeCore(_ text: String) -> CoreResult {
        guard !text.isEmpty, options.isEnabled else {
            return CoreResult(text: text, parseAttempts: 0, exceededAttemptLimit: false)
        }

        let protected = protectedRanges(in: text)
        let tokens = wordTokens(in: text)
        let spokenCandidates = spokenCandidates(in: text, tokens: tokens, protected: protected)
        guard spokenCandidates.count <= options.maximumParseAttempts else {
            return CoreResult(text: text, parseAttempts: 0, exceededAttemptLimit: true)
        }

        var replacements = numericReplacements(in: text, protected: protected)
        var attempts = 0
        for candidate in spokenCandidates {
            attempts += 1
            guard let integer = parseExactInteger(
                String(text[candidate.range])
            ), !isPossibleYear(integer, currencySymbol: candidate.currencySymbol) else { continue }

            let replacementRange = candidate.currencyRange.map {
                candidate.range.lowerBound..<$0.upperBound
            } ?? candidate.range
            let replacementText = String(integer) + (candidate.currencySymbol ?? "")
            replacements.append(Replacement(range: replacementRange, text: replacementText))
        }

        guard !replacements.isEmpty else {
            return CoreResult(text: text, parseAttempts: attempts, exceededAttemptLimit: false)
        }
        let ordered = replacements.sorted { $0.range.lowerBound < $1.range.lowerBound }
        guard rangesDoNotOverlap(ordered) else {
            return CoreResult(text: text, parseAttempts: attempts, exceededAttemptLimit: false)
        }
        return CoreResult(
            text: applying(ordered, to: text),
            parseAttempts: attempts,
            exceededAttemptLimit: false
        )
    }

    /// S1-mini sometimes changes a spoken integer into an incorrect digit
    /// sequence while otherwise producing valid cleanup text. For the narrow
    /// one-number case, the original transcript remains the numeric source of
    /// truth. Reconcile only when both sides expose exactly one compatible,
    /// unprotected slot; every ambiguous shape keeps the direct result.
    private func sourceAnchoredCorrection(
        of direct: CoreResult,
        source: String
    ) -> CoreResult {
        guard direct.parseAttempts == 0 else { return direct }
        let outputProtected = protectedRanges(in: direct.text)
        let slots = numericSlots(in: direct.text, protected: outputProtected)
        guard slots.count == 1 else { return direct }

        let sourceProtected = protectedRanges(in: source)
        guard numericSlots(in: source, protected: sourceProtected).isEmpty else { return direct }
        let sourceTokens = wordTokens(in: source)
        let candidates = spokenCandidates(
            in: source,
            tokens: sourceTokens,
            protected: sourceProtected
        )
        let totalAttempts = direct.parseAttempts + candidates.count
        guard totalAttempts <= options.maximumParseAttempts else {
            return CoreResult(
                text: direct.text,
                parseAttempts: 0,
                exceededAttemptLimit: false
            )
        }

        let anchors = candidates.compactMap { candidate -> SourceAnchor? in
            guard let integer = parseExactInteger(String(source[candidate.range])) else {
                return nil
            }
            guard !isPossibleYear(integer, currencySymbol: candidate.currencySymbol) else {
                return nil
            }
            return SourceAnchor(integer: integer, currencySymbol: candidate.currencySymbol)
        }
        guard candidates.count == 1, anchors.count == 1 else {
            return CoreResult(
                text: direct.text,
                parseAttempts: totalAttempts,
                exceededAttemptLimit: false
            )
        }

        let anchor = anchors[0]
        let slot = slots[0]
        guard anchor.currencySymbol == slot.currencySymbol,
              anchor.integer != slot.integer,
              !numericContextIsGuarded(slot, in: direct.text),
              digitEditDistanceAtMostTwo(
                String(anchor.integer),
                slot.digits
              ) else {
            return CoreResult(
                text: direct.text,
                parseAttempts: totalAttempts,
                exceededAttemptLimit: false
            )
        }
        let replacement = String(anchor.integer) + (anchor.currencySymbol ?? "")
        return CoreResult(
            text: applying([Replacement(range: slot.range, text: replacement)], to: direct.text),
            parseAttempts: totalAttempts,
            exceededAttemptLimit: false
        )
    }

    private func numericSlots(
        in text: String,
        protected: [Range<String.Index>]
    ) -> [NumericSlot] {
        var slots: [NumericSlot] = []
        var index = text.startIndex
        while index < text.endIndex {
            if protected.contains(where: { $0.contains(index) }) {
                index = text.index(after: index)
                continue
            }
            if let slot = numericSlot(startingAt: index, in: text),
               !intersects(slot.range, protected) {
                slots.append(slot)
                index = slot.range.upperBound
            } else {
                index = text.index(after: index)
            }
        }
        return slots
    }

    private func numericSlot(startingAt start: String.Index, in text: String) -> NumericSlot? {
        let first = text[start]
        let prefixSymbol = Self.currencySymbols.contains(first) ? String(first) : nil
        var numberStart = start
        if prefixSymbol != nil {
            numberStart = text.index(after: start)
            guard numberStart < text.endIndex, text[numberStart].isNumber else { return nil }
        } else {
            guard first.isNumber else { return nil }
            if start > text.startIndex, Self.currencySymbols.contains(text[text.index(before: start)]) {
                return nil
            }
        }

        guard hasSafeNumericBoundary(before: start, in: text) else { return nil }
        var numberEnd = numberStart
        while numberEnd < text.endIndex,
              text[numberEnd].isNumber || text[numberEnd] == "," {
            numberEnd = text.index(after: numberEnd)
        }
        while numberEnd > numberStart, text[text.index(before: numberEnd)] == "," {
            numberEnd = text.index(before: numberEnd)
        }
        guard numberEnd > numberStart else { return nil }
        if numberEnd < text.endIndex,
           text[numberEnd] == ".",
           text.index(after: numberEnd) < text.endIndex,
           text[text.index(after: numberEnd)].isNumber {
            return nil
        }

        var end = numberEnd
        var suffixSymbol: String?
        if end < text.endIndex, Self.currencySymbols.contains(text[end]) {
            suffixSymbol = String(text[end])
            end = text.index(after: end)
        } else if let currency = currencyWordFollowing(index: end, in: text) {
            suffixSymbol = currency.symbol
            end = currency.range.upperBound
        }
        if let prefixSymbol, let suffixSymbol, prefixSymbol != suffixSymbol { return nil }
        let symbol = suffixSymbol ?? prefixSymbol
        guard hasSafeNumericBoundary(after: end, in: text),
              !hasCompoundCentsOrFraction(after: end, in: text) else { return nil }

        let rawNumber = String(text[numberStart..<numberEnd])
        let digits = rawNumber.filter(\.isNumber)
        guard !digits.isEmpty,
              digits.count == 1 || digits.first != "0",
              digits.count <= 13,
              let integer = Int64(digits),
              integer >= 11,
              integer <= options.maximumValue else { return nil }
        return NumericSlot(
            range: start..<end,
            integer: integer,
            digits: digits,
            currencySymbol: symbol
        )
    }

    private func numericContextIsGuarded(_ slot: NumericSlot, in text: String) -> Bool {
        if isPossibleYear(slot.integer, currencySymbol: slot.currencySymbol) { return true }
        if slot.range.lowerBound > text.startIndex {
            let previous = text[text.index(before: slot.range.lowerBound)]
            if previous == ":" { return true }
        }
        if slot.range.upperBound < text.endIndex {
            let next = text[slot.range.upperBound]
            if next == ":" || next == "%" { return true }
        }

        let tokens = wordTokens(in: text)
        let previousIndex = tokens.lastIndex { $0.range.upperBound <= slot.range.lowerBound }
        if let previousIndex,
           separator(
            in: text,
            from: tokens[previousIndex].range.upperBound,
            to: slot.range.lowerBound
           ) == " " {
            let word = tokens[previousIndex].lowercased
            if Self.semanticGuards.contains(word)
                || Self.negativeGuards.contains(word)
                || Self.identifierGuards.contains(word)
                || isOrdinalToken(word) {
                return true
            }
        }

        guard let followingIndex = tokens.firstIndex(where: {
            $0.range.lowerBound >= slot.range.upperBound
        }), separator(
            in: text,
            from: slot.range.upperBound,
            to: tokens[followingIndex].range.lowerBound
        ) == " " else { return false }

        let following = tokens[followingIndex].lowercased
        if Self.semanticGuards.contains(following) || isOrdinalToken(following) {
            return true
        }
        let addressLookaheadEnd = min(tokens.count, followingIndex + 3)
        for index in followingIndex..<addressLookaheadEnd {
            if index > followingIndex,
               separator(
                in: text,
                from: tokens[index - 1].range.upperBound,
                to: tokens[index].range.lowerBound
               ) != " " {
                break
            }
            if Self.addressSuffixes.contains(tokens[index].lowercased) { return true }
        }
        return false
    }

    private func digitEditDistanceAtMostTwo(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= 2 else { return false }
        var previous = Array(0...right.count)
        for (leftIndex, leftDigit) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)
            for (rightIndex, rightDigit) in right.enumerated() {
                let deletion = previous[rightIndex + 1] + 1
                let insertion = current[rightIndex] + 1
                let substitution = previous[rightIndex]
                    + (leftDigit == rightDigit ? 0 : 1)
                current.append(min(deletion, min(insertion, substitution)))
            }
            previous = current
        }
        return previous[right.count] <= 2
    }

    private func spokenCandidates(
        in text: String,
        tokens: [WordToken],
        protected: [Range<String.Index>]
    ) -> [SpokenCandidate] {
        var result: [SpokenCandidate] = []
        var tokenIndex = 0

        while tokenIndex < tokens.count {
            guard isNumberToken(tokens[tokenIndex].lowercased),
                  !intersects(tokens[tokenIndex].range, protected) else {
                tokenIndex += 1
                continue
            }

            let startIndex = tokenIndex
            var endIndex = tokenIndex
            var cursor = tokenIndex + 1
            while cursor < tokens.count,
                  separator(in: text, from: tokens[endIndex].range.upperBound,
                            to: tokens[cursor].range.lowerBound) == " " {
                if isNumberToken(tokens[cursor].lowercased),
                   !intersects(tokens[cursor].range, protected) {
                    endIndex = cursor
                    cursor += 1
                    continue
                }
                if tokens[cursor].lowercased == "and",
                   cursor + 1 < tokens.count,
                   separator(in: text, from: tokens[cursor].range.upperBound,
                             to: tokens[cursor + 1].range.lowerBound) == " ",
                   isNumberToken(tokens[cursor + 1].lowercased),
                   !intersects(tokens[cursor].range, protected),
                   !intersects(tokens[cursor + 1].range, protected) {
                    endIndex = cursor + 1
                    cursor += 2
                    continue
                }
                break
            }

            tokenIndex = endIndex + 1
            if startIndex == endIndex,
               Self.valuesAtOrBelowTen.contains(tokens[startIndex].lowercased) {
                continue
            }

            let candidateRange = tokens[startIndex].range.lowerBound..<tokens[endIndex].range.upperBound
            guard !intersects(candidateRange, protected),
                  hasSafeWordBoundaries(candidateRange, in: text),
                  !hasSemanticGuard(
                    before: startIndex,
                    after: endIndex,
                    tokens: tokens,
                    text: text
                  ),
                  !hasFollowingFraction(after: endIndex, tokens: tokens, text: text) else {
                continue
            }

            let currency = currencyFollowing(
                tokenIndex: endIndex,
                tokens: tokens,
                text: text
            )
            if let currency,
               hasCompoundCentsOrFraction(after: currency.range.upperBound, in: text) {
                continue
            }

            result.append(SpokenCandidate(
                range: candidateRange,
                currencySymbol: currency?.symbol,
                currencyRange: currency?.range
            ))
        }
        return result
    }

    private func parseExactInteger(_ phrase: String) -> Int64? {
        let parseInput = phrase.lowercased()
        var object: AnyObject?
        var consumed = NSRange(location: 0, length: (parseInput as NSString).length)
        do {
            try formatter.getObjectValue(&object, for: parseInput, range: &consumed)
        } catch {
            return nil
        }
        guard consumed.location == 0,
              consumed.length == (parseInput as NSString).length,
              let number = object as? NSNumber else { return nil }

        let decimal = number.decimalValue
        var decimalCopy = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimalCopy, 0, .plain)
        guard rounded == decimal,
              rounded >= Decimal(11),
              rounded <= Decimal(options.maximumValue) else { return nil }

        let integer = NSDecimalNumber(decimal: rounded).int64Value
        guard Decimal(integer) == rounded,
              let reverse = formatter.string(from: NSNumber(value: integer)),
              normalizedSpokenForm(reverse) == normalizedSpokenForm(phrase) else {
            return nil
        }
        return integer
    }

    private func normalizedSpokenForm(_ value: String) -> [String] {
        value.lowercased().split {
            $0.isWhitespace || $0 == "-"
        }.map(String.init).filter { $0 != "and" }
    }

    private func numericReplacements(
        in text: String,
        protected: [Range<String.Index>]
    ) -> [Replacement] {
        var result: [Replacement] = []
        var index = text.startIndex
        while index < text.endIndex {
            if protected.contains(where: { $0.contains(index) }) {
                index = text.index(after: index)
                continue
            }
            if let replacement = numericReplacement(startingAt: index, in: text),
               !intersects(replacement.range, protected) {
                result.append(replacement)
                index = replacement.range.upperBound
            } else {
                index = text.index(after: index)
            }
        }
        return result
    }

    private func numericReplacement(startingAt start: String.Index, in text: String) -> Replacement? {
        let first = text[start]
        let prefixSymbol = Self.currencySymbols.contains(first) ? String(first) : nil
        var numberStart = start
        if prefixSymbol != nil {
            numberStart = text.index(after: start)
            guard numberStart < text.endIndex, text[numberStart].isNumber else { return nil }
        } else {
            guard first.isNumber else { return nil }
            if start > text.startIndex, Self.currencySymbols.contains(text[text.index(before: start)]) {
                return nil
            }
        }

        guard hasSafeNumericBoundary(before: start, in: text) else { return nil }
        var numberEnd = numberStart
        while numberEnd < text.endIndex,
              text[numberEnd].isNumber || text[numberEnd] == "," {
            numberEnd = text.index(after: numberEnd)
        }
        while numberEnd > numberStart, text[text.index(before: numberEnd)] == "," {
            numberEnd = text.index(before: numberEnd)
        }

        let rawNumber = String(text[numberStart..<numberEnd])
        let grouped = isCanonicalGroupedInteger(rawNumber)
        let plain = isCanonicalPlainInteger(rawNumber)
        guard grouped || plain else { return nil }
        if numberEnd < text.endIndex,
           text[numberEnd] == ".",
           text.index(after: numberEnd) < text.endIndex,
           text[text.index(after: numberEnd)].isNumber {
            return nil
        }

        var end = numberEnd
        var suffixSymbol: String?
        if end < text.endIndex, Self.currencySymbols.contains(text[end]) {
            suffixSymbol = String(text[end])
            end = text.index(after: end)
        } else if let currency = currencyWordFollowing(index: end, in: text) {
            suffixSymbol = currency.symbol
            end = currency.range.upperBound
        }

        if let prefixSymbol, let suffixSymbol, prefixSymbol != suffixSymbol { return nil }
        let symbol = suffixSymbol ?? prefixSymbol
        guard grouped || symbol != nil else { return nil }
        guard hasSafeNumericBoundary(after: end, in: text),
              !hasCompoundCentsOrFraction(after: end, in: text) else { return nil }

        let digits = rawNumber.filter(\.isNumber)
        guard digits.count <= 13,
              let integer = Int64(digits),
              integer >= 11,
              integer <= options.maximumValue else { return nil }
        let slot = NumericSlot(
            range: start..<end,
            integer: integer,
            digits: digits,
            currencySymbol: symbol
        )
        guard !numericContextIsGuarded(slot, in: text) else { return nil }
        return Replacement(range: start..<end, text: String(integer) + (symbol ?? ""))
    }

    private func currencyFollowing(
        tokenIndex: Int,
        tokens: [WordToken],
        text: String
    ) -> (symbol: String, range: Range<String.Index>)? {
        let next = tokenIndex + 1
        guard next < tokens.count,
              separator(in: text, from: tokens[tokenIndex].range.upperBound,
                        to: tokens[next].range.lowerBound) == " ",
              let symbol = Self.currencyWords[tokens[next].lowercased] else { return nil }
        return (symbol, tokens[next].range)
    }

    private func currencyWordFollowing(
        index: String.Index,
        in text: String
    ) -> (symbol: String, range: Range<String.Index>)? {
        guard index < text.endIndex, text[index] == " " else { return nil }
        let wordStart = text.index(after: index)
        guard wordStart < text.endIndex, text[wordStart].isLetter else { return nil }
        var wordEnd = wordStart
        while wordEnd < text.endIndex, text[wordEnd].isLetter {
            wordEnd = text.index(after: wordEnd)
        }
        let word = String(text[wordStart..<wordEnd]).lowercased()
        guard let symbol = Self.currencyWords[word] else { return nil }
        return (symbol, wordStart..<wordEnd)
    }

    private func hasCompoundCentsOrFraction(after index: String.Index, in text: String) -> Bool {
        var cursor = index
        if cursor < text.endIndex, text[cursor] == "," {
            cursor = text.index(after: cursor)
        }
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        let tail = String(text[cursor...].prefix(64)).lowercased()
        let words = tail.split { !$0.isLetter }.prefix(6).map(String.init)
        guard words.first == "and" else { return false }
        return words.contains("cent") || words.contains("cents")
            || words.contains("half") || words.contains("halves")
            || words.contains("quarter") || words.contains("quarters")
    }

    private func hasFollowingFraction(
        after end: Int,
        tokens: [WordToken],
        text: String
    ) -> Bool {
        let andIndex = end + 1
        let articleIndex = end + 2
        let fractionIndex = end + 3
        guard fractionIndex < tokens.count,
              tokens[andIndex].lowercased == "and",
              tokens[articleIndex].lowercased == "a",
              Self.semanticGuards.contains(tokens[fractionIndex].lowercased),
              separator(in: text, from: tokens[end].range.upperBound,
                        to: tokens[andIndex].range.lowerBound) == " ",
              separator(in: text, from: tokens[andIndex].range.upperBound,
                        to: tokens[articleIndex].range.lowerBound) == " ",
              separator(in: text, from: tokens[articleIndex].range.upperBound,
                        to: tokens[fractionIndex].range.lowerBound) == " " else {
            return false
        }
        return true
    }

    private func hasSemanticGuard(
        before start: Int,
        after end: Int,
        tokens: [WordToken],
        text: String
    ) -> Bool {
        if start > 0,
           separator(in: text, from: tokens[start - 1].range.upperBound,
                     to: tokens[start].range.lowerBound) == " " {
            let previous = tokens[start - 1].lowercased
            if Self.semanticGuards.contains(previous)
                || Self.negativeGuards.contains(previous)
                || Self.identifierGuards.contains(previous)
                || isOrdinalToken(previous) {
                return true
            }
        }
        if end + 1 < tokens.count,
           separator(in: text, from: tokens[end].range.upperBound,
                     to: tokens[end + 1].range.lowerBound) == " " {
            let next = tokens[end + 1].lowercased
            if Self.semanticGuards.contains(next) || isOrdinalToken(next) {
                return true
            }
        }
        let addressLookaheadEnd = min(tokens.count, end + 4)
        if end + 1 < addressLookaheadEnd {
            for index in (end + 1)..<addressLookaheadEnd {
                guard separator(
                    in: text,
                    from: tokens[index - 1].range.upperBound,
                    to: tokens[index].range.lowerBound
                ) == " " else { break }
                if Self.addressSuffixes.contains(tokens[index].lowercased) {
                    return true
                }
            }
        }
        return false
    }

    private func isPossibleYear(_ integer: Int64, currencySymbol: String?) -> Bool {
        currencySymbol == nil && (1900...2099).contains(integer)
    }

    private func isOrdinalToken(_ token: String) -> Bool {
        if Self.ordinalWords.contains(token) { return true }
        guard let final = token.split(separator: "-").last else { return false }
        return Self.ordinalWords.contains(String(final))
    }

    private func isNumberToken(_ token: String) -> Bool {
        let parts = token.split(separator: "-").map(String.init)
        return !parts.isEmpty && parts.allSatisfy(Self.numberWords.contains)
    }

    private func wordTokens(in text: String) -> [WordToken] {
        var result: [WordToken] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter else {
                index = text.index(after: index)
                continue
            }
            let start = index
            index = text.index(after: index)
            while index < text.endIndex {
                if text[index].isLetter {
                    index = text.index(after: index)
                    continue
                }
                if text[index] == "-" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next].isLetter {
                        index = text.index(after: next)
                        continue
                    }
                }
                break
            }
            let range = start..<index
            result.append(WordToken(
                range: range,
                lowercased: String(text[range]).lowercased()
            ))
        }
        return result
    }

    private func protectedRanges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var backtickRuns: [(range: Range<String.Index>, count: Int)] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "`" {
                let start = index
                var count = 0
                while index < text.endIndex, text[index] == "`" {
                    count += 1
                    index = text.index(after: index)
                }
                backtickRuns.append((start..<index, count))
            } else {
                index = text.index(after: index)
            }
        }

        var runIndex = 0
        while runIndex < backtickRuns.count {
            let opener = backtickRuns[runIndex]
            if let closingIndex = backtickRuns[(runIndex + 1)...].firstIndex(where: {
                $0.count == opener.count
            }) {
                result.append(opener.range.lowerBound..<backtickRuns[closingIndex].range.upperBound)
                runIndex = closingIndex + 1
            } else {
                result.append(opener.range.lowerBound..<text.endIndex)
                break
            }
        }

        index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }
            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
            let range = start..<index
            let token = String(text[range])
            if token.contains("://") || (token.contains("@") && token.contains(".")) {
                result.append(range)
            }
        }
        return result
    }

    private func isCanonicalGroupedInteger(_ value: String) -> Bool {
        let groups = value.split(separator: ",", omittingEmptySubsequences: false)
        guard groups.count > 1,
              (1...3).contains(groups[0].count),
              groups[0].first != "0",
              groups.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    private func isCanonicalPlainInteger(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.allSatisfy(\.isNumber),
              value.count == 1 || value.first != "0" else { return false }
        return true
    }

    private func hasSafeWordBoundaries(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex {
            let previous = text[text.index(before: range.lowerBound)]
            if previous.isLetter || previous.isNumber || "'_+-/:".contains(previous) { return false }
        }
        if range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next.isLetter || next.isNumber || "'_+-/:".contains(next) { return false }
        }
        return true
    }

    private func hasSafeNumericBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !previous.isLetter && !previous.isNumber && !"_+-,./:".contains(previous)
    }

    private func hasSafeNumericBoundary(after index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        let next = text[index]
        return !next.isLetter && !next.isNumber && !"_+-/:%".contains(next)
    }

    private func separator(
        in text: String,
        from start: String.Index,
        to end: String.Index
    ) -> Substring {
        text[start..<end]
    }

    private func intersects(
        _ range: Range<String.Index>,
        _ protected: [Range<String.Index>]
    ) -> Bool {
        protected.contains { range.overlaps($0) }
    }

    private func rangesDoNotOverlap(_ replacements: [Replacement]) -> Bool {
        guard replacements.count > 1 else { return true }
        for index in 1..<replacements.count
        where replacements[index - 1].range.overlaps(replacements[index].range) {
            return false
        }
        return true
    }

    private func applying(_ replacements: [Replacement], to text: String) -> String {
        var output = ""
        var cursor = text.startIndex
        for replacement in replacements {
            output += text[cursor..<replacement.range.lowerBound]
            output += replacement.text
            cursor = replacement.range.upperBound
        }
        output += text[cursor...]
        return output
    }
}
