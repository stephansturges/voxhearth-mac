# Building VoxHearth

VoxHearth is a Swift Package Manager macOS app. The release pipeline constructs
the `.app` bundle explicitly so every executable, model, entitlement, and legal
file has one auditable path into the signed artifact.

## Pinned release environment

- Git
- macOS runner image `macos-26`
- Xcode 26.2 and its Swift 6 toolchain
- Apple Silicon (`arm64`)
- Python 3 (standard library only)
- Apple command-line tools: `codesign`, `hdiutil`, `xcrun notarytool`,
  `xcrun stapler`, `spctl`, `plutil`, and `ditto`

macOS 14 is the deployment target. Other recent Xcode versions may work for
development, but an official v0.4.0 artifact is built only in the pinned
environment.

## Source dependencies

The root package has no remote Swift package dependency. It builds the local
`Vendor/FluidAudioLocal` target: a reviewed ASR-only subset adapted from
FluidAudio 0.15.5 at full commit:

```text
19600a485baa4998812e4654b70d2bab8f2c9949
```

FluidAudio has no external Swift package dependencies at that revision. The
vendored subset omits its HTTP, model-download/cache, CLI, speech synthesis,
and unrelated model surfaces. `Vendor/FluidAudioLocal/UPSTREAM.md` records file
provenance and modifications. Relevant third-party license texts remain under
`LICENSES/`.

The two Core ML speech models and S1-mini cleanup GGUF are separate build
inputs pinned to Hugging Face revisions:

```text
aed02740059203c4a87495924f685de3722ae9ce
9bc92ead6e8f17eca92a869fd578ae76842b82ba
8eab4779866f477ae6e7f237ca45fc2c65153f50
```

S1-mini by Superwhisper is executed by the committed llama.cpp/ggml subset at
revision `9ee9fc04c136ef2ae729bfc60d18961b23c13ddf`. Its sealed Metal library is
built from manifest-locked source and must reproduce
`Vendor/LlamaLocal/METALLIB.json`. Xcode 26.2 requires the optional Metal
Toolchain component:

```sh
xcodebuild -downloadComponent MetalToolchain
./scripts/build-metallib.sh
```

The build pins `air64-apple-macos14.0` explicitly so the sealed library does
not inherit the hosted machine's Darwin patch version. The normal command is
fail-closed and accepts only the digest in `Vendor/LlamaLocal/METALLIB.json`.
CI may use `--candidate` solely to produce a twice-built, byte-compared review
artifact; candidate mode does not approve the artifact for app packaging.

## Test and compile

From the repository root:

```sh
./scripts/local-check.sh
```

This resolves the exact Swift dependency, runs all tests, builds debug and
release configurations, validates shell and Python helpers, validates all
model/runtime/license manifests, generates and audits sample SBOM/provenance,
checks action pins, rejects tracked model/release secrets, and scans
the runtime source for forbidden networking/updater APIs.

## Diagnose dictation latency

VoxHearth emits only fixed-name lifecycle markers. To inspect timing without
recording audio, transcript text, clipboard contents, or paths, run:

```sh
voxhearth_pid="$(pgrep -x VoxHearth)"
/usr/bin/log stream --level info --style compact \
  --predicate "subsystem == \"com.stephansturges.voxhearth\" AND processIdentifier == $voxhearth_pid"
```

The PID clause matters: real-model development tests run in a separate process
and use a `.tests` subsystem, so their deliberately dense soak traffic must not
be mistaken for an installed-app session.

Do not run `scripts/soak-eval.sh` while dictating in the installed app. The soak
intentionally drives sustained real-model inference; Core ML/CPU contention can
make the otherwise separate app appear to hang. A line whose process is
`swiftpm-testing-helper` is evaluator evidence, not a VoxHearth lifecycle event.

A normal hold-to-talk session follows this sequence:

