@preconcurrency import AVFoundation
@preconcurrency import CoreML
import FluidAudioLocal
import Foundation
import os

/// Offline-only Parakeet TDT v3 adapter. Model assets are injected by URL and
/// opened directly with Core ML; this type never invokes a download or cache API.
public actor ParakeetEngine: LocalTranscriptionEngine {
    public static let modelDirectoryName = "parakeet-tdt-0.6b-v3-coreml"
    public static let requiredAssetNames = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json",
    ]

    private let modelDirectoryURL: URL
    private var manager: AsrManager?
    private let logger = PrivacySafeLogger(category: "LocalTranscription")

    public private(set) var isPrepared = false

    public init(modelDirectoryURL: URL) {
        self.modelDirectoryURL = modelDirectoryURL.standardizedFileURL
    }

    public func prepare() async throws {
        guard !isPrepared else { return }
        #if !arch(arm64)
        throw ParakeetEngineError.unsupportedArchitecture
        #else
        logger.info(.localModelLoadStarted)
        do {
            try Self.validateAssets(in: modelDirectoryURL)

            let generalConfiguration = MLModelConfiguration()
            generalConfiguration.computeUnits = .cpuAndNeuralEngine
            generalConfiguration.allowLowPrecisionAccumulationOnGPU = true

            let preprocessorConfiguration = MLModelConfiguration()
            preprocessorConfiguration.computeUnits = .cpuOnly

            let preprocessor = try MLModel(
                contentsOf: modelDirectoryURL.appendingPathComponent("Preprocessor.mlmodelc"),
                configuration: preprocessorConfiguration
            )
            let encoder = try MLModel(
                contentsOf: modelDirectoryURL.appendingPathComponent("Encoder.mlmodelc"),
                configuration: generalConfiguration
            )
            let decoder = try MLModel(
                contentsOf: modelDirectoryURL.appendingPathComponent("Decoder.mlmodelc"),
                configuration: generalConfiguration
            )
            let joint = try MLModel(
                contentsOf: modelDirectoryURL.appendingPathComponent("JointDecisionv3.mlmodelc"),
                configuration: generalConfiguration
            )
            let vocabulary = try Self.loadVocabulary(
                from: modelDirectoryURL.appendingPathComponent("parakeet_vocab.json")
            )

            let models = AsrModels(
                encoder: encoder,
                preprocessor: preprocessor,
                decoder: decoder,
                joint: joint,
                configuration: generalConfiguration,
                vocabulary: vocabulary,
                version: .v3
            )
            let configuration = ASRConfig(
                streamingEnabled: false,
                melChunkContext: false
            )
            manager = AsrManager(config: configuration, models: models)
            isPrepared = true
            logger.info(.localModelLoadCompleted)
        } catch let error as ParakeetEngineError {
            logger.error(.operationFailed, error: error)
            throw error
        } catch {
            logger.error(.operationFailed, error: error)
            throw ParakeetEngineError.modelLoadFailed
        }
        #endif
    }

    public func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage
    ) async throws -> String {
        guard !audio.samples.isEmpty, audio.sampleRate > 0 else {
            throw ParakeetEngineError.emptyAudio
        }
        if !isPrepared {
            try await prepare()
        }
        guard let manager else { throw ParakeetEngineError.modelLoadFailed }

        do {
            logger.info(.localTranscriptionStarted)
            let normalizedSamples = try PCMResampler.resample(
                audio.samples,
                from: audio.sampleRate,
                to: 16_000
            )
            var decoderState = try TdtDecoderState(decoderLayers: 2)
            let result = try await manager.transcribe(
                normalizedSamples,
                decoderState: &decoderState,
                language: language.fluidAudioLanguage
            )
            logger.info(.localTranscriptionCompleted)
            return result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch let error as ParakeetEngineError {
            logger.error(.operationFailed, error: error)
            throw error
        } catch {
            logger.error(.operationFailed, error: error)
            throw ParakeetEngineError.transcriptionFailed
        }
    }

    static func validateAssets(in directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ParakeetEngineError.missingModelAsset(Self.modelDirectoryName)
        }

        for assetName in requiredAssetNames {
            let assetURL = directory.appendingPathComponent(assetName)
            guard FileManager.default.fileExists(atPath: assetURL.path) else {
                throw ParakeetEngineError.missingModelAsset(assetName)
            }
        }
    }

    static func loadVocabulary(from url: URL) throws -> [Int: String] {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let rawVocabulary = try JSONDecoder().decode([String: String].self, from: data)
            let vocabulary = Dictionary(
                uniqueKeysWithValues: rawVocabulary.compactMap { key, value in
                    Int(key).map { ($0, value) }
                }
            )
            guard !vocabulary.isEmpty else { throw ParakeetEngineError.invalidVocabulary }
            return vocabulary
        } catch let error as ParakeetEngineError {
            throw error
        } catch {
            throw ParakeetEngineError.invalidVocabulary
        }
    }
}

