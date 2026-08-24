import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import VoxHearthCore

private func insertable(_ text: String) -> InsertableTranscript {
    CleanupPolicy().passthrough(
        FinalTranscript(sessionID: DictationSessionID(), text: text)
    )
}

@Test func testProcessesUseIsolatedLoggingSubsystem() {
    #expect(
        PrivacyLogSubsystem.resolved(
            processName: "xctest",
            environment: ["XCTestConfigurationFilePath": "/redacted"]
        ) == AppIdentity.bundleIdentifier + ".tests"
    )
    #expect(
        PrivacyLogSubsystem.resolved(
            processName: "VoxHearth",
            environment: [:]
        ) == AppIdentity.bundleIdentifier
    )
    #expect(PrivacyLogSubsystem.current.hasSuffix(".tests"))
}

private final class MockInsertionBackend: TextInsertionBackend, @unchecked Sendable {
    private let lock = NSLock()
    var isAccessibilityTrusted = true
    var accessibilityResult: AccessibilityInsertionOutcome = .unavailable
    var unicodeResult = false
    var clipboardResult = false
    private var recordedCalls: [String] = []
    private var recordedClipboardTexts: [String] = []

    var calls: [String] { lock.withLock { recordedCalls } }
    var clipboardTexts: [String] { lock.withLock { recordedClipboardTexts } }

    func replaceSelectedText(_ text: String) -> AccessibilityInsertionOutcome {
        lock.withLock { recordedCalls.append("accessibility") }
        return accessibilityResult
    }

    func postUnicodeText(_ text: String) -> Bool {
        lock.withLock { recordedCalls.append("unicode") }
        return unicodeResult
    }

    @MainActor
    func copyToClipboard(_ text: String) -> Bool {
        lock.withLock {
            recordedCalls.append("copy")
            recordedClipboardTexts.append(text)
        }
        return true
    }

    @MainActor
    func pasteWithSafeClipboardRestore(_ text: String) async throws -> Bool {
        lock.withLock {
            recordedCalls.append("clipboard")
            recordedClipboardTexts.append(text)
        }
        return clipboardResult
    }
}

private final class QueueAffinityRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    var observations: [Bool] { lock.withLock { values } }

    func recordCurrentThread() {
        lock.withLock { values.append(Thread.isMainThread) }
    }
}

@MainActor
private struct MockDestinationSafety: MultilineDestinationSafety {
    let disposition: MultilineDestinationDisposition

    func dispositionForFocusedDestination() -> MultilineDestinationDisposition {
        disposition
    }
}

@Test @MainActor func insertionPrefersAccessibility() async throws {
    let backend = MockInsertionBackend()
    backend.accessibilityResult = .inserted
    let service = TextInsertionService(backend: backend)

    let method = try await service.insert(insertable("private transcript"), clipboardFallbackEnabled: true)
    #expect(method == .accessibility)
    #expect(backend.calls == ["accessibility"])
}

@Test @MainActor func uncertainAccessibilityInsertionNeverFallsBackAutomatically() async {
    let backend = MockInsertionBackend()
    backend.accessibilityResult = .ambiguous
    backend.unicodeResult = true
    backend.clipboardResult = true
    let service = TextInsertionService(backend: backend)

    await #expect(throws: TextInsertionError.insertionUncertain) {
        try await service.insert(insertable("hello"), clipboardFallbackEnabled: true)
    }
    #expect(backend.calls == ["accessibility"])
}

@Test @MainActor func accessibilitySetOutcomeClassifierIsConservative() {
    #expect(MacTextInsertionBackend.classifySetOutcome(.success) == .inserted)
    #expect(MacTextInsertionBackend.classifySetOutcome(.cannotComplete) == .ambiguous)
    #expect(MacTextInsertionBackend.classifySetOutcome(.attributeUnsupported) == .unavailable)
    #expect(MacTextInsertionBackend.classifySetOutcome(.illegalArgument) == .unavailable)
    #expect(MacTextInsertionBackend.classifySetOutcome(.invalidUIElement) == .unavailable)
    #expect(MacTextInsertionBackend.classifySetOutcome(.notImplemented) == .unavailable)
}

@Test @MainActor func accessibilityTimeoutsAreScopedAndResetOnSuccess() {
    let focusedElement = AXUIElementCreateSystemWide()
    var timeouts: [Float] = []
    let messaging = AccessibilityMessaging(
        setMessagingTimeout: { _, timeout in
            timeouts.append(timeout)
            return .success
        },
        copyFocusedElement: { _ in (.success, focusedElement) },
        isSelectedTextSettable: { _ in (.success, true) },
        setSelectedText: { _, _ in .success }
    )
    let backend = MacTextInsertionBackend(messaging: messaging, mode: .accessibilityFirst)

    #expect(backend.replaceSelectedText("hello") == .inserted)
    #expect(timeouts == [
        MacTextInsertionBackend.accessibilityQueryTimeout,
        MacTextInsertionBackend.accessibilityQueryTimeout,
        MacTextInsertionBackend.accessibilitySetTimeout,
        0,
    ])
}

