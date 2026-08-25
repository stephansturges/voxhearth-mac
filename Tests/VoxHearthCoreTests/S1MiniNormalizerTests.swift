import Dispatch
import Foundation
import Testing
@testable import VoxHearthCore

private final class RuntimeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _loads: [LlamaBackend] = []
    private var _generations = 0
    private var _unloads = 0
    private var _warmups = 0
    private var _requests: [LlamaBackend] = []

    func loaded(_ backend: LlamaBackend) { lock.withLock { _loads.append(backend) } }
    func generated() { lock.withLock { _generations += 1 } }
    func unloaded() { lock.withLock { _unloads += 1 } }
    func warmedUp() { lock.withLock { _warmups += 1 } }
    func requested(_ backend: LlamaBackend) { lock.withLock { _requests.append(backend) } }
    var loads: [LlamaBackend] { lock.withLock { _loads } }
    var generations: Int { lock.withLock { _generations } }
    var unloads: Int { lock.withLock { _unloads } }
    var warmups: Int { lock.withLock { _warmups } }
    var requests: [LlamaBackend] { lock.withLock { _requests } }
}

private final class FakeS1Session: S1MiniRuntimeSession, @unchecked Sendable {
    enum Behavior: Sendable {
        case output(String)
        case echo
        case invalidateWhenInputContains(String)
        case fail(S1MiniError, producedTokens: Int)
    }

    let backend: LlamaBackend
    private let recorder: RuntimeRecorder
    private let behavior: Behavior

    init(backend: LlamaBackend, recorder: RuntimeRecorder, behavior: Behavior) {
        self.backend = backend
        self.recorder = recorder
        self.behavior = behavior
        recorder.loaded(backend)
    }

    func unload() { recorder.unloaded() }

    func tokenCount(_ text: String, parseSpecial: Bool) -> Int {
        _ = parseSpecial
        return text.split(whereSeparator: \.isWhitespace).count
    }

    func trustedPromptTokenCount(styling: CleanupStyling, format: CleanupFormat) -> Int {
        _ = styling
        _ = format
        return 10
    }

    func promptTokens(input: String, styling: CleanupStyling, format: CleanupFormat) -> [Int32] {
        _ = styling
        _ = format
        return input.utf8.map(Int32.init)
    }

    func generate(
        input: String,
        styling: CleanupStyling,
        format: CleanupFormat,
        maximumNewTokens: Int,
        cancellation: S1MiniCancellationToken,
        deadline: DispatchTime
    ) throws -> CleanupGenerationResult {
        _ = input
        _ = styling
        _ = format
        _ = maximumNewTokens
        recorder.generated()
        if cancellation.isCancelled {
            throw LlamaGenerationFailure(error: .cancelled, producedTokens: 0)
        }
        if DispatchTime.now() >= deadline {
            throw LlamaGenerationFailure(error: .deadlineExceeded, producedTokens: 0)
        }
        switch behavior {
        case let .output(text):
            return CleanupGenerationResult(
                text: text,
                outputTokens: max(1, text.split(whereSeparator: \.isWhitespace).count),
                reachedEndOfGeneration: true
            )
        case .echo:
            return CleanupGenerationResult(
                text: input,
                outputTokens: max(1, input.split(whereSeparator: \.isWhitespace).count),
                reachedEndOfGeneration: true
            )
        case let .invalidateWhenInputContains(fragment):
            let text = input.contains(fragment) ? "<think>invalid</think>" : input
            return CleanupGenerationResult(
                text: text,
                outputTokens: max(1, text.split(whereSeparator: \.isWhitespace).count),
                reachedEndOfGeneration: true
            )
        case let .fail(error, producedTokens):
            throw LlamaGenerationFailure(error: error, producedTokens: producedTokens)
        }
    }

    func warmUp(cancellation: S1MiniCancellationToken, deadline: DispatchTime) throws {
        if cancellation.isCancelled || DispatchTime.now() >= deadline {
            throw LlamaGenerationFailure(error: .cancelled, producedTokens: 0)
        }
        recorder.warmedUp()
    }
}

