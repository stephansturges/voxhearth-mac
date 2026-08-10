import Testing
@testable import FluidAudioLocal

@Test func vendoredLoggerNeverEvaluatesMessageContent() {
    var evaluationCount = 0
    func sensitiveMessage() -> String {
        evaluationCount += 1
        return "content that must never be materialized"
    }

    let logger = AppLogger(category: "PrivacyTest")
    logger.debug(sensitiveMessage())
    logger.info(sensitiveMessage())
    logger.notice(sensitiveMessage())
    logger.warning(sensitiveMessage())
    logger.error(sensitiveMessage())
    logger.fault(sensitiveMessage())

    #expect(evaluationCount == 0)
}

@Test func vendoredChunkProcessorReadsOnlyItsMemoryBuffer() throws {
    let processor = ChunkProcessor(audioSamples: [1, 2, 3, 4])

    #expect(try processor.readSamples(offset: 1, count: 2) == [2, 3])
    #expect(throws: ASRError.self) {
        try processor.readSamples(offset: -1, count: 1)
    }
    #expect(throws: ASRError.self) {
        try processor.readSamples(offset: 3, count: 2)
    }
}
