import Foundation
import LlamaLocal

private func discardLlamaLog(
    _ level: ggml_log_level,
    _ message: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) {
    _ = level
    _ = message
    _ = userData
}

/// Owns llama.cpp's process-global initialization. The global backend is never
/// torn down during normal application lifetime because other model instances
/// may still be using its registries.
public final class LlamaRuntime: @unchecked Sendable {
    public static let shared = LlamaRuntime()

    private init() {
        llama_log_set(discardLlamaLog, nil)
        llama_backend_init()
    }

    public func hasDevice(ofType type: ggml_backend_dev_type) -> Bool {
        device(ofType: type) != nil
    }

    func device(ofType type: ggml_backend_dev_type) -> ggml_backend_dev_t? {
        ggml_backend_dev_by_type(type)
    }
}

public final class S1MiniCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.withLock { cancelled = true }
    }

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }
}

struct LlamaGenerationFailure: Error {
    let error: S1MiniError
    let producedTokens: Int
}

private final class LlamaAbortState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: S1MiniCancellationToken?
    private var deadline: DispatchTime = .distantFuture

    func configure(cancellation: S1MiniCancellationToken, deadline: DispatchTime) {
        lock.withLock {
            self.cancellation = cancellation
            self.deadline = deadline
        }
    }

    func shouldAbort() -> Bool {
        lock.withLock {
            cancellation?.isCancelled == true || DispatchTime.now() >= deadline
        }
    }
}

private func llamaAbortCallback(_ rawState: UnsafeMutableRawPointer?) -> Bool {
    guard let rawState else { return false }
    return Unmanaged<LlamaAbortState>.fromOpaque(rawState).takeUnretainedValue().shouldAbort()
}

/// A single model/context pair. Every method must execute on the normalizer's
/// dedicated serial queue. Explicit `unload()` is required; deinit performs no
/// llama.cpp or Metal calls.
final class LlamaModelSession: @unchecked Sendable {
    let backend: LlamaBackend
    private(set) var model: OpaquePointer?
    private(set) var context: OpaquePointer?
    private(set) var sampler: UnsafeMutablePointer<llama_sampler>?
    private(set) var vocabulary: OpaquePointer?
    private let abortState = LlamaAbortState()

    init(modelURL: URL, backend: LlamaBackend, contextTokens: Int = 2_048) throws {
        _ = LlamaRuntime.shared
        guard modelURL.isFileURL,
              let values = try? modelURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw S1MiniError.invalidModelAsset
        }

        self.backend = backend
        var modelParameters = llama_model_default_params()
        modelParameters.n_gpu_layers = backend == .metal ? -1 : 0
        modelParameters.check_tensors = true

        var devices: [ggml_backend_dev_t?]
        if backend == .metal {
            guard let metal = LlamaRuntime.shared.device(ofType: GGML_BACKEND_DEVICE_TYPE_GPU) else {
                throw S1MiniError.contextCreationFailed
            }
            devices = [metal, nil]
        } else {
            devices = [nil]
        }
        let loadedModel = devices.withUnsafeMutableBufferPointer { deviceBuffer in
            modelParameters.devices = deviceBuffer.baseAddress
            return modelURL.path.withCString {
                llama_model_load_from_file($0, modelParameters)
            }
        }
        guard let loadedModel else { throw S1MiniError.modelLoadFailed }
        model = loadedModel

