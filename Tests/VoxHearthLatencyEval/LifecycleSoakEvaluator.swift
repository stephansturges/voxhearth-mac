@preconcurrency import AVFoundation
import Darwin
import Foundation
import Testing
import VoxHearthCore

private struct SoakFixtureManifest: Decodable {
    let schemaVersion: Int
    let fixtures: [Fixture]

    struct Fixture: Decodable {
        let id: String
        let file: String
        let role: String
    }
}

private struct SoakCycle: Codable {
    let windowIndex: Int
    let cycleIndex: Int
    let previewEnabled: Bool
    let fixtureID: String
    let pressToRecordingMs: Double
    let releaseToInsertDispatchMs: Double
    let pressToVisibleTextDispatchMs: Double
    let transcriptDigest: String
}

private struct SoakResourceSample: Codable {
    let cpuSeconds: Double
    let peakResidentBytes: UInt64
    let physicalFootprintBytes: UInt64
    let residentBytes: UInt64
    let threadCount: Int
}

private struct SoakWindow: Codable {
    let index: Int
    let previewEnabled: Bool
    let cycles: [SoakCycle]
    let pressToVisibleTextP50Ms: Double
    let pressToVisibleTextP95Ms: Double
    let pressToVisibleTextMaximumMs: Double
    let resources: SoakResourceSample
}

private struct SoakVerdict: Codable {
    let degraded: Bool
    let reasons: [String]
    let lastToFirstP95Ratio: Double
    let p95IncreaseMs: Double
    let physicalFootprintIncreaseBytes: Int64
    let threadCountIncrease: Int
    let singleCycleStallObserved: Bool
}

private struct SoakResult: Codable {
    let schemaVersion: Int
    let soakSchema: String
    let gitCommit: String
    let dirty: Bool
    let windowCount: Int
    let cyclesPerWindow: Int
    let processID: Int32
    let environment: [String: String]
    let windows: [SoakWindow]
    let transcriptDigests: [String: String]
    let verdict: SoakVerdict
}

