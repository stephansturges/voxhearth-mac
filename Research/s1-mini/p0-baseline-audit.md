# S1-mini P0 baseline audit

Date: 2026-08-20

## Provenance and preservation

- Implementation worktree: `/Users/stephansturges/voxhearth-s1-mini-integration`
- Implementation branch: `agent/s1-mini-cleanup-integration`
- Baseline commit: `d4be74c8b1435b303a7f8f291d43c632b9e92527`
- GitHub `origin/main` at audit time: `e6ca5da217f621650e66ca6821e3121f3f9c7734`
- The dirty checkout at `/Users/stephansturges/voxhearth-mac` remains on
  `agent/parakeet-110m-model-switcher` at `e8c3683959f66504df3e61c426a70ed5a385ab64`.
  It was not reformatted, staged, or left modified by this implementation.
- Recovery snapshot: stash commit
  `c9e106d9e1c380f8c8365e0b75542175497af65d`, named
  `codex-preserve-s1-mini-p0-2026-08-20`. The stash includes all four modified
  scripts and all three untracked paths. It was applied back immediately with
  its index state; the complete pre/post porcelain status is byte-identical.
- `e8c3683` is an ancestor of `d4be74c8`, so the implementation baseline includes
  the compact-model commit and all later diagnostics/latency work.

### Dirty model-switcher reconciliation

The preservation inventory from the approved plan was compared file-by-file
against the clean diagnostics baseline:

| Dirty-checkout path | Baseline disposition |
| --- | --- |
| `scripts/fetch-model.sh` | Byte-identical; already integrated. |
| `scripts/model-smoke.sh` | Byte-identical; already integrated. |
| `scripts/verify-model.py` | Byte-identical; already integrated. |
| `scripts/fetch-models.sh` | Byte-identical; already integrated. |
| `Models/parakeet-tdt-ctc-110m-coreml.json` | Same keys, file entries, sizes, and hashes; dirty copy only expands JSON formatting. Keep the compact tracked baseline formatting. |
| `scripts/local-check.sh` | Not equivalent. The dirty copy is based on the earlier branch and omits the diagnostics scripts, privacy-logger checks, latency/soak inertness checks, evaluator locks, and retained compute-unit guard. Keep the diagnostics baseline version. |

No dirty-checkout file needs to be copied. This decision preserves its content
without weakening the newer diagnostics baseline.

## Current state and actor seams

### Session presentation state

`DictationSessionState` currently contains:

- `.idle`
- `.preparing`
- `.recording`
- `.transcribing`
- `.inserting`
- `.failed(DictationFailure)`

There is no cleanup/normalization state. `VoxHearthFrontendModel` maps preparing,
transcribing, and inserting to the single `.transcribing` presentation. Hotkey
presses are accepted only from idle, failure, or a background-preparation seam;
presses while transcribing/inserting are ignored.

### Activation, preview, and final transcription

- `DictationController` is `@MainActor`.
- Accepted start/stop work runs in `.userInitiated` tasks.
- `requestStart()` accepts synchronously on the MainActor, increments
  `sessionEpoch`, clears the one pending transcript, begins a latency-critical
  lifecycle activity, and queues cue/model/audio start.
- `requestStop()` accepts synchronously, increments `sessionEpoch`, transitions
  to transcribing, and cancels the preview task.
- `runAcceptedStop()` stops `AVAudioEngine` capture before awaiting the cancelled
  preview task. Only after the preview join does it start final transcription.
- `LivePreviewSession` is a separate actor. Its scheduling task has `.medium`
  priority; it snapshots bounded trailing audio, invokes the shared Parakeet
  actor, then crosses to MainActor through publish/circuit callbacks only.
- Preview and final transcription deliberately serialize through the same
  Parakeet actor. Final transcription never overlaps the cancelled preview.
- A live preview that exceeds its latency budget opens a per-recording circuit.
  Three consecutive preview failures also stop the preview session.
