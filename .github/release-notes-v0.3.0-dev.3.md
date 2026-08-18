# VoxHearth 0.3.0 Development Preview 3

This preview restores the fast hold-to-talk response of earlier builds while
keeping the optional, fully local live transcript overlay. It supersedes
Development Preview 2 because its internal build number is 948, ensuring Macs
already running build 947 recognize the replacement and show the required
update/Accessibility setup flow.

## What changed

- The hidden overlay no longer runs a continuous SwiftUI waveform animation
  between dictation sessions. In side-by-side post-warm-up sampling, the exact
  Preview 1 build remained at roughly 3–6% CPU while idle; this build registered
  0.0% in every corresponding sample.
- Carbon hotkey events delivered on the main event loop are handled immediately
  instead of being queued through an additional main-actor task.
- Live preview copies only the most recent eight seconds of audio rather than
  exposing the full, growing capture buffer every 600 ms.
- Releasing the shortcut stops microphone capture before waiting for preview
  work to end, and final transcription no longer overlaps an in-flight preview.
- Fixed-name, content-free lifecycle events make any remaining delay measurable
  in Console without recording audio, transcript text, clipboard data, or paths.

The regression suite includes a cancellation-resistant preview engine and
verifies that preview and final transcription have a maximum concurrency of one.

## Install this unsigned development preview

1. Quit the currently running VoxHearth before replacing it.
2. Download `VoxHearth-v0.3.0-dev.3-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
3. Open the DMG and drag VoxHearth to Applications, replacing the older build.
4. Because this preview is ad-hoc signed and not notarized, follow the documented
   **Open Anyway** procedure in `Documentation/VERIFY_RELEASE.md`.
5. Launch VoxHearth and complete the update permission flow.

Source revision: `{{SOURCE_REVISION}}`

The release workflow publishes the complete two-model DMG, source archive,
SPDX SBOM, provenance record, checksums, and GitHub attestations.