private func runtimeInput(_ text: String) -> NormalizationInput {
    NormalizationInput(
        parse: CleanupDirectiveParser().parse(
            FinalTranscript(sessionID: DictationSessionID(), text: text),
            listEnabled: true,
            emailEnabled: true
        )
    )
}

private func selection(_ backend: LlamaBackend) -> LlamaBackendSelection {
    LlamaBackendSelection(
        capabilities: .init(
            hasMetalDevice: backend == .metal,
            hasSealedMetalLibrary: backend == .metal
        )
    )
}

private final class BlockingFactoryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _hasEntered = false
    let release = DispatchSemaphore(value: 0)

    var hasEntered: Bool { lock.withLock { _hasEntered } }
    func markEntered() { lock.withLock { _hasEntered = true } }
}

private final class RecordingCanonicalizer: CleanupOutputCanonicalizing, @unchecked Sendable {
    private let lock = NSLock()
    private let underlying: any CleanupOutputCanonicalizing
    private var _calls = 0

    init(_ underlying: any CleanupOutputCanonicalizing = SpokenNumberCanonicalizer()) {
        self.underlying = underlying
    }

    func canonicalize(_ text: String, source: String) -> CleanupCanonicalizationResult {
        lock.withLock { _calls += 1 }
        return underlying.canonicalize(text, source: source)
    }

    var calls: Int { lock.withLock { _calls } }
}

private final class FixedCanonicalizer: CleanupOutputCanonicalizing, @unchecked Sendable {
    let output: String

    init(output: String) {
        self.output = output
    }

    func canonicalize(_ text: String, source: String) -> CleanupCanonicalizationResult {
        CleanupCanonicalizationResult(
            text: output,
            parseAttempts: text == output ? 0 : 1,
            isOperational: true
        )
    }
}

@Test func preparationFallsBackFromMetalToCPU() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        if backend == .metal { throw S1MiniError.contextCreationFailed }
        return FakeS1Session(backend: backend, recorder: recorder, behavior: .output("Clean."))
    }
    let backend = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.metal),
        warmUp: false
    )
    #expect(backend == .cpu)
    #expect(recorder.loads == [.cpu])
    await normalizer.unload()
}

@Test func demotedCPUPreparationReusesTheResidentSession() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        if backend == .metal { throw S1MiniError.contextCreationFailed }
        return FakeS1Session(backend: backend, recorder: recorder, behavior: .output("Clean."))
    }
    let modelURL = URL(fileURLWithPath: "/tmp/fake.gguf")

    #expect(try await normalizer.prepare(
        modelURL: modelURL,
        selection: selection(.metal),
        warmUp: false
    ) == .cpu)
    #expect(try await normalizer.prepare(
        modelURL: modelURL,
        selection: selection(.metal),
        warmUp: false
    ) == .cpu)
    #expect(try await normalizer.prepare(
        modelURL: modelURL,
        selection: selection(.metal),
        warmUp: false
    ) == .cpu)
    #expect(recorder.loads == [.cpu])
    #expect(recorder.unloads == 0)
    await normalizer.unload()
}

@Test func demotedPreparationAfterUnloadRetainsTheExistingStickyPolicy() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        recorder.requested(backend)
        if backend == .metal { throw S1MiniError.contextCreationFailed }
        return FakeS1Session(backend: backend, recorder: recorder, behavior: .output("Clean."))
    }
    let modelURL = URL(fileURLWithPath: "/tmp/fake.gguf")

    #expect(try await normalizer.prepare(
        modelURL: modelURL,
        selection: selection(.metal),
        warmUp: false
    ) == .cpu)
    await normalizer.unload()
    #expect(try await normalizer.prepare(
        modelURL: modelURL,
        selection: selection(.metal),
        warmUp: false
    ) == .cpu)
    #expect(recorder.requests == [.metal, .cpu, .cpu])
    await normalizer.unload()
}

