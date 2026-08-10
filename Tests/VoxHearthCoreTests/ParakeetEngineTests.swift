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