```text
hotkey_pressed → activation_handling_started → lifecycle_activity_began
→ dictation_start_accepted → start_cue_started → start_cue_play_entered
→ start_cue_play_returned → start_cue_delay_resumed → start_cue_completed
→ model_preparation_started
→ model_preparation_completed → audio_capture_start_entered
→ audio_capture_started

live_preview_snapshot_started → audio_snapshot_lock_entered
→ audio_snapshot_copy_completed → live_preview_snapshot_completed
→ live_preview_inference_started → local_transcription_started
→ audio_resample_started → audio_resample_completed
→ local_inference_returned → local_transcription_completed
→ live_preview_inference_completed → live_preview_publish_requested
→ live_preview_actor_entered → overlay_text_applied
→ overlay_screen_query_started → overlay_screen_query_completed
→ overlay_position_applied → overlay_order_front_started
→ overlay_order_front_completed → live_preview_published

hotkey_released → dictation_stop_accepted → live_preview_cancellation_requested
→ audio_capture_stop_entered → audio_capture_stopped
→ lifecycle_activity_narrowed → live_preview_cancellation_joined
→ final_transcription_started
→ local_transcription_started → audio_resample_started
→ audio_resample_completed → local_inference_returned
→ local_transcription_completed
→ final_transcription_completed → text_insertion_started
→ accessibility_focus_query_started → accessibility_focus_query_completed
→ accessibility_settable_query_started → accessibility_settable_query_completed
→ accessibility_set_value_started → accessibility_set_value_completed
→ text_insertion_completed → lifecycle_activity_ended
→ session_returned_to_idle
```

Only the first visible preview queries a screen, repositions, and orders the
panel. Later preview updates emit `overlay_text_applied` only when their display
text changes. Screen-configuration changes can trigger a new screen query and
position marker without reordering every refresh.

Use the dominant gap to identify the mechanism:

| Marker or gap | Interpretation |
| --- | --- |
| `hotkey_dispatch_delayed` or `hotkey_dispatch_stalled` | The Carbon event waited more than 100 ms or 500 ms before handling. |
| Hotkey event to `activation_handling_started` | Main event-loop delivery was delayed after Carbon dispatch. |
| `dictation_start_abandoned` / `dictation_stop_abandoned` | An older asynchronous continuation resumed after a newer lifecycle epoch and was deliberately prevented from mutating the new session. |
| `start_cue_play_entered` to `start_cue_play_returned` | AppKit sound dispatch itself stalled. |
| Cue play return to `start_cue_delay_resumed` | The short cue-isolation timer was throttled or starved. |
| `local_transcription_started` to `local_inference_returned` | Resampling plus the real model pipeline was slow. |
| `audio_snapshot_lock_entered` to `audio_snapshot_copy_completed` | The bounded preview snapshot waited on or copied the accumulator buffer. |
| `local_inference_returned` to `local_transcription_completed` | Postprocessing or scoped Core ML object release was slow. |
| `live_preview_publish_requested` to `live_preview_actor_entered` | The preview waited to enter MainActor. |
| Overlay substep markers | SwiftUI/AppKit screen lookup, positioning, or WindowServer ordering was slow. |
| `live_preview_budget_exceeded` / `live_preview_circuit_opened` | One complete preview cycle exceeded its budget. Later previews are disabled only for this recording so final transcription gets the engine. |
| Audio-capture stop entry to stopped | `AVAudioEngine` teardown delayed microphone release. |
| Preview cancellation request to joined | Release waited for an in-flight preview operation. |
| Accessibility operation start to completion | The destination's Accessibility process delayed insertion. |
| `accessibility_insertion_uncertain` | The final AX write timed out ambiguously; inspect the field before retrying or discarding the in-memory transcript. |
| `unicode_insertion_dispatched` | Unicode events were posted. This is not acknowledgement that the destination rendered them. |
| Lifecycle activity begin/narrow/end | The scoped App Nap/QoS protection is balanced across audio-critical and post-audio work. |

The diagnostic build bounds the first two Accessibility queries to 350 ms each
and the final write to 600 ms. A definite query or write refusal safely falls
through to Unicode events. A final `kAXErrorCannotComplete` never falls through
automatically because the destination may have applied the text without
acknowledging it; VoxHearth retains the transcript for an explicit retry or
discard instead.

