import Foundation

public enum PendingInsertionReason: Equatable, Sendable {
    case insertionFailed
    case insertionUncertain
    case multilineClipboardDisabled
    case blockedTerminal
}

public struct PendingInsertionEntry: Identifiable, Equatable, Sendable {
    public var id: DictationSessionID { transcript.sessionID }
    public let transcript: InsertableTranscript
    public let reason: PendingInsertionReason
    public let createdAt: Date
    public let expiresAt: Date

    public var text: String { transcript.text }

    init(
        transcript: InsertableTranscript,
        reason: PendingInsertionReason,
        createdAt: Date,
        expiresAt: Date
    ) {
        self.transcript = transcript
        self.reason = reason
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

/// A small, memory-only ownership boundary for text that did not reach its
/// destination. Entries never migrate between dictation session identifiers.
public struct PendingInsertionStore: Equatable, Sendable {
    public let capacity: Int
    private(set) public var entries: [PendingInsertionEntry] = []

    public init(capacity: Int = 3) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var isFull: Bool { entries.count >= capacity }

    public func entry(for sessionID: DictationSessionID) -> PendingInsertionEntry? {
        entries.first { $0.id == sessionID }
    }

    @discardableResult
    public mutating func retain(
        _ transcript: InsertableTranscript,
        reason: PendingInsertionReason,
        now: Date = Date(),
        lifetime: TimeInterval = 120
    ) -> Bool {
        precondition(lifetime >= 0)
        expire(at: now)
        let entry = PendingInsertionEntry(
            transcript: transcript,
            reason: reason,
            createdAt: now,
            expiresAt: now.addingTimeInterval(lifetime)
        )
        if let index = entries.firstIndex(where: { $0.id == transcript.sessionID }) {
            entries[index] = entry
            return true
        }
        guard !isFull else { return false }
        entries.append(entry)
        return true
    }

    @discardableResult
    public mutating func remove(
        sessionID: DictationSessionID
    ) -> PendingInsertionEntry? {
        guard let index = entries.firstIndex(where: { $0.id == sessionID }) else {
            return nil
        }
        return entries.remove(at: index)
    }

    @discardableResult
    public mutating func expire(at now: Date = Date()) -> [PendingInsertionEntry] {
        let expired = entries.filter { $0.expiresAt <= now }
        guard !expired.isEmpty else { return [] }
        let expiredIDs = Set(expired.map(\.id))
        entries.removeAll { expiredIDs.contains($0.id) }
        return expired
    }
}
