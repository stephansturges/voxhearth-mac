import Foundation
import Testing
@testable import VoxHearthCore

private let parser = CleanupDirectiveParser()

private func parsed(
    _ text: String,
    listEnabled: Bool = true,
    emailEnabled: Bool = true
) -> DirectiveParse {
    parser.parse(
        FinalTranscript(
            sessionID: DictationSessionID(
                rawValue: UUID(uuidString: "37C729B5-09D3-4666-9E30-A44BFE730497")!
            ),
            text: text
        ),
        listEnabled: listEnabled,
        emailEnabled: emailEnabled
    )
}

@Test(arguments: [
    ("list milk eggs bread", RecognizedDirective.list, "milk eggs bread"),
    (" LIST: milk eggs bread", .list, "milk eggs bread"),
    ("list, milk eggs bread", .list, "milk eggs bread"),
    ("List. Batteries and water.", .list, "Batteries and water."),
    ("email, Hi John", .email, "Hi John"),
    ("EMAIL   Hi John", .email, "Hi John"),
])
func recognizesOnlyFrozenLeadingDirectiveForms(
    example: (String, RecognizedDirective, String)
) {
    let result = parsed(example.0)
    #expect(result.directive == example.1)
    #expect(String(result.effectiveText) == example.2)
    #expect(result.format == (example.1 == .list ? .listGeneral : .proseEmail))
}

@Test(arguments: [
    "listing the options",
    "listening to Michael",
    "emailing John today",
    "my email is example at test dot com",
    "the list Michael sent",
    "in reference to the list Michael sent",
    "uh list milk eggs bread",
    "list",
    "email   ",
    "list:items",
    "list,milk",
    "list.. milk",
    "\u{FEFF}list milk",
    "\u{200B}list milk",
    "\"list milk",
    ".list milk",
    "lіst milk",
])
func rejectsNearMissesWithoutTransformingPayload(text: String) {
    let result = parsed(text)
    #expect(result.directive == nil)
    #expect(result.format == .proseGeneral)
    #expect(String(result.effectiveText) == text)
    #expect(result.payloadUTF8Offset == 0)
}

@Test func disabledDirectiveRemainsOrdinaryContent() {
    let list = parsed("list milk eggs bread", listEnabled: false)
    let email = parsed("email Hi John", emailEnabled: false)
    #expect(list.directive == nil)
    #expect(String(list.effectiveText) == "list milk eggs bread")
    #expect(email.directive == nil)
    #expect(String(email.effectiveText) == "email Hi John")
}

@Test func parserUsesOnlyTheFirstWord() {
    let list = parsed("list email John about the meeting")
    let email = parsed("email list milk eggs and bread")
    #expect(list.directive == .list)
    #expect(String(list.effectiveText) == "email John about the meeting")
    #expect(email.directive == .email)
    #expect(String(email.effectiveText) == "list milk eggs and bread")
}

@Test func parserCostIsBoundedByThePrefixForMaximumSizeInput() {
    let tail = String(repeating: " ordinary transcript text", count: 50_000)
    let transcript = "opening words" + tail + " list this later mention is not a command"
    let started = ContinuousClock.now
    let result = parsed(transcript)
    let elapsed = started.duration(to: .now)
    #expect(result.directive == nil)
    #expect(result.payloadUTF8Offset == 0)
    #expect(result.effectiveText.utf8.count == transcript.utf8.count)
    #expect(elapsed < .milliseconds(50))
}

@Test func UTF8OffsetIsValidAfterUnicodeWhitespace() {
    let result = parsed("\u{2003}\u{00A0}LIST. crème brûlée")
    #expect(result.directive == .list)
    #expect(String(result.effectiveText) == "crème brûlée")
    #expect(result.payloadUTF8Offset > 8)
}

private struct ASRCorpus: Decodable {
    struct Model: Decodable {
        struct Result: Decodable {
            let directive: String?
            let transcript: String
        }
        let results: [Result]
    }
    let models: [Model]
}

private func corpus(_ name: String) throws -> ASRCorpus {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(ASRCorpus.self, from: Data(contentsOf: url))
}

@Test func pinnedParakeetDirectiveCorpusMatchesFrozenGrammar() throws {
    let fixture = try corpus("directive-asr-results")
    #expect(fixture.models.count == 2)
    for model in fixture.models {
        #expect(model.results.count == 20)
        for result in model.results {
            let parse = parsed(result.transcript)
            #expect(parse.directive?.rawValue == result.directive)
            #expect(!parse.effectiveText.isEmpty)
        }
    }
}

@Test func pinnedParakeetNearMissCorpusNeverTriggers() throws {
    let fixture = try corpus("directive-asr-near-miss-results")
    #expect(fixture.models.count == 2)
    for model in fixture.models {
        #expect(model.results.count == 20)
        for result in model.results {
            let parse = parsed(result.transcript)
            #expect(parse.directive == nil)
            #expect(String(parse.effectiveText) == result.transcript)
        }
    }
}