To compare the Unicode path without attempting Accessibility insertion, quit
VoxHearth and run:

```sh
defaults write com.stephansturges.voxhearth \
  VoxHearth.diagnostics.insertionMode -string unicode-first
```

Restore the bounded Accessibility-first default with:

```sh
defaults delete com.stephansturges.voxhearth \
  VoxHearth.diagnostics.insertionMode
```

Unicode-first is diagnostic-only. It is not the default insertion behavior.

Two additional experiments remain opt-in because they are not proven latency
fixes. They execute only after returning idle:

```sh
defaults write com.stephansturges.voxhearth \
  VoxHearth.diagnostics.releasePooledArrays -bool true
defaults write com.stephansturges.voxhearth \
  VoxHearth.diagnostics.modelReloadOnStall -bool true
```

The first requests that FluidAudio clear its shared MLMultiArray pool. The
second permits one idle model reload after a preview circuit opens. Both can
increase the next cold operation, so the diagnostic build leaves them off.
Delete the keys to restore the default.

### Same-process lifecycle soak

The supplemental soak keeps one process, controller, and real model alive and
runs preview plus final inference on every cycle. It denies network access,
checks transcript digests, records raw latency and resource windows, and fails
sustained first-to-last drift.

```sh
scripts/soak-eval.sh quick /private/tmp/voxhearth-soak-quick.json
scripts/soak-eval.sh full /private/tmp/voxhearth-soak-full.json
```

The default model roots are the two verified payloads under `.build/models`.
Set `VOXHEARTH_SOAK_MULTILINGUAL_MODEL_ROOT` and
`VOXHEARTH_SOAK_COMPACT_MODEL_ROOT` to use other already-local verified roots.
The evaluator is inert during ordinary `swift test` runs. It cannot exercise
AppKit/WindowServer or reproduce 20 hours of wall-clock uptime, so a clean soak
does not exonerate the installed UI path.

### Capture a slow installed process

Run this immediately after a slow session, using the exact VoxHearth PID:

```sh
scripts/capture-diagnostics.sh \
  --pid 12345 \
  --out /private/tmp/VoxHearth-diagnostics-slow-session \
  --last 15m \
  --sample-seconds 3
```

`logs.txt` requests info-level entries. Retrospective info records may not be
present in the unified-log archive unless persistence was enabled before the
slow session. For a long observation window, either keep the PID-scoped
`log stream --level info` command above running, or first configure the
subsystem explicitly:

```sh
sudo /usr/bin/log config \
  --subsystem com.stephansturges.voxhearth \
  --mode "level:info,persist:info"
```

Restore the default logging policy after the investigation with:

```sh
sudo /usr/bin/log config \
  --subsystem com.stephansturges.voxhearth \
  --reset
```

The script pins the VoxHearth log subsystem and one PID. It collects fixed
process columns, thread states, `vmmap -summary`, a quiet heap class summary,
and a short stack sample when macOS permits them. Paths are redacted; process
environment, transcripts, clipboard content, audio, and unrelated processes
are never requested. The script does not install, terminate, or modify the app.

## Fetch the build-only models

```sh
./scripts/fetch-models.sh
```

The script downloads exactly the three manifests' allowlisted files over HTTPS
into fresh temporary directories, verifies every size and SHA-256, and then
moves the valid trees to:

```text
.build/models/parakeet-tdt-0.6b-v3-coreml
.build/models/parakeet-tdt-ctc-110m-coreml
.build/models/s1-mini-gguf
```

It does not download optional model variants. It refuses to overwrite an
existing invalid destination. To validate both payloads without network
access:

```sh
./scripts/verify-model.py .build/models/parakeet-tdt-0.6b-v3-coreml
./scripts/verify-model.py \
  --manifest Models/parakeet-tdt-ctc-110m-coreml.json \
  .build/models/parakeet-tdt-ctc-110m-coreml
./scripts/verify-model.py \
  --manifest Models/s1-mini-gguf.json \
  .build/models/s1-mini-gguf
./scripts/check-attribution.py
```

## Construct the app and development DMG

