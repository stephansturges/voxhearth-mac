import Foundation

public protocol CleanupTokenCounting: Sendable {
    func tokenCount(for text: String) throws -> Int
}

public struct CleanupPolicy: Sendable {
    public struct Limits: Equatable, Sendable {
        public let contextTokens: Int
        public let safeSinglePassInputTokens: Int

        public init(contextTokens: Int = 2_048, safeSinglePassInputTokens: Int = 42) {
            precondition(contextTokens > 0)
            precondition(safeSinglePassInputTokens > 0)
            self.contextTokens = contextTokens
            self.safeSinglePassInputTokens = safeSinglePassInputTokens
        }
    }

    public let limits: Limits

    public init(limits: Limits = Limits()) {
        self.limits = limits
    }

    func passthrough(_ transcript: FinalTranscript) -> InsertableTranscript {
        InsertableTranscript(
            sessionID: transcript.sessionID,
            text: transcript.text,
            origin: .original
        )
    }

    public func fallback(
        for input: NormalizationInput,
        reason: CleanupFallbackReason
    ) -> InsertableTranscript {
        let origin: InsertableTranscript.Origin = input.parse.directive == nil
            ? .original
            : .directiveStrippedFallback(reason)
        return InsertableTranscript(
            sessionID: input.sessionID,
            text: String(input.text),
            origin: origin
        )
    }

    public func cleaned(
        for input: NormalizationInput,
        text: String
    ) -> InsertableTranscript {
        InsertableTranscript(sessionID: input.sessionID, text: text, origin: .cleaned)
    }

    public func plan(
        input: NormalizationInput,
        promptTokenCount: Int,
        tokenCounter: any CleanupTokenCounting
    ) throws -> CleanupExecutionPlan {
        let text = String(input.text)
        let inputTokens = try tokenCounter.tokenCount(for: text)
        guard inputTokens > 0 else { return .fallback(.inputTooLong) }

        if inputTokens <= limits.safeSinglePassInputTokens {
            guard let budget = budget(
                inputTokens: inputTokens,
                promptTokenCount: promptTokenCount,
                format: input.format
            ) else {
                return .fallback(.inputTooLong)
            }
            return .singlePass(NormalizationChunk(text: text, budget: budget))
        }

        guard input.format == .proseGeneral else {
            return .fallback(.inputTooLong)
        }
        guard let sentences = sentenceSegments(text), sentences.count > 1 else {
            return .fallback(.inputTooLong)
        }

        var chunks: [NormalizationChunk] = []
        var current = ""
        var currentSeparatorBefore = ""
        for sentence in sentences {
            let candidate = current.isEmpty
                ? sentence.text
                : current + sentence.separatorBefore + sentence.text
            let candidateTokens = try tokenCounter.tokenCount(for: candidate)
            if candidateTokens <= limits.safeSinglePassInputTokens {
                current = candidate
                continue
            }

            guard !current.isEmpty else { return .fallback(.inputTooLong) }
            let currentTokens = try tokenCounter.tokenCount(for: current)
            guard let currentBudget = budget(
                inputTokens: currentTokens,
                promptTokenCount: promptTokenCount,
                format: .proseGeneral
            ) else {
                return .fallback(.inputTooLong)
            }
            chunks.append(NormalizationChunk(
                text: current,
                budget: currentBudget,
                separatorBefore: currentSeparatorBefore
            ))
            current = sentence.text
            currentSeparatorBefore = sentence.separatorBefore
            guard try tokenCounter.tokenCount(for: current) <= limits.safeSinglePassInputTokens else {
                return .fallback(.inputTooLong)
            }
        }

        if !current.isEmpty {
            let currentTokens = try tokenCounter.tokenCount(for: current)
            guard let currentBudget = budget(
                inputTokens: currentTokens,
                promptTokenCount: promptTokenCount,
                format: .proseGeneral
            ) else {
                return .fallback(.inputTooLong)
            }
            chunks.append(NormalizationChunk(
                text: current,
                budget: currentBudget,
                separatorBefore: currentSeparatorBefore
            ))
        }
        return chunks.count > 1 ? .chunks(chunks) : .fallback(.inputTooLong)
    }

    public func validate(
        _ generation: CleanupGenerationResult,
        for input: NormalizationInput,
        budget: CleanupTokenBudget
    ) -> CleanupValidationResult {
        guard generation.reachedEndOfGeneration else { return .fallback(.truncated) }
        guard generation.outputTokens <= budget.maximumNewTokens else { return .fallback(.truncated) }

        let output = generation.text
        let source = String(input.text)
        if output.isEmpty {
            return isFillerOnly(source) ? .accepted(output) : .fallback(.invalidOutput)
        }
        guard outputTextIsSafe(output, source: source) else { return .fallback(.invalidOutput) }
        return .accepted(output)
    }

