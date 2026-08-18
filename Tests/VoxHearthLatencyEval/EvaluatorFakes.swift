import Dispatch
import Foundation
import VoxHearthCore

enum LatencyEvaluatorError: Error, CustomStringConvertible {
    case concurrentTranscription
    case missingEvent(String)
    case invalidOrdering(String)
    case timeout(String)

    var description: String {
        switch self {
        case .concurrentTranscription: "transcriptions overlapped"
        case let .missingEvent(name): "missing evaluator event: \(name)"
        case let .invalidOrdering(name): "invalid evaluator event ordering: \(name)"
        case let .timeout(state): "timed out waiting for controller state: \(state)"
        }
    }
}

enum EvaluatorEvent: String, CaseIterable, Sendable {
    case cueDispatch
    case captureStartExit
    case recordingObserved
    case release
    case stopEntry
    case stopExit
    case transcribeEntry
    case transcribeExit
    case insertEntry
    case insertExit
    case idleObserved
}

actor EvaluatorEventLog {
    private var values: [EvaluatorEvent: UInt64] = [:]

    func reset() {
        values.removeAll(keepingCapacity: true)
    }

    func stamp(_ event: EvaluatorEvent) {
        values[event] = DispatchTime.now().uptimeNanoseconds
    }

    func value(_ event: EvaluatorEvent) throws -> UInt64 {
        guard let value = values[event] else {
            throw LatencyEvaluatorError.missingEvent(event.rawValue)
        }
        return value
    }

    func has(_ event: EvaluatorEvent) -> Bool {
        values[event] != nil
    }
}

actor EvaluatorGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

actor FixtureCapture: AudioCapturing {
    private let events: EvaluatorEventLog
    private var audio = CapturedAudio(samples: [0], sampleRate: 48_000)
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var snapshotCount = 0
    private(set) var cancelCount = 0

    init(events: EvaluatorEventLog) {
        self.events = events
    }

    func use(_ audio: CapturedAudio) {
        self.audio = audio
    }

    func availableInputDevices() async -> [AudioInputDevice] { [] }

    func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws -> AudioInputSelection {
        _ = inputDeviceUID
        _ = maximumDurationReached
        startCount += 1
        await events.stamp(.captureStartExit)
        return .systemDefault
    }

    func snapshot(maximumDuration: TimeInterval) async -> CapturedAudio? {
        snapshotCount += 1
        guard maximumDuration > 0 else { return nil }
        let maximumSamples = Int(Double(audio.samples.count) * min(1, maximumDuration / audio.duration))
        return CapturedAudio(
            samples: Array(audio.samples.suffix(max(1, maximumSamples))),
            sampleRate: audio.sampleRate
        )
    }

    func stop() async throws -> CapturedAudio {
        await events.stamp(.stopEntry)
        stopCount += 1
        let result = audio
        await events.stamp(.stopExit)
        return result
    }

    func cancel() async {
        cancelCount += 1
    }

    func counts() -> (start: Int, stop: Int, snapshot: Int, cancel: Int) {
        (startCount, stopCount, snapshotCount, cancelCount)
    }
}

actor CountingEngine: LocalTranscriptionEngine {
    private let wrapped: any LocalTranscriptionEngine
    private let events: EvaluatorEventLog
    private var active = false
    private(set) var prepareCount = 0
    private(set) var transcribeCount = 0

    init(wrapping wrapped: any LocalTranscriptionEngine, events: EvaluatorEventLog) {
        self.wrapped = wrapped
        self.events = events
    }

    func prepare(model: TranscriptionModel) async throws {
        prepareCount += 1
        try await wrapped.prepare(model: model)
    }

    func transcribe(
        _ audio: CapturedAudio,
        language: DictationLanguage,
        model: TranscriptionModel
    ) async throws -> String {
        guard !active else { throw LatencyEvaluatorError.concurrentTranscription }
        active = true
        transcribeCount += 1
        let isFinal = await events.has(.release)
        if isFinal { await events.stamp(.transcribeEntry) }
        do {
            let text = try await wrapped.transcribe(audio, language: language, model: model)
            if isFinal { await events.stamp(.transcribeExit) }
            active = false
            return text
        } catch {
            active = false
            throw error
        }
    }

    func counts() -> (prepare: Int, transcribe: Int) {
        (prepareCount, transcribeCount)
    }
}

@MainActor
final class RecordingInserter: TextInserting {
    private let events: EvaluatorEventLog
    var method: TextInsertionMethod
    private(set) var insertedTexts: [String] = []
    private(set) var clipboardFlags: [Bool] = []

    init(events: EvaluatorEventLog, method: TextInsertionMethod) {
        self.events = events
        self.method = method
    }

    func insert(
        _ text: String,
        clipboardFallbackEnabled: Bool
    ) async throws -> TextInsertionMethod {
        await events.stamp(.insertEntry)
        insertedTexts.append(text)
        clipboardFlags.append(clipboardFallbackEnabled)
        await events.stamp(.insertExit)
        return method
    }
}

@MainActor
final class EvaluatorHotkey: GlobalHotkeyRegistering {
    private var handler: (@MainActor @Sendable (GlobalHotkeyPhase) -> Void)?

    func register(
        _ configuration: HotkeyConfiguration,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) throws {
        _ = configuration
        handler = onEvent
    }

    func unregister() {
        handler = nil
    }

    func emit(_ phase: GlobalHotkeyPhase) {
        handler?(phase)
    }
}

@MainActor
final class EvaluatorPointer: GlobalPointerButtonRegistering {
    private var handler: (@MainActor @Sendable (GlobalHotkeyPhase) -> Void)?

    func register(
        buttonNumber: UInt32?,
        onEvent: @escaping @MainActor @Sendable (GlobalHotkeyPhase) -> Void
    ) {
        handler = buttonNumber == nil ? nil : onEvent
    }

    func unregister() {
        handler = nil
    }

    func emit(_ phase: GlobalHotkeyPhase) {
        handler?(phase)
    }
}
