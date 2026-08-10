# Changelog

All notable user-visible changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versioning for release tags.

Entries may describe a release candidate before its signed GitHub Release
exists. A version is published only when both its Git tag and release assets
are present on GitHub.

## [0.1.0]

### Added

- A focused Apple Silicon/macOS 14+ menu bar dictation application.
- Hold-to-talk global shortcut with Control-Option-Space as the default.
- Memory-only microphone capture with a ten-minute safety limit.
- Fully local multilingual transcription using a bundled Parakeet-TDT-0.6B-v3
  Core ML model through a reviewed network-free subset of FluidAudio 0.15.5.
- Accessibility and Unicode-event text insertion, plus an off-by-default
  clipboard compatibility fallback that conditionally restores prior contents.
- Microphone, language, shortcut, launch-at-login, privacy, and permission UI.
- A closed, content-free Unified Logging vocabulary.
- Exact per-file model size/SHA-256 manifest and build-only downloader.
- Developer ID signing, Apple notarization, stapled DMG, checksum, SPDX SBOM,
  source bundle, provenance metadata, and GitHub artifact-attestation pipeline.
- Privacy statement, threat model, model provenance, build guide, independent
  release-verification guide, security policy, and third-party notices.

### Removed from upstream

- Cloud engines, runtime model downloads, accounts, telemetry, appcasts,
  automatic updates, plugins, network integrations, transcription history, and
  unrelated application surfaces.
- TypeWhisper product identity, artwork, bundle identifiers, release workflows,
  screenshots, and distribution configuration.

### Security

- Release inputs are pinned by immutable Git/Hugging Face revisions.
- GitHub Actions are pinned by full commit and release credentials are confined
  to a protected Environment.
- Final artifacts are checked for the expected identity, entitlements, bundled
  model, notarization tickets, and known updater/network dependencies.

[0.1.0]: ../../releases/tag/v0.1.0
