@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import os

/// Thread-safe, memory-only audio storage shared with AVAudioEngine's render callback.
final class AudioSampleAccumulator: @unchecked Sendable {
    private struct BorrowedSamples: @unchecked Sendable {
        let baseAddress: UnsafePointer<Float>?
        let count: Int
    }

    struct State: Sendable {
        var samples: [Float] = []
        var didSignalLimit = false
    }

    let sampleRate: Double
    let maximumSampleCount: Int
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(sampleRate: Double, maximumDuration: TimeInterval) {
        self.sampleRate = sampleRate
        maximumSampleCount = max(1, Int((sampleRate * maximumDuration).rounded(.down)))
    }

    /// Returns true exactly once, when the duration cap is first reached.
    @discardableResult
    func append(_ newSamples: [Float]) -> Bool {
        newSamples.withUnsafeBufferPointer { append($0) }
    }

    /// Pointer overload used by the audio render callback so it does not need
    /// to materialize a transient `[Float]` for every input buffer.
    @discardableResult
    func append(_ newSamples: UnsafeBufferPointer<Float>) -> Bool {
        let borrowed = BorrowedSamples(
            baseAddress: newSamples.baseAddress,
            count: newSamples.count
        )
        return state.withLock { state in
            let newSamples = UnsafeBufferPointer(
                start: borrowed.baseAddress,
                count: borrowed.count
            )
            guard state.samples.count < maximumSampleCount else { return false }
            let remaining = maximumSampleCount - state.samples.count
            state.samples.append(contentsOf: newSamples.prefix(remaining))
            guard state.samples.count == maximumSampleCount, !state.didSignalLimit else {
                return false
            }
            state.didSignalLimit = true
            return true
        }
    }

    func snapshot() -> [Float] {
        state.withLock { $0.samples }
    }

    func trailingSnapshot(maximumSampleCount: Int) -> [Float] {
        state.withLock { state in
            Array(state.samples.suffix(max(1, maximumSampleCount)))
        }
    }
}

/// Reuses one bounded mixdown scratch buffer for the lifetime of an installed
/// tap. AVAudioEngine invokes one tap serially; this object is captured by only
/// that callback and never crosses into controller state.
final class AudioTapSampleProcessor: @unchecked Sendable {
    private var mixdownScratch: [Float]

    init(initialFrameCapacity: Int) {
        mixdownScratch = [Float](repeating: 0, count: max(1, initialFrameCapacity))
    }

    @discardableResult
    func append(
        _ buffer: AVAudioPCMBuffer,
        to accumulator: AudioSampleAccumulator
    ) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return false }

        if channelCount == 1 {
            return accumulator.append(
                UnsafeBufferPointer(start: channels[0], count: frameCount)
            )
        }

        if mixdownScratch.count < frameCount {
            mixdownScratch = [Float](repeating: 0, count: frameCount)
        }
        let scale = 1 / Float(channelCount)
        return mixdownScratch.withUnsafeMutableBufferPointer { scratch in
            for frame in 0..<frameCount {
                var mixed: Float = 0
                for channel in 0..<channelCount {
                    // Preserve the former mixdown's floating-point operation
                    // order exactly: scale each channel contribution before
                    // accumulation rather than scaling the final sum.
                    mixed += channels[channel][frame] * scale
                }
                scratch[frame] = mixed
            }
            return accumulator.append(
                UnsafeBufferPointer(rebasing: scratch[..<frameCount])
            )
        }
    }
}

