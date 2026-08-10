# Verify a VoxHearth release

Verification answers three different questions:

1. Did the files arrive unchanged?
2. Did the official GitHub workflow build them from the claimed commit?
3. Did the claimed Apple developer sign them and did Apple accept them for
   notarization?

Perform all three checks before granting VoxHearth microphone and Accessibility
permissions.

## Download the release set

From the same GitHub release, download:

```text
VoxHearth-v0.1.0.dmg
VoxHearth-v0.1.0.spdx.json
VoxHearth-v0.1.0-provenance.json
VoxHearth-v0.1.0-source.tar.gz
SHA256SUMS
```

## Check SHA-256

Run from the download directory:

```sh
shasum -a 256 -c SHA256SUMS
```

Every listed asset must report `OK`. A checksum proves only that your copy
matches the published file; repository compromise could replace both.

## Verify GitHub provenance and SBOM attestations

Install the GitHub CLI, authenticate, and run from the download directory:

```sh
gh attestation verify VoxHearth-v0.1.0.dmg --repo OWNER/voxhearth-mac
```

Replace `OWNER` with the repository owner shown on the release page. Confirm
that the returned provenance and SBOM attestations name
`.github/workflows/release.yml`, the expected repository, and the v0.1.0 tag
commit. GitHub documents how to apply stricter
workflow/ref/signing-repository policies with additional flags.

## Verify the Apple signature and notarization

```sh
codesign --verify --strict --verbose=2 VoxHearth-v0.1.0.dmg
xcrun stapler validate VoxHearth-v0.1.0.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=2 VoxHearth-v0.1.0.dmg
```

Mount the DMG and inspect the app:

```sh
hdiutil attach -readonly -nobrowse VoxHearth-v0.1.0.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/VoxHearth/VoxHearth.app
xcrun stapler validate /Volumes/VoxHearth/VoxHearth.app
spctl --assess --type execute --verbose=2 /Volumes/VoxHearth/VoxHearth.app
codesign -dvvv /Volumes/VoxHearth/VoxHearth.app
codesign -d --entitlements :- /Volumes/VoxHearth/VoxHearth.app
hdiutil detach /Volumes/VoxHearth
```

Confirm the Developer ID identity and `TeamIdentifier` match the value published
in that release's notes. Entitlements must not contain network client/server,
iCloud, associated domains, app groups, or `get-task-allow`.

From a checkout of the same source tag, the repository verifier automates these
checks and rehashes all model files inside the mounted app:

```sh
APPLE_TEAM_ID='EXPECTEDTEAM' ./scripts/verify-release.sh \
  /path/to/VoxHearth-v0.1.0.dmg
```

## Inspect the locked model

The embedded manifest must be byte-identical to
`Models/parakeet-tdt-0.6b-v3-coreml.json` at the release tag. The verifier
checks exactly 21 files totaling 483,105,645 bytes and rejects extra files or
directories. The manifest names immutable Hugging Face revision
`aed02740059203c4a87495924f685de3722ae9ce`.

## Inspect source and SBOM

Extract `VoxHearth-v0.1.0-source.tar.gz`. It must contain:

- the tagged VoxHearth source, model manifest, workflows, and build scripts;
- `Vendor/FluidAudioLocal`, including provenance from FluidAudio commit
  `19600a485baa4998812e4654b70d2bab8f2c9949`; and
- all GPL, Apache, component, and model license/notice files.

The SPDX JSON should list VoxHearth, FluidAudio 0.15.5, and the exact Parakeet
model revision with their respective GPL-3.0-or-later, Apache-2.0, and
CC-BY-4.0 declarations. The provenance JSON should reproduce the SHA-256 of the
DMG and source archive.

## Check the runtime offline claim

Static verification cannot prove the absence of every malicious behavior, but
it makes the intended boundary inspectable:

- search `Sources/` for `URLSession`, Network.framework, sockets, WebSockets,
  Sparkle, appcasts, telemetry, and downloader APIs;
- confirm `Package.swift` has no remote package dependency and uses only the
  committed `FluidAudioLocal` target for ASR;
- confirm the app has no network entitlement and no linked updater/network SDK;
- run while disconnected and confirm dictation still works; and
- optionally use a local outbound firewall or `nettop` to observe that the
  VoxHearth process opens no connections during launch, dictation, insertion,
  and quit.

The installed app does not check GitHub for updates. Visiting the release page
and downloading a future DMG are deliberate user actions outside the process.

If any check fails, do not bypass Gatekeeper or grant permissions. Save only
non-sensitive output and report privately as described in
[SECURITY.md](../SECURITY.md).
