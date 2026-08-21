import Dispatch
import Foundation

protocol S1MiniRuntimeSession: AnyObject, Sendable {
    var backend: LlamaBackend { get }
    func unload()
    func tokenCount(_ text: String, parseSpecial: Bool) throws -> Int
    func trustedPromptTokenCount(styling: CleanupStyling, format: CleanupFormat) throws -> Int
    func promptTokens(input: String, styling: CleanupStyling, format: CleanupFormat) throws -> [Int32]
    func generate(
        input: String,
        styling: CleanupStyling,
        format: CleanupFormat,
        maximumNewTokens: Int,
        cancellation: S1MiniCancellationToken,
        deadline: DispatchTime
    ) throws -> CleanupGenerationResult
    func warmUp(cancellation: S1MiniCancellationToken, deadline: DispatchTime) throws
}

extension LlamaModelSession: S1MiniRuntimeSession {}

private struct SessionTokenCounter: CleanupTokenCounting {
    let session: any S1MiniRuntimeSession

    func tokenCount(for text: String) throws -> Int {
        try session.tokenCount(text, parseSpecial: false)
    }
}

final class S1MiniQueueState: @unchecked Sendable {
    typealias Factory = @Sendable (URL, LlamaBackend) throws -> any S1MiniRuntimeSession

    private let factory: Factory
    private let policy: CleanupPolicy
    private let logger = PrivacySafeLogger(category: "Cleanup")
    private var session: (any S1MiniRuntimeSession)?
    private var modelURL: URL?
    private(set) var counters = CleanupResourceCounters()
    private(set) var metalDemoted = false

    init(policy: CleanupPolicy, factory: @escaping Factory) {
        self.policy = policy
        self.factory = factory
    }

    func prepare(
        modelURL: URL,
        requestedBackend: LlamaBackend,
        warmUp: Bool,
        deadline: DispatchTime
    ) throws -> LlamaBackend {
        if let session,
           self.modelURL == modelURL,
           session.backend == requestedBackend,
           !metalDemoted {
            return session.backend
        }

        unload()
        self.modelURL = modelURL
        let preferred = metalDemoted ? LlamaBackend.cpu : requestedBackend
        do {
            return try loadAndWarm(
                modelURL: modelURL,
                backend: preferred,
                warmUp: warmUp,
                deadline: deadline
            )
        } catch {
            counters.failures += 1
            guard preferred == .metal else { throw error }
            metalDemoted = true
            logger.info(.cleanupBackendDemoted)
            unloadSessionOnly()
            return try loadAndWarm(
                modelURL: modelURL,
                backend: .cpu,
                warmUp: warmUp,
                deadline: deadline
            )
        }
    }

    func normalize(
        _ input: NormalizationInput,
        settings: CleanupSettings,
        cancellation: S1MiniCancellationToken,
        started: DispatchTime,
        deadline: DispatchTime
    ) -> DictationOutcome {
        guard settings.isEnabled else {
            return .insert(policy.fallback(for: input, reason: .modelUnavailable))
        }
        guard let session else {
            return .recover(
                policy.fallback(for: input, reason: .modelUnavailable),
                .modelUnavailable
            )
        }

        do {
            return try execute(
                input,
                settings: settings,
                session: session,
                cancellation: cancellation,
                deadline: deadline
            )
        } catch let failure as LlamaGenerationFailure {
            counters.failures += 1
            if failure.error == .cancelled {
                return .cancelled(input.sessionID)
            }

            if session.backend == .metal {
                metalDemoted = true
                logger.info(.cleanupBackendDemoted)
                let budget = deadline.uptimeNanoseconds - started.uptimeNanoseconds
                let elapsed = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                if failure.producedTokens == 0,
                   elapsed < budget / 4,
                   let modelURL,
                   let cpu = try? replaceWithCPU(modelURL: modelURL, deadline: deadline) {
                    do {
                        return try execute(
                            input,
                            settings: settings,
                            session: cpu,
                            cancellation: cancellation,
                            deadline: deadline
                        )
                    } catch {
                        counters.failures += 1
                    }
                }
            }
            let reason = fallbackReason(for: failure.error)
            return .recover(policy.fallback(for: input, reason: reason), reason)
        } catch {
            counters.failures += 1
            return .recover(
                policy.fallback(for: input, reason: .generationFailed),
                .generationFailed
            )
        }
    }

    func demoteMetalIfNeeded(deadline: DispatchTime) {
        guard metalDemoted,
              session?.backend == .metal,
              let modelURL else { return }
        _ = try? replaceWithCPU(modelURL: modelURL, deadline: deadline)
    }