@Test @MainActor func accessibilityTimeoutIsResetAfterEarlyFailure() {
    var timeouts: [Float] = []
    let messaging = AccessibilityMessaging(
        setMessagingTimeout: { _, timeout in
            timeouts.append(timeout)
            return .success
        },
        copyFocusedElement: { _ in (.cannotComplete, nil) },
        isSelectedTextSettable: { _ in (.success, true) },
        setSelectedText: { _, _ in .success }
    )
    let backend = MacTextInsertionBackend(messaging: messaging, mode: .accessibilityFirst)

    #expect(backend.replaceSelectedText("hello") == .unavailable)
    #expect(timeouts == [MacTextInsertionBackend.accessibilityQueryTimeout, 0])
}

@Test @MainActor func selfProcessAccessibilityMutationHopsToMainFromWorker() async {
    let focusedElement = AXUIElementCreateApplication(getpid())
    let recorder = QueueAffinityRecorder()
    let messaging = AccessibilityMessaging(
        setMessagingTimeout: { _, _ in .success },
        copyFocusedElement: { _ in (.success, focusedElement) },
        isSelectedTextSettable: { _ in
            recorder.recordCurrentThread()
            return (.success, true)
        },
        setSelectedText: { _, _ in
            recorder.recordCurrentThread()
            return .success
        }
    )
    let backend = MacTextInsertionBackend(messaging: messaging, mode: .accessibilityFirst)

    let outcome = await Task.detached(priority: .userInitiated) {
        backend.replaceSelectedText("hello")
    }.value

    #expect(outcome == .inserted)
    #expect(recorder.observations == [true, true])
}

@Test @MainActor func externalProcessAccessibilityMutationStaysOffMain() async {
    let focusedElement = AXUIElementCreateApplication(1)
    let recorder = QueueAffinityRecorder()
    let messaging = AccessibilityMessaging(
        setMessagingTimeout: { _, _ in .success },
        copyFocusedElement: { _ in (.success, focusedElement) },
        isSelectedTextSettable: { _ in
            recorder.recordCurrentThread()
            return (.success, true)
        },
        setSelectedText: { _, _ in
            recorder.recordCurrentThread()
            return .success
        }
    )
    let backend = MacTextInsertionBackend(messaging: messaging, mode: .accessibilityFirst)

    let outcome = await Task.detached(priority: .userInitiated) {
        backend.replaceSelectedText("hello")
    }.value

    #expect(outcome == .inserted)
    #expect(recorder.observations == [false, false])
}

@Test @MainActor func unicodeFirstDiagnosticModeSkipsAccessibilityMessaging() {
    var messagingCallCount = 0
    let messaging = AccessibilityMessaging(
        setMessagingTimeout: { _, _ in
            messagingCallCount += 1
            return .success
        },
        copyFocusedElement: { _ in
            messagingCallCount += 1
            return (.success, AXUIElementCreateSystemWide())
        },
        isSelectedTextSettable: { _ in
            messagingCallCount += 1
            return (.success, true)
        },
        setSelectedText: { _, _ in
            messagingCallCount += 1
            return .success
        }
    )
    let backend = MacTextInsertionBackend(messaging: messaging, mode: .unicodeFirst)

    #expect(backend.replaceSelectedText("hello") == .unavailable)
    #expect(messagingCallCount == 0)
}

@Test func privacyLogEventVocabularyIsClosedAndPolicySafe() {
    let values = PrivacyLogEvent.allCases.map(\.rawValue)
    let forbidden = [
        "urlsession", "cfnetwork", "nwconnection", "websocket", "modelhub",
        "hfclient", "filedownloader", "assetdownloader", "downloader",
        "http://", "https://", "telemetry", "analytics",
    ]

    #expect(Set(values).count == values.count)
    #expect(values.allSatisfy { value in
        value == value.lowercased()
            && value.range(of: #"^[a-z0-9]+(?:_[a-z0-9]+)*$"#, options: .regularExpression) != nil
            && forbidden.allSatisfy { !value.contains($0) }
    })
}

@Test @MainActor func insertionUsesUnicodeBeforeClipboard() async throws {
    let backend = MockInsertionBackend()
    backend.unicodeResult = true
    let service = TextInsertionService(backend: backend)

    let method = try await service.insert(insertable("hello"), clipboardFallbackEnabled: true)
    #expect(method == .unicodeEvents)
    #expect(backend.calls == ["accessibility", "unicode"])
}

@Test @MainActor func clipboardFallbackRequiresExplicitOptIn() async {
    let backend = MockInsertionBackend()
    backend.clipboardResult = true
    let service = TextInsertionService(backend: backend)

    await #expect(throws: TextInsertionError.clipboardFallbackDisabled) {
        try await service.insert(insertable("hello"), clipboardFallbackEnabled: false)
    }
    #expect(backend.calls == ["accessibility", "unicode"])
}

