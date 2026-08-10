# VoxHearth 0.1.0 Development Preview 1

> [!WARNING]
> This is an **unsigned, unnotarized development prerelease**. The app bundle
> has only an anonymous ad-hoc signature. macOS cannot verify a publisher, and
> Apple has not notarized this build. Do not mistake it for the future official
> `v0.1.0` release.

This preview provides private, local dictation for Apple Silicon Macs running
macOS 14 or later. It includes the bundled transcription model and does not
need a runtime network connection, account, telemetry service, automatic
updater, cloud transcription service, or model download.

## Install

1. Download `VoxHearth-v0.1.0-dev.1-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum before opening the disk image.
2. Drag VoxHearth to Applications.
3. Try to open VoxHearth. macOS is expected to block this unnotarized preview.
4. If you accept that risk after verifying the source and checksum, open
   **System Settings → Privacy & Security**, find the blocked VoxHearth entry,
   and choose **Open Anyway**. Do not disable Gatekeeper globally.
5. Complete the microphone and Accessibility permission steps.

For a trusted publisher identity and normal one-click installation, wait for
the signed and notarized `v0.1.0` release.

## Included changes

- Reliable single-instance startup and a visible first-launch setup window.
- Brief local start cue before microphone capture.
- Shortcut editing directly in the menu panel.
- Optional middle/extra mouse-button and unmodified F13-F20 activation.
- Optional launch-at-login checkbox backed by the standard macOS service.
- Memory-only local Parakeet transcription and privacy-preserving insertion.
- A bounded external-audio ingress for future direct Pebble Index 01 support;
  no unverified Bluetooth driver is included.

Pebble Index 01 protocol support is tracked upstream in
[coredevices/mobileapp#333](https://github.com/coredevices/mobileapp/issues/333).

Source commit: `{{SOURCE_REVISION}}`.

## Verification material

This prerelease includes checksums, complete corresponding source, an SPDX 2.3
SBOM, human-readable provenance metadata, and GitHub build-provenance/SBOM
attestations for the unsigned DMG. These establish source and workflow origin;
they are not substitutes for Apple Developer ID signing or notarization.

The bundled Core ML model is FluidInference's conversion of NVIDIA
Parakeet-TDT-0.6B-v3 at revision
`aed02740059203c4a87495924f685de3722ae9ce`, redistributed conservatively under
CC BY 4.0. VoxHearth is an independent GPL-3.0-or-later fork of TypeWhisper
v1.5.1 and is not endorsed by TypeWhisper, NVIDIA, FluidInference, Core Devices,
or Apple.