    func unload() {
        unloadSessionOnly()
        modelURL = nil
    }

    func tokenIDs(
        input: String,
        styling: CleanupStyling,
        format: CleanupFormat
    ) throws -> [Int32] {
        guard let session else { throw S1MiniError.modelLoadFailed }
        return try session.promptTokens(input: input, styling: styling, format: format)
    }

    private func execute(
        _ input: NormalizationInput,
        settings: CleanupSettings,
        session: any S1MiniRuntimeSession,
        cancellation: S1MiniCancellationToken,
        deadline: DispatchTime
    ) throws -> DictationOutcome {
        let promptTokens = try session.trustedPromptTokenCount(
            styling: settings.styling,
            format: input.format
        )
        let plan = try policy.plan(
            input: input,
            promptTokenCount: promptTokens,
            tokenCounter: SessionTokenCounter(session: session)
        )
        switch plan {
        case let .fallback(reason):
            return .recover(policy.fallback(for: input, reason: reason), reason)
        case let .singlePass(chunk):
            let generated = try generate(
                chunk,
                source: input,
                settings: settings,
                session: session,
                cancellation: cancellation,
                deadline: deadline
            )
            return generated
        case let .chunks(chunks):
            var cleanedChunks: [String] = []
            var totalOutputTokens = 0
            for chunk in chunks {
                let chunkInput = normalizationInput(for: chunk.text, source: input)
                let generation = try session.generate(
                    input: chunk.text,
                    styling: settings.styling,
                    format: .proseGeneral,
                    maximumNewTokens: chunk.budget.maximumNewTokens,
                    cancellation: cancellation,
                    deadline: deadline
                )
                counters.generations += 1
                switch policy.validate(generation, for: chunkInput, budget: chunk.budget) {
                case let .accepted(text):
                    cleanedChunks.append(text)
                    totalOutputTokens += generation.outputTokens
                case let .fallback(reason):
                    return .recover(policy.fallback(for: input, reason: reason), reason)
                }
            }
            let joined = zip(chunks.indices, cleanedChunks).reduce(into: "") { result, pair in
                let (index, cleaned) = pair
                if index > chunks.startIndex {
                    result += chunks[index].separatorBefore
                }
                result += cleaned
            }
            let aggregateBudget = CleanupTokenBudget(
                inputTokens: chunks.reduce(0) { $0 + $1.budget.inputTokens },
                maximumNewTokens: chunks.reduce(0) { $0 + $1.budget.maximumNewTokens }
            )
            let aggregate = CleanupGenerationResult(
                text: joined,
                outputTokens: totalOutputTokens,
                reachedEndOfGeneration: true
            )
            switch policy.validate(aggregate, for: input, budget: aggregateBudget) {
            case let .accepted(text): return .insert(policy.cleaned(for: input, text: text))
            case let .fallback(reason):
                return .recover(policy.fallback(for: input, reason: reason), reason)
            }
        }
    }

    private func generate(
        _ chunk: NormalizationChunk,
        source: NormalizationInput,
        settings: CleanupSettings,
        session: any S1MiniRuntimeSession,
        cancellation: S1MiniCancellationToken,
        deadline: DispatchTime
    ) throws -> DictationOutcome {
        let generation = try session.generate(
            input: chunk.text,
            styling: settings.styling,
            format: source.format,
            maximumNewTokens: chunk.budget.maximumNewTokens,
            cancellation: cancellation,
            deadline: deadline
        )
        counters.generations += 1
        switch policy.validate(generation, for: source, budget: chunk.budget) {
        case let .accepted(text): return .insert(policy.cleaned(for: source, text: text))
        case let .fallback(reason):
            return .recover(policy.fallback(for: source, reason: reason), reason)
        }
    }

    private func normalizationInput(
        for text: String,
        source: NormalizationInput
    ) -> NormalizationInput {
        let transcript = FinalTranscript(sessionID: source.sessionID, text: text)
        return NormalizationInput(
            parse: DirectiveParse(
                source: transcript,
                directive: nil,
                format: .proseGeneral,
                payloadUTF8Offset: 0
            )
        )
    }

    private func replaceWithCPU(modelURL: URL, deadline: DispatchTime) throws -> any S1MiniRuntimeSession {
        unloadSessionOnly()
        _ = try loadAndWarm(
            modelURL: modelURL,
            backend: .cpu,
            warmUp: false,
            deadline: deadline
        )
        guard let session else { throw S1MiniError.modelLoadFailed }
        return session
    }

