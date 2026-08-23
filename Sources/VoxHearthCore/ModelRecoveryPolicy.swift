import Foundation

struct ModelRecoveryPolicy: Sendable {
    let pathologicalEventThreshold: Int

    init(pathologicalEventThreshold: Int = 1) {
        self.pathologicalEventThreshold = max(1, pathologicalEventThreshold)
    }

    func shouldAttemptRecovery(
        state: DictationSessionState,
        pathologicalEventCount: Int,
        alreadyAttempted: Bool
    ) -> Bool {
        state == .idle
            && pathologicalEventCount >= pathologicalEventThreshold
            && !alreadyAttempted
    }
}