@Test @MainActor
func lifecycleSoakEvaluator() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["VOXHEARTH_SOAK_EVAL"] == "1" else { return }

    let repoRoot = try soakRequiredURL("VOXHEARTH_SOAK_REPO_ROOT", environment)
    let outputURL = try soakRequiredURL("VOXHEARTH_SOAK_OUTPUT", environment)
    let multilingualRoot = try soakRequiredURL(
        "VOXHEARTH_SOAK_MULTILINGUAL_MODEL_ROOT",
        environment
    )
    let compactRoot = try soakRequiredURL(
        "VOXHEARTH_SOAK_COMPACT_MODEL_ROOT",
        environment
    )
    let windowCount = try soakRequiredPositiveInt("VOXHEARTH_SOAK_WINDOWS", environment)
    let cyclesPerWindow = try soakRequiredPositiveInt(
        "VOXHEARTH_SOAK_CYCLES_PER_WINDOW",
        environment
    )

    let manifest = try JSONDecoder().decode(
        SoakFixtureManifest.self,
        from: Data(
            contentsOf: repoRoot.appendingPathComponent(
                "Research/latency/fixtures.manifest.json"
            )
        )
    )
    #expect(manifest.schemaVersion == 1)
    let scoredFixtures = manifest.fixtures.filter { $0.role == "scored" }
    let fixture = try #require(scoredFixtures.first)
    let audio = try soakLoadAudio(
        repoRoot.appendingPathComponent("Research/latency/fixtures/\(fixture.file)")
    )

    let events = EvaluatorEventLog()
    let capture = FixtureCapture(events: events)
    await capture.use(audio)
    let realEngine = ParakeetEngine(
        multilingualModelDirectoryURL: multilingualRoot,
        compactEnglishModelDirectoryURL: compactRoot
    )
    let engine = CountingEngine(wrapping: realEngine, events: events)
    let inserter = RecordingInserter(events: events, method: .accessibility)
    let hotkey = EvaluatorHotkey()
    let pointer = EvaluatorPointer()
    var settings = AppSettings(
        transcriptionModel: .multilingual,
        language: .english,
        liveTranscriptOverlayEnabled: false
    )
    let controller = DictationController(
        transcriptionEngine: engine,
        settings: settings,
        audioCapture: capture,
        textInserter: inserter,
        hotkeyService: hotkey,
        pointerButtonService: pointer,
        livePreviewInterval: .zero,
        livePreviewMinimumDuration: 0,
        livePreviewLatencyBudget: .seconds(30)
    )
    controller.onStartCue = { await events.stamp(.cueDispatch) }
    try controller.activate()
    defer { controller.deactivate() }
    await controller.prepareEngine()
    #expect(controller.state == .idle)

    var windows: [SoakWindow] = []
    var stableDigests: [String: String] = [:]
    for windowIndex in 0..<windowCount {
        // Keep the measured workload identical across windows so first-to-last
        // drift is meaningful. Every cycle exercises both preview and final.
        let previewEnabled = true
        settings.liveTranscriptOverlayEnabled = previewEnabled
        try controller.applySettings(settings)
        var cycles: [SoakCycle] = []

        for cycleIndex in 0..<cyclesPerWindow {
            await capture.use(audio)
            await events.reset()
            let press = DispatchTime.now().uptimeNanoseconds
            hotkey.emit(.pressed)
            try await soakWaitForState(.recording, controller)
            let recording = DispatchTime.now().uptimeNanoseconds

            var visible = recording
            if previewEnabled {
                try await soakWaitForPreview(controller)
                visible = DispatchTime.now().uptimeNanoseconds
            }

            await events.stamp(.release)
            let release = DispatchTime.now().uptimeNanoseconds
            hotkey.emit(.released)
            try await soakWaitForState(.idle, controller)
            let insert = try await events.value(.insertEntry)
            let transcript = try #require(inserter.insertedTexts.last)
            let digest = soakStableDigest(transcript)
            if let previous = stableDigests[fixture.id] {
                #expect(previous == digest)
            } else {
                stableDigests[fixture.id] = digest
            }
            cycles.append(
                SoakCycle(
                    windowIndex: windowIndex,
                    cycleIndex: cycleIndex,
                    previewEnabled: previewEnabled,
                    fixtureID: fixture.id,
                    pressToRecordingMs: soakMilliseconds(press, recording),
                    releaseToInsertDispatchMs: soakMilliseconds(release, insert),
                    pressToVisibleTextDispatchMs: soakMilliseconds(press, visible),
                    transcriptDigest: digest
                )
            )
        }

        let visibleValues = cycles.map(\.pressToVisibleTextDispatchMs)
        windows.append(
            SoakWindow(
                index: windowIndex,
                previewEnabled: previewEnabled,
                cycles: cycles,
                pressToVisibleTextP50Ms: soakPercentile(visibleValues, 0.50),
                pressToVisibleTextP95Ms: soakPercentile(visibleValues, 0.95),
                pressToVisibleTextMaximumMs: visibleValues.max() ?? 0,
                resources: soakResourceSample()
            )
        )
    }

    let first = try #require(windows.first)
    let last = try #require(windows.last)
    let p95Increase = last.pressToVisibleTextP95Ms - first.pressToVisibleTextP95Ms
    let p95Ratio = last.pressToVisibleTextP95Ms
        / max(first.pressToVisibleTextP95Ms, 0.001)
    let footprintIncrease = Int64(last.resources.physicalFootprintBytes)
        - Int64(first.resources.physicalFootprintBytes)
    let threadIncrease = last.resources.threadCount - first.resources.threadCount
    var reasons: [String] = []
    if last.pressToVisibleTextP95Ms > first.pressToVisibleTextP95Ms * 2 + 250 {
        reasons.append("latency_drift")
    }
    if footprintIncrease > 64 * 1_024 * 1_024 {
        reasons.append("physical_footprint_growth")
    }
    if threadIncrease > 4 {
        reasons.append("thread_growth")
    }
    let allDigests = windows.flatMap(\.cycles).map(\.transcriptDigest)
    if Set(allDigests).count != stableDigests.count {
        reasons.append("transcript_drift")
    }
    let singleCycleStall = windows
        .flatMap(\.cycles)
        .contains { $0.pressToVisibleTextDispatchMs > 5_000 }
    let verdict = SoakVerdict(
        degraded: !reasons.isEmpty,
        reasons: reasons,
        lastToFirstP95Ratio: p95Ratio,
        p95IncreaseMs: p95Increase,
        physicalFootprintIncreaseBytes: footprintIncrease,
        threadCountIncrease: threadIncrease,
        singleCycleStallObserved: singleCycleStall
    )
    #if DEBUG
    let buildConfiguration = "debug"
    #else
    let buildConfiguration = "release"
    #endif
    let result = SoakResult(
        schemaVersion: 1,
        soakSchema: "voxhearth.soak.v1",
        gitCommit: environment["VOXHEARTH_SOAK_GIT_COMMIT"] ?? "unknown",
        dirty: environment["VOXHEARTH_SOAK_GIT_DIRTY"] != "0",
        windowCount: windowCount,
        cyclesPerWindow: cyclesPerWindow,
        processID: getpid(),
        environment: [
            "buildConfiguration": buildConfiguration,
            "testabilityEnabled": "true",
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "lowPowerMode": String(ProcessInfo.processInfo.isLowPowerModeEnabled),
            "thermalState": String(describing: ProcessInfo.processInfo.thermalState),
        ],
        windows: windows,
        transcriptDigests: stableDigests,
        verdict: verdict
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(result).write(to: outputURL, options: .atomic)
    #expect(!verdict.degraded)
}

