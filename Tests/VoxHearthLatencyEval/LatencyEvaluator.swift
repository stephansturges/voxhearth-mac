@preconcurrency import AVFoundation
import Darwin
import Foundation
import Testing
import VoxHearthCore

private struct FixtureManifest: Decodable {
    let schemaVersion: Int
    let fixtures: [Fixture]

    struct Fixture: Decodable {
        let id: String
        let file: String
        let text: String
        let language: String
        let role: String
    }
}

private struct LatencySample: Codable {
    let repeatIndex: Int
    let profile: String
    let fixtureID: String
    let model: String
    let language: String
    let classification: String
    let scored: Bool
    let cueDispatchMs: Double
    let captureStartCompletionMs: Double
    let audioStopEntryMs: Double
    let visibleTextDispatchMs: Double
    let segmentsMs: [String: Double]
    let transcript: String
}

private struct ResourceSample: Codable {
    let cpuSeconds: Double
    let peakResidentBytes: UInt64
}

private struct PartialResult: Codable {
    let schemaVersion: Int
    let gitCommit: String
    let dirty: Bool
    let profile: String
    let repeatIndex: Int
    let digests: [String: String]
    let environment: [String: String]
    let samples: [LatencySample]
    let resources: ResourceSample
    let counts: [String: Int]
}

