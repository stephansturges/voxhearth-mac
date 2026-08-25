import Foundation
import Testing
@testable import VoxHearthCore

private struct WordTokenCounter: CleanupTokenCounting {
    func tokenCount(for text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

private func normalizationInput(
    _ text: String,
    listEnabled: Bool = true,
    emailEnabled: Bool = true
) -> NormalizationInput {
    let final = FinalTranscript(sessionID: DictationSessionID(), text: text)
    return NormalizationInput(
        parse: CleanupDirectiveParser().parse(
            final,
            listEnabled: listEnabled,
            emailEnabled: emailEnabled
        )
    )
}

@Test func fallbackAlwaysStripsARecognizedCommand() {
    let input = normalizationInput("list apples oranges pears")
    for reason in CleanupFallbackReason.allCasesForTesting {
        let fallback = CleanupPolicy().fallback(for: input, reason: reason)
        #expect(fallback.text == "apples oranges pears")
        #expect(fallback.sessionID == input.sessionID)
        #expect(fallback.origin == .directiveStrippedFallback(reason))
    }
}

@Test func ordinaryFallbackPreservesOriginalBytes() {
    let text = "  In reference to the list Michael sent…\n"
    let input = normalizationInput(text)
    let fallback = CleanupPolicy().fallback(for: input, reason: .deadline)
    #expect(fallback.text == text)
    #expect(fallback.origin == .original)
}

@Test func structuredInputAboveConservativeCapMakesZeroPassPlan() throws {
    let policy = CleanupPolicy(limits: .init(contextTokens: 2_048, safeSinglePassInputTokens: 5))
    let input = normalizationInput("list one two three four five six")
    let plan = try policy.plan(input: input, promptTokenCount: 10, tokenCounter: WordTokenCounter())
    #expect(plan == .fallback(.inputTooLong))
}

@Test func proseChunksOnlyAtSentenceBoundaries() throws {
    let policy = CleanupPolicy(limits: .init(contextTokens: 2_048, safeSinglePassInputTokens: 4))
    let input = normalizationInput("One two three. Four five six. Seven eight.")
    let plan = try policy.plan(input: input, promptTokenCount: 10, tokenCounter: WordTokenCounter())
    guard case let .chunks(chunks) = plan else {
        Issue.record("expected a chunked plan")
        return
    }
    #expect(chunks.map(\.text) == ["One two three.", "Four five six.", "Seven eight."])
    #expect(chunks.map(\.separatorBefore) == ["", " ", " "])
    #expect(chunks.allSatisfy { $0.budget.inputTokens <= 4 })
}

@Test func proseChunkPlanPreservesParagraphSeparators() throws {
    let policy = CleanupPolicy(limits: .init(contextTokens: 2_048, safeSinglePassInputTokens: 3))
    let input = normalizationInput("One two.\n\nThree four.")
    let plan = try policy.plan(input: input, promptTokenCount: 10, tokenCounter: WordTokenCounter())
    guard case let .chunks(chunks) = plan else {
        Issue.record("expected paragraph chunks")
        return
    }
    #expect(chunks.map(\.text) == ["One two.", "Three four."])
    #expect(chunks.map(\.separatorBefore) == ["", "\n\n"])
}

@Test func proseWithoutSafeBoundaryFallsBack() throws {
    let policy = CleanupPolicy(limits: .init(contextTokens: 2_048, safeSinglePassInputTokens: 3))
    let input = normalizationInput("one two three four five")
    #expect(try policy.plan(input: input, promptTokenCount: 10, tokenCounter: WordTokenCounter()) == .fallback(.inputTooLong))
}

@Test func insufficientFormatHeadroomFallsBackBeforeGeneration() throws {
    let policy = CleanupPolicy(limits: .init(contextTokens: 140, safeSinglePassInputTokens: 42))
    let input = normalizationInput("email Hi John")
    #expect(try policy.plan(input: input, promptTokenCount: 12, tokenCounter: WordTokenCounter()) == .fallback(.inputTooLong))
}

@Test(arguments: [CleanupFormat.proseGeneral, .listGeneral, .proseEmail])
func documentedBudgetUsesFormatFloor(format: CleanupFormat) throws {
    let directive = format == .listGeneral ? "list " : format == .proseEmail ? "email " : ""
    let input = normalizationInput(directive + "one two three")
    let plan = try CleanupPolicy().plan(
        input: input,
        promptTokenCount: 20,
        tokenCounter: WordTokenCounter()
    )
    guard case let .singlePass(chunk) = plan else {
        Issue.record("expected one pass")
        return
    }
    #expect(chunk.budget.maximumNewTokens >= format.minimumOutputTokens)
}

@Test func validationRequiresEOGAndRejectsContractLeakage() {
    let input = normalizationInput("send the report Thursday")
    let budget = CleanupTokenBudget(inputTokens: 4, maximumNewTokens: 64)
    let policy = CleanupPolicy()
    #expect(policy.validate(.init(text: "Send the report Thursday.", outputTokens: 5, reachedEndOfGeneration: false), for: input, budget: budget) == .fallback(.truncated))
    #expect(policy.validate(.init(text: "<think>hidden</think>", outputTokens: 5, reachedEndOfGeneration: true), for: input, budget: budget) == .fallback(.invalidOutput))
    #expect(policy.validate(.init(text: "[Styling: formal] leaked", outputTokens: 5, reachedEndOfGeneration: true), for: input, budget: budget) == .fallback(.invalidOutput))
}

@Test func validationRejectsForbiddenScalarsAndRunawayRepetition() {
    let input = normalizationInput("hello there")
    let budget = CleanupTokenBudget(inputTokens: 2, maximumNewTokens: 100)
    let policy = CleanupPolicy()
    #expect(policy.validate(.init(text: "hello\rthere", outputTokens: 2, reachedEndOfGeneration: true), for: input, budget: budget) == .fallback(.invalidOutput))
    let repeated = Array(repeating: "alpha beta gamma", count: 4).joined(separator: " ")
    #expect(policy.validate(.init(text: repeated, outputTokens: 12, reachedEndOfGeneration: true), for: input, budget: budget) == .fallback(.invalidOutput))
}

@Test func validationPreservesProtectedSpansAndAllowsTraceableAddresses() {
    let policy = CleanupPolicy()
    let budget = CleanupTokenBudget(inputTokens: 20, maximumNewTokens: 100)
    let literal = normalizationInput("visit https://example.com and use `alpha-beta`")
    #expect(policy.validate(.init(text: "Visit the site.", outputTokens: 4, reachedEndOfGeneration: true), for: literal, budget: budget) == .fallback(.invalidOutput))

    let spoken = normalizationInput("email Stephen at example dot com about the report")
    #expect(policy.validate(.init(text: "Email stephen@example.com about the report.", outputTokens: 8, reachedEndOfGeneration: true), for: spoken, budget: budget) == .accepted("Email stephen@example.com about the report."))
    #expect(policy.validate(.init(text: "Email invented@example.com.", outputTokens: 4, reachedEndOfGeneration: true), for: spoken, budget: budget) == .fallback(.invalidOutput))
}

@Test func onlyDeterministicFillerMayNormalizeToEmpty() {
    let policy = CleanupPolicy()
    let budget = CleanupTokenBudget(inputTokens: 3, maximumNewTokens: 64)
    #expect(policy.validate(.init(text: "", outputTokens: 0, reachedEndOfGeneration: true), for: normalizationInput("um uh erm"), budget: budget) == .accepted(""))
    #expect(policy.validate(.init(text: "", outputTokens: 0, reachedEndOfGeneration: true), for: normalizationInput("please send it"), budget: budget) == .fallback(.invalidOutput))
}

@Test func extractedTextSafetyPredicatePreservesEveryValidationCheck() {
    let policy = CleanupPolicy()
    #expect(policy.outputTextIsSafe("Send the report.", source: "send the report"))
    #expect(!policy.outputTextIsSafe("hello\rthere", source: "hello there"))
    #expect(!policy.outputTextIsSafe("<think>hidden</think>", source: "hidden"))
    #expect(!policy.outputTextIsSafe(String(repeating: "x", count: 300), source: "x"))
    let repeated = Array(repeating: "alpha beta gamma", count: 4).joined(separator: " ")
    #expect(!policy.outputTextIsSafe(repeated, source: "alpha beta gamma"))
    #expect(!policy.outputTextIsSafe("Visit the site.", source: "visit https://example.com"))
}

private extension CleanupFallbackReason {
    static let allCasesForTesting: [CleanupFallbackReason] = [
        .cancelled, .deadline, .inputTooLong, .modelUnavailable,
        .backendUnavailable, .generationFailed, .invalidOutput, .truncated,
    ]
}