```sh
./scripts/build-app-bundle.sh \
  --version 0.4.0 \
  --build 1 \
  --output .build/distribution/VoxHearth.app

./scripts/create-dmg.sh \
  .build/distribution/VoxHearth.app \
  .build/distribution/VoxHearth-v0.4.0-unsigned.dmg
```

Or run both validation and packaging:

```sh
VERSION=0.4.0 BUILD_NUMBER=1 ./scripts/build-release-local.sh
```

The local app has an anonymous ad-hoc signature so LaunchServices can validate
its complete bundle and resources. The DMG is unsigned, and neither artifact
has a trusted publisher identity or Apple notarization. They are suitable for
development. The same form of artifact may be published only as an explicitly
named development prerelease with checksums, source, SBOM, provenance, GitHub
attestations, and prominent Gatekeeper warnings. Existing output is never
overwritten; move it aside or remove the specific `.build/distribution`
artifact before rebuilding.

The automated development path is
`.github/workflows/development-release.yml`. It requires no Apple secrets and
publishes only tag `v0.4.0-dev.4` as a GitHub prerelease. It must not be renamed
to `VoxHearth-v0.4.0.dmg`, marked as the latest stable release, or described as
signed/notarized.

## Sign and notarize manually

Public releases require a paid Apple Developer Program membership, a valid
**Developer ID Application** certificate, and an App Store Connect API key with
notarization access.

With the certificate already installed in your keychain:

```sh
export MACOS_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID1234)'
export APPLE_TEAM_ID='TEAMID1234'

./scripts/sign-release.sh .build/distribution/VoxHearth.app
./scripts/archive-app.sh \
  .build/distribution/VoxHearth.app \
  .build/distribution/VoxHearth-v0.4.0-notary.zip

export ASC_KEY_ID='ABC123DEFG'
export ASC_ISSUER_ID='00000000-0000-0000-0000-000000000000'
export ASC_PRIVATE_KEY_PATH='/absolute/path/to/AuthKey_ABC123DEFG.p8'

./scripts/notarize-release.sh \
  .build/distribution/VoxHearth-v0.4.0-notary.zip \
  .build/distribution/VoxHearth.app

./scripts/create-dmg.sh \
  .build/distribution/VoxHearth.app \
  .build/distribution/VoxHearth-v0.4.0.dmg
./scripts/sign-release.sh .build/distribution/VoxHearth-v0.4.0.dmg
./scripts/notarize-release.sh \
  .build/distribution/VoxHearth-v0.4.0.dmg \
  .build/distribution/VoxHearth-v0.4.0.dmg

./scripts/verify-release.sh .build/distribution/VoxHearth-v0.4.0.dmg
```

The app is notarized and stapled before it enters the DMG. The DMG is then
signed, notarized, and stapled separately.

## Release source, SBOM, and provenance

Create the complete corresponding source archive for the checked-out release
tag:

```sh
./scripts/create-source-bundle.sh v0.4.0 0.4.0 \
  .build/distribution/VoxHearth-v0.4.0-source.tar.gz
```

This Git archive includes the exact VoxHearth tree and its complete reviewed
FluidAudio subset under `Vendor/FluidAudioLocal`.

The release workflow also runs:

```sh
./scripts/generate-sbom.py --version 0.4.0 --source-revision "$GIT_COMMIT" \
  --artifact .build/distribution/VoxHearth-v0.4.0.dmg \
  --output .build/distribution/VoxHearth-v0.4.0.spdx.json
```

`generate-provenance.py` records artifact and material digests. The pinned
`actions/attest` workflow action signs separate SLSA build-provenance and SPDX
SBOM attestations using GitHub's OIDC identity; the JSON metadata file is
explanatory and is not a substitute for those signed attestations.

## What is never committed

- model binaries or compiled `*.mlmodelc` directories;
- `.app`, `.zip`, `.dmg`, SBOM, provenance, or checksum build output;
- Developer ID certificates, temporary keychains, App Store Connect keys, or
  any password/token; and
- SwiftPM build/checkouts under `.build/`.

Official binaries live as GitHub Release assets, not as Git objects.