@Test func warmPreparationWarmsAnUnwarmedResidentDemotedSession() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        if backend == .metal { throw S1MiniError.contextCreationFailed }
        return FakeS1Session(backend: backend, recorder: recorder, behavior: .output("Clean."))
    }
    let modelURL = URL(fileURLWithPath: "/tmp/fake.gguf")

    #expect(try await normalizer.prepare(
        modelURL: modelURL,
        selection: selection(.metal),
        warmUp: false
    ) == .cpu)
    #expect(try await normalizer.prepare(
        modelURL: modelURL,
        selection: selection(.metal),
        warmUp: true
    ) == .cpu)
    #expect(recorder.warmups == 1)
    let counters = await normalizer.resourceCounters()
    #expect(counters.modelLoads == 1)
    #expect(counters.warmups == 1)
    await normalizer.unload()
}

@Test func completedNormalizationCancelsItsDeadlineCallback() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        FakeS1Session(backend: backend, recorder: recorder, behavior: .output("Clean."))
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let cancellation = S1MiniCancellationToken()
    _ = await normalizer.normalize(
        runtimeInput("please send it"),
        settings: CleanupSettings(),
        cancellation: cancellation,
        deadlineMilliseconds: 200
    )
    try? await Task.sleep(for: .milliseconds(400))
    #expect(!cancellation.isCancelled)
    await normalizer.unload()
}

@Test func normalizationDeadlineIncludesQueueAdmissionBehindPreparation() async throws {
    let recorder = RuntimeRecorder()
    let gate = BlockingFactoryGate()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        gate.markEntered()
        gate.release.wait()
        return FakeS1Session(backend: backend, recorder: recorder, behavior: .echo)
    }
    let preparation = Task {
        try await normalizer.prepare(
            modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
            selection: selection(.cpu),
            warmUp: false
        )
    }
    while !gate.hasEntered {
        await Task.yield()
    }

    let input = runtimeInput("please send it")
    let started = ContinuousClock.now
    let outcome = await normalizer.normalize(
        input,
        settings: CleanupSettings(),
        deadlineMilliseconds: 30
    )
    let elapsed = started.duration(to: .now)
    #expect(outcome == .recover(
        CleanupPolicy().fallback(for: input, reason: .deadline),
        .deadline
    ))
    #expect(elapsed < .milliseconds(500))

    gate.release.signal()
    _ = try await preparation.value
    await normalizer.unload()
}

@Test func recognizedDirectiveFallbackNeverReinsertsCommand() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        FakeS1Session(
            backend: backend,
            recorder: recorder,
            behavior: .output("<think>bad</think>")
        )
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let input = runtimeInput("list apples oranges pears")
    let outcome = await normalizer.normalize(input, settings: CleanupSettings())
    #expect(outcome == .recover(
        CleanupPolicy().fallback(for: input, reason: .invalidOutput),
        .invalidOutput
    ))
    await normalizer.unload()
}

@Test func structuredPreflightMakesZeroGenerationCalls() async throws {
    let recorder = RuntimeRecorder()
    let policy = CleanupPolicy(limits: .init(contextTokens: 2_048, safeSinglePassInputTokens: 3))
    let normalizer = S1MiniNormalizer(policy: policy) { _, backend in
        FakeS1Session(backend: backend, recorder: recorder, behavior: .output("Unused"))
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let input = runtimeInput("email one two three four")
    let outcome = await normalizer.normalize(input, settings: CleanupSettings())
    #expect(outcome == .recover(
        CleanupPolicy().fallback(for: input, reason: .inputTooLong),
        .inputTooLong
    ))
    #expect(recorder.generations == 0)
    await normalizer.unload()
}

