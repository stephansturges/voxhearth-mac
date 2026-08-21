import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol TextInsertionBackend: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    func replaceSelectedText(_ text: String) -> AccessibilityInsertionOutcome
    func postUnicodeText(_ text: String) -> Bool
    func pasteWithSafeClipboardRestore(_ text: String) async throws -> Bool
}

enum AccessibilityInsertionOutcome: Equatable, Sendable {
    case inserted
    case unavailable
    case ambiguous
}

@MainActor
public final class TextInsertionService: TextInserting {
    private let backend: any TextInsertionBackend
    private let logger = PrivacySafeLogger(category: "TextInsertion")
    private let signposter = PrivacySafeSignposter(category: "TextInsertion")

    public convenience init() {
        self.init(backend: MacTextInsertionBackend())
    }

    init(backend: any TextInsertionBackend) {
        self.backend = backend
    }

    public func insert(
        _ transcript: InsertableTranscript,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        let text = transcript.text
        guard !text.isEmpty else { throw TextInsertionError.insertionFailed }
        guard backend.isAccessibilityTrusted else {
            throw TextInsertionError.accessibilityPermissionRequired
        }

        switch backend.replaceSelectedText(text) {
        case .inserted:
            logger.info(.textInsertionCompleted)
            return .accessibility
        case .ambiguous:
            logger.info(.accessibilityInsertionUncertain)
            throw TextInsertionError.insertionUncertain
        case .unavailable:
            logger.info(.accessibilityInsertionUnavailable)
        }

        logger.info(.unicodeInsertionStarted)
        let unicodeInterval = signposter.begin(.unicodeInsertionStarted)
        if backend.postUnicodeText(text) {
            // CGEvent posting confirms dispatch only. macOS provides no target
            // application acknowledgement for this fallback.
            signposter.end(.unicodeInsertionDispatched, unicodeInterval)
            logger.info(.unicodeInsertionDispatched)
            logger.info(.textInsertionCompleted)
            return .unicodeEvents
        }
        signposter.end(.unicodeInsertionDispatched, unicodeInterval)

        guard clipboardFallbackEnabled else {
            throw TextInsertionError.clipboardFallbackDisabled
        }
        logger.info(.clipboardInsertionStarted)
        let clipboardInterval = signposter.begin(.clipboardInsertionStarted)
        defer { signposter.end(.clipboardInsertionCompleted, clipboardInterval) }
        guard try await backend.pasteWithSafeClipboardRestore(text) else {
            throw TextInsertionError.insertionFailed
        }
        logger.info(.clipboardInsertionCompleted)
        logger.info(.textInsertionCompleted)
        return .clipboard
    }
}

enum DiagnosticInsertionMode: Equatable, Sendable {
    case accessibilityFirst
    case unicodeFirst
}

@MainActor
struct AccessibilityMessaging {
    let setMessagingTimeout: (AXUIElement, Float) -> AXError
    let copyFocusedElement: (AXUIElement) -> (AXError, AXUIElement?)
    let isSelectedTextSettable: (AXUIElement) -> (AXError, Bool)
    let setSelectedText: (AXUIElement, String) -> AXError

    static let live = AccessibilityMessaging(
        setMessagingTimeout: { element, timeout in
            AXUIElementSetMessagingTimeout(element, timeout)
        },
        copyFocusedElement: { systemWideElement in
            var focusedValue: AnyObject?
            let status = AXUIElementCopyAttributeValue(
                systemWideElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue
            )
            guard status == .success,
                  let focusedValue,
                  CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
                return (status, nil)
            }
            return (status, (focusedValue as! AXUIElement))
        },
        isSelectedTextSettable: { focusedElement in
            var isSettable = DarwinBoolean(false)
            let status = AXUIElementIsAttributeSettable(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                &isSettable
            )
            return (status, isSettable.boolValue)
        },
        setSelectedText: { focusedElement, text in
            AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
        }
    )
}

@MainActor
final class MacTextInsertionBackend: TextInsertionBackend {
    private static let unicodeChunkSize = 32
    private static let clipboardRestoreDelay: Duration = .milliseconds(120)
    static let accessibilityQueryTimeout: Float = 0.35
    static let accessibilitySetTimeout: Float = 0.60

    private let messaging: AccessibilityMessaging
    private let insertionMode: DiagnosticInsertionMode
    private let logger = PrivacySafeLogger(category: "TextInsertion")
    private let signposter = PrivacySafeSignposter(category: "TextInsertion")

