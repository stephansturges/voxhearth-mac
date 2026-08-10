@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import VoxHearthCore

@Test func parakeetValidationFailsClosedForMissingAssets() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(throws: ParakeetEngineError.missingModelAsset("Preprocessor.mlmodelc")) {
        try ParakeetEngine.validateAssets(in: directory)
    }
}

@Test func parakeetValidationAcceptsOnlyCompleteLocalAssetSet() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for assetName in ParakeetEngine.requiredAssetNames {
        let assetURL = directory.appendingPathComponent(assetName)
        if assetName.hasSuffix(".mlmodelc") {
            try FileManager.default.createDirectory(at: assetURL, withIntermediateDirectories: true)
        } else {
            try Data("{}".utf8).write(to: assetURL)
        }
    }

    try ParakeetEngine.validateAssets(in: directory)
}

@Test func vocabularyLoaderRejectsEmptyOrMalformedData() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try Data("{}".utf8).write(to: fileURL)
    #expect(throws: ParakeetEngineError.invalidVocabulary) {
        _ = try ParakeetEngine.loadVocabulary(from: fileURL)
    }

    try Data("not-json".utf8).write(to: fileURL)
    #expect(throws: ParakeetEngineError.invalidVocabulary) {
        _ = try ParakeetEngine.loadVocabulary(from: fileURL)
    }
}

@Test func vocabularyLoaderMapsNumericTokenIdentifiers() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    try Data(#"{"0":"<blank>","42":"▁home"}"#.utf8).write(to: fileURL)

    let vocabulary = try ParakeetEngine.loadVocabulary(from: fileURL)
    #expect(vocabulary[0] == "<blank>")
    #expect(vocabulary[42] == "▁home")
}

/// Opt-in end-to-end gate used by `scripts/model-smoke.sh` after the locked
/// model has been staged. Normal unit-test runs do not require the large model.
@Test func realModelSmokeTranscribesGeneratedSpeech() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["VOXHEARTH_MODEL_SMOKE"] == "1" else { return }

    let modelPath = try #require(environment["VOXHEARTH_MODEL_SMOKE_MODEL_DIR"])
    let audioPath = try #require(environment["VOXHEARTH_MODEL_SMOKE_AUDIO_FILE"])
    let audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
    #expect(audioFile.length > 0)

    let frameCapacity = AVAudioFrameCount(audioFile.length)
    let buffer = try #require(
        AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCapacity)
    )
    try audioFile.read(into: buffer)
    let channel = try #require(buffer.floatChannelData?[0])
    let samples = Array(
        UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
    )
    #expect(!samples.isEmpty)

    let engine = ParakeetEngine(modelDirectoryURL: URL(fileURLWithPath: modelPath))
    let transcript = try await engine.transcribe(
        CapturedAudio(samples: samples, sampleRate: audioFile.processingFormat.sampleRate),
        language: .english
    )
    #expect(!transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}
