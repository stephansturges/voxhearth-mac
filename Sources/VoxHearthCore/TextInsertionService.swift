import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol TextInsertionBackend: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    func replaceSelectedText(_ text: String) -> Bool
    func postUnicodeText(_ text: String) -> Bool
    func pasteWithSafeClipboardRestore(_ text: String) async throws -> Bool
}

@MainActor
public final class TextInsertionService: TextInserting {
    private let backend: any TextInsertionBackend
    private let logger = PrivacySafeLogger(category: "TextInsertion")

    public convenience init() {
        self.init(backend: MacTextInsertionBackend())
    }

    init(backend: any TextInsertionBackend) {
        self.backend = backend
    }

    public func insert(
        _ text: String,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        guard !text.isEmpty else { throw TextInsertionError.insertionFailed }
        guard backend.isAccessibilityTrusted else {
            throw TextInsertionError.accessibilityPermissionRequired
        }

        if backend.replaceSelectedText(text) {
            logger.info(.textInsertionCompleted)
            return .accessibility
        }

        if backend.postUnicodeText(text) {
            logger.info(.textInsertionCompleted)
            return .unicodeEvents
        }

        guard clipboardFallbackEnabled else {
            throw TextInsertionError.clipboardFallbackDisabled
        }
        guard try await backend.pasteWithSafeClipboardRestore(text) else {
            throw TextInsertionError.insertionFailed
        }
        logger.info(.textInsertionCompleted)
        return .clipboard
    }
}

@MainActor
final class MacTextInsertionBackend: TextInsertionBackend {
    private static let unicodeChunkSize = 32
    private static let clipboardRestoreDelay: Duration = .milliseconds(120)

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func replaceSelectedText(_ text: String) -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return false
        }

        let focusedElement = focusedValue as! AXUIElement
        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        ) == .success, isSettable.boolValue else {
            return false
        }

        return AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
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