@Test @MainActor
func latencyEvaluator() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["VOXHEARTH_LATENCY_EVAL"] == "1" else { return }

    let repoRoot = try requiredURL("VOXHEARTH_LATENCY_REPO_ROOT", environment: environment)
    let outputURL = try requiredURL("VOXHEARTH_LATENCY_EVAL_OUTPUT", environment: environment)
    let multilingualRoot = try requiredURL(
        "VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT",
        environment: environment
    )
    let compactRoot = try requiredURL(
        "VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT",
        environment: environment
    )
    let profile = environment["VOXHEARTH_LATENCY_PROFILE"] ?? "P0"
    let repeatIndex = Int(environment["VOXHEARTH_LATENCY_REPEAT_INDEX"] ?? "0") ?? 0

    let manifestURL = repoRoot.appendingPathComponent("Research/latency/fixtures.manifest.json")
    let manifest = try JSONDecoder().decode(
        FixtureManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    #expect(manifest.schemaVersion == 1)

    let events = EvaluatorEventLog()
    let capture = FixtureCapture(events: events)
    let realEngine = ParakeetEngine(
        multilingualModelDirectoryURL: multilingualRoot,
        compactEnglishModelDirectoryURL: compactRoot
    )
    let engine = CountingEngine(wrapping: realEngine, events: events)
    let inserter = RecordingInserter(
        events: events,
        method: profile == "P3" ? .clipboard : (profile == "P4" ? .unicodeEvents : .accessibility)
    )
    let hotkey = EvaluatorHotkey()
    let pointer = EvaluatorPointer()
    var settings = AppSettings(
        pointerButton: profile == "P4" ? 4 : nil,
        transcriptionModel: profile == "P2" ? .compactEnglish : .multilingual,
        language: .english,
        liveTranscriptOverlayEnabled: profile == "P1",
        clipboardCompatibilityEnabled: profile == "P3"
    )
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: capture,
        textInserter: inserter,
        hotkeyService: hotkey,
        pointerButtonService: pointer
    )
    controller.onStartCue = { await events.stamp(.cueDispatch) }
    try controller.activate()
    defer { controller.deactivate() }

    if profile == "P4" {
        let cueGate = EvaluatorGate()
        controller.onStartCue = {
            await events.stamp(.cueDispatch)
            await cueGate.wait()
        }
        hotkey.emit(.pressed)
        try await waitForState(.preparing, controller: controller)
        hotkey.emit(.released)
        await cueGate.open()
        try await waitForState(.idle, controller: controller)
        #expect(await capture.counts().cancel > 0)
        controller.onStartCue = { await events.stamp(.cueDispatch) }
    }

    let selectedFixtures: [FixtureManifest.Fixture]
    if profile == "P4" {
        selectedFixtures = manifest.fixtures.filter { $0.role == "guardrail" }
    } else if profile == "P5" {
        selectedFixtures = Array(manifest.fixtures.filter { $0.role == "scored" }.prefix(2))
    } else {
        selectedFixtures = manifest.fixtures.filter { $0.role == "scored" }
    }
    #expect(!selectedFixtures.isEmpty)

    if profile != "P5" {
        await controller.prepareEngine()
        #expect(controller.state == .idle)
    }

    let usageStart = currentResourceUsage()
    var samples: [LatencySample] = []
    for (index, fixture) in selectedFixtures.enumerated() {
        if profile == "P5", index == 1 {
            settings.transcriptionModel = .compactEnglish
            settings.language = .english
            try controller.applySettings(settings)
        } else if fixture.language == "fr" {
            settings.language = .french
            try controller.applySettings(settings)
        }

        let audio = try loadAudio(
            repoRoot.appendingPathComponent("Research/latency/fixtures/\(fixture.file)")
        )
        await capture.use(audio)
        await events.reset()

        let press = DispatchTime.now().uptimeNanoseconds
        if profile == "P4", index.isMultiple(of: 2) {
            pointer.emit(.pressed)
        } else {
            hotkey.emit(.pressed)
        }
        try await waitForState(.recording, controller: controller)
        await events.stamp(.recordingObserved)

        let hold: Duration = profile == "P1" ? .seconds(2) : .milliseconds(250)
        try await Task.sleep(for: hold)
        await events.stamp(.release)
        if profile == "P4", index.isMultiple(of: 2) {
            pointer.emit(.released)
        } else {
            hotkey.emit(.released)
        }
        try await waitForState(.idle, controller: controller)
        await events.stamp(.idleObserved)

        let classification: String
        let scored: Bool
        if profile == "P0", index == 0 {
            classification = "process-warmup"
            scored = false
        } else if profile == "P0" {
            classification = "warm"
            scored = true
        } else if profile == "P5" {
            classification = index == 0 ? "cold-launch" : "cold-model-switch"
            scored = false
        } else {
            classification = "guardrail"
            scored = false
        }

        let transcript = try #require(inserter.insertedTexts.last)
        let sample = try await makeSample(
            repeatIndex: repeatIndex,
            profile: profile,
            fixture: fixture,
            model: controller.settings.transcriptionModel,
            classification: classification,
            scored: scored,
            press: press,
            transcript: transcript,
            events: events
        )
        try assertFinite(sample)
        samples.append(sample)
    }

    let usageEnd = currentResourceUsage()
    let captureCounts = await capture.counts()
    let engineCounts = await engine.counts()
    #expect(captureCounts.start == captureCounts.stop)
    #expect(samples.allSatisfy { !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

    let result = PartialResult(
        schemaVersion: 1,
        gitCommit: environment["VOXHEARTH_LATENCY_GIT_COMMIT"] ?? "unknown",
        dirty: environment["VOXHEARTH_LATENCY_GIT_DIRTY"] != "0",
        profile: profile,
        repeatIndex: repeatIndex,
        digests: [
            "evaluatorLock": environment["VOXHEARTH_LATENCY_EVALUATOR_DIGEST"] ?? "",
            "fixtureManifest": environment["VOXHEARTH_LATENCY_FIXTURE_DIGEST"] ?? "",
            "multilingualManifest": environment["VOXHEARTH_LATENCY_MULTILINGUAL_MANIFEST_DIGEST"] ?? "",
            "compactManifest": environment["VOXHEARTH_LATENCY_COMPACT_MANIFEST_DIGEST"] ?? "",
        ],
        environment: [
            "architecture": ProcessInfo.processInfo.machineArchitecture,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "lowPowerMode": String(ProcessInfo.processInfo.isLowPowerModeEnabled),
            "thermalState": String(describing: ProcessInfo.processInfo.thermalState),
        ],
        samples: samples,
        resources: ResourceSample(
            cpuSeconds: max(0, usageEnd.cpuSeconds - usageStart.cpuSeconds),
            peakResidentBytes: usageEnd.peakResidentBytes
        ),
        counts: [
            "captureStart": captureCounts.start,
            "captureStop": captureCounts.stop,
            "captureSnapshot": captureCounts.snapshot,
            "captureCancel": captureCounts.cancel,
            "enginePrepare": engineCounts.prepare,
            "engineTranscribe": engineCounts.transcribe,
            "insert": inserter.insertedTexts.count,
        ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(result).write(to: outputURL, options: .atomic)
}

private func requiredURL(
    _ key: String,
    environment: [String: String]
) throws -> URL {
    let value = try #require(environment[key])
    return URL(fileURLWithPath: value)
}

private func loadAudio(_ url: URL) throws -> CapturedAudio {
    let file = try AVAudioFile(forReading: url)
    let frameCapacity = AVAudioFrameCount(file.length)
    let buffer = try #require(
        AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity)
    )
    try file.read(into: buffer)
    let channel = try #require(buffer.floatChannelData?[0])
    return CapturedAudio(
        samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
        sampleRate: file.processingFormat.sampleRate
    )
}