        let abortPointer = Unmanaged.passUnretained(abortState).toOpaque()
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(contextTokens)
        contextParameters.n_batch = UInt32(min(512, contextTokens))
        contextParameters.n_ubatch = UInt32(min(256, contextTokens))
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let threadCount = max(2, min(6, processorCount - 2))
        contextParameters.n_threads = Int32(threadCount)
        contextParameters.n_threads_batch = Int32(threadCount)
        contextParameters.no_perf = true
        contextParameters.abort_callback = llamaAbortCallback
        contextParameters.abort_callback_data = abortPointer
        if backend == .cpu {
            contextParameters.offload_kqv = false
            contextParameters.op_offload = false
        }

        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            model = nil
            throw S1MiniError.contextCreationFailed
        }
        context = loadedContext
        vocabulary = llama_model_get_vocab(loadedModel)

        var samplerParameters = llama_sampler_chain_default_params()
        samplerParameters.no_perf = true
        guard let loadedSampler = llama_sampler_chain_init(samplerParameters) else {
            llama_free(loadedContext)
            llama_model_free(loadedModel)
            context = nil
            model = nil
            throw S1MiniError.contextCreationFailed
        }
        sampler = loadedSampler
        installGreedySamplers(loadedSampler)
    }

    func unload() {
        if let sampler {
            llama_sampler_free(sampler)
            self.sampler = nil
        }
        if let context {
            llama_free(context)
            self.context = nil
            vocabulary = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
    }

    func tokenCount(_ text: String, parseSpecial: Bool = false) throws -> Int {
        try tokenize(text, parseSpecial: parseSpecial).count
    }

    func promptTokens(
        input: String,
        styling: CleanupStyling,
        format: CleanupFormat
    ) throws -> [llama_token] {
        let pieces = S1MiniPrompt.pieces(input: input, styling: styling, format: format)
        let markerTokens = try S1MiniPrompt.trustedMarkers.map { marker -> llama_token in
            let tokens = try tokenize(marker, parseSpecial: true)
            guard tokens.count == 1, let token = tokens.first else {
                throw S1MiniError.promptContractViolation
            }
            return token
        }

        var untrusted = try tokenize(pieces.untrustedTranscript, parseSpecial: false)
        if untrusted.contains(where: markerTokens.contains) {
            untrusted = try pieces.untrustedTranscript.unicodeScalars.flatMap {
                try tokenize(String($0), parseSpecial: false)
            }
        }
        guard untrusted.allSatisfy({ !markerTokens.contains($0) }) else {
            throw S1MiniError.promptContractViolation
        }
        let untrustedRoundTrip = try untrusted.map(piece).joined()
        guard untrustedRoundTrip == pieces.untrustedTranscript else {
            throw S1MiniError.promptContractViolation
        }
        let prefix = try tokenize(pieces.trustedPrefix, parseSpecial: true)
        let assistant = try tokenize(pieces.trustedAssistantPrefix, parseSpecial: true)
        let assembled = prefix + untrusted + assistant

        if !input.contains("<|") {
            let canonical = try tokenize(pieces.canonicalText, parseSpecial: true)
            guard assembled == canonical else { throw S1MiniError.promptContractViolation }
        }
        return assembled
    }

    func trustedPromptTokenCount(styling: CleanupStyling, format: CleanupFormat) throws -> Int {
        let pieces = S1MiniPrompt.pieces(input: "", styling: styling, format: format)
        return try tokenize(pieces.trustedPrefix, parseSpecial: true).count
            + tokenize(pieces.trustedAssistantPrefix, parseSpecial: true).count
    }

    func generate(
        input: String,
        styling: CleanupStyling,
        format: CleanupFormat,
        maximumNewTokens: Int,
        cancellation: S1MiniCancellationToken,
        deadline: DispatchTime
    ) throws -> CleanupGenerationResult {
        guard let context, let vocabulary, let sampler else {
            throw LlamaGenerationFailure(error: .contextCreationFailed, producedTokens: 0)
        }
        guard maximumNewTokens > 0 else {
            throw LlamaGenerationFailure(error: .outputTruncated, producedTokens: 0)
        }
        abortState.configure(cancellation: cancellation, deadline: deadline)
        try checkCancellation(cancellation, deadline: deadline, producedTokens: 0)
        llama_memory_clear(llama_get_memory(context), false)
        llama_sampler_reset(sampler)

        let prompt: [llama_token]
        do {
            prompt = try promptTokens(input: input, styling: styling, format: format)
        } catch let error as S1MiniError {
            throw LlamaGenerationFailure(error: error, producedTokens: 0)
        }

        let promptStatus = prompt.withUnsafeBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            let mutable = UnsafeMutablePointer(mutating: baseAddress)
            return llama_decode(context, llama_batch_get_one(mutable, Int32(buffer.count)))
        }
        guard promptStatus == 0 else {
            try checkCancellation(cancellation, deadline: deadline, producedTokens: 0)
            throw LlamaGenerationFailure(error: .decodeFailed, producedTokens: 0)
        }

        var output = ""
        var outputTokens = 0
        for _ in 0..<maximumNewTokens {
            try checkCancellation(cancellation, deadline: deadline, producedTokens: outputTokens)
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) {
                llama_memory_clear(llama_get_memory(context), false)
                return CleanupGenerationResult(
                    text: output,
                    outputTokens: outputTokens,
                    reachedEndOfGeneration: true
                )
            }
            do {
                output += try piece(for: token)
            } catch let error as S1MiniError {
                throw LlamaGenerationFailure(error: error, producedTokens: outputTokens)
            }
            outputTokens += 1

            var mutableToken = token
            let status = withUnsafeMutablePointer(to: &mutableToken) {
                llama_decode(context, llama_batch_get_one($0, 1))
            }
            guard status == 0 else {
                try checkCancellation(cancellation, deadline: deadline, producedTokens: outputTokens)
                throw LlamaGenerationFailure(error: .decodeFailed, producedTokens: outputTokens)
            }
        }
        llama_memory_clear(llama_get_memory(context), false)
        return CleanupGenerationResult(
            text: output,
            outputTokens: outputTokens,
            reachedEndOfGeneration: false
        )
    }

    func warmUp(cancellation: S1MiniCancellationToken, deadline: DispatchTime) throws {
        let result = try generate(
            input: "This is, um, a fixed warm-up transcript.",
            styling: .semiFormal,
            format: .proseGeneral,
            maximumNewTokens: 2,
            cancellation: cancellation,
            deadline: deadline
        )
        guard result.outputTokens >= 2 else { throw S1MiniError.decodeFailed }
        if let context { llama_memory_clear(llama_get_memory(context), false) }
    }

    private func tokenize(_ text: String, parseSpecial: Bool) throws -> [llama_token] {
        guard let vocabulary else { throw S1MiniError.tokenizerFailure }
        let utf8Count = text.utf8.count
        let required = text.withCString {
            llama_tokenize(vocabulary, $0, Int32(utf8Count), nil, 0, false, parseSpecial)
        }
        if required == 0 { return [] }
        guard required < 0 else { throw S1MiniError.tokenizerFailure }
        var tokens = [llama_token](repeating: 0, count: Int(-required))
        let count = text.withCString { stringPointer in
            tokens.withUnsafeMutableBufferPointer { tokenBuffer in
                llama_tokenize(
                    vocabulary,
                    stringPointer,
                    Int32(utf8Count),
                    tokenBuffer.baseAddress,
                    Int32(tokenBuffer.count),
                    false,
                    parseSpecial
                )
            }
        }
        guard count >= 0 else { throw S1MiniError.tokenizerFailure }
        tokens.removeSubrange(Int(count)..<tokens.count)
        return tokens
    }

    private func piece(for token: llama_token) throws -> String {
        guard let vocabulary else { throw S1MiniError.tokenizerFailure }
        var buffer = [CChar](repeating: 0, count: 256)
        var count = buffer.withUnsafeMutableBufferPointer {
            llama_token_to_piece(vocabulary, token, $0.baseAddress, Int32($0.count), 0, true)
        }
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = buffer.withUnsafeMutableBufferPointer {
                llama_token_to_piece(vocabulary, token, $0.baseAddress, Int32($0.count), 0, true)
            }
        }
        guard count >= 0 else { throw S1MiniError.tokenizerFailure }
        let bytes = buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
        guard let result = String(bytes: bytes, encoding: .utf8) else {
            throw S1MiniError.tokenizerFailure
        }
        return result
    }

    private func checkCancellation(
        _ cancellation: S1MiniCancellationToken,
        deadline: DispatchTime,
        producedTokens: Int
    ) throws {
        if cancellation.isCancelled {
            throw LlamaGenerationFailure(error: .cancelled, producedTokens: producedTokens)
        }
        if DispatchTime.now() >= deadline {
            throw LlamaGenerationFailure(error: .deadlineExceeded, producedTokens: producedTokens)
        }
    }

    private func installGreedySamplers(_ sampler: UnsafeMutablePointer<llama_sampler>) {
        guard let vocabulary else { return }
        var suppressedCount: Int32 = 0
        if let suppressed = llama_vocab_get_suppress_tokens(vocabulary, &suppressedCount), suppressedCount > 0 {
            var biases = (0..<Int(suppressedCount)).map {
                llama_logit_bias(token: suppressed[$0], bias: -Float.infinity)
            }
            biases.withUnsafeMutableBufferPointer {
                llama_sampler_chain_add(
                    sampler,
                    llama_sampler_init_logit_bias(
                        llama_vocab_n_tokens(vocabulary),
                        Int32($0.count),
                        $0.baseAddress
                    )
                )
            }
        }
        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_penalties(llama_vocab_n_tokens(vocabulary), 64, 1, 0, 0)
        )
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp_ext(0, 0, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(0))
    }
}
