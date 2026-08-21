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
    public var enabled: Bool
    public var styling: CleanupStyling
    public var detectListDirective: Bool
    public var detectEmailDirective: Bool

    public init(
        enabled: Bool = true,
        styling: CleanupStyling = .semiFormal,
        detectListDirective: Bool = true,
        detectEmailDirective: Bool = true
    ) {
        self.enabled = enabled
        self.styling = styling
        self.detectListDirective = detectListDirective
        self.detectEmailDirective = detectEmailDirective
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