    private func loadAndWarm(
        modelURL: URL,
        backend: LlamaBackend,
        warmUp: Bool,
        deadline: DispatchTime
    ) throws -> LlamaBackend {
        let loaded = try factory(modelURL, backend)
        session = loaded
        counters.modelLoads += 1
        counters.contextCreations += 1
        do {
            if warmUp {
                let cancellation = S1MiniCancellationToken()
                try loaded.warmUp(cancellation: cancellation, deadline: deadline)
                counters.warmups += 1
            }
        } catch {
            loaded.unload()
            session = nil
            throw error
        }
        return backend
    }

    private func unloadSessionOnly() {
        session?.unload()
        session = nil
    }

    private func fallbackReason(for error: S1MiniError) -> CleanupFallbackReason {
        switch error {
        case .cancelled: .cancelled
        case .deadlineExceeded: .deadline
        case .outputTruncated: .truncated
        case .invalidModelAsset, .modelLoadFailed: .modelUnavailable
        case .contextCreationFailed: .backendUnavailable
        case .tokenizerFailure, .promptContractViolation, .decodeFailed: .generationFailed
        }
    }
}

public actor S1MiniNormalizer {
    private let queue = DispatchQueue(label: "com.stephansturges.voxhearth.s1-mini")
    private let state: S1MiniQueueState
    private let logger = PrivacySafeLogger(category: "Cleanup")

    public init(policy: CleanupPolicy = CleanupPolicy()) {
        state = S1MiniQueueState(policy: policy) { modelURL, backend in
            try LlamaModelSession(modelURL: modelURL, backend: backend)
        }
    }

    init(policy: CleanupPolicy, runtimeFactory: @escaping S1MiniQueueState.Factory) {
        state = S1MiniQueueState(policy: policy, factory: runtimeFactory)
    }

    @discardableResult
    public func prepare(
        modelURL: URL,
        selection: LlamaBackendSelection = .production(),
        warmUp: Bool = true,
        deadlineMilliseconds: Int = 30_000
    ) async throws -> LlamaBackend {
        precondition(deadlineMilliseconds > 0)
        logger.info(.cleanupPreparationStarted)
        let state = self.state
        let deadline = DispatchTime.now() + .milliseconds(deadlineMilliseconds)
        let backend = try await enqueue(qos: .utility) {
            try state.prepare(
                modelURL: modelURL,
                requestedBackend: selection.selected,
                warmUp: warmUp,
                deadline: deadline
            )
        }
        logger.info(.cleanupPreparationCompleted)
        return backend
    }

    public func normalize(
        _ input: NormalizationInput,
        settings: CleanupSettings,
        cancellation: S1MiniCancellationToken = S1MiniCancellationToken(),
        deadlineMilliseconds: Int = 2_000
    ) async -> DictationOutcome {
        precondition(deadlineMilliseconds > 0)
        logger.info(.cleanupGenerationStarted)
        let state = self.state
        let started = DispatchTime.now()
        let deadline = started + .milliseconds(deadlineMilliseconds)
        let outcome = (try? await enqueue(qos: .userInitiated) {
            state.normalize(
                input,
                settings: settings,
                cancellation: cancellation,
                started: started,
                deadline: deadline
            )
        }) ?? .recover(
            CleanupPolicy().fallback(for: input, reason: .generationFailed),
            .generationFailed
        )

        queue.async(qos: .utility) {
            state.demoteMetalIfNeeded(deadline: .now() + .seconds(30))
        }
        switch outcome {
        case .insert:
            logger.info(.cleanupGenerationCompleted)
        case .cancelled:
            logger.info(.cleanupCancelled)
        case .recover:
            logger.info(.cleanupFallback)
        }
        return outcome
    }

    public func unload() async {
        let state = self.state
        _ = try? await enqueue(qos: .utility) { state.unload() }
    }

    public func resourceCounters() async -> CleanupResourceCounters {
        let state = self.state
        return (try? await enqueue(qos: .utility) { state.counters }) ?? CleanupResourceCounters()
    }

    func tokenIDs(
        input: String,
        styling: CleanupStyling,
        format: CleanupFormat
    ) async throws -> [Int32] {
        let state = self.state
        return try await enqueue(qos: .userInitiated) {
            try state.tokenIDs(input: input, styling: styling, format: format)
        }
    }

    private func enqueue<Value: Sendable>(
        qos: DispatchQoS.QoSClass,
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let item = DispatchWorkItem(
                qos: DispatchQoS(qosClass: qos, relativePriority: 0)
            ) {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
            queue.async(execute: item)
        }
    }
}
