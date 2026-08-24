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

## [0.4.0-dev.8] - 2026-08-24

### Fixed

- Prevented first-use dictation in VoxHearth's setup test window from crashing
  when accessibility text insertion re-entered the app's own AppKit text view
  from a background queue.
- Kept accessibility calls for external applications on the worker path so the
  crash fix does not restore synchronous cross-process work to the UI thread.

### Engineering

- Added fail-first queue-affinity coverage for both self-process and
  external-process accessibility destinations.

## [0.4.0-dev.7] - 2026-08-24

### Fixed

- Prevented the menu-bar window from collapsing into a nearly zero-height shell
  by giving its scrollable content explicit minimum, ideal, and maximum height
  bounds.

### Engineering

- Added a fail-first presentation regression that requires the nonzero sizing
  policy to remain wired into the production menu content.

## [0.4.0-dev.6] - 2026-08-24

### Fixed

- Released superseded dictation recovery reservations and stale cancellation
  bookkeeping so repeated sessions cannot accumulate avoidable lifecycle state.
- Reused the resident CPU cleanup session after a Metal fallback instead of
  repeatedly loading the same model, while preserving the existing fallback
  and memory-pressure behavior.
- Cancelled completed cleanup deadline work and removed a transient audio
  allocation from the capture callback without increasing steady-state buffers.
- Gave overlapping performance signposts unique identities and made the
  lifecycle soak evaluator run optimized code with its build configuration
  recorded in the result.

### Engineering

- Added focused long-running lifecycle regressions and an opt-in,
  network-denied real-model latency evaluator with fixed local fixtures and
  reproducible warm, cold, transcript, CPU, and peak-RSS gates.
- Pinned the sealed Metal compiler target explicitly, required two
  byte-identical hosted builds in the protected check, and replaced a
  scheduler-sensitive preview-cancellation fixture with an explicit gate.
- Separated hosted semantic verification from hardware-floor performance
  acceptance. Shared CI uses a bounded evaluator-only deadline while the app's
  production cleanup deadline remains 2 seconds.
- Retained the existing CPU-only multilingual preprocessor after every tested
  compute-unit alternative slowed warm weighted p95 and regressed cold/resource
  evidence; no experimental runtime change was promoted.
- Verified the complete source with 165 tests, release builds, offline policy
  checks, real-model smoke coverage, and release-configured lifecycle soaks.

## [0.4.0] - 2026-08-21

### Added

- Optional, default-checked English transcript cleanup with S1-mini by
  Superwhisper after an explicit setup disclosure.
- Semi-formal default styling plus independent default-on, session-leading
  `list` and `email` format commands with exact first-word-only parsing.
- Raw-versus-cleaned setup examples, a live test area, cleanup progress in the
  top overlay, cancellation, and session-keyed recovery actions.
- A sealed, statically linked llama.cpp/ggml Metal runtime, exact S1-mini GGUF
  and metallib manifests, CPU fallback/control, bounded generation, and safe
  command-stripped fallback.
- Complete S1-mini naming license, Qwen3-0.6B and llama.cpp attribution, SPDX
  relationships, provenance, app Legal inventory, and fail-closed checks.

### Security

- Cleanup receives final English text only and has no runtime networking,
  downloads, telemetry, environment-selected backend, dynamic loading, or
  runtime shader compilation.
- Typed session ownership and exactly-once insertion prevent late cleanup from
  mutating or inserting into a newer dictation session.

## [0.4.0-dev.1] - 2026-08-21

### Added

- First unsigned development preview of the complete 0.4 transcript-cleanup
  feature and its model/runtime/legal packaging.

## [0.3.0-dev.3] - 2026-08-18

### Fixed

- Advanced the internal bundle build from 947 to 948 so Macs already running
  build 947 recognize this replacement as a new build and show the required
  update/Accessibility setup flow.

## [0.3.0-dev.2] - 2026-08-18

### Fixed

- The hidden live-preview panel now stops its waveform animation between
  dictation sessions, restoring an idle main run loop and prompt shortcut,
  acknowledgement-cue, and microphone-release handling.
- Live preview copies only its bounded trailing eight-second audio window
  instead of sharing the full growing capture buffer.
- Final transcription now waits for a cancelled preview inference to quiesce,
  while microphone capture is stopped first, preventing simultaneous Core ML
  work from delaying the final result.

### Added

- Privacy-safe lifecycle markers for shortcut press/release, cue playback,
  final transcription, and insertion, without logging audio or transcript text.

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

[Unreleased]: https://github.com/stephansturges/voxhearth-mac/compare/v0.4.0-dev.8...HEAD
[0.4.0-dev.8]: https://github.com/stephansturges/voxhearth-mac/compare/v0.4.0-dev.7...v0.4.0-dev.8
[0.4.0-dev.7]: https://github.com/stephansturges/voxhearth-mac/compare/v0.4.0-dev.6...v0.4.0-dev.7
[0.4.0-dev.6]: https://github.com/stephansturges/voxhearth-mac/compare/v0.3.0-dev.3...v0.4.0-dev.6
[0.4.0]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.4.0
[0.4.0-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.4.0-dev.1
[0.3.0-dev.3]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.3.0-dev.3
[0.3.0-dev.2]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.3.0-dev.2
[0.3.0-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.3.0-dev.1
[0.2.1-dev.3]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.1-dev.3
[0.2.1-dev.2]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.1-dev.2
[0.2.1-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.1-dev.1
[0.2.0-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.2.0-dev.1
[0.1.0-dev.1]: https://github.com/stephansturges/voxhearth-mac/releases/tag/v0.1.0-dev.1