- After final ASR succeeds, the full final transcript is published to the
  overlay before insertion. It remains visible for two seconds after completion
  or error, then is cleared.

### Current identity boundary

`sessionEpoch` is a mutable generation guard, not a stable session identifier.
It increments independently on accepted start, accepted stop, cancellation, and
start cancellation. It is sufficient to abandon stale tasks in the present
single-session pipeline but cannot identify or retain late work from an older
cleanup session while a newer session records. The S1 implementation therefore
still needs a separate stable `DictationSessionID`.

## Model settings, language, and decoding

### Model/settings fields

`AppSettings` currently persists:

- hotkey and optional pointer button;
- input-device UID;
- `TranscriptionModel` (`multilingual` or `compactEnglish`);
- `DictationLanguage`;
- launch-at-login;
- optional live overlay;
- optional clipboard compatibility.

The multilingual model supports the 25 enumerated languages. Selecting the
compact English model normalizes the language to English. Legacy settings that
do not contain a model retain multilingual behavior.

### Language resolution

There is no detected/resolved-language result in the app contract. The app
passes the user-selected language as a script-filtering hint for multilingual
v3. The compact 110M/v2 decoder receives no language hint. Vendored `ASRResult`
contains text, confidence, duration, processing metrics, timings, and optional
CTC rescoring metadata, but no resolved-language field. Cleanup must therefore
use the selected/normalized app language unless a separately tested language
contract is introduced; it must not imply that Parakeet detected a language.

### Hand-written decoding

Core ML executes the Parakeet network components, while the vendored
`FluidAudioLocal` runtime owns the Swift TDT decode loop, decoder state, joint
decision, token filtering, chunking, and text assembly. `ParakeetEngine` creates
a fresh `TdtDecoderState` for each complete transcription and calls
`AsrManager.transcribe`. Decoder choice is version-specific (`TdtDecoderV3` for
multilingual, `TdtDecoderV2` for compact). This is a hand-written local decode
path, not an opaque system speech API.

## Lifecycle and latency guards

### Activity-token placement

- Accepted microphone start begins one
  `.userInitiatedAllowingIdleSystemSleep + .latencyCritical` ProcessInfo
  activity before cue/model preparation/audio start.
- Immediately after audio capture stops, the controller replaces it with one
  `.userInitiatedAllowingIdleSystemSleep` activity without a nap-eligible gap.
- External audio and explicit insertion retry begin the user-initiated scope.
- Transition to idle or failure ends the activity. Cancellation/deactivation
  also balance it.

Cleanup must remain inside the narrowed user-initiated scope for the owning
session, while expedited new capture begins its own audio-critical scope.

### Current promotion guard

The frozen latency evaluator measures same-machine relative p95 for four fake
control-plane components:

```text
0.10 * press-to-cue-dispatch p95
+ 0.10 * press-to-capture-completion p95
+ 0.20 * release-to-audio-stop-entry p95
+ 0.60 * release-to-visible-text-dispatch p95
```

It uses R-7 p95, ten samples per P0 repeat with one excluded warmup, three fresh
processes, immutable audio fixtures, exact transcript ratchets, compact/preview/
clipboard/cancellation/cold guardrail profiles, and CPU/peak-RSS gates. The
recorded generation-zero baseline weighted warm p95 is 48.089 ms. The evaluator
does not observe real Carbon delivery, audible cue, AVAudioEngine timing,
WindowServer, Accessibility, CGEvent receipt, or destination visibility. The S1
spike must therefore retain this automated ratchet and add real OS/hardware
measurements rather than treating the existing score as end-to-end latency.

## Parakeet compute placement

The integrated baseline does **not** use GPU compute units for Parakeet:

- multilingual preprocessor: `.cpuOnly`;
- compact preprocessor: `.cpuAndNeuralEngine`;
- encoder/decoder/joint general configuration: `.cpuAndNeuralEngine`.

