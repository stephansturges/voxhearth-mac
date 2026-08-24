# Release checklist

VoxHearth has two deliberately separate publication channels:

- `.github/workflows/development-release.yml` is prepared to publish the
  ad-hoc-signed, unnotarized `v0.4.0-dev.5` GitHub prerelease without Apple
  secrets.
- `.github/workflows/release.yml` is prepared to publish the future Developer
  ID-signed and Apple-notarized `v0.4.0` release.

Manual building and signing are documented in [BUILDING.md](BUILDING.md).

## Publish v0.4.0-dev.5

Tags `v0.4.0-dev.2`, `v0.4.0-dev.3`, and `v0.4.0-dev.4` are failed publication
attempts. Their workflows stopped before packaging and they have no GitHub
Release or assets. Do not install or promote any of these tags.

- [ ] The development-release commit is reviewed and merged to `main`.
- [ ] `./scripts/local-check.sh` passes from a clean checkout.
- [ ] No model, app, DMG, certificate, key, or password is tracked by Git.
- [ ] Create annotated tag `v0.4.0-dev.5` on that exact commit and push it.
- [ ] Confirm the workflow publishes the unsigned DMG, source archive, SBOM,
      provenance, `SHA256SUMS`, and both GitHub attestations.
- [ ] Confirm GitHub marks the release as a prerelease and that its title,
      notes, artifact name, and provenance all say unsigned/unnotarized.
- [ ] Download the assets and follow the development verification path in
      [VERIFY_RELEASE.md](VERIFY_RELEASE.md).

This preview is useful for testing and source review. It is not a substitute
for Developer ID signing or notarization, and must never be marked `latest` or
presented as the official `v0.4.0` release.

## One-time prerequisites

1. Create the public GitHub repository and enable private vulnerability
   reporting.
2. Create a protected `release` GitHub Environment. Restrict deployments to
   tags matching `v*` and require maintainer approval.
3. Protect `main` and require the build workflow.
4. Enroll the publishing organization/person in the Apple Developer Program.
5. Create and export a Developer ID Application certificate with its private
   key as a password-protected PKCS#12 file.
6. Create an App Store Connect API key with permission to submit notarization
   jobs and retain its `.p8`, key ID, and issuer ID.
7. Publish the expected Apple Team ID in the repository/release documentation.

## GitHub configuration

Create these **Environment secrets** in `release`:

| Secret | Format |
| --- | --- |
| `MACOS_SIGNING_P12` | Base64 of the binary Developer ID Application `.p12`, on one line |
| `MACOS_SIGNING_P12_PASSWORD` | Password protecting that `.p12` |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer UUID |
| `ASC_PRIVATE_KEY_P8` | Complete multiline contents of `AuthKey_<KEY_ID>.p8` |

Create this **Environment variable**:

| Variable | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Ten-character Apple Developer team identifier |

The workflow sets `APP_NAME=VoxHearth` and
`APP_BUNDLE_ID=com.stephansturges.voxhearth` itself. GitHub provides the scoped
`GITHUB_TOKEN`; no personal access token is needed.

Never put secret material in repository variables, workflow arguments, build
logs, artifacts, issues, or release notes. Rotate a key immediately if any
secret may have been exposed.

## Prepare v0.4.0

- [ ] `CHANGELOG.md` has the final version/date and no unsupported claims.
- [ ] `Documentation/PRIVACY.md` and `THREAT_MODEL.md` match the code.
- [ ] Dependency and GitHub Action references are full immutable commits.
- [ ] All three model revisions/manifests, the sealed Metal library, S1-mini by
      Superwhisper naming term, Qwen3-0.6B attribution, llama.cpp license, and
      built-app Legal inventory are unchanged or have received a fresh review.
- [ ] `./scripts/check-attribution.py --verify-upstream` proves the two pinned
      S1-mini repositories still publish the same 11,878-byte license and that
      the pinned Qwen license digest is unchanged.
- [ ] `./scripts/local-check.sh` passes on a clean checkout.
- [ ] There are no tracked model binaries, DMGs, certificates, or keys.
- [ ] The release commit is reviewed and merged to `main`.
- [ ] Create an annotated, signed tag `v0.4.0` on that commit and push it.

The release workflow rejects any tag other than `v0.4.0` and rejects a tag that
does not point at the checked-out commit. It runs on `macos-26` with Xcode 26.2,
fetches and verifies all three models and the sealed Metal library, builds and
signs the app, notarizes and staples the app, creates/signs/notarizes/staples
the DMG, runs the final verifier and attribution checker, and
generates the source archive, SPDX SBOM, provenance JSON, checksums, and GitHub
provenance/SBOM attestations.

## Review before publication

- [ ] GitHub Environment approval is granted only after confirming the tag.
- [ ] Apple notarization reports `Accepted` for both app archive and DMG.
- [ ] Final release verifier passes against the stapled DMG.
- [ ] `SHA256SUMS` includes DMG, SBOM, provenance, and source archive.
- [ ] Both GitHub attestations target the final DMG, not an earlier unsigned image.
- [ ] Release notes publish the commit, Developer ID Team ID, minimum macOS,
      Apple Silicon requirement, model attribution, and privacy statement.
- [ ] A second person or fresh machine follows `VERIFY_RELEASE.md`.
- [ ] The release is published only after every asset is present.

## External blockers

The repository can build an unsigned app without signing authority. Model fetch
still requires access to the pinned Hugging Face revision. An
official one-click Gatekeeper-ready DMG cannot be produced until all of these
exist: GitHub repository/release permissions, protected release Environment,
Developer ID Application certificate/private key, App Store Connect notarization
key, and correct Apple Team ID. Apple may also require current developer
agreements to be accepted. Those are operational prerequisites, not code
defects, and cannot be fabricated or bypassed by the workflow.
