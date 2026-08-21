import CryptoKit
import Foundation
import VoxHearthCore

private struct Fixture: Decodable {
    let id: String
    let transcript: String
    let expectedDirective: String?
    let expectedFormat: String
    let expectedExact: String?
    let mustContain: [String]
    let mustNotContain: [String]
    let requireLineBreak: Bool
    let expectedDisposition: String
    let expectedFallbackReason: String?
}

private struct Corpus: Decodable {
    let schemaVersion: Int
    let fixtures: [Fixture]
}

private struct FixtureResult: Encodable {
    let id: String
    let passed: Bool
    let directive: String?
    let format: String
    let disposition: String
    let fallbackReason: String?
    let outputSHA256: String
    let outputBytes: Int
    let latencyMilliseconds: Double
}

private struct Percentiles: Encodable {
    let p50: Double
    let p95: Double
    let p99: Double
    let maximum: Double
}

private struct Report: Encodable {
    let schemaVersion: Int
    let backend: String
    let modelSHA256: String
    let modelBytes: Int
    let fixtureCount: Int
    let passedFixtureCount: Int
    let deterministicRepeat: Bool
    let fixtureDigest: String
    let resultDigest: String
    let latenciesMilliseconds: Percentiles
    let repeatCount: Int
    let counters: Counters
    let fixtures: [FixtureResult]
}

private struct Counters: Encodable {
    let modelLoads: Int
    let contextCreations: Int
    let warmups: Int
    let generations: Int
    let failures: Int
}

private struct Configuration {
    let backend: LlamaBackend
    let modelURL: URL
    let fixturesURL: URL
    let repeats: Int
    let intervalMilliseconds: Int
}

@main
private enum S1MiniEvaluator {
    static func main() async {
        do {
            let configuration = try parseArguments()
            let report = try await run(configuration)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
            guard report.passedFixtureCount == report.fixtureCount,
                  report.deterministicRepeat else {
                exit(2)
            }
        } catch {
            FileHandle.standardError.write(Data("s1-mini evaluator failed\n".utf8))
            exit(1)
        }
    }

    private static func run(_ configuration: Configuration) async throws -> Report {
        let modelValues = try configuration.modelURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard modelValues.isRegularFile == true,
              modelValues.isSymbolicLink != true,
              modelValues.fileSize == S1MiniModelAsset.byteCount else {
            throw EvaluationError.invalidModel
        }
        let modelDigest = try sha256(file: configuration.modelURL)
        guard modelDigest == S1MiniModelAsset.sha256 else {
            throw EvaluationError.invalidModel
        }

        let fixtureData = try Data(contentsOf: configuration.fixturesURL)
        let corpus = try JSONDecoder().decode(Corpus.self, from: fixtureData)
        guard corpus.schemaVersion == 1,
              !corpus.fixtures.isEmpty,
              Set(corpus.fixtures.map(\.id)).count == corpus.fixtures.count else {
            throw EvaluationError.invalidFixtures
        }

        let normalizer = S1MiniNormalizer()
        let selection = LlamaBackendSelection(capabilities: .init(
            hasMetalDevice: configuration.backend == .metal,
            hasSealedMetalLibrary: configuration.backend == .metal
        ))
        let loadedBackend = try await normalizer.prepare(
            modelURL: configuration.modelURL,
            selection: selection,
            warmUp: true
        )
        guard loadedBackend == configuration.backend else {
            throw EvaluationError.backendMismatch
        }

        let settings = CleanupSettings()
        var results: [FixtureResult] = []
        var resultIdentities: [String] = []
        var latencies: [Double] = []
        for fixture in corpus.fixtures {
            let measured = await evaluate(
                fixture,
                normalizer: normalizer,
                settings: settings
            )
            results.append(measured.result)
            resultIdentities.append(measured.identity)
            latencies.append(measured.result.latencyMilliseconds)
        }

        var repeatIdentities: [String] = []
        let workload = corpus.fixtures[0]
        for index in 0..<configuration.repeats {
            if index > 0, configuration.intervalMilliseconds > 0 {
                try await Task.sleep(for: .milliseconds(configuration.intervalMilliseconds))
            }
            let measured = await evaluate(
                workload,
                normalizer: normalizer,
                settings: settings
            )
            repeatIdentities.append(measured.identity)
            latencies.append(measured.result.latencyMilliseconds)
        }

        let counters = await normalizer.resourceCounters()
        await normalizer.unload()
        let sorted = latencies.sorted()
        let resultDigest = sha256(Data(resultIdentities.joined(separator: "\n").utf8))
        return Report(
            schemaVersion: 1,
            backend: configuration.backend.rawValue,
            modelSHA256: modelDigest,
            modelBytes: modelValues.fileSize ?? 0,
            fixtureCount: results.count,
            passedFixtureCount: results.filter(\.passed).count,
            deterministicRepeat: Set(repeatIdentities).count == 1,
            fixtureDigest: sha256(fixtureData),
            resultDigest: resultDigest,
            latenciesMilliseconds: Percentiles(
                p50: percentile(sorted, 0.50),
                p95: percentile(sorted, 0.95),
                p99: percentile(sorted, 0.99),
                maximum: sorted.last ?? 0
            ),
            repeatCount: configuration.repeats,
            counters: Counters(
                modelLoads: counters.modelLoads,
                contextCreations: counters.contextCreations,
                warmups: counters.warmups,
                generations: counters.generations,
                failures: counters.failures
            ),
            fixtures: results
        )
    }

