import Foundation
import Testing
@testable import VoxHearthCore

@Test func numberCanonicalizerBenchmark() {
    guard ProcessInfo.processInfo.environment[
        "VOXHEARTH_NUMBER_CANONICALIZER_BENCHMARK"
    ] == "1" else { return }

    let canonicalizer = SpokenNumberCanonicalizer()
    let samples = [
        ("This ordinary cleaned sentence has no number candidates at all.",
         "this ordinary cleaned sentence has no number candidates at all"),
        ("The invoice is seven thousand and twelve dollars.",
         "the invoice is seven thousand and twelve dollars"),
        ("The totals are eleven, twelve, thirteen, and fourteen.",
         "the totals are eleven twelve thirteen and fourteen"),
        ("The invoice total is $7,12.",
         "the invoice total is seven thousand and twelve dollars"),
        (String(repeating: "This is a bounded chunk of ordinary cleaned prose. ", count: 10),
         String(repeating: "this is a bounded chunk of ordinary source prose ", count: 10)),
    ]
    for _ in 0..<10 {
        for sample in samples {
            _ = canonicalizer.canonicalize(sample.0, source: sample.1)
        }
    }

    var durations: [Double] = []
    let clock = ContinuousClock()
    for _ in 0..<100 {
        for sample in samples {
            let start = clock.now
            _ = canonicalizer.canonicalize(sample.0, source: sample.1)
            durations.append(milliseconds(start.duration(to: clock.now)))
        }
    }
    durations.sort()
    let p99 = durations[min(durations.count - 1, Int(Double(durations.count) * 0.99))]
    let p50 = durations[durations.count / 2]
    FileHandle.standardError.write(Data(
        "number_canonicalizer_benchmark p50_ms=\(p50) p99_ms=\(p99) samples=\(durations.count)\n".utf8
    ))
    #expect(p99 <= 25)
}

private func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
}
