# VoxHearth 0.1.0

VoxHearth is private, local dictation for Apple Silicon Macs running macOS 14
or later. Audio is transcribed with the model bundled inside the app; there is
no account, telemetry, automatic updater, cloud transcription, or runtime
download.

## Install

Download `VoxHearth-v0.1.0.dmg`, verify `SHA256SUMS`, open the disk image, and
drag VoxHearth to Applications. The app requests microphone access for capture
and Accessibility access for text insertion.

The DMG and app are signed and notarized. Expected Apple Developer Team ID:
`{{APPLE_TEAM_ID}}`.

Source commit: `{{SOURCE_REVISION}}`.

## Verify

This release includes:

- `SHA256SUMS`
- SPDX 2.3 SBOM
- human-auditable provenance metadata
- complete corresponding source with the reviewed network-free FluidAudio subset
- GitHub build-provenance and SPDX SBOM attestations for the final DMG

Follow `Documentation/VERIFY_RELEASE.md` at the source tag before installing.

## Model attribution

The bundled Core ML model is FluidInference's conversion of NVIDIA
Parakeet-TDT-0.6B-v3, revision
`aed02740059203c4a87495924f685de3722ae9ce`, redistributed conservatively under
CC BY 4.0. Full attribution and per-file hashes are included in the app and
source release.

VoxHearth is an independent GPL-3.0-or-later fork of TypeWhisper v1.5.1 and is
not endorsed by TypeWhisper, NVIDIA, FluidInference, or Apple.