@MainActor
private func waitForState(
    _ state: DictationSessionState,
    controller: DictationController
) async throws {
    let deadline = ContinuousClock.now + .seconds(300)
    while controller.state != state {
        if ContinuousClock.now >= deadline {
            throw LatencyEvaluatorError.timeout(String(describing: state))
        }
        await Task.yield()
    }
}

private func milliseconds(from start: UInt64, to end: UInt64, name: String) throws -> Double {
    guard end >= start else { throw LatencyEvaluatorError.invalidOrdering(name) }
    return Double(end - start) / 1_000_000
}

private func makeSample(
    repeatIndex: Int,
    profile: String,
    fixture: FixtureManifest.Fixture,
    model: TranscriptionModel,
    classification: String,
    scored: Bool,
    press: UInt64,
    transcript: String,
    events: EvaluatorEventLog
) async throws -> LatencySample {
    let cue = try await events.value(.cueDispatch)
    let capture = try await events.value(.captureStartExit)
    let recording = try await events.value(.recordingObserved)
    let release = try await events.value(.release)
    let stopEntry = try await events.value(.stopEntry)
    let stopExit = try await events.value(.stopExit)
    let transcribeEntry = try await events.value(.transcribeEntry)
    let transcribeExit = try await events.value(.transcribeExit)
    let insertEntry = try await events.value(.insertEntry)
    let insertExit = try await events.value(.insertExit)
    let idle = try await events.value(.idleObserved)
    return LatencySample(
        repeatIndex: repeatIndex,
        profile: profile,
        fixtureID: fixture.id,
        model: model.rawValue,
        language: fixture.language,
        classification: classification,
        scored: scored,
        cueDispatchMs: try milliseconds(from: press, to: cue, name: "press-to-cue"),
        captureStartCompletionMs: try milliseconds(from: press, to: capture, name: "press-to-capture"),
        audioStopEntryMs: try milliseconds(from: release, to: stopEntry, name: "release-to-stop"),
        visibleTextDispatchMs: try milliseconds(from: release, to: insertEntry, name: "release-to-insert"),
        segmentsMs: [
            "captureStartExitToRecording": try milliseconds(from: capture, to: recording, name: "capture-to-recording"),
            "stopEntryToExit": try milliseconds(from: stopEntry, to: stopExit, name: "stop-entry-to-exit"),
            "stopExitToTranscribeEntry": try milliseconds(from: stopExit, to: transcribeEntry, name: "stop-to-transcribe"),
            "transcribeEntryToExit": try milliseconds(from: transcribeEntry, to: transcribeExit, name: "transcribe"),
            "transcribeExitToInsertEntry": try milliseconds(from: transcribeExit, to: insertEntry, name: "transcribe-to-insert"),
            "insertEntryToExit": try milliseconds(from: insertEntry, to: insertExit, name: "insert-entry-to-exit"),
            "insertExitToIdle": try milliseconds(from: insertExit, to: idle, name: "insert-to-idle"),
        ],
        transcript: transcript
    )
}

private func assertFinite(_ sample: LatencySample) throws {
    let numbers = [
        sample.cueDispatchMs,
        sample.captureStartCompletionMs,
        sample.audioStopEntryMs,
        sample.visibleTextDispatchMs,
    ] + Array(sample.segmentsMs.values)
    guard numbers.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
        throw LatencyEvaluatorError.invalidOrdering("non-finite or negative measurement")
    }
}

private func currentResourceUsage() -> (cpuSeconds: Double, peakResidentBytes: UInt64) {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return (0, 0) }
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    return (user + system, UInt64(max(0, usage.ru_maxrss)))
}

private extension ProcessInfo {
    var machineArchitecture: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