public actor AudioCaptureService: AudioCapturing {
    public static let maximumDuration: TimeInterval = 10 * 60
    private static let tapBufferSize: AVAudioFrameCount = 1_024

    private var engine: AVAudioEngine?
    private var accumulator: AudioSampleAccumulator?
    private let logger = PrivacySafeLogger(category: "AudioCapture")
    private let signposter = PrivacySafeSignposter(category: "AudioCapture")

    public init() {}

    public func availableInputDevices() async -> [AudioInputDevice] {
        Self.inputDevices()
    }

    public func start(
        inputDeviceUID: String?,
        maximumDurationReached: @escaping @Sendable () async -> Void
    ) async throws -> AudioInputSelection {
        logger.info(.audioCaptureStartEntered)
        let captureStartInterval = signposter.begin(.audioCaptureStartEntered)
        defer { signposter.end(.audioCaptureStarted, captureStartInterval) }
        guard engine == nil else { throw AudioCaptureError.alreadyRecording }
        guard await Self.requestMicrophonePermission() else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        var newEngine = AVAudioEngine()
        var inputNode = newEngine.inputNode
        var inputSelection = AudioInputSelection.systemDefault

        if let inputDeviceUID {
            if let deviceID = Self.audioDeviceID(forUID: inputDeviceUID),
               Self.hasInputStreams(deviceID) {
                do {
                    try Self.selectInputDevice(deviceID, on: inputNode)
                    inputSelection = .requestedDevice
                } catch {
                    // Recreate the engine so a failed device selection cannot
                    // leave partially configured Audio Unit state behind.
                    newEngine = AVAudioEngine()
                    inputNode = newEngine.inputNode
                    inputSelection = .fellBackToSystemDefault
                }
            } else {
                inputSelection = .fellBackToSystemDefault
            }
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidInputFormat
        }
        guard let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidInputFormat
        }

        let newAccumulator = AudioSampleAccumulator(
            sampleRate: tapFormat.sampleRate,
            maximumDuration: Self.maximumDuration
        )
        let sampleProcessor = AudioTapSampleProcessor(
            initialFrameCapacity: Int(Self.tapBufferSize)
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: tapFormat
        ) { buffer, _ in
            if sampleProcessor.append(buffer, to: newAccumulator) {
                Task {
                    await maximumDurationReached()
                }
            }
        }

        do {
            newEngine.prepare()
            try newEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            newEngine.stop()
            logger.error(.operationFailed, error: error)
            throw AudioCaptureError.engineStartFailed
        }

        engine = newEngine
        accumulator = newAccumulator
        logger.info(.audioCaptureStarted)
        return inputSelection
    }

    public func stop() async throws -> CapturedAudio {
        logger.info(.audioCaptureStopEntered)
        let captureStopInterval = signposter.begin(.audioCaptureStopEntered)
        defer { signposter.end(.audioCaptureStopped, captureStopInterval) }
        guard let activeEngine = engine, let activeAccumulator = accumulator else {
            throw AudioCaptureError.notRecording
        }

        activeEngine.inputNode.removeTap(onBus: 0)
        activeEngine.stop()
        engine = nil
        accumulator = nil

        let samples = activeAccumulator.snapshot()
        guard !samples.isEmpty else { throw AudioCaptureError.noAudioCaptured }
        logger.info(.audioCaptureStopped)
        return CapturedAudio(samples: samples, sampleRate: activeAccumulator.sampleRate)
    }

    public func snapshot(maximumDuration: TimeInterval) async -> CapturedAudio? {
        guard engine != nil, let activeAccumulator = accumulator else { return nil }
        guard maximumDuration.isFinite, maximumDuration > 0 else { return nil }
        let boundedSampleCount = min(
            Double(activeAccumulator.maximumSampleCount),
            activeAccumulator.sampleRate * maximumDuration
        )
        let maximumSampleCount = max(
            1,
            Int(boundedSampleCount.rounded(.down))
        )
        logger.info(.audioSnapshotLockEntered)
        let samples = activeAccumulator.trailingSnapshot(
            maximumSampleCount: maximumSampleCount
        )
        logger.info(.audioSnapshotCopyCompleted)
        guard !samples.isEmpty else { return nil }
        return CapturedAudio(samples: samples, sampleRate: activeAccumulator.sampleRate)
    }

    public func cancel() async {
        guard let activeEngine = engine else { return }
        activeEngine.inputNode.removeTap(onBus: 0)
        activeEngine.stop()
        engine = nil
        accumulator = nil
        logger.info(.audioCaptureCancelled)
    }

    private static func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            true
        case .denied:
            false
        case .undetermined:
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            false
        }
    }

    private static func selectInputDevice(
        _ deviceID: AudioDeviceID,
        on inputNode: AVAudioInputNode
    ) throws {
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioCaptureError.microphoneUnavailable
        }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw AudioCaptureError.microphoneUnavailable }
    }

    private static func inputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var identifiers = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &identifiers
        ) == noErr else { return [] }

        return identifiers.compactMap { identifier in
            guard hasInputStreams(identifier),
                  let uid = stringProperty(
                      selector: kAudioDevicePropertyDeviceUID,
                      deviceID: identifier
                  ),
                  let name = stringProperty(
                      selector: kAudioObjectPropertyName,
                      deviceID: identifier
                  ) else { return nil }
            return AudioInputDevice(uid: uid, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func stringProperty(
        selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedUID: Unmanaged<CFString>? = Unmanaged.passUnretained(uid as CFString)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<Unmanaged<CFString>?>.size),
            &unmanagedUID,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }
}
