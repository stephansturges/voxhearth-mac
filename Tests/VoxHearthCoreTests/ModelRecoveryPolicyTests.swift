import Testing
@testable import VoxHearthCore

@Test func modelRecoveryPolicyIsIdleBoundedAndOneShot() {
    let policy = ModelRecoveryPolicy(pathologicalEventThreshold: 2)

    #expect(!policy.shouldAttemptRecovery(
        state: .recording,
        pathologicalEventCount: 2,
        alreadyAttempted: false
    ))
    #expect(!policy.shouldAttemptRecovery(
        state: .transcribing,
        pathologicalEventCount: 2,
        alreadyAttempted: false
    ))
    #expect(!policy.shouldAttemptRecovery(
        state: .inserting,
        pathologicalEventCount: 2,
        alreadyAttempted: false
    ))
    #expect(!policy.shouldAttemptRecovery(
        state: .idle,
        pathologicalEventCount: 1,
        alreadyAttempted: false
    ))
    #expect(policy.shouldAttemptRecovery(
        state: .idle,
        pathologicalEventCount: 2,
        alreadyAttempted: false
    ))
    #expect(!policy.shouldAttemptRecovery(
        state: .idle,
        pathologicalEventCount: 3,
        alreadyAttempted: true
    ))
}