    private static func evaluate(
        _ fixture: Fixture,
        normalizer: S1MiniNormalizer,
        settings: CleanupSettings
    ) async -> (result: FixtureResult, identity: String) {
        let final = FinalTranscript(sessionID: DictationSessionID(), text: fixture.transcript)
        let parse = CleanupDirectiveParser().parse(
            final,
            listEnabled: settings.listDirectiveEnabled,
            emailEnabled: settings.emailDirectiveEnabled
        )
        let started = ContinuousClock.now
        let outcome = await normalizer.normalize(
            NormalizationInput(parse: parse),
            settings: settings,
            deadlineMilliseconds: 3_000
        )
        let latency = milliseconds(started.duration(to: .now))

        let output: String
        let disposition: String
        let fallbackReason: String?
        switch outcome {
        case let .insert(transcript):
            output = transcript.text
            disposition = transcript.origin == .cleaned ? "cleaned" : "inserted"
            fallbackReason = nil
        case let .recover(transcript, reason):
            output = transcript.text
            disposition = "fallback"
            fallbackReason = reason.rawValue
        case .cancelled:
            output = ""
            disposition = "cancelled"
            fallbackReason = CleanupFallbackReason.cancelled.rawValue
        }

        let lowered = output.lowercased()
        let exactPass = fixture.expectedExact.map { output == $0 } ?? true
        let containsPass = fixture.mustContain.allSatisfy { lowered.contains($0.lowercased()) }
        let excludesPass = fixture.mustNotContain.allSatisfy { !lowered.contains($0.lowercased()) }
        let lineBreakPass = !fixture.requireLineBreak || output.contains("\n")
        let passed = parse.directive?.rawValue == fixture.expectedDirective
            && parse.format.rawValue == fixture.expectedFormat
            && disposition == fixture.expectedDisposition
            && fallbackReason == fixture.expectedFallbackReason
            && exactPass
            && containsPass
            && excludesPass
            && lineBreakPass
        let outputDigest = sha256(Data(output.utf8))
        let identity = [fixture.id, disposition, fallbackReason ?? "", outputDigest].joined(separator: ":")
        return (
            FixtureResult(
                id: fixture.id,
                passed: passed,
                directive: parse.directive?.rawValue,
                format: parse.format.rawValue,
                disposition: disposition,
                fallbackReason: fallbackReason,
                outputSHA256: outputDigest,
                outputBytes: output.utf8.count,
                latencyMilliseconds: latency
            ),
            identity
        )
    }

    private static func parseArguments() throws -> Configuration {
        var arguments = Array(CommandLine.arguments.dropFirst())
        func take(_ name: String) throws -> String {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
                throw EvaluationError.invalidArguments
            }
            let value = arguments[index + 1]
            arguments.removeSubrange(index...index + 1)
            return value
        }
        guard let backend = LlamaBackend(rawValue: try take("--backend")),
              let repeats = Int(try take("--repeats")), repeats > 0,
              let interval = Int(try take("--interval-ms")), interval >= 0 else {
            throw EvaluationError.invalidArguments
        }
        let modelURL = URL(fileURLWithPath: try take("--model")).standardizedFileURL
        let fixturesURL = URL(fileURLWithPath: try take("--fixtures")).standardizedFileURL
        guard arguments.isEmpty else { throw EvaluationError.invalidArguments }
        return Configuration(
            backend: backend,
            modelURL: modelURL,
            fixturesURL: fixturesURL,
            repeats: repeats,
            intervalMilliseconds: interval
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * fraction).rounded(.up))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    private static func sha256(file url: URL) throws -> String {
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

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum EvaluationError: Error {
    case invalidArguments
    case invalidFixtures
    case invalidModel
    case backendMismatch
}
