# Changelog

All notable user-visible changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versioning for release tags.

An entry is published only when both its Git tag and matching GitHub Release
assets exist. Development prereleases are named and documented separately from
Developer ID-signed, Apple-notarized releases.

## [Unreleased]

### Planned

- Direct, phone-free Pebble Index 01 collection transfer, pending publication
  of the Haversine/Telesto protocol or a suitable macOS transport. The request
  is tracked in [coredevices/mobileapp#333](https://github.com/coredevices/mobileapp/issues/333).

## [0.3.0-dev.1] - 2026-08-11

### Added

- An off-by-default, non-activating live transcript subtitle strip that shows
  only the latest approximate on-device words near the top-right of the active
  screen. Preview audio and text remain in memory, Notification Center is not
  used, and the complete final recording is still transcribed separately for
  insertion.

## [0.2.1-dev.3] - 2026-08-11

### Fixed

- Setup now opens and comes to the foreground once for every newly installed
  app build, with update-specific Accessibility reauthorization guidance.
- Updated builds automatically invoke Apple's Accessibility request. Setup and
  Settings also expose the required manual `+` flow and reveal the current app
  in Finder when macOS does not relist an unsigned replacement.

## [0.2.1-dev.2] - 2026-08-11

### Fixed

- If a saved microphone disconnects or becomes unavailable, VoxHearth now
  switches to the current macOS system-default input and clears the stale
  selection instead of failing dictation.

## [0.2.1-dev.1] - 2026-08-11

### Fixed

- Settings now activates VoxHearth and brings its window to the front when
  opened from the menu bar.
- Added a persistent Accessibility setup and recovery control with instructions
  for removing a stale authorization after replacing the app with a new build.

## [0.2.0-dev.1] - 2026-08-10

### Added

- Bundled Parakeet TDT-CTC 110M as a compact English-only speech model for
  faster startup and lower memory use on smaller Apple silicon Macs.
- Added a persisted Speech model picker under Settings → Dictation → Speech.
- Added exact hashes, offline real-model smoke coverage, SBOM entries,
  provenance, attribution, and packaging checks for both bundled models.

### Changed

- Existing settings migrate to the multilingual 600M model, preserving the
  prior behavior. Choosing the compact model safely constrains language to English.
- Release packaging now includes both models and never downloads either at runtime.

## [0.1.0-dev.1] - 2026-08-10

### Added

- A focused Apple Silicon/macOS 14+ menu bar dictation application.
- A visible first-launch setup window that closes after onboarding.
- Hold-to-talk global shortcut with Control-Option-Space as the default.
- A brief in-memory start cue that finishes before microphone capture begins.
- Discoverable in-panel shortcut editing and launch-at-login checkbox.
- Optional middle/extra mouse-button activation and unmodified F13-F20
  bindings for remappable USB accessories.
- A bounded, memory-only external-audio ingress for future local accessories;
  no unverified Pebble Bluetooth driver is included.
- Memory-only microphone capture with a ten-minute safety limit.
- Fully local multilingual transcription using a bundled Parakeet-TDT-0.6B-v3
  Core ML model through a reviewed network-free subset of FluidAudio 0.15.5.
- Accessibility and Unicode-event text insertion, plus an off-by-default
  clipboard compatibility fallback that conditionally restores prior contents.
- Microphone, language, shortcut, launch-at-login, privacy, and permission UI.
- A closed, content-free Unified Logging vocabulary.
- Exact per-file model size/SHA-256 manifest and build-only downloader.
- Separate development-prerelease and Developer ID signing/notarization
  pipelines, with checksum, SPDX SBOM, source, provenance, and GitHub
  attestations.
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
- Development artifacts are required to identify their ad-hoc signature and
  absent notarization; official artifacts additionally require the expected
  Developer ID identity and stapled notarization tickets.
- macOS bundle policy and an in-process guard prevent duplicate app instances
  from registering the dictation shortcut twice.

[Unreleased]: https://github.com/stephansturges/voxhearth-mac/compare/v0.3.0-dev.1...HEAD
[0.3.0-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.3.0-dev.1
[0.2.1-dev.3]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.1-dev.3
[0.2.1-dev.2]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.1-dev.2
[0.2.1-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.1-dev.1
[0.2.0-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.0-dev.1
[0.1.0-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.1.0-dev.1
