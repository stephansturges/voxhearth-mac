import Foundation
import Testing
@testable import VoxHearthCore

private struct CanonicalizationCase: Sendable {
    let input: String
    let expected: String
}

private func canonicalize(_ text: String) -> CleanupCanonicalizationResult {
    SpokenNumberCanonicalizer().canonicalize(text)
}

@Test(arguments: [
    CanonicalizationCase(input: "eleven", expected: "11"),
    CanonicalizationCase(input: "Twelve people attended.", expected: "12 people attended."),
    CanonicalizationCase(input: "one hundred and five boxes", expected: "105 boxes"),
    CanonicalizationCase(input: "seven thousand and twelve dollars", expected: "7012$"),
    CanonicalizationCase(input: "one hundred and five euros", expected: "105€"),
    CanonicalizationCase(input: "nine hundred yen", expected: "900¥"),
    CanonicalizationCase(input: "seven thousand pounds", expected: "7000 pounds"),
    CanonicalizationCase(
        input: "I need twelve apples and fifteen pears.",
        expected: "I need 12 apples and 15 pears."
    ),
    CanonicalizationCase(input: "twenty-four items", expected: "24 items"),
    CanonicalizationCase(input: "one trillion", expected: "1000000000000"),
])
private func safeSpokenIntegersAreCanonicalized(testCase: CanonicalizationCase) {
    let result = canonicalize(testCase.input)
    #expect(result.text == testCase.expected)
    #expect(result.isOperational)
}

@Test(arguments: [
    CanonicalizationCase(input: "1,200", expected: "1200"),
    CanonicalizationCase(input: "$7,012", expected: "7012$"),
    CanonicalizationCase(input: "€1,200", expected: "1200€"),
    CanonicalizationCase(input: "1,200 euros", expected: "1200€"),
    CanonicalizationCase(input: "1200 dollars", expected: "1200$"),
    CanonicalizationCase(input: "1,200€", expected: "1200€"),
    CanonicalizationCase(input: "1,200 yen", expected: "1200¥"),
    CanonicalizationCase(input: "1,200 pounds", expected: "1200 pounds"),
])
private func narrowExistingNumericFormsAreRestyled(testCase: CanonicalizationCase) {
    let result = canonicalize(testCase.input)
    #expect(result.text == testCase.expected)
    #expect(result.parseAttempts == 0)
}

@Test(arguments: [
    "zero", "one", "ten", "eleventy", "one two three", "twenty twenty-four",
    "twelve point five", "12.5", "August twenty fifth", "twenty-first",
    "negative forty-two", "minus forty-two", "five five five one two one two",
    "one hundred dollars and five cents", "one hundred dollars and 5 cents",
    "fifty dollars, and twenty five cents", "fifty dollars\nand fifty cents",
    "twelve and a half", "twelve dollars and a half", "twelve and one quarter",
    "$7,012.50", "$1,20 dollars", "1,20", "01,200", "1,200th", "v1,200", "-1,200", "+1,200",
    "2024", "twelve-B", "Section twelve-B", "twelve_percent", "twelve percent",
    "version twelve", "room twelve", "one hundred Main Street", "twelve Elm Tree Road",
    "the year is two thousand twenty-four",
    "Model 1,200", "Route 1,200", "In 1,999",
    "one trillion one", "hundred", "and", "",
])
func ambiguousAndUnsupportedFormsAreByteIdentical(input: String) {
    #expect(canonicalize(input).text == input)
}

@Test func protectedContentIsByteIdentical() {
    let values = [
        "Use `seven thousand and twelve` here.",
        "``seven thousand and twelve`` and fifteen",
        "```\nseven thousand and twelve\n``` and fifteen",
        "An unmatched `seven thousand and twelve and fifteen",
        "Visit https://example.com/seven-thousand and twelve.",
        "Email twelve.thousand@example.com and fifteen people.",
    ]
    let expected = [
        "Use `seven thousand and twelve` here.",
        "``seven thousand and twelve`` and 15",
        "```\nseven thousand and twelve\n``` and 15",
        "An unmatched `seven thousand and twelve and fifteen",
        "Visit https://example.com/seven-thousand and 12.",
        "Email twelve.thousand@example.com and 15 people.",
    ]
    for (input, output) in zip(values, expected) {
        #expect(canonicalize(input).text == output)
    }
}

@Test func parseAttemptsAreDeterministicallyBounded() {
    let noNumber = canonicalize("This ordinary sentence has no candidate words.")
    #expect(noNumber.parseAttempts == 0)

    let four = canonicalize("eleven cats. twelve dogs. thirteen birds. fourteen fish.")
    #expect(four.text == "11 cats. 12 dogs. 13 birds. 14 fish.")
    #expect(four.parseAttempts == 4)

    let fiveInput = "eleven cats. twelve dogs. thirteen birds. fourteen fish. fifteen mice."
    let five = canonicalize(fiveInput)
    #expect(five.text == fiveInput)
    #expect(five.parseAttempts == 0)
}

