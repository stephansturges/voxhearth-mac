# Verify a VoxHearth build

## Current development prerelease

`v0.4.0-dev.8` is intentionally ad-hoc signed and not notarized. Download these
files from that exact prerelease:

```text
VoxHearth-v0.4.0-dev.8-unsigned.dmg
VoxHearth-v0.4.0-dev.8.spdx.json
VoxHearth-v0.4.0-dev.8-provenance.json
VoxHearth-v0.4.0-dev.8-source.tar.gz
SHA256SUMS
```

Run:

```sh
shasum -a 256 -c SHA256SUMS
gh attestation verify VoxHearth-v0.4.0-dev.8-unsigned.dmg \
  --repo stephansturges/voxhearth-mac
```

Confirm the attestation identifies
`.github/workflows/development-release.yml`, tag `v0.4.0-dev.8`, and the commit
shown in the release notes. Inspect the provenance JSON and confirm it says
`development-prerelease`, `anonymous ad-hoc signature`, and `notarization:
absent`.

After mounting the DMG, this command must validate the app's internal ad-hoc
seal:

```sh
codesign --verify --deep --strict --verbose=2 /Volumes/VoxHearth/VoxHearth.app
codesign -dvvv /Volumes/VoxHearth/VoxHearth.app
```

The second command must report `Signature=adhoc` and no ten-character Apple
Team Identifier. `spctl` and `stapler` are expected to reject this development
build; that rejection is not a defect. If you choose to run it after reviewing
the source and verification evidence, use only macOS's per-app **Open Anyway**
control. Do not disable Gatekeeper globally.

## Future official release

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
VoxHearth-v0.4.0.dmg
VoxHearth-v0.4.0.spdx.json
VoxHearth-v0.4.0-provenance.json
VoxHearth-v0.4.0-source.tar.gz
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
gh attestation verify VoxHearth-v0.4.0.dmg --repo OWNER/voxhearth-mac
```

Replace `OWNER` with the repository owner shown on the release page. Confirm
that the returned provenance and SBOM attestations name
`.github/workflows/release.yml`, the expected repository, and the v0.4.0 tag
commit. GitHub documents how to apply stricter
workflow/ref/signing-repository policies with additional flags.

## Verify the Apple signature and notarization

```sh
codesign --verify --strict --verbose=2 VoxHearth-v0.4.0.dmg
xcrun stapler validate VoxHearth-v0.4.0.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=2 VoxHearth-v0.4.0.dmg
```

Mount the DMG and inspect the app:

```sh
hdiutil attach -readonly -nobrowse VoxHearth-v0.4.0.dmg
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
  /path/to/VoxHearth-v0.4.0.dmg
```

## Inspect the locked models and cleanup runtime

The embedded manifests must be byte-identical to
`Models/parakeet-tdt-0.6b-v3-coreml.json`,
`Models/parakeet-tdt-ctc-110m-coreml.json`, and `Models/s1-mini-gguf.json` at
the release tag. The verifier checks the multilingual model's 21 files totaling
483,105,645 bytes, compact model's 16 files totaling 227,466,209 bytes, and
S1-mini's one 484,219,808-byte GGUF, rejecting extra files or directories.
Their immutable Hugging Face revisions are
`aed02740059203c4a87495924f685de3722ae9ce` and
`9bc92ead6e8f17eca92a869fd578ae76842b82ba`, and
`8eab4779866f477ae6e7f237ca45fc2c65153f50`.

The app must also contain exactly `Resources/Metal/ggml-llama.metallib` and
its byte-identical reviewed manifest. Run `scripts/check-attribution.py --app`
from the tagged source to compare the complete Legal tree, including the exact
S1-mini by Superwhisper license and naming clause, Qwen3-0.6B license, and
llama.cpp MIT license.

## Inspect source and SBOM

Extract `VoxHearth-v0.4.0-source.tar.gz`. It must contain:

- the tagged VoxHearth source, both model manifests, workflows, and build scripts;
- `Vendor/FluidAudioLocal`, including provenance from FluidAudio commit
  `19600a485baa4998812e4654b70d2bab8f2c9949`; and
- all GPL, Apache, component, and model license/notice files.

The SPDX JSON should additionally list S1-mini by Superwhisper as
`Apache-2.0 AND LicenseRef-S1-mini-Naming-Clause`, its Qwen3-0.6B base as
Apache-2.0, and llama.cpp as MIT. The extracted licensing information must
contain the complete naming term. The provenance JSON should reproduce the
SHA-256 of the DMG and source archive and pin the model card, GGUF, runtime,
metallib, and license inputs.

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
