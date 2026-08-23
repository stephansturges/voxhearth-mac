import Foundation

/// Injectable wrapper around ProcessInfo activity assertions. The opaque token
/// never leaves MainActor isolation in production.
@MainActor
public protocol LifecycleActivityAsserting: AnyObject {
    func beginActivity(
        options: ProcessInfo.ActivityOptions,
        reason: String
    ) -> any NSObjectProtocol

    func endActivity(_ activity: any NSObjectProtocol)
}

@MainActor
private final class ProcessLifecycleActivityAsserter: LifecycleActivityAsserting {
    func beginActivity(
        options: ProcessInfo.ActivityOptions,
        reason: String
    ) -> any NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
    }

    func endActivity(_ activity: any NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(activity)
    }
}

/// Owns the one scoped activity assertion associated with user-visible work.
/// Narrowing begins the replacement before ending the old token so there is no
/// nap-eligible gap between microphone teardown and final transcription.
@MainActor
final class LifecycleActivityScope {
    private let asserter: any LifecycleActivityAsserting
    private let logger = PrivacySafeLogger(category: "Lifecycle")
    private var token: (any NSObjectProtocol)?

    init(asserter: (any LifecycleActivityAsserting)? = nil) {
        self.asserter = asserter ?? ProcessLifecycleActivityAsserter()
    }

    var isActive: Bool { token != nil }

    func beginAudioCritical() {
        replace(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            event: .lifecycleActivityBegan
        )
    }

    func beginUserInitiated() {
        replace(
            options: [.userInitiatedAllowingIdleSystemSleep],
            event: .lifecycleActivityBegan
        )
    }

    func narrowToUserInitiated() {
        guard token != nil else { return }
        replace(
            options: [.userInitiatedAllowingIdleSystemSleep],
            event: .lifecycleActivityNarrowed
        )
    }

    func end() {
        guard let token else { return }
        self.token = nil
        asserter.endActivity(token)
        logger.info(.lifecycleActivityEnded)
    }

    private func replace(
        options: ProcessInfo.ActivityOptions,
        event: PrivacyLogEvent
    ) {
        let replacement = asserter.beginActivity(
            options: options,
            reason: "voxhearth_user_visible_dictation"
        )
        let previous = token
        token = replacement
        if let previous {
            asserter.endActivity(previous)
        }
        logger.info(event)
    }
}
