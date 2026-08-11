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
development, but an official v0.2.1 artifact is built only in the pinned
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

The two Core ML models are separate build inputs pinned to Hugging Face revisions:

```text
aed02740059203c4a87495924f685de3722ae9ce
9bc92ead6e8f17eca92a869fd578ae76842b82ba
```

## Test and compile

From the repository root:

```sh
./scripts/local-check.sh
```

This resolves the exact Swift dependency, runs all tests, builds debug and
release configurations, validates shell and Python helpers, validates both model
manifest, checks action pins, rejects tracked model/release secrets, and scans
the runtime source for forbidden networking/updater APIs.

## Fetch the build-only models

```sh
./scripts/fetch-models.sh
```

The script downloads exactly the two manifests' allowlisted files over HTTPS
into fresh temporary directories, verifies every size and SHA-256, and then
moves the valid trees to:

```text
.build/models/parakeet-tdt-0.6b-v3-coreml
.build/models/parakeet-tdt-ctc-110m-coreml
```

It does not download optional model variants. It refuses to overwrite an
existing invalid destination. To validate both payloads without network
access:

```sh
./scripts/verify-model.py .build/models/parakeet-tdt-0.6b-v3-coreml
./scripts/verify-model.py \
  --manifest Models/parakeet-tdt-ctc-110m-coreml.json \
  .build/models/parakeet-tdt-ctc-110m-coreml
```

## Construct the app and development DMG

```sh
./scripts/build-app-bundle.sh \
  --version 0.2.1 \
  --build 1 \
  --output .build/distribution/VoxHearth.app

./scripts/create-dmg.sh \
  .build/distribution/VoxHearth.app \
  .build/distribution/VoxHearth-v0.2.1-unsigned.dmg
```

Or run both validation and packaging:

```sh
VERSION=0.2.1 BUILD_NUMBER=1 ./scripts/build-release-local.sh
```

The local app has an anonymous ad-hoc signature so LaunchServices can validate
its complete bundle and resources. The DMG is unsigned, and neither artifact
has a trusted publisher identity or Apple notarization. They are suitable for
development. The same form of artifact may be published only as an explicitly
named development prerelease with checksums, source, SBOM, provenance, GitHub
attestations, and prominent Gatekeeper warnings. Existing output is never
overwritten; move it aside or remove the specific `.build/distribution`
artifact before rebuilding.

The automated development path is
`.github/workflows/development-release.yml`. It requires no Apple secrets and
publishes only tag `v0.2.1-dev.2` as a GitHub prerelease. It must not be renamed
to `VoxHearth-v0.2.1.dmg`, marked as the latest stable release, or described as
signed/notarized.

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
  .build/distribution/VoxHearth-v0.2.1-notary.zip

export ASC_KEY_ID='ABC123DEFG'
export ASC_ISSUER_ID='00000000-0000-0000-0000-000000000000'
export ASC_PRIVATE_KEY_PATH='/absolute/path/to/AuthKey_ABC123DEFG.p8'

./scripts/notarize-release.sh \
  .build/distribution/VoxHearth-v0.2.1-notary.zip \
  .build/distribution/VoxHearth.app

./scripts/create-dmg.sh \
  .build/distribution/VoxHearth.app \
  .build/distribution/VoxHearth-v0.2.1.dmg
./scripts/sign-release.sh .build/distribution/VoxHearth-v0.2.1.dmg
./scripts/notarize-release.sh \
  .build/distribution/VoxHearth-v0.2.1.dmg \
  .build/distribution/VoxHearth-v0.2.1.dmg

./scripts/verify-release.sh .build/distribution/VoxHearth-v0.2.1.dmg
```

The app is notarized and stapled before it enters the DMG. The DMG is then
signed, notarized, and stapled separately.

## Release source, SBOM, and provenance

Create the complete corresponding source archive for the checked-out release
tag:

```sh
./scripts/create-source-bundle.sh v0.2.1 0.2.1 \
  .build/distribution/VoxHearth-v0.2.1-source.tar.gz
```

This Git archive includes the exact VoxHearth tree and its complete reviewed
FluidAudio subset under `Vendor/FluidAudioLocal`.

The release workflow also runs:

```sh
./scripts/generate-sbom.py --version 0.2.1 --source-revision "$GIT_COMMIT" \
  --artifact .build/distribution/VoxHearth-v0.2.1.dmg \
  --output .build/distribution/VoxHearth-v0.2.1.spdx.json
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
