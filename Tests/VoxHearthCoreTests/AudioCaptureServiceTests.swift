@preconcurrency import AVFoundation
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

@Test func audioTapProcessorAppendsMonoWithoutChangingSamples() throws {
    let format = try #require(
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )
    )
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4
    let channel = try #require(buffer.floatChannelData?[0])
    let samples: [Float] = [0.25, -0.5, 0.75, 1]
    channel.update(from: samples, count: samples.count)
    let accumulator = AudioSampleAccumulator(sampleRate: 48_000, maximumDuration: 1)
    let processor = AudioTapSampleProcessor(initialFrameCapacity: 4)

    #expect(!processor.append(buffer, to: accumulator))
    #expect(accumulator.snapshot() == [0.25, -0.5, 0.75, 1])
}

@Test func audioTapProcessorReusesMixdownAndSignalsLimitOnce() throws {
    let format = try #require(
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 4,
            channels: 2,
            interleaved: false
        )
    )
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4
    let channels = try #require(buffer.floatChannelData)
    let left: [Float] = [1, 0.5, -1, 0]
    let right: [Float] = [-1, 0.5, 1, 1]
    channels[0].update(from: left, count: left.count)
    channels[1].update(from: right, count: right.count)
    let accumulator = AudioSampleAccumulator(sampleRate: 4, maximumDuration: 1)
    let processor = AudioTapSampleProcessor(initialFrameCapacity: 2)

    #expect(processor.append(buffer, to: accumulator))
    #expect(!processor.append(buffer, to: accumulator))
    #expect(accumulator.snapshot() == [0, 0.5, 0, 0.5])
}

@Test func audioTapProcessorPreservesLegacyMixdownOperationOrder() throws {
    let format = try #require(
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )
    )
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4
    let channels = try #require(buffer.floatChannelData)
    let input: [[Float]] = [
        [0.1, .greatestFiniteMagnitude, -0.333_333_34, 0.000_000_1],
        [0.2, .greatestFiniteMagnitude, 0.666_666_7, -0.000_000_2],
    ]
    for channel in input.indices {
        channels[channel].update(from: input[channel], count: input[channel].count)
    }

    // This is the exact arithmetic performed by the former implementation.
    let scale = Float(1) / Float(input.count)
    var expected = [Float](repeating: 0, count: 4)
    for channel in input.indices {
        for frame in expected.indices {
            expected[frame] += input[channel][frame] * scale
        }
    }

    let accumulator = AudioSampleAccumulator(sampleRate: 48_000, maximumDuration: 1)
    let processor = AudioTapSampleProcessor(initialFrameCapacity: 4)

    #expect(!processor.append(buffer, to: accumulator))
    #expect(accumulator.snapshot() == expected)
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