@Test func layoutAndLengthInvariantsHold() {
    let input = "- twelve apples\n- fifteen pears\n\nTotal: twenty-seven items"
    let result = canonicalize(input).text
    #expect(result == "- 12 apples\n- 15 pears\n\nTotal: 27 items")
    #expect(result.filter { $0 == "\n" }.count == input.filter { $0 == "\n" }.count)
    #expect(result.utf8.count <= input.utf8.count)
}

@Test func groupedNumberBeforePunctuationIsNormalizedWithoutEatingPunctuation() {
    let input = "The total was 1,200, approximately."
    #expect(canonicalize(input).text == "The total was 1200, approximately.")
}

@Test func canonicalizationIsIdempotentAndRepeatable() {
    let input = "The invoice is seven thousand and twelve dollars and one hundred euros."
    let canonicalizer = SpokenNumberCanonicalizer()
    let first = canonicalizer.canonicalize(input).text
    #expect(first == "The invoice is 7012$ and 100€.")
    #expect(canonicalizer.canonicalize(first).text == first)
    for _ in 0..<100 {
        #expect(canonicalizer.canonicalize(input).text == first)
    }
}

@Test(arguments: [
    CanonicalizationCase(
        input: "The invoice total is $7,12.",
        expected: "The invoice total is 7012$."
    ),
    CanonicalizationCase(
        input: "We counted 115 boxes.",
        expected: "We counted 105 boxes."
    ),
])
private func singleModelDigitDriftIsReconciledFromSpokenSource(testCase: CanonicalizationCase) {
    let sources = [
        "the invoice total is seven thousand and twelve dollars",
        "we counted one hundred and five boxes",
    ]
    let source = testCase.input.contains("invoice") ? sources[0] : sources[1]
    let result = SpokenNumberCanonicalizer().canonicalize(testCase.input, source: source)
    #expect(result.text == testCase.expected)
    #expect(result.parseAttempts == 1)
}

@Test func sourceAnchoringFailsClosedForAmbiguousShapes() {
    let canonicalizer = SpokenNumberCanonicalizer()
    let source = "we counted one hundred and five boxes and twelve crates"
    let output = "We counted 115 boxes and 12 crates."
    #expect(canonicalizer.canonicalize(output, source: source).text == output)

    let protectedOutput = "Use `115` boxes."
    #expect(canonicalizer.canonicalize(
        protectedOutput,
        source: "use one hundred and five boxes"
    ).text == protectedOutput)

    let decimalOutput = "The invoice total is $7.12."
    #expect(canonicalizer.canonicalize(
        decimalOutput,
        source: "the invoice total is seven thousand and twelve dollars"
    ).text == decimalOutput)

    let yearOutput = "The year is 2025."
    #expect(canonicalizer.canonicalize(
        yearOutput,
        source: "the year is two thousand twenty-four"
    ).text == yearOutput)

    let identifierOutput = "Use version 13."
    #expect(canonicalizer.canonicalize(
        identifierOutput,
        source: "use version twelve"
    ).text == identifierOutput)

    let mixedSource = "we counted one hundred and five boxes in room 12"
    let mixedOutput = "We counted 115 boxes."
    #expect(canonicalizer.canonicalize(mixedOutput, source: mixedSource).text == mixedOutput)

    let guardedSlots = [
        ("The 2025 budget is ready.", "the twelve month budget is ready"),
        ("Use version 13.", "use twelve tickets"),
        ("We start at 11:45.", "we start at quarter to twelve"),
        ("We grew 25%.", "we shipped twenty units"),
        ("Order 0012 shipped.", "order twenty crates shipped"),
    ]
    for (output, source) in guardedSlots {
        #expect(canonicalizer.canonicalize(output, source: source).text == output)
    }

    let ambiguousSpokenSource = "we should ship twelve units before twenty twenty five"
    let ambiguousOutput = "We should ship 13 units before the review."
    #expect(canonicalizer.canonicalize(
        ambiguousOutput,
        source: ambiguousSpokenSource
    ).text == ambiguousOutput)

    let directSpokenOutput = "We counted thirteen boxes."
    #expect(canonicalizer.canonicalize(
        directSpokenOutput,
        source: "we counted one hundred and five boxes"
    ).text == "We counted 13 boxes.")
}

@Test func sourceAttemptCapDoesNotUndoDirectOutputRestyling() {
    let source = "eleven cats. twelve dogs. thirteen birds. fourteen fish. fifteen mice."
    let result = SpokenNumberCanonicalizer().canonicalize(
        "The budget is $7,012.",
        source: source
    )
    #expect(result.text == "The budget is 7012$.")
    #expect(result.parseAttempts == 0)
}

@Test func selfCheckFailurePermanentlyDisablesTheInstance() {
    let canonicalizer = SpokenNumberCanonicalizer(selfCheckProbes: [
        .init(input: "eleven", expected: "not eleven"),
    ])
    #expect(!canonicalizer.isOperational)
    let result = canonicalizer.canonicalize("seven thousand and twelve dollars")
    #expect(result.text == "seven thousand and twelve dollars")
    #expect(result.parseAttempts == 0)
    #expect(!result.isOperational)
}

@Test func disabledOptionIsAnIdentityFunction() {
    let canonicalizer = SpokenNumberCanonicalizer(options: .disabled)
    let input = "seven thousand and twelve dollars"
    #expect(canonicalizer.canonicalize(input).text == input)
}
