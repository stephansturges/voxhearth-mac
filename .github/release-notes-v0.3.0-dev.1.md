# VoxHearth 0.3.0 Development Preview 1

This preview adds optional, fully local live transcription feedback while you
speak.

## What changed

- An off-by-default **Show live transcript overlay** checkbox is available in
  both the menu pop-down and Dictation settings.
- The overlay is a passive, single-line subtitle strip near the top-right of
  the active screen. It never takes focus from the app receiving dictation.
- It keeps only the newest ten recognized words visible, dropping older words
  from the left so the latest result is always readable.
- Preview inference uses at most the most recent eight seconds of in-memory
  audio and requests another pass after a short 600 ms pause. Actual cadence
  depends on the selected model and Mac.
- The complete recording is still transcribed separately after release, and
  only that final result is inserted. Preview and final text may differ.
- Preview text is never written to disk or Notification Center and clears on
  cancellation or shortly after completion.

The overlay performs extra local inference and makes dictated text visible to
nearby people or screen-capture software. Leave it disabled when display
privacy or minimum energy use is more important than immediate feedback.

## Install this unsigned development preview

1. Quit the currently running VoxHearth before replacing it.
2. Download `VoxHearth-v0.3.0-dev.1-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
3. Open the DMG and drag VoxHearth to Applications, replacing the older build.
4. Because this preview is ad-hoc signed and not notarized, follow the documented
   **Open Anyway** procedure in `Documentation/VERIFY_RELEASE.md`.
5. Launch VoxHearth, complete the update permission flow, then enable the live
   transcript overlay from its menu if desired.

Source revision: `{{SOURCE_REVISION}}`

The release workflow publishes the complete two-model DMG, source archive,
SPDX SBOM, provenance record, checksums, and GitHub attestations.