    func outputTextIsSafe(_ output: String, source: String) -> Bool {
        guard output.unicodeScalars.allSatisfy(isAllowedOutputScalar) else { return false }
        guard !containsContractLeak(output) else { return false }
        guard output.utf8.count <= max(source.utf8.count * 4, source.utf8.count + 256) else {
            return false
        }
        guard !hasUngroundedRepetition(output) else { return false }
        return protectedContentIsGrounded(source: source, output: output)
    }

    private func budget(
        inputTokens: Int,
        promptTokenCount: Int,
        format: CleanupFormat
    ) -> CleanupTokenBudget? {
        let remaining = limits.contextTokens - promptTokenCount - inputTokens
        guard remaining >= format.minimumOutputTokens else { return nil }
        let documentedCeiling = (13 * inputTokens + 9) / 10 + 32
        let maximum = min(
            remaining,
            max(documentedCeiling, format.minimumOutputTokens)
        )
        guard maximum >= format.minimumOutputTokens else { return nil }
        return CleanupTokenBudget(inputTokens: inputTokens, maximumNewTokens: maximum)
    }

    private struct SentenceSegment {
        let text: String
        let separatorBefore: String
    }

    private func sentenceSegments(_ text: String) -> [SentenceSegment]? {
        var result: [SentenceSegment] = []
        var start = text.startIndex
        var index = text.startIndex
        var separatorBefore = ""
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if (character == "." || character == "?" || character == "!"),
               next == text.endIndex || text[next].isWhitespace {
                let sentence = String(text[start..<next])
                if !sentence.isEmpty {
                    result.append(SentenceSegment(
                        text: sentence,
                        separatorBefore: separatorBefore
                    ))
                }
                index = next
                while index < text.endIndex, text[index].isWhitespace {
                    index = text.index(after: index)
                }
                separatorBefore = String(text[next..<index])
                start = index
                continue
            }
            index = next
        }
        if start < text.endIndex {
            let tail = String(text[start...])
            if !tail.isEmpty {
                result.append(SentenceSegment(
                    text: tail,
                    separatorBefore: separatorBefore
                ))
            }
        }
        return result.isEmpty ? nil : result
    }

    private func isAllowedOutputScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\t" || scalar == "\n" { return true }
        if scalar.value < 0x20 { return false }
        if scalar.value == 0x7F
            || scalar.value == 0x85
            || scalar.value == 0x2028
            || scalar.value == 0x2029
            || scalar.value == 0xFFFD {
            return false
        }
        return true
    }

    private func containsContractLeak(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("<|im_start|>")
            || lowered.contains("<|im_end|>")
            || lowered.contains("<think>")
            || lowered.contains("</think>")
            || lowered.contains("[styling:")
            || lowered.contains("[structure:")
            || lowered.contains("[context:")
            || lowered.contains("you are a text normalizer for speech-to-text transcripts")
    }

    private func isFillerOnly(_ input: String) -> Bool {
        let fillers: Set<String> = ["ah", "er", "erm", "hmm", "mhm", "uh", "um"]
        let words = input.lowercased().split { !$0.isLetter }.map(String.init)
        return !words.isEmpty && words.allSatisfy(fillers.contains)
    }

    private func hasUngroundedRepetition(_ output: String) -> Bool {
        let words = output.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.count >= 12 else { return false }
        var counts: [String: Int] = [:]
        for index in 0...(words.count - 3) {
            let key = words[index...index + 2].joined(separator: " ")
            counts[key, default: 0] += 1
            if counts[key, default: 0] >= 4 { return true }
        }
        return false
    }

    private func protectedContentIsGrounded(source: String, output: String) -> Bool {
        let sourceProtected = protectedSpans(in: source)
        guard sourceProtected.allSatisfy(output.contains) else { return false }

        let sourceCanonical = spokenAddressCanonical(source)
        for span in protectedSpans(in: output) where !source.contains(span) {
            guard sourceCanonical.contains(addressCanonical(span)) else { return false }
        }
        return true
    }

    private func protectedSpans(in text: String) -> [String] {
        var result: [String] = []
        var backtickStart: String.Index?
        for index in text.indices where text[index] == "`" {
            if let start = backtickStart {
                result.append(String(text[start...index]))
                backtickStart = nil
            } else {
                backtickStart = index
            }
        }
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let value = String(token).trimmingCharacters(in: CharacterSet(charactersIn: ",;()[]{}<>\"'"))
            if value.contains("://") || (value.contains("@") && value.contains(".")) {
                result.append(value)
            }
        }
        return result
    }

    private func spokenAddressCanonical(_ text: String) -> String {
        let substitutions = [
            "at": "@", "dot": ".", "dash": "-", "hyphen": "-",
            "underscore": "_", "slash": "/", "colon": ":",
            "zero": "0", "one": "1", "two": "2", "three": "3",
            "four": "4", "five": "5", "six": "6", "seven": "7",
            "eight": "8", "nine": "9",
        ]
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.map { substitutions[String($0)] ?? String($0) }.joined()
    }

    private func addressCanonical(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || "@./:-_".unicodeScalars.contains($0)
        }.map(String.init).joined()
    }
}