@Test func proseChunkingGeneratesEveryChunkAndPreservesSeparators() async throws {
    let recorder = RuntimeRecorder()
    let policy = CleanupPolicy(limits: .init(contextTokens: 2_048, safeSinglePassInputTokens: 4))
    let normalizer = S1MiniNormalizer(policy: policy) { _, backend in
        FakeS1Session(backend: backend, recorder: recorder, behavior: .echo)
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let input = runtimeInput("First part works.\n\nSecond part works.")
    let outcome = await normalizer.normalize(input, settings: CleanupSettings())
    guard case let .insert(transcript) = outcome else {
        Issue.record("expected a joined cleaned result")
        return
    }
    #expect(transcript.text == "First part works.\n\nSecond part works.")
    #expect(recorder.generations == 2)
    await normalizer.unload()
}

@Test func proseChunkingFallsBackAsAWholeWhenAnyChunkIsInvalid() async throws {
    let recorder = RuntimeRecorder()
    let policy = CleanupPolicy(limits: .init(contextTokens: 2_048, safeSinglePassInputTokens: 4))
    let normalizer = S1MiniNormalizer(policy: policy) { _, backend in
        FakeS1Session(
            backend: backend,
            recorder: recorder,
            behavior: .invalidateWhenInputContains("Second")
        )
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let input = runtimeInput("First part works. Second part fails.")
    let outcome = await normalizer.normalize(input, settings: CleanupSettings())
    #expect(outcome == .recover(
        CleanupPolicy().fallback(for: input, reason: .invalidOutput),
        .invalidOutput
    ))
    #expect(recorder.generations == 2)
    await normalizer.unload()
}

@Test func cancellationProducesNoInsertableOutcome() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        FakeS1Session(backend: backend, recorder: recorder, behavior: .output("Clean."))
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let token = S1MiniCancellationToken()
    token.cancel()
    let input = runtimeInput("please send it")
    #expect(await normalizer.normalize(input, settings: CleanupSettings(), cancellation: token) == .cancelled(input.sessionID))
    await normalizer.unload()
}

@Test func earlyTokenlessMetalFailureRetriesExactlyOnceOnCPU() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        let behavior: FakeS1Session.Behavior = backend == .metal
            ? .fail(.decodeFailed, producedTokens: 0)
            : .output("Please send it.")
        return FakeS1Session(backend: backend, recorder: recorder, behavior: behavior)
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.metal),
        warmUp: false
    )
    let outcome = await normalizer.normalize(
        runtimeInput("please send it"),
        settings: CleanupSettings(),
        deadlineMilliseconds: 10_000
    )
    guard case let .insert(transcript) = outcome else {
        Issue.record("expected successful CPU retry")
        return
    }
    #expect(transcript.text == "Please send it.")
    #expect(recorder.loads == [.metal, .cpu])
    #expect(recorder.generations == 2)
    await normalizer.unload()
}

@Test func metalFailureAfterAProducedTokenDoesNotRetrySameRequest() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        FakeS1Session(
            backend: backend,
            recorder: recorder,
            behavior: backend == .metal
                ? .fail(.decodeFailed, producedTokens: 1)
                : .output("Please send it.")
        )
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.metal),
        warmUp: false
    )
    let input = runtimeInput("please send it")
    let outcome = await normalizer.normalize(
        input,
        settings: CleanupSettings(),
        deadlineMilliseconds: 10_000
    )
    #expect(outcome == .recover(
        CleanupPolicy().fallback(for: input, reason: .generationFailed),
        .generationFailed
    ))
    #expect(recorder.generations == 1)
    await normalizer.unload()
}

