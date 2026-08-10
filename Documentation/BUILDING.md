# Building VoxHearth

VoxHearth is a Swift Package Manager macOS app. The release pipeline constructs
the `.app` bundle explicitly so every executable, model, entitlement, and legal
file has one auditable path into the signed artifact.

## Pinned release environment

- Git
- macOS runner image `macos-26`
- Xcode 26.2 and its Swift 6 toolchain
- Apple Silicon (`arm64`)
- Python 3 (standard library only)
- Apple command-line tools: `codesign`, `hdiutil`, `xcrun notarytool`,
  `xcrun stapler`, `spctl`, `plutil`, and `ditto`

macOS 14 is the deployment target. Other recent Xcode versions may work for
development, but an official v0.1.0 artifact is built only in the pinned
environment.

## Source dependencies

The root package has no remote Swift package dependency. It builds the local
`Vendor/FluidAudioLocal` target: a reviewed ASR-only subset adapted from
FluidAudio 0.15.5 at full commit:

```text
19600a485baa4998812e4654b70d2bab8f2c9949
```

FluidAudio has no external Swift package dependencies at that revision. The
vendored subset omits its HTTP, model-download/cache, CLI, speech synthesis,
and unrelated model surfaces. `Vendor/FluidAudioLocal/UPSTREAM.md` records file
provenance and modifications. Relevant third-party license texts remain under
`LICENSES/`.

The Core ML model is a separate build input pinned to Hugging Face revision:

```text
aed02740059203c4a87495924f685de3722ae9ce
```

## Test and compile

From the repository root:

```sh
./scripts/local-check.sh
```

This resolves the exact Swift dependency, runs all tests, builds debug and
release configurations, validates shell and Python helpers, validates the model
manifest, checks action pins, rejects tracked model/release secrets, and scans
the runtime source for forbidden networking/updater APIs.

## Fetch the build-only model

```sh
./scripts/fetch-model.sh
```

The script downloads exactly the manifest's 21 files over HTTPS into a fresh
temporary directory, verifies every size and SHA-256, and then moves the valid
tree to:

```text
.build/models/parakeet-tdt-0.6b-v3-coreml
```

It does not download optional model variants. It refuses to overwrite an
existing invalid destination. To validate an existing payload without network
access:

```sh
./scripts/verify-model.py .build/models/parakeet-tdt-0.6b-v3-coreml
```

## Construct the app and development DMG

```sh
./scripts/build-app-bundle.sh \
  --version 0.1.0 \
  --build 1 \
  --output .build/distribution/VoxHearth.app

./scripts/create-dmg.sh \
  .build/distribution/VoxHearth.app \
  .build/distribution/VoxHearth-v0.1.0-unsigned.dmg
```

Or run both validation and packaging:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 ./scripts/build-release-local.sh
```

These local artifacts are intentionally unsigned. They are suitable for
development, not public distribution. Existing output is never overwritten;
move it aside or remove the specific `.build/distribution` artifact before
rebuilding.

## Sign and notarize manually

Public releases require a paid Apple Developer Program membership, a valid
**Developer ID Application** certificate, and an App Store Connect API key with
notarization access.

With the certificate already installed in your keychain:

```sh
export MACOS_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID1234)'
export APPLE_TEAM_ID='TEAMID1234'

./scripts/sign-release.sh .build/distribution/VoxHearth.app
./scripts/archive-app.sh \
  .build/distribution/VoxHearth.app \
  .build/distribution/VoxHearth-v0.1.0-notary.zip

export ASC_KEY_ID='ABC123DEFG'
export ASC_ISSUER_ID='00000000-0000-0000-0000-000000000000'
export ASC_PRIVATE_KEY_PATH='/absolute/path/to/AuthKey_ABC123DEFG.p8'

./scripts/notarize-release.sh \
  .build/distribution/VoxHearth-v0.1.0-notary.zip \
  .build/distribution/VoxHearth.app

./scripts/create-dmg.sh \
  .build/distribution/VoxHearth.app \
  .build/distribution/VoxHearth-v0.1.0.dmg
./scripts/sign-release.sh .build/distribution/VoxHearth-v0.1.0.dmg
./scripts/notarize-release.sh \
  .build/distribution/VoxHearth-v0.1.0.dmg \
  .build/distribution/VoxHearth-v0.1.0.dmg

./scripts/verify-release.sh .build/distribution/VoxHearth-v0.1.0.dmg
```

The app is notarized and stapled before it enters the DMG. The DMG is then
signed, notarized, and stapled separately.

## Release source, SBOM, and provenance

Create the complete corresponding source archive for the checked-out release
tag:

```sh
./scripts/create-source-bundle.sh v0.1.0 0.1.0 \
  .build/distribution/VoxHearth-v0.1.0-source.tar.gz
```

This Git archive includes the exact VoxHearth tree and its complete reviewed
FluidAudio subset under `Vendor/FluidAudioLocal`.

The release workflow also runs:

```sh
./scripts/generate-sbom.py --version 0.1.0 --source-revision "$GIT_COMMIT" \
  --artifact .build/distribution/VoxHearth-v0.1.0.dmg \
  --output .build/distribution/VoxHearth-v0.1.0.spdx.json
```

`generate-provenance.py` records artifact and material digests. The pinned
`actions/attest` workflow action signs separate SLSA build-provenance and SPDX
SBOM attestations using GitHub's OIDC identity; the JSON metadata file is
explanatory and is not a substitute for those signed attestations.

## What is never committed

- model binaries or compiled `*.mlmodelc` directories;
- `.app`, `.zip`, `.dmg`, SBOM, provenance, or checksum build output;
- Developer ID certificates, temporary keychains, App Store Connect keys, or
  any password/token; and
- SwiftPM build/checkouts under `.build/`.

Official binaries live as GitHub Release assets, not as Git objects.
