# VoxHearth

**Dictation that stays home.**

[![Build](https://github.com/stephansturges/voxhearth-mac/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/stephansturges/voxhearth-mac/actions/workflows/build.yml)

VoxHearth is a small, open-source macOS menu bar app for private dictation. It
records into memory, transcribes with a bundled Core ML model, and inserts the
result into the focused app. The installed app has no account, telemetry,
automatic updater, remote API, or runtime model download.

![VoxHearth app icon](Brand/VoxHearthIcon.svg)

## What “local” means

```text
microphone → in-memory audio → bundled Core ML model → in-memory text → focused app
```

- Audio and transcripts are not written to a VoxHearth history or cache. If
  insertion fails, the transcript may remain in memory for up to two minutes so
  you can Retry or Discard it; it is then discarded automatically.
- The model is part of the signed app and is loaded through a reviewed,
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

Official binaries exist only as tagged [GitHub Releases](../../releases). If
that page does not list `v0.1.0`, no official VoxHearth binary has been
published yet; build from source and treat any unsigned local DMG as a
development artifact.

To install a published release:

1. Open the [latest GitHub release](../../releases/latest) and confirm its tag.
2. Download the matching `VoxHearth-v<VERSION>.dmg` and `SHA256SUMS`.
3. Verify the checksum and, optionally, the GitHub provenance/SBOM attestations by
   following [VERIFY_RELEASE.md](Documentation/VERIFY_RELEASE.md).
4. Open the DMG, drag VoxHearth to Applications, and launch it.
5. Complete the microphone and Accessibility permission steps.

The release workflow publishes a DMG only after it is signed with a Developer
ID Application certificate, notarized by Apple, and given a stapled ticket.
VoxHearth has no automatic updater; install future versions manually from
GitHub Releases.

## Use

The default shortcut is **Control-Option-Space**. Hold it while speaking and
release to transcribe and insert. You can also start and stop from the menu bar.
Settings let you choose the shortcut, microphone, and one of the model's 25
supported European languages.

The Accessibility insertion path is preferred. Clipboard compatibility is an
explicit opt-in for applications that reject the normal paths; clipboard
managers and Universal Clipboard can observe that temporary value.

## Build from source

Xcode 26.2 and its Swift 6 toolchain are the pinned release environment.

```sh
./scripts/local-check.sh
./scripts/fetch-model.sh
./scripts/build-app-bundle.sh
```

The app appears at `.build/distribution/VoxHearth.app`. To create a local,
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
- The model is pinned to Hugging Face revision
  `aed02740059203c4a87495924f685de3722ae9ce`.
- [`Models/parakeet-tdt-0.6b-v3-coreml.json`](Models/parakeet-tdt-0.6b-v3-coreml.json)
  locks every permitted model file by byte count and SHA-256.
- Each release includes checksums, SPDX 2.3 SBOM, provenance metadata, a
  complete source archive containing the reviewed FluidAudio subset, and GitHub
  provenance and SBOM attestations.

The signed DMG is not bit-for-bit reproducible because Apple timestamps,
notarization tickets, and disk-image metadata vary. Its source and model inputs
are immutable and independently checkable.

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
