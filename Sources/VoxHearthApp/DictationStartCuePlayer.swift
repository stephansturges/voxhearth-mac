import AppKit
import Foundation
import VoxHearthCore

/// Plays a deliberately short, low-volume acknowledgement tone entirely from
/// memory. Waiting for the 45 ms tone to finish before capture prevents the
/// Mac's speakers from feeding the cue back into the transcript.
@MainActor
final class DictationStartCuePlayer {
    private let sound: NSSound?
    private let logger = PrivacySafeLogger(category: "StartCue")

    init() {
        sound = NSSound(data: Self.makeToneData())
        sound?.volume = 0.22
    }

    func play() async {
        guard let sound else { return }
        sound.stop()
        sound.currentTime = 0
        logger.info(.startCuePlayEntered)
        sound.play()
        logger.info(.startCuePlayReturned)
        try? await Task.sleep(for: .milliseconds(55))
        logger.info(.startCueDelayResumed)
    }

    nonisolated static func makeToneData(
        sampleRate: Int = 44_100,
        duration: Double = 0.045,
        frequency: Double = 880
    ) -> Data {
        let sampleCount = max(1, Int(Double(sampleRate) * duration))
        let pcmByteCount = sampleCount * MemoryLayout<Int16>.size
        var data = Data()

        func appendASCII(_ value: String) {
            data.append(contentsOf: value.utf8)
        }
        func appendUInt16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + pcmByteCount))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * MemoryLayout<Int16>.size))
        appendUInt16(UInt16(MemoryLayout<Int16>.size))
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(pcmByteCount))

        let fadeSamples = max(1, Int(Double(sampleRate) * 0.006))
        for index in 0..<sampleCount {
            let attack = min(1, Double(index) / Double(fadeSamples))
            let release = min(1, Double(sampleCount - index - 1) / Double(fadeSamples))
            let envelope = min(attack, release)
            let phase = 2 * Double.pi * frequency * Double(index) / Double(sampleRate)
            let value = Int16((sin(phase) * envelope * 0.42 * Double(Int16.max)).rounded())
            appendUInt16(UInt16(bitPattern: value))
        }

        return data
    }
}
