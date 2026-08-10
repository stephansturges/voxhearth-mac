// Derived from FluidAudio 0.15.5 at revision
// 19600a485baa4998812e4654b70d2bab8f2c9949, licensed under Apache-2.0.
// Modified for VoxHearth: 2026-08-10. Removed every download, cache, model-hub,
// and automatic-recovery API; retained only local Core ML model value types.

@preconcurrency import CoreML
import Foundation

public enum AsrModelVersion: Equatable, Sendable {
    case v2
    case v3
    case tdtCtc110m
    case tdtJa

    public var hasFusedEncoder: Bool {
        self == .tdtCtc110m
    }

    public var encoderHiddenSize: Int {
        self == .tdtCtc110m ? 512 : 1024
    }

    public var blankId: Int {
        switch self {
        case .v2, .tdtCtc110m: 1024
        case .v3: 8192
        case .tdtJa: 3072
        }
    }

    public var decoderLayers: Int {
        self == .tdtCtc110m ? 1 : 2
    }
}

public struct AsrModels: Sendable {
    public let encoder: MLModel?
    public let preprocessor: MLModel
    public let decoder: MLModel
    public let joint: MLModel
    public let configuration: MLModelConfiguration
    public let vocabulary: [Int: String]
    public let version: AsrModelVersion

    public init(
        encoder: MLModel?,
        preprocessor: MLModel,
        decoder: MLModel,
        joint: MLModel,
        configuration: MLModelConfiguration,
        vocabulary: [Int: String],
        version: AsrModelVersion
    ) {
        self.encoder = encoder
        self.preprocessor = preprocessor
        self.decoder = decoder
        self.joint = joint
        self.configuration = configuration
        self.vocabulary = vocabulary
        self.version = version
    }

    public var usesSplitFrontend: Bool {
        !version.hasFusedEncoder
    }

    public static func optimizedPredictionOptions() -> MLPredictionOptions {
        let options = MLPredictionOptions()
        options.outputBackings = [:]
        return options
    }
}