    init(
        messaging: AccessibilityMessaging = .live,
        mode: DiagnosticInsertionMode? = nil
    ) {
        self.messaging = messaging
        if let mode {
            insertionMode = mode
        } else if UserDefaults.standard.string(
            forKey: "VoxHearth.diagnostics.insertionMode"
        ) == "unicode-first" {
            insertionMode = .unicodeFirst
        } else {
            insertionMode = .accessibilityFirst
        }
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func replaceSelectedText(_ text: String) -> AccessibilityInsertionOutcome {
        guard insertionMode == .accessibilityFirst else { return .unavailable }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard messaging.setMessagingTimeout(
            systemWideElement,
            Self.accessibilityQueryTimeout
        ) == .success else {
            return .unavailable
        }
        defer { _ = messaging.setMessagingTimeout(systemWideElement, 0) }

        logger.info(.accessibilityFocusQueryStarted)
        let focusInterval = signposter.begin(.accessibilityFocusQueryStarted)
        let (focusStatus, focusedElement) = messaging.copyFocusedElement(systemWideElement)
        signposter.end(.accessibilityFocusQueryCompleted, focusInterval)
        logger.info(.accessibilityFocusQueryCompleted)
        guard focusStatus == .success, let focusedElement else {
            return .unavailable
        }

        guard messaging.setMessagingTimeout(
            focusedElement,
            Self.accessibilityQueryTimeout
        ) == .success else {
            return .unavailable
        }

        logger.info(.accessibilitySettableQueryStarted)
        let settableInterval = signposter.begin(.accessibilitySettableQueryStarted)
        let (settableStatus, isSettable) = messaging.isSelectedTextSettable(focusedElement)
        signposter.end(.accessibilitySettableQueryCompleted, settableInterval)
        logger.info(.accessibilitySettableQueryCompleted)
        guard settableStatus == .success, isSettable else {
            return .unavailable
        }

        guard messaging.setMessagingTimeout(
            focusedElement,
            Self.accessibilitySetTimeout
        ) == .success else {
            return .unavailable
        }

        logger.info(.accessibilitySetValueStarted)
        let setValueInterval = signposter.begin(.accessibilitySetValueStarted)
        let setValueStatus = messaging.setSelectedText(focusedElement, text)
        signposter.end(.accessibilitySetValueCompleted, setValueInterval)
        logger.info(.accessibilitySetValueCompleted)

        let outcome = Self.classifySetOutcome(setValueStatus)
        switch outcome {
        case .inserted:
            break
        case .ambiguous:
            logger.info(.accessibilitySetValueTimedOut)
        case .unavailable:
            logger.info(.accessibilitySetValueRefused)
        }
        return outcome
    }

    static func classifySetOutcome(_ status: AXError) -> AccessibilityInsertionOutcome {
        switch status {
        case .success:
            .inserted
        case .cannotComplete:
            .ambiguous
        default:
            .unavailable
        }
    }

    func postUnicodeText(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        for chunk in Self.unicodeChunks(text, maximumUTF16Units: Self.unicodeChunkSize) {
            let utf16 = Array(chunk.utf16)
            guard !utf16.isEmpty,
                  let keyDown = CGEvent(
                      keyboardEventSource: source,
                      virtualKey: 0,
                      keyDown: true
                  ),
                  let keyUp = CGEvent(
                      keyboardEventSource: source,
                      virtualKey: 0,
                      keyDown: false
                  ) else { return false }

            utf16.withUnsafeBufferPointer { characters in
                guard let baseAddress = characters.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(
                    stringLength: characters.count,
                    unicodeString: baseAddress
                )
                keyUp.keyboardSetUnicodeString(
                    stringLength: characters.count,
                    unicodeString: baseAddress
                )
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    func pasteWithSafeClipboardRestore(_ text: String) async throws -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = try PasteboardSnapshot(pasteboard: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            _ = snapshot.restore(to: pasteboard)
            throw TextInsertionError.clipboardWriteFailed
        }
        let ownedChangeCount = pasteboard.changeCount

        guard Self.postCommandV() else {
            if pasteboard.changeCount == ownedChangeCount {
                _ = snapshot.restore(to: pasteboard)
            }
            throw TextInsertionError.pasteEventCreationFailed
        }

        try? await Task.sleep(for: Self.clipboardRestoreDelay)
        // Another app or the user changed the clipboard after our write. Their
        // newer content wins; restoring here would destroy it.
        guard pasteboard.changeCount == ownedChangeCount else { return true }
        guard snapshot.restore(to: pasteboard) else {
            throw TextInsertionError.clipboardWriteFailed
        }
        return true
    }

    static func unicodeChunks(
        _ text: String,
        maximumUTF16Units: Int
    ) -> [String] {
        guard maximumUTF16Units > 0, !text.isEmpty else { return [] }
        var chunks: [String] = []
        var current = ""
        var currentCount = 0

        for character in text {
            let characterText = String(character)
            let count = characterText.utf16.count
            if currentCount > 0, currentCount + count > maximumUTF16Units {
                chunks.append(current)
                current = ""
                currentCount = 0
            }
            current.append(character)
            currentCount += count
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 9,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 9,
                  keyDown: false
              ) else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

struct PasteboardSnapshot {
    typealias Item = [(type: NSPasteboard.PasteboardType, data: Data)]
    let items: [Item]

    @MainActor
    init(pasteboard: NSPasteboard) throws {
        try self.init(items: pasteboard.pasteboardItems ?? [])
    }

    init(items pasteboardItems: [NSPasteboardItem]) throws {
        items = try pasteboardItems.map { pasteboardItem in
            try pasteboardItem.types.map { type in
                guard let data = pasteboardItem.data(forType: type) else {
                    throw TextInsertionError.clipboardSnapshotFailed
                }
                return (type, data)
            }
        }
    }

    @MainActor
    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else { return true }

        return pasteboard.writeObjects(makePasteboardItems())
    }

    func makePasteboardItems() -> [NSPasteboardItem] {
        items.map { snapshotItem in
            let pasteboardItem = NSPasteboardItem()
            for entry in snapshotItem {
                pasteboardItem.setData(entry.data, forType: entry.type)
            }
            return pasteboardItem
        }
    }
}