@Test func acceptedSinglePassOutputIsCanonicalizedExactlyOnce() async throws {
    let recorder = RuntimeRecorder()
    let canonicalizer = RecordingCanonicalizer()
    let output = "The invoice is seven thousand and twelve dollars."
    let normalizer = S1MiniNormalizer(
        policy: CleanupPolicy(),
        outputCanonicalizer: canonicalizer
    ) { _, backend in
        FakeS1Session(backend: backend, recorder: recorder, behavior: .output(output))
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let outcome = await normalizer.normalize(runtimeInput(output), settings: CleanupSettings())
    guard case let .insert(transcript) = outcome else {
        Issue.record("expected cleaned insertion")
        return
    }
    #expect(transcript.text == "The invoice is 7012$.")
    #expect(transcript.origin == .cleaned)
    #expect(canonicalizer.calls == 1)
    await normalizer.unload()
}

@Test func acceptedSinglePassDigitDriftUsesOriginalSpokenNumber() async throws {
    let recorder = RuntimeRecorder()
    let normalizer = S1MiniNormalizer(policy: CleanupPolicy()) { _, backend in
        FakeS1Session(
            backend: backend,
            recorder: recorder,
            behavior: .output("The invoice total is $7,12.")
        )
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let outcome = await normalizer.normalize(
        runtimeInput("the invoice total is seven thousand and twelve dollars"),
        settings: CleanupSettings()
    )
    guard case let .insert(transcript) = outcome else {
        Issue.record("expected cleaned insertion")
        return
    }
    #expect(transcript.text == "The invoice total is 7012$.")
    #expect(transcript.origin == .cleaned)
    await normalizer.unload()
}

@Test func chunkedOutputIsCanonicalizedOnceAfterAggregateValidation() async throws {
    let recorder = RuntimeRecorder()
    let canonicalizer = RecordingCanonicalizer()
    let policy = CleanupPolicy(limits: .init(contextTokens: 2_048, safeSinglePassInputTokens: 5))
    let normalizer = S1MiniNormalizer(
        policy: policy,
        outputCanonicalizer: canonicalizer
    ) { _, backend in
        FakeS1Session(backend: backend, recorder: recorder, behavior: .echo)
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let input = runtimeInput("First section has twelve items.\n\nSecond section has fifteen items.")
    let outcome = await normalizer.normalize(input, settings: CleanupSettings())
    guard case let .insert(transcript) = outcome else {
        Issue.record("expected joined cleaned insertion")
        return
    }
    #expect(transcript.text == "First section has 12 items.\n\nSecond section has 15 items.")
    #expect(canonicalizer.calls == 1)
    #expect(recorder.generations == 2)
    await normalizer.unload()
}

@Test func unsafeCanonicalizedCandidateFallsBackToValidatedModelText() async throws {
    let recorder = RuntimeRecorder()
    let canonicalizer = FixedCanonicalizer(output: "<think>unsafe</think>")
    let modelOutput = "Please send it."
    let normalizer = S1MiniNormalizer(
        policy: CleanupPolicy(),
        outputCanonicalizer: canonicalizer
    ) { _, backend in
        FakeS1Session(backend: backend, recorder: recorder, behavior: .output(modelOutput))
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )
    let outcome = await normalizer.normalize(runtimeInput("please send it"), settings: CleanupSettings())
    guard case let .insert(transcript) = outcome else {
        Issue.record("expected accepted model text rather than recovery")
        return
    }
    #expect(transcript.text == modelOutput)
    #expect(transcript.origin == .cleaned)
    await normalizer.unload()
}

@Test func canonicalizerIsNotCalledForDisabledOrInvalidCleanup() async throws {
    let recorder = RuntimeRecorder()
    let canonicalizer = RecordingCanonicalizer()
    let normalizer = S1MiniNormalizer(
        policy: CleanupPolicy(),
        outputCanonicalizer: canonicalizer
    ) { _, backend in
        FakeS1Session(
            backend: backend,
            recorder: recorder,
            behavior: .output("<think>invalid</think>")
        )
    }
    _ = try await normalizer.prepare(
        modelURL: URL(fileURLWithPath: "/tmp/fake.gguf"),
        selection: selection(.cpu),
        warmUp: false
    )

    let disabledInput = runtimeInput("twelve items")
    #expect(await normalizer.normalize(
        disabledInput,
        settings: CleanupSettings(isEnabled: false)
    ) == .insert(CleanupPolicy().fallback(for: disabledInput, reason: .modelUnavailable)))

    let invalidInput = runtimeInput("please send it")
    #expect(await normalizer.normalize(invalidInput, settings: CleanupSettings()) == .recover(
        CleanupPolicy().fallback(for: invalidInput, reason: .invalidOutput),
        .invalidOutput
    ))
    #expect(canonicalizer.calls == 0)
    await normalizer.unload()
}
