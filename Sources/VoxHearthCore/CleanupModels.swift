import Foundation

public enum RecognizedDirective: String, CaseIterable, Sendable, Codable {
    case list
    case email
}

public enum CleanupFormat: String, CaseIterable, Sendable, Codable {
    case proseGeneral
    case listGeneral
    case proseEmail

    public var structureControlValue: String {
        switch self {
        case .proseGeneral, .proseEmail: "prose"
        case .listGeneral: "lists"
        }
    }

    public var contextControlValue: String {
        switch self {
        case .proseGeneral, .listGeneral: "general"
        case .proseEmail: "email"
        }
    }

    public var minimumOutputTokens: Int {
        switch self {
        case .proseGeneral: 64
        case .listGeneral: 96
        case .proseEmail: 128
        }
    }
}

public enum CleanupStyling: String, CaseIterable, Sendable, Codable {
    case casual
    case semiCasual = "semi-casual"
    case semiFormal = "semi-formal"
    case formal
}

public struct CleanupSettings: Equatable, Sendable, Codable {
    public var isEnabled: Bool
    public var styling: CleanupStyling
    public var listDirectiveEnabled: Bool
    public var emailDirectiveEnabled: Bool

    public init(
        isEnabled: Bool = true,
        styling: CleanupStyling = .semiFormal,
        listDirectiveEnabled: Bool = true,
        emailDirectiveEnabled: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.styling = styling
        self.listDirectiveEnabled = listDirectiveEnabled
        self.emailDirectiveEnabled = emailDirectiveEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case styling
        case listDirectiveEnabled
        case emailDirectiveEnabled
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            styling: try values.decodeIfPresent(CleanupStyling.self, forKey: .styling)
                ?? .semiFormal,
            listDirectiveEnabled: try values.decodeIfPresent(
                Bool.self,
                forKey: .listDirectiveEnabled
            ) ?? true,
            emailDirectiveEnabled: try values.decodeIfPresent(
                Bool.self,
                forKey: .emailDirectiveEnabled
            ) ?? true
        )
    }
}

public enum CleanupDisclosure {
    public static let requiredVersion = 1
    public static let defaultsKey = "VoxHearth.cleanupDisclosureVersion.v1"
}

public enum CleanupRuntimeLimits {
    public static let productionDeadlineMilliseconds = 2_000
}

public enum S1MiniModelAsset {
    public static let bundleRoot = "s1-mini-gguf"
    public static let fileName = "s1-mini-q4_k_m.gguf"
    public static let byteCount = 484_219_808
    public static let sha256 = "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634"

    /// Performs the cheap, cacheable runtime-presence check. Full SHA-256
    /// verification belongs to build/package validation and once-per-process
    /// preparation, never the per-dictation path.
    public static func verifiedBundledURL(resourceURL: URL?) -> URL? {
        guard let resourceURL, resourceURL.isFileURL else { return nil }
        let root = resourceURL.standardizedFileURL
        let candidate = root
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(bundleRoot, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
            .standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix),
              let values = try? candidate.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
              ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.fileSize == byteCount else {
            return nil
        }
        return candidate
    }
}

public enum CleanupIneffectiveReason: Equatable, Sendable {
    case disabled
    case disclosureRequired
    case unsupportedLanguage
    case modelUnavailable
}

public struct CleanupEnablement: Equatable, Sendable {
    public let isEffective: Bool
    public let listDirectiveEnabled: Bool
    public let emailDirectiveEnabled: Bool
    public let ineffectiveReason: CleanupIneffectiveReason?

    public static func resolve(
        settings: AppSettings,
        disclosureVersion: Int,
        modelAssetVerified: Bool
    ) -> CleanupEnablement {
        let settings = settings.normalizedForSelectedModel()
        let reason: CleanupIneffectiveReason?
        if !settings.cleanup.isEnabled {
            reason = .disabled
        } else if disclosureVersion < CleanupDisclosure.requiredVersion {
            reason = .disclosureRequired
        } else if settings.language != .english {
            reason = .unsupportedLanguage
        } else if !modelAssetVerified {
            reason = .modelUnavailable
        } else {
            reason = nil
        }
        let effective = reason == nil
        return CleanupEnablement(
            isEffective: effective,
            listDirectiveEnabled: effective && settings.cleanup.listDirectiveEnabled,
            emailDirectiveEnabled: effective && settings.cleanup.emailDirectiveEnabled,
            ineffectiveReason: reason
        )
    }
}

public enum CleanupStatus: Equatable, Sendable {
    case disabled
    case preparing
    case ready
    case cleaning(DictationSessionID)
    case fallingBack(DictationSessionID, CleanupFallbackReason)
}

public enum CleanupFallbackReason: String, Error, Equatable, Sendable, Codable {
    case cancelled
    case deadline
    case inputTooLong
    case modelUnavailable
    case backendUnavailable
    case generationFailed
    case invalidOutput
    case truncated
}

public enum S1MiniError: Error, Equatable, Sendable {
    case invalidModelAsset
    case modelLoadFailed
    case contextCreationFailed
    case tokenizerFailure
    case promptContractViolation
    case decodeFailed
    case cancelled
    case deadlineExceeded
    case outputTruncated
}

public struct CleanupTokenBudget: Equatable, Sendable {
    public let inputTokens: Int
    public let maximumNewTokens: Int
}

public struct NormalizationChunk: Equatable, Sendable {
    public let text: String
    public let budget: CleanupTokenBudget
    public let separatorBefore: String

    init(
        text: String,
        budget: CleanupTokenBudget,
        separatorBefore: String = ""
    ) {
        self.text = text
        self.budget = budget
        self.separatorBefore = separatorBefore
    }
}

public enum CleanupExecutionPlan: Equatable, Sendable {
    case singlePass(NormalizationChunk)
    case chunks([NormalizationChunk])
    case fallback(CleanupFallbackReason)
}

public struct CleanupGenerationResult: Equatable, Sendable {
    public let text: String
    public let outputTokens: Int
    public let reachedEndOfGeneration: Bool

    public init(text: String, outputTokens: Int, reachedEndOfGeneration: Bool) {
        self.text = text
        self.outputTokens = outputTokens
        self.reachedEndOfGeneration = reachedEndOfGeneration
    }
}

public enum CleanupValidationResult: Equatable, Sendable {
    case accepted(String)
    case fallback(CleanupFallbackReason)
}

public struct CleanupResourceCounters: Equatable, Sendable {
    public var modelLoads = 0
    public var contextCreations = 0
    public var warmups = 0
    public var generations = 0
    public var failures = 0

    public init() {}
}
