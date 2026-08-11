# VoxHearth 0.2.1 Development Preview 2

This preview keeps the Accessibility and foreground-Settings fixes from
Development Preview 1 and makes saved microphone selection resilient to device
disconnects.

## What changed

- If a chosen microphone UID no longer resolves or no longer exposes an input
  stream, VoxHearth starts recording with the current macOS system-default
  microphone instead of failing dictation.
- The stale selection is cleared and persisted, so later dictations continue
  using the system default until another microphone is selected.
- Settings displays a brief notice when this fallback occurs.

## Install this unsigned development preview

1. Download `VoxHearth-v0.2.1-dev.2-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
2. Open the DMG and drag VoxHearth to Applications, replacing the older build.
3. Because this preview is ad-hoc signed and not notarized, follow the documented
   **Open Anyway** procedure in `Documentation/VERIFY_RELEASE.md`.
4. If text insertion is not authorized after replacement, open VoxHearth
   Settings → Privacy → **Set Up Accessibility** and follow the on-screen steps.

Source revision: `{{SOURCE_REVISION}}`

The release workflow publishes the source archive, SPDX SBOM, provenance record,
checksums, and GitHub attestations next to the DMG.
