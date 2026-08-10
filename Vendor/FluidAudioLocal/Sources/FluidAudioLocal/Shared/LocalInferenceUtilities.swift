// Derived from FluidAudio 0.15.5 at revision
// 19600a485baa4998812e4654b70d2bab8f2c9949, licensed under Apache-2.0.
// Modified for VoxHearth: 2026-08-10. Extracted only the local ASR token
// boundary helpers and ANE prefetch hint; omitted unrelated diarization and
// vocabulary-rescoring implementations.

@preconcurrency import CoreML
import Foundation

public func isWordBoundary(_ token: String) -> Bool {
    token.hasPrefix(ASRConstants.sentencePieceWordBoundary) || token.hasPrefix(" ")
}

public func stripWordBoundaryPrefix(_ token: String) -> String {
    if isWordBoundary(token) {
        return String(token.dropFirst())
    }
    return token
}

extension MLMultiArray {
    public func prefetchToNeuralEngine() {
        if count > 0 {
            _ = self[0]
            _ = self[count - 1]
        }
    }
}
