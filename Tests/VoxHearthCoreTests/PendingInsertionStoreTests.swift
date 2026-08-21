import Foundation
import Testing
@testable import VoxHearthCore

private func pendingValue(
    _ text: String,
    sessionID: DictationSessionID = DictationSessionID()
) -> InsertableTranscript {
    CleanupPolicy().passthrough(FinalTranscript(sessionID: sessionID, text: text))
}

@Test func pendingStoreIsSessionKeyedBoundedAndDeterministicallyOrdered() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let first = pendingValue("first")
    let second = pendingValue("second")
    let third = pendingValue("third")
    let fourth = pendingValue("fourth")
    var store = PendingInsertionStore(capacity: 3)

    let retainedFirst = store.retain(first, reason: .insertionFailed, now: start)
    let retainedSecond = store.retain(
        second,
        reason: .insertionUncertain,
        now: start.addingTimeInterval(1)
    )
    let retainedThird = store.retain(
        third,
        reason: .blockedTerminal,
        now: start.addingTimeInterval(2)
    )
    let retainedFourth = store.retain(
        fourth,
        reason: .insertionFailed,
        now: start.addingTimeInterval(3)
    )
    #expect(retainedFirst)
    #expect(retainedSecond)
    #expect(retainedThird)
    #expect(!retainedFourth)
    #expect(store.entries.map(\.id) == [first.sessionID, second.sessionID, third.sessionID])

    let replacement = pendingValue("first revised", sessionID: first.sessionID)
    let retainedReplacement = store.retain(
        replacement,
        reason: .multilineClipboardDisabled,
        now: start.addingTimeInterval(4)
    )
    #expect(retainedReplacement)
    #expect(store.entries.map(\.id) == [first.sessionID, second.sessionID, third.sessionID])
    #expect(store.entry(for: first.sessionID)?.text == "first revised")
}

@Test func pendingStoreExpiresAndRemovesOnlyTheAddressedSession() throws {
    let start = Date(timeIntervalSince1970: 2_000)
    let first = pendingValue("first")
    let second = pendingValue("second")
    var store = PendingInsertionStore()
    let retainedFirst = store.retain(
        first,
        reason: .insertionFailed,
        now: start,
        lifetime: 2
    )
    let retainedSecond = store.retain(
        second,
        reason: .blockedTerminal,
        now: start.addingTimeInterval(1),
        lifetime: 2
    )
    #expect(retainedFirst)
    #expect(retainedSecond)

    let expired = store.expire(at: start.addingTimeInterval(2))
    #expect(expired.map(\.id) == [first.sessionID])
    #expect(store.entries.map(\.id) == [second.sessionID])
    let missing = store.remove(sessionID: first.sessionID)
    let removed = store.remove(sessionID: second.sessionID)
    #expect(missing == nil)
    #expect(removed?.text == "second")
    #expect(store.entries.isEmpty)
}
