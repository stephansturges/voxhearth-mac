# VoxHearth

**Dictation that stays home.**

[![Build](https://github.com/stephansturges/voxhearth-mac/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/stephansturges/voxhearth-mac/actions/workflows/build.yml)

VoxHearth is a small, open-source macOS menu bar app for private dictation. It
records into memory, transcribes with one of two bundled Core ML models, and inserts the
result into the focused app. The installed app has no account, telemetry,
automatic updater, remote API, or runtime model download.

![VoxHearth app icon](Brand/VoxHearthIcon.svg)

## Origin and credit

VoxHearth is a privacy-focused fork, not a from-scratch implementation. It is
based on [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) v1.5.1,
and the upstream authors retain credit through the preserved Git history,
copyright notices, and GPL license. This fork replaces the product identity and
reduces the application to one local-only dictation path; the exact fork point
and a summary of the changes are documented in [UPSTREAM.md](UPSTREAM.md).

## What “local” means

```text
microphone → in-memory audio → bundled Core ML model → in-memory text → focused app
```

- Audio and transcripts are not written to a VoxHearth history or cache. If
  insertion fails, the transcript may remain in memory for up to two minutes so
  you can Retry or Discard it; it is then discarded automatically.
- Both selectable models are part of the app and are loaded through a reviewed,
  network-free FluidAudio subset; downloader and cache clients are not linked.
- The normal insertion paths use macOS Accessibility or Unicode keyboard
  events. An optional clipboard compatibility fallback is off by default.
- Logs contain fixed operation names and error types, never audio, transcript
  text, clipboard contents, or file paths.
- Release checks reject network entitlements, known updater/network
  dependencies, unapproved model files, and source use of network APIs.

Building, signing, and Apple notarization require network access. Running the
installed app does not. Read the complete [privacy statement](Documentation/PRIVACY.md)
and [threat model](Documentation/THREAT_MODEL.md), including the macOS and
destination-app trust boundaries.

## Requirements

- Apple Silicon Mac
- macOS 14 Sonoma or later
- Microphone permission
- Accessibility permission to insert text into other applications

## Install

The current downloadable build is
[`v0.2.0-dev.1`](https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.0-dev.1),
an explicitly **unsigned and unnotarized development prerelease**. It includes
the bundled model, checksums, complete source, SBOM, provenance, and GitHub
attestations, but it has no trusted Apple publisher identity. macOS is expected
to block it on first launch.

To install that development preview:

1. Download `VoxHearth-v0.2.0-dev.1-unsigned.dmg` and `SHA256SUMS` from the same
   release.
2. Verify the checksum by following
   [VERIFY_RELEASE.md](Documentation/VERIFY_RELEASE.md).
3. Open the DMG and drag VoxHearth to Applications.
4. Try to launch it. If macOS blocks it and you accept the development-build
   risk after verification, use the per-app **Open Anyway** control in
   **System Settings → Privacy & Security**. Never disable Gatekeeper globally.
5. Complete the microphone and Accessibility permission steps.

The first launch opens a visible setup window. After setup, VoxHearth remains
in the menu bar; launching it again reuses the existing instance instead of
registering a second dictation listener.

The future official `v0.2.0` release remains reserved for a DMG signed with a
Developer ID Application certificate, notarized by Apple, and given a stapled
ticket. No such official build exists yet because the project does not have the
required Apple signing credentials. VoxHearth has no automatic updater; install
future versions manually from GitHub Releases.

## Use

The default shortcut is **Control-Option-Space**. Hold it while speaking and
release to transcribe and insert. You can also start and stop from the menu bar.
Settings let you choose the shortcut, microphone, speech model, and language.
The multilingual 600M model remains the default and supports 25 European
languages. The compact 110M model is English-only and is intended for faster
startup and lower memory use on smaller Apple silicon Macs.

The menu panel exposes the shortcut editor directly. VoxHearth also accepts an
unmodified F13-F20 key for USB macro buttons and device remapping utilities. In
Settings, an optional middle or extra mouse/accessory button can be captured as
a second hold-to-talk control. Devices that do not present a keyboard or mouse
event require a dedicated local adapter.

Direct, phone-free **Pebble Index 01** support is being designed as a native
CoreBluetooth audio source, with no webhook, MCP bridge, or network relay. The
local transcription ingress is ready, but the driver is not advertised as
working until Pebble's unpublished collection-transfer layer is available and
the complete flow passes physical-ring tests. See the evidence, security model,
and exact remaining work in
[PEBBLE_INDEX.md](Documentation/PEBBLE_INDEX.md).

To start VoxHearth automatically after signing in to your Mac:

1. Keep `VoxHearth.app` in `/Applications` rather than running it from a DMG or
   build folder.
2. Open the menu bar icon, choose **Settings**, and enable **Launch VoxHearth at
   login** under **Dictation → Mac**.
3. macOS will show the registration under **System Settings → General → Login
   Items & Extensions**.

This uses Apple's standard login-item service and does not require a package
installer or privileged helper. Disable the setting before moving or deleting
the app. Developer ID signing and notarization are still needed for a smooth,
trusted public download; they are separate from the login-item mechanism.

The Accessibility insertion path is preferred. Clipboard compatibility is an
explicit opt-in for applications that reject the normal paths; clipboard
managers and Universal Clipboard can observe that temporary value.

## Build from source

Xcode 26.2 and its Swift 6 toolchain are the pinned release environment.

```sh
./scripts/local-check.sh
./scripts/fetch-models.sh
./scripts/build-app-bundle.sh
```

The app appears at `.build/distribution/VoxHearth.app`. It receives an anonymous
ad-hoc signature so the complete local bundle launches consistently, but it has
no trusted publisher identity or Apple notarization. To create a local,
unsigned development DMG in one command:

```sh
./scripts/build-release-local.sh
```

Model and DMG bytes live under `.build/` and are never committed. See
[BUILDING.md](Documentation/BUILDING.md) for signing, notarization, source
bundling, and the exact release credentials.

## Reproducible inputs and release evidence

- `Vendor/FluidAudioLocal` is an attributed, network-free subset adapted from
  FluidAudio commit `19600a485baa4998812e4654b70d2bab8f2c9949`
  (release 0.15.5). The root package has no remote runtime dependency.
- The multilingual model is pinned to Hugging Face revision
  `aed02740059203c4a87495924f685de3722ae9ce`.
- The compact English model is pinned to Hugging Face revision
  `9bc92ead6e8f17eca92a869fd578ae76842b82ba`.
- [`Models/parakeet-tdt-0.6b-v3-coreml.json`](Models/parakeet-tdt-0.6b-v3-coreml.json)
  and [`Models/parakeet-tdt-ctc-110m-coreml.json`](Models/parakeet-tdt-ctc-110m-coreml.json)
  lock every permitted model file by byte count and SHA-256.
- Each published build includes checksums, SPDX 2.3 SBOM, provenance metadata, a
  complete source archive containing the reviewed FluidAudio subset, and GitHub
  provenance and SBOM attestations.

Development prereleases are visibly named `unsigned` and describe the absent
Apple trust properties in both their notes and provenance. A future signed DMG
will not be bit-for-bit reproducible because Apple timestamps, notarization
tickets, and disk-image metadata vary. Source and model inputs remain immutable
and independently checkable in both channels.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report
vulnerabilities privately as described in [SECURITY.md](SECURITY.md); never put
private audio, transcripts, or credentials in a public issue.

## License and provenance

VoxHearth is GPL-3.0-or-later. It is a renamed, independent fork of TypeWhisper
v1.5.1. See [LICENSE](LICENSE), [NOTICE](NOTICE), and [UPSTREAM.md](UPSTREAM.md).

The bundled FluidAudio code is Apache-2.0, its incorporated components retain
their notices, and the model is conservatively redistributed under CC BY 4.0.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md),
[MODEL_PROVENANCE.md](Documentation/MODEL_PROVENANCE.md), and [LICENSES](LICENSES).

TypeWhisper is a trademark of its respective owner. VoxHearth is not affiliated
with or endorsed by TypeWhisper, NVIDIA, FluidInference, or Apple.
