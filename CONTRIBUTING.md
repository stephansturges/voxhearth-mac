# Contributing to VoxHearth

Thank you for helping make private dictation simpler and more trustworthy.
VoxHearth deliberately has a narrow product and privacy boundary; proposed
changes should make that boundary easier to understand, test, or maintain.

## Before opening a change

Use a GitHub issue for a user-visible feature, model/dependency change, new
permission, persistence, or privacy-boundary change. Security and privacy
vulnerabilities belong in a private report under [SECURITY.md](SECURITY.md), not
a public issue.

Changes that add accounts, analytics, advertising, cloud inference, remote
configuration, automatic updates, runtime downloads, or other runtime network
access are out of scope for VoxHearth. A separate fork is the right place for
those product choices.

## Development setup

You need an Apple Silicon Mac, Xcode 26.2 with Swift 6, Git, and Python 3. The
application targets macOS 14 and later.

```sh
git clone YOUR_FORK_URL
cd voxhearth-mac
./scripts/local-check.sh
```

The normal test/build loop does not need model bytes. For end-to-end app
packaging, fetch the immutable build-only model and create an unsigned bundle:

```sh
./scripts/fetch-model.sh
./scripts/build-app-bundle.sh
```

The approximately 483 MB model and every generated app/DMG stay under `.build/`
and must not be committed.

## Privacy invariants

Every pull request must preserve these properties:

- installed runtime operation requires no network;
- models are bundled, pinned, and verified before signing;
- audio and transcripts are memory-only and never enter logs;
- no VoxHearth transcription/audio history is created;
- clipboard insertion remains an explicit, off-by-default compatibility path;
- the global shortcut does not become a general keyboard event tap;
- updater, appcast, telemetry, crash-upload, and account code remain absent;
- only the documented preferences are persisted; and
- new permissions or trust-boundary changes receive documentation and threat
  model updates in the same pull request.

Do not weaken the offline scan to make a new API pass. Explain the requirement
and discuss a privacy-preserving design first.

## Tests and checks

Run:

```sh
./scripts/local-check.sh
git diff --check
```

Add focused unit tests for new state transitions, persistence, permission
handling, model validation, and text-insertion edge cases. Manually exercise
the menu bar state, onboarding, push-to-talk press/release behavior, cancellation,
permission denial, and clipboard fallback when your change touches them.

Signing and notarization credentials are not available to pull requests. The
release workflow is intentionally tag- and Environment-gated.

## Dependency or model updates

These are security-sensitive changes and should be isolated in their own pull
request:

1. pin a full immutable commit, never a branch or floating tag;
2. review upstream source, package targets, network behavior, and all licenses;
3. regenerate and independently verify every model file size and SHA-256;
4. update the SBOM generator, source bundler, notices, provenance, privacy
   statement, threat model, and release verifier;
5. document model behavior/quality testing; and
6. never add model binary bytes to Git.

GitHub Actions must also use full 40-character commit pins. Keep the readable
release/version comment beside each pin.

## Pull requests

- Start from `main` and keep one coherent concern per pull request.
- Preserve existing authorship and license notices.
- Use clear commits that can be reviewed independently.
- Complete the Summary, Privacy impact, and Test plan sections in the template.
- Include screenshots only when the interface changed, and ensure they contain
  no private transcription or system information.
- Update `CHANGELOG.md` for user-visible changes.

Maintainers may request a smaller change or additional evidence when code
touches microphone capture, Accessibility, clipboard, logging, model loading,
signing, or release permissions.

## License

By intentionally contributing material to this repository, you agree to
license that contribution under GPL-3.0-or-later. Do not submit code, model
files, artwork, or documentation you lack the right to distribute. Third-party
material must include its exact source, version/revision, license, attribution,
and any required notices.
