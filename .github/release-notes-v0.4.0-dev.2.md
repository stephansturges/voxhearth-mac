# VoxHearth 0.4.0 Development Preview 2

This unsigned preview combines the optional, fully local S1-mini transcript
cleanup feature with fixes aimed at keeping shortcut, preview, capture, and
cleanup behavior responsive during long-running use.

## What changed

- Final English dictation can be cleaned for fillers, false starts,
  punctuation, capitalization, numbers, dates, and spoken addresses.
- Starting a new session with the complete word `list` or `email` selects the
  corresponding trained structure/context when that detector is enabled.
  Mentioning either word later does not activate it.
- Setup includes raw-versus-cleaned examples and a live test area. The top
  overlay shows cleanup progress after release and exposes cancellation and
  safe recovery states.
- Superseded sessions now release recovery reservations and stale cancellation
  bookkeeping instead of retaining avoidable lifecycle state.
- After Metal cleanup falls back to CPU, the resident CPU session is reused
  instead of reloading the same model on subsequent requests.
- Completed cleanup operations cancel their delayed deadline work. The audio
  callback reuses bounded scratch storage instead of making a transient mono
  allocation for each multichannel input buffer.
- Performance signposts now identify overlapping operations independently, and
  lifecycle soak measurements execute optimized code and record their build
  configuration.
- Cleanup remains session-isolated, deadline-bounded, and cannot delay
  microphone release or block a newer hotkey press. Invalid or unavailable
  cleanup falls back to the command-stripped original transcript.
- S1-mini runs through a sealed, statically linked llama.cpp Metal runtime. The
  app has no account, telemetry, runtime networking, updater, model download,
  dynamic backend discovery, or runtime shader compilation.

Cleanup adds a roughly 462 MiB bundled model and consumes additional local
memory and compute while enabled. Performance depends on the Mac, system load,
and transcript length. The feature is English-only in this release. The
release-configured synthetic lifecycle soak did not detect degradation, but it
does not replace physical-microphone, Accessibility-target, or multi-day use
testing and no universal speedup is claimed.

## Verification performed

- 165 Swift tests
- debug and release builds plus release-binary policy checks
- offline/privacy, model-manifest, attribution, and packaging checks
- real local Parakeet smoke coverage
- release-configured lifecycle soak coverage
- independent Claude Opus/max code review with an approval verdict

## Install this unsigned development preview

1. Quit the currently running VoxHearth before replacing it.
2. Download `VoxHearth-v0.4.0-dev.2-unsigned.dmg` and `SHA256SUMS` from this
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