private func soakRequiredURL(_ key: String, _ environment: [String: String]) throws -> URL {
    URL(fileURLWithPath: try #require(environment[key]))
}

private func soakRequiredPositiveInt(
    _ key: String,
    _ environment: [String: String]
) throws -> Int {
    let value = try #require(environment[key].flatMap(Int.init))
    return try #require(value > 0 ? value : nil)
}

private func soakLoadAudio(_ url: URL) throws -> CapturedAudio {
    let file = try AVAudioFile(forReading: url)
    let buffer = try #require(
        AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )
    )
    try file.read(into: buffer)
    let channel = try #require(buffer.floatChannelData?[0])
    return CapturedAudio(
        samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
        sampleRate: file.processingFormat.sampleRate
    )
}

@MainActor
private func soakWaitForState(
    _ expected: DictationSessionState,
    _ controller: DictationController
) async throws {
    let deadline = ContinuousClock.now + .seconds(300)
    while controller.state != expected {
        guard ContinuousClock.now < deadline else {
            throw LatencyEvaluatorError.timeout(String(describing: expected))
        }
        await Task.yield()
    }
}

@MainActor
private func soakWaitForPreview(_ controller: DictationController) async throws {
    let deadline = ContinuousClock.now + .seconds(300)
    while controller.liveTranscriptPreview?.isEmpty != false {
        guard ContinuousClock.now < deadline else {
            throw LatencyEvaluatorError.timeout("live-preview")
        }
        await Task.yield()
    }
}

private func soakMilliseconds(_ start: UInt64, _ end: UInt64) -> Double {
    guard end >= start else { return .infinity }
    return Double(end - start) / 1_000_000
}

private func soakPercentile(_ values: [Double], _ probability: Double) -> Double {
    let ordered = values.sorted()
    guard !ordered.isEmpty else { return 0 }
    let position = Double(ordered.count - 1) * probability
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    guard lower != upper else { return ordered[lower] }
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - Double(lower))
}

private func soakStableDigest(_ text: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}

private func soakResourceSample() -> SoakResourceSample {
    var usage = rusage()
    _ = getrusage(RUSAGE_SELF, &usage)
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000

    var taskData = proc_taskinfo()
    let taskSize = proc_pidinfo(
        getpid(),
        PROC_PIDTASKINFO,
        0,
        &taskData,
        Int32(MemoryLayout<proc_taskinfo>.size)
    )

    var vmInfo = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let vmResult = withUnsafeMutablePointer(to: &vmInfo) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { rebound in
            task_info(
                mach_task_self_,
                task_flavor_t(TASK_VM_INFO),
                rebound,
                &vmCount
            )
        }
    }

    return SoakResourceSample(
        cpuSeconds: max(0, user + system),
        peakResidentBytes: UInt64(max(0, usage.ru_maxrss)),
        physicalFootprintBytes: vmResult == KERN_SUCCESS ? vmInfo.phys_footprint : 0,
        residentBytes: taskSize == MemoryLayout<proc_taskinfo>.size
            ? taskData.pti_resident_size
            : 0,
        threadCount: taskSize == MemoryLayout<proc_taskinfo>.size
            ? Int(taskData.pti_threadnum)
            : 0
    )
}