extension DictationLanguage {
    var fluidAudioLanguage: Language {
        switch self {
        case .bulgarian: .bulgarian
        case .croatian: .croatian
        case .czech: .czech
        case .danish: .danish
        case .dutch: .dutch
        case .english: .english
        case .estonian: .estonian
        case .finnish: .finnish
        case .french: .french
        case .german: .german
        case .greek: .greek
        case .hungarian: .hungarian
        case .italian: .italian
        case .latvian: .latvian
        case .lithuanian: .lithuanian
        case .maltese: .maltese
        case .polish: .polish
        case .portuguese: .portuguese
        case .romanian: .romanian
        case .russian: .russian
        case .slovak: .slovak
        case .slovenian: .slovenian
        case .spanish: .spanish
        case .swedish: .swedish
        case .ukrainian: .ukrainian
        }
    }
}

enum PCMResampler {
    static func resample(
        _ samples: [Float],
        from sourceRate: Double,
        to destinationRate: Double
    ) throws -> [Float] {
        guard !samples.isEmpty, sourceRate > 0, destinationRate > 0 else {
            throw ParakeetEngineError.emptyAudio
        }
        if abs(sourceRate - destinationRate) < 0.5 {
            return samples
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceRate,
            channels: 1,
            interleaved: false
        ), let destinationFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: destinationRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat),
        let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw ParakeetEngineError.transcriptionFailed
        }

        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        sourceBuffer.floatChannelData?[0].update(from: samples, count: samples.count)

        let ratio = destinationRate / sourceRate
        // `AVAudioConverter.convert(to:from:)` requires destination capacity
        // to be at least the input frame length even while downsampling.
        let expectedOutputCount = Int(ceil(Double(samples.count) * ratio)) + 32
        let outputCapacity = AVAudioFrameCount(max(samples.count, expectedOutputCount))
        guard let destinationBuffer = AVAudioPCMBuffer(
            pcmFormat: destinationFormat,
            frameCapacity: outputCapacity
        ) else {
            throw ParakeetEngineError.transcriptionFailed
        }

        let inputState = OSAllocatedUnfairLock(initialState: false)
        var conversionError: NSError?
        let status = converter.convert(
            to: destinationBuffer,
            error: &conversionError
        ) { _, inputStatus in
            let shouldProvideInput = inputState.withLock { didProvideInput in
                guard !didProvideInput else { return false }
                didProvideInput = true
                return true
            }
            guard shouldProvideInput else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return sourceBuffer
        }
        guard conversionError == nil, status != .error else {
            throw ParakeetEngineError.transcriptionFailed
        }
        guard let output = destinationBuffer.floatChannelData?[0] else {
            throw ParakeetEngineError.transcriptionFailed
        }
        return Array(UnsafeBufferPointer(start: output, count: Int(destinationBuffer.frameLength)))
    }
}
