# VoxHearth 0.4.0 Development Preview 1

This unsigned preview adds optional, fully local transcript cleanup with
S1-mini by Superwhisper. Cleanup is disclosed during setup, checked by default,
uses semi-formal style by default, and can be disabled at any time.

## What changed

- Final English dictation can be cleaned for fillers, false starts,
  punctuation, capitalization, numbers, dates, and spoken addresses.
- Starting a new session with the complete word `list` or `email` selects the
  corresponding trained structure/context when that detector is enabled.
  Mentioning either word later does not activate it.
- Setup includes raw-versus-cleaned examples and a live test area. The top
  overlay shows cleanup progress after release and exposes cancellation and
  safe recovery states.
- Cleanup is session-isolated, deadline-bounded, and never delays microphone
  release or blocks a newer hotkey press. Invalid or unavailable cleanup falls
  back to the command-stripped original transcript.
- S1-mini runs through a sealed, statically linked llama.cpp Metal runtime. The
  app has no account, telemetry, runtime networking, updater, model download,
  dynamic backend discovery, or runtime shader compilation.
- The complete S1-mini naming license, Qwen3-0.6B and llama.cpp attribution,
  exact model/runtime manifests, SPDX relationships, and provenance are
  included in the app and release evidence.

Cleanup adds a roughly 462 MiB bundled model and consumes additional local
memory and compute while enabled. Performance depends on the Mac and transcript
length. The feature is English-only in this release.

## Install this unsigned development preview

1. Quit the currently running VoxHearth before replacing it.
2. Download `VoxHearth-v0.4.0-dev.1-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
3. Open the DMG and drag VoxHearth to Applications, replacing the older build.
4. This preview is ad-hoc signed and not notarized. Follow the per-app **Open
   Anyway** procedure in `Documentation/VERIFY_RELEASE.md`; never disable
   Gatekeeper globally.
5. Launch VoxHearth, review the cleanup disclosure and examples, and complete
   the update permission flow.

Source revision: `{{SOURCE_REVISION}}`

The workflow publishes the complete three-model DMG, sealed Metal library,
source archive, SPDX SBOM, provenance record, checksums, and GitHub attestations.
