# VoxHearth 0.2.1 Development Preview 1

This preview fixes two macOS integration problems while preserving VoxHearth's
local-only runtime and the two bundled speech-model choices from 0.2.0.

## What changed

- Settings now activates VoxHearth and opens in front of the current app instead
  of appearing behind other windows.
- Settings → Privacy now shows the current Accessibility status and provides a
  direct **Set Up Accessibility** button.
- The recovery panel explains how to remove a stale VoxHearth authorization,
  add the current app from `/Applications`, enable it, and relaunch after an
  update.

## Install this unsigned development preview

1. Download `VoxHearth-v0.2.1-dev.1-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
2. Open the DMG and drag VoxHearth to Applications, replacing the older build.
3. Because this preview is ad-hoc signed and not notarized, follow the documented
   **Open Anyway** procedure in `Documentation/VERIFY_RELEASE.md`.
4. If text insertion is not authorized, open VoxHearth Settings → Privacy →
   **Set Up Accessibility** and follow the on-screen replacement instructions.

Source revision: `{{SOURCE_REVISION}}`

The release workflow publishes the source archive, SPDX SBOM, provenance record,
checksums, and GitHub attestations next to the DMG.