`allowLowPrecisionAccumulationOnGPU` is set on the general configuration, but
GPU is excluded by its `.cpuAndNeuralEngine` compute-unit selection. There is no
`.cpuAndGPU` or `.all` production configuration. The P0 stop rule is therefore
not triggered, and S1 Metal contention can be measured against an ASR path that
uses CPU plus Neural Engine.

## Insertion and recovery seams

### Current tiers

`TextInsertionService` is MainActor-isolated and currently tries:

1. Accessibility selected-text replacement;
2. Unicode CGEvent text dispatch if Accessibility is unavailable;
3. Command-V clipboard paste only when the user explicitly enabled clipboard
   compatibility.

Accessibility focus queries use a 0.35-second messaging timeout and set-value
uses 0.60 seconds. `.cannotComplete` is classified as ambiguous and never
automatically falls through, preventing a duplicate insertion. Unicode CGEvent
success means dispatch only, not target acknowledgement. Clipboard restore is
change-count guarded and delayed 120 ms.

The diagnostic `VoxHearth.diagnostics.insertionMode=unicode-first` setting
skips Accessibility. No current route distinguishes single-line from multiline
text, so multiline safety must be added above every diagnostic/fallback branch.

### Framework policy

Insertion imports AppKit and ApplicationServices; CoreGraphics event APIs arrive
through the macOS SDK imports. SwiftPM declares no remote dependencies or
explicit extra linker settings. The current release-binary gate denies known
network/updater frameworks and symbols, but it is a deny-list rather than a
positive framework allowlist. Vendored llama integration must add the exact
audited runtime/framework closure without broadening this policy silently.

### Pending transcript behavior

The current controller owns one `String?` pending transcript with a 120-second
in-memory expiry. Insertion failure or uncertainty retains it; UI offers Retry
and Discard; concurrent retry is guarded by state. A new accepted recording
calls `clearPendingTranscript()`, so the old item is lost. There is no Copy
action, no session-keyed store, no three-entry capacity, no terminal
classification, and no Insert Anyway confirmation. These are mandatory S1
changes rather than existing capabilities.

## Multi-model staging

- Manifests:
  - `Models/parakeet-tdt-0.6b-v3-coreml.json`: bundle root
    `parakeet-tdt-0.6b-v3-coreml`, 21 files, 483105645 bytes.
  - `Models/parakeet-tdt-ctc-110m-coreml.json`: bundle root
    `parakeet-tdt-ctc-110m-coreml`, 16 files, 227466209 bytes.
- `scripts/fetch-models.sh` iterates both manifests through the single exact,
  staged, non-overwriting `fetch-model.sh` implementation.
- `scripts/build-app-bundle.sh` verifies both roots, stages them beneath
  `Contents/Resources/Models/<bundleRoot>`, includes both manifests, and verifies
  the staged copies before signing.
- `VoxHearthFrontendModel` resolves both fixed bundle roots below
  `Contents/Resources/Models`; the runtime has no fetch fallback.
- The current build script exposes separate multilingual and compact input
  arguments. S1 packaging should generalize this manifest-driven staging rather
  than adding a third unrelated one-off path.

## Untouched baseline verification

Command:

```bash
./scripts/local-check.sh
```

Result: pass, exit 0, 2026-08-20. Evidence included 78 Swift tests, inert latency
and lifecycle-soak evaluator checks, 14-fixture and evaluator-lock verification,
both Parakeet manifest validations, debug and release builds, and release-binary
policy validation. Optional real-model smoke tests were skipped because verified
local model roots were absent in this worktree; P1 must supply exact roots.

## P0 decision

P0 passes. The approved plan is compatible with the actual integrated seams,
the dirty model-switcher work is preserved without copying older guards, and
Parakeet is not configured for GPU compute units. No S1 product implementation
has occurred. The next permitted gate is the isolated Metal-first versus
CPU+Accelerate spike; its code is throwaway and may not be merged into product
until the complete P1 measurements and stop rules pass.
