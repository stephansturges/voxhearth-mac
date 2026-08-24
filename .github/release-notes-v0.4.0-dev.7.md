# VoxHearth 0.4.0 Development Preview 7

This unsigned preview prevents the SwiftUI menu-bar window from collapsing to
a nearly zero-height shell while retaining the optional, fully local S1-mini
transcript cleanup and the long-running lifecycle fixes from Preview 6.

## What changed

- The completed-onboarding menu now has explicit 480-point minimum, 620-point
  ideal, and 720-point maximum height bounds. Its existing scroll view remains
  available when content exceeds the bounded window.
- A fail-first regression requires the nonzero sizing policy to stay wired into
  the production menu content.
- Final English dictation can be cleaned for fillers, false starts,
  punctuation, capitalization, numbers, dates, and spoken addresses.
- Starting a new session with the complete word `list` or `email` selects the
  corresponding trained structure/context when that detector is enabled.
  Mentioning either word later does not activate it.
- Setup includes raw-versus-cleaned examples and a live test area. The top
  overlay shows cleanup progress after release and exposes cancellation and
  safe recovery states.
- Superseded sessions release recovery reservations and stale cancellation
  bookkeeping. Cleanup reuses its resident CPU session after Metal fallback,
  and completed operations cancel their delayed deadline work.
- The app has no account, telemetry, runtime networking, updater, model
  download, dynamic backend discovery, or runtime shader compilation.

Cleanup adds a roughly 462 MiB bundled model and consumes additional local
memory and compute while enabled. Performance depends on the Mac, system load,
and transcript length. The feature is English-only in this release. Automated
coverage verifies the menu sizing contract, but it does not replace multi-day
manual AppKit/WindowServer observation and no universal speedup is claimed.

## Verification performed

- 166 Swift tests, including the fail-first menu sizing regression
- debug and release builds plus release-binary policy checks
- offline/privacy, model-manifest, attribution, and packaging checks
- real local Parakeet smoke coverage
- real S1-mini CPU and Metal semantic coverage with a bounded hosted deadline
- two byte-identical hosted Metal builds with an explicit target
- strict ad-hoc bundle signature, DMG, checksum, provenance, and attestation
  verification in the release workflow

## Install this unsigned development preview

1. Quit the currently running VoxHearth before replacing it.
2. Download `VoxHearth-v0.4.0-dev.7-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
3. Open the DMG and drag VoxHearth to Applications, replacing the older build.
4. This preview is ad-hoc signed and not notarized. Follow the per-app **Open
   Anyway** procedure in `Documentation/VERIFY_RELEASE.md`; never disable
   Gatekeeper globally.
5. Launch VoxHearth, open its menu-bar window, and confirm the full menu appears
   at a stable height.

Source revision: `{{SOURCE_REVISION}}`

The workflow publishes the complete three-model DMG, sealed Metal library,
source archive, SPDX SBOM, provenance record, checksums, and GitHub attestations.
