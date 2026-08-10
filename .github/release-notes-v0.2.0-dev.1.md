# VoxHearth 0.2.0 Development Preview 1

This preview adds a second, compact on-device speech model while preserving
VoxHearth's local-only runtime. The DMG now contains both models; no model is
downloaded after installation.

## What changed

- Added Parakeet TDT-CTC 110M for faster startup and lower memory use on smaller
  Apple silicon Macs.
- Added a Speech model picker in Settings. The existing multilingual 600M model
  remains the default; the compact model supports English only.
- Model selection is stored locally and older settings migrate to the existing
  multilingual behavior.
- Both immutable Core ML payloads are hash-verified, exercised under a deny-network
  test profile, represented in the SBOM, and bundled into the app.

## Install this unsigned development preview

1. Download `VoxHearth-v0.2.0-dev.1-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
2. Open the DMG and drag VoxHearth to Applications.
3. Because this preview is ad-hoc signed and not notarized, follow the documented
   **Open Anyway** procedure in `Documentation/VERIFY_RELEASE.md`.

Source revision: `{{SOURCE_REVISION}}`

The release workflow publishes the source archive, SPDX SBOM, provenance record,
checksums, and GitHub attestations next to the DMG.
