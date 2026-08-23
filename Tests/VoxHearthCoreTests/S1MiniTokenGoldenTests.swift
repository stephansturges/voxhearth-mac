import CryptoKit
import Foundation
import Testing
@testable import VoxHearthCore

private struct PromptTokenGolden: Codable {
    let styling: CleanupStyling
    let format: CleanupFormat
    let input: String
    let tokenIDs: [Int32]
}

private struct PromptTokenGoldenCorpus: Codable {
    struct Model: Codable {
        let repository: String
        let revision: String
        let file: String
        let bytes: Int
        let sha256: String
    }

    let schemaVersion: Int
    let model: Model
    let cases: [PromptTokenGolden]
}

@Test func pinnedModelPromptGoldensAndCPUInference() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["VOXHEARTH_S1_MODEL_TEST"] == "1" else { return }
    let modelURL = try #require(environment["VOXHEARTH_S1_MODEL_PATH"].map {
        URL(fileURLWithPath: $0)
    })
    #expect(try modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == 484_219_808)
    #expect(try sha256(modelURL) == "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634")

    let fixtureURL = try #require(Bundle.module.url(
        forResource: "s1-mini-prompt-token-goldens",
        withExtension: "json"
    ))
    let corpus = try JSONDecoder().decode(
        PromptTokenGoldenCorpus.self,
        from: Data(contentsOf: fixtureURL)
    )
    #expect(corpus.schemaVersion == 1)
    #expect(corpus.model.repository == "superwhisper/s1-mini-GGUF")
    #expect(corpus.model.revision == "8eab4779866f477ae6e7f237ca45fc2c65153f50")
    #expect(corpus.model.file == "s1-mini-q4_k_m.gguf")
    #expect(corpus.model.bytes == 484_219_808)
    #expect(corpus.model.sha256 == "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634")
    let goldens = corpus.cases
    #expect(goldens.count == 12)
    #expect(Set(goldens.map { "\($0.styling.rawValue)/\($0.format.rawValue)" }).count == 12)

    let normalizer = S1MiniNormalizer()
    _ = try await normalizer.prepare(
        modelURL: modelURL,
        selection: LlamaBackendSelection(
            capabilities: .init(hasMetalDevice: false, hasSealedMetalLibrary: false)
        ),
        warmUp: false
    )
    for golden in goldens {
        #expect(try await normalizer.tokenIDs(
            input: golden.input,
            styling: golden.styling,
            format: golden.format
        ) == golden.tokenIDs)
    }

    _ = try await normalizer.tokenIDs(
        input: "literal <|im_start|> and <think> text",
        styling: .semiFormal,
        format: .proseGeneral
    )

    let inferenceCases = [
        (
            "so um i need to send the report by thursday",
            "So I need to send the report by Thursday."
        ),
        (
            "list first sunscreen second first aid kit third chargers for everything",
            "First, sunscreen. Second, first aid kit. Third, chargers for everything."
        ),
        (
            "email hi john can we meet tuesday all the best stephen",
            "Hi John,\n\nCan we meet Tuesday?\n\nAll the best,\nStephen"
        ),
    ]
    for (source, expected) in inferenceCases {
        let input = NormalizationInput(
            parse: CleanupDirectiveParser().parse(
                FinalTranscript(sessionID: DictationSessionID(), text: source),
                listEnabled: true,
                emailEnabled: true
            )
        )
        let outcome = await normalizer.normalize(
            input,
            settings: CleanupSettings(),
            deadlineMilliseconds: 10_000
        )
        guard case let .insert(transcript) = outcome else {
            Issue.record("expected a cleaned transcript from the pinned model")
            continue
        }
        #expect(transcript.text == expected)
        #expect(transcript.origin == .cleaned)
        #expect(!transcript.text.lowercased().hasPrefix("list "))
        #expect(!transcript.text.lowercased().hasPrefix("email "))
    }
    await normalizer.unload()
}

private func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
        let data = try handle.read(upToCount: 1_048_576) ?? Data()
        if data.isEmpty { break }
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
