import Foundation
import Testing
@testable import VoxHearthCore

@Test func audioAccumulatorCapsAtTenMinutesAndSignalsOnce() {
    let accumulator = AudioSampleAccumulator(sampleRate: 2, maximumDuration: 3)

    #expect(accumulator.append([0, 1, 2]) == false)
    #expect(accumulator.append([3, 4, 5, 6]) == true)
    #expect(accumulator.append([7, 8]) == false)
    #expect(accumulator.snapshot() == [0, 1, 2, 3, 4, 5])
    #expect(accumulator.trailingSnapshot(maximumSampleCount: 3) == [3, 4, 5])
}

@Test func capturedAudioDurationUsesItsActualSampleRate() {
    let audio = CapturedAudio(samples: [0, 0, 0, 0], sampleRate: 2)
    #expect(audio.duration == 2)
}

@Test func resamplerReturnsInputUnchangedAtTargetRate() throws {
    let samples: [Float] = [0, 0.25, -0.5, 1]
    #expect(try PCMResampler.resample(samples, from: 16_000, to: 16_000) == samples)
}

@Test func resamplerProducesFiniteMonoSamples() throws {
    let samples = (0..<4_800).map { index in
        Float(sin(Double(index) * 0.03))
    }
    let converted = try PCMResampler.resample(samples, from: 48_000, to: 16_000)
    #expect(converted.count > 1_500)
    #expect(converted.count < 1_700)
    #expect(converted.allSatisfy { $0.isFinite })
}