@Test @MainActor func explicitClipboardFallbackRunsLast() async throws {
    let backend = MockInsertionBackend()
    backend.clipboardResult = true
    let service = TextInsertionService(backend: backend)

    let method = try await service.insert(insertable("hello"), clipboardFallbackEnabled: true)
    #expect(method == .clipboard)
    #expect(backend.calls == ["accessibility", "unicode", "clipboard"])
}

@Test @MainActor func insertionFailsBeforeReadingClipboardWithoutAccessibility() async {
    let backend = MockInsertionBackend()
    backend.isAccessibilityTrusted = false
    let service = TextInsertionService(backend: backend)

    await #expect(throws: TextInsertionError.accessibilityPermissionRequired) {
        try await service.insert(insertable("hello"), clipboardFallbackEnabled: true)
    }
    #expect(backend.calls.isEmpty)
}

@Test @MainActor func unicodeChunkingPreservesExtendedGraphemeClusters() {
    let original = "A👨‍👩‍👧‍👦 café Ελληνικά Українська"
    let chunks = MacTextInsertionBackend.unicodeChunks(original, maximumUTF16Units: 8)

    #expect(chunks.joined() == original)
    #expect(chunks.allSatisfy { !$0.isEmpty })
}

@Test @MainActor func clipboardSnapshotRestoresEveryItemAndType() throws {
    let first = NSPasteboardItem()
    first.setString("plain", forType: .string)
    first.setData(Data([1, 2, 3]), forType: .init("com.voxhearth.test.binary"))
    let second = NSPasteboardItem()
    second.setString("second", forType: .string)

    let snapshot = try PasteboardSnapshot(items: [first, second])
    let restored = snapshot.makePasteboardItems()
    try #require(restored.count == 2)
    #expect(restored[0].string(forType: .string) == "plain")
    #expect(restored[0].data(forType: .init("com.voxhearth.test.binary")) == Data([1, 2, 3]))
    #expect(restored[1].string(forType: .string) == "second")
}

@Test @MainActor func everyLineSeparatorBypassesUnicodeEvenWhenAccessibilityIsUnavailable() async {
    let separators = ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"]
    for separator in separators {
        let backend = MockInsertionBackend()
        backend.unicodeResult = true
        backend.clipboardResult = true
        let service = TextInsertionService(
            backend: backend,
            destinationSafety: MockDestinationSafety(disposition: .automaticInsertionAllowed)
        )

        let method = try? await service.insert(
            insertable("one\(separator)two"),
            clipboardFallbackEnabled: true
        )
        #expect(method == .clipboard)
        #expect(backend.calls == ["accessibility", "clipboard"])
    }
}

@Test @MainActor func untrustedMultilineUsesOnlyExplicitClipboardCompatibility() async {
    let backend = MockInsertionBackend()
    backend.isAccessibilityTrusted = false
    backend.clipboardResult = true
    let service = TextInsertionService(
        backend: backend,
        destinationSafety: MockDestinationSafety(disposition: .automaticInsertionAllowed)
    )

    await #expect(throws: TextInsertionError.multilineClipboardFallbackDisabled) {
        try await service.insert(insertable("one\ntwo"), clipboardFallbackEnabled: false)
    }
    #expect(backend.calls.isEmpty)

    let method = try? await service.insert(
        insertable("one\ntwo"),
        clipboardFallbackEnabled: true
    )
    #expect(method == .clipboard)
    #expect(backend.calls == ["clipboard"])
}

@Test @MainActor func blockedTerminalRetainsMultilineWithoutAnyAutomaticAttempt() async {
    let backend = MockInsertionBackend()
    backend.accessibilityResult = .inserted
    backend.unicodeResult = true
    backend.clipboardResult = true
    let service = TextInsertionService(
        backend: backend,
        destinationSafety: MockDestinationSafety(disposition: .blockedTerminal)
    )

    await #expect(throws: TextInsertionError.blockedMultilineDestination) {
        try await service.insert(insertable("one\ntwo"), clipboardFallbackEnabled: true)
    }
    #expect(backend.calls.isEmpty)
}

@Test @MainActor func confirmedMultilineOverrideTrimsOnlyItsOneShotPastePayload() async throws {
    let backend = MockInsertionBackend()
    backend.clipboardResult = true
    let service = TextInsertionService(
        backend: backend,
        destinationSafety: MockDestinationSafety(disposition: .blockedTerminal)
    )
    let original = insertable("echo one\necho two\r\n\u{2028}")

    let method = try await service.insertConfirmedMultiline(original)
    #expect(method == .clipboard)
    #expect(original.text == "echo one\necho two\r\n\u{2028}")
    #expect(backend.calls == ["clipboard"])
    #expect(backend.clipboardTexts == ["echo one\necho two"])
}

@Test @MainActor func explicitCopyLeavesTheExactPendingValueOnTheClipboard() throws {
    let backend = MockInsertionBackend()
    let service = TextInsertionService(backend: backend)
    let value = insertable("first\nsecond\n")

    try service.copyToClipboard(value)
    #expect(backend.calls == ["copy"])
    #expect(backend.clipboardTexts == [value.text])
}
