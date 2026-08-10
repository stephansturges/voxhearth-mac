# FluidAudioLocal provenance

`FluidAudioLocal` is a source-minimized derivative of FluidAudio 0.15.5:

- Upstream: https://github.com/FluidInference/FluidAudio
- Exact revision: `19600a485baa4998812e4654b70d2bab8f2c9949`
- Upstream license: Apache License 2.0, reproduced in `LICENSE`

The vendored module retains only the Parakeet TDT v3 batch-ASR implementation
and its required local inference utilities. Network clients, downloaders,
model hubs, cache recovery, TTS, diarization, VAD, CLI, and unrelated ASR
engines are intentionally omitted. All copied upstream `.swift` files remain
byte-for-byte identical to that revision unless explicitly listed below.

The following five files are adapted and carry prominent modification notices:

- `LocalAsrModels.swift` replaces upstream's
download/cache-aware `AsrModels.swift` with the model value types needed to
accept already-loaded Core ML objects.
- `LocalInferenceUtilities.swift` carries two token-boundary
helpers and the Neural Engine prefetch hint extracted from larger upstream
files whose unrelated vocabulary-rescoring and diarization implementations are
not vendored.
- `AppLogger.swift` is a compatible no-op sink whose message autoclosures are
never evaluated, stored, or emitted.
- `AsrManager.swift` exposes only transcription from caller-owned in-memory
`[Float]` samples; its AVAudioPCMBuffer, file-URL, and disk-backed entry points
are removed.
- `ChunkProcessor.swift` reads exclusively from an in-memory `[Float]` array
instead of the upstream disk-capable sample-source abstraction.

The upstream `AudioConverter.swift`, `AudioSourceFactory.swift`,
`AudioSampleSource.swift`, `AudioSource.swift`, and `AudioStream.swift` files
are intentionally omitted. VoxHearth opens bundled model assets itself and
exposes no runtime model acquisition or durable-audio path.
