# VoxHearth 0.4.0 Development Preview 8

This unsigned preview replaces Preview 7, which could crash during first-use
dictation in VoxHearth's own setup test window. It retains the stable menu
height, optional fully local S1-mini transcript cleanup, and long-running
lifecycle fixes from the preceding previews.

## What changed

- Accessibility insertion now detects when the focused text field belongs to
  VoxHearth itself and performs that in-process AppKit operation on the main
  queue. This fixes the setup test-window crash on macOS 26.4.
- Accessibility calls targeting other applications remain on the worker path,
  avoiding synchronous cross-process AX waits on the UI thread.
- Fail-first regressions cover both the self-process main-queue requirement and
  the external-process worker requirement.
- The completed-onboarding menu retains explicit 480-point minimum, 620-point
  ideal, and 720-point maximum height bounds with bounded scrolling.
- Final English dictation can optionally be cleaned locally for fillers, false
  starts, punctuation, capitalization, numbers, dates, and spoken addresses.
- Starting a new session with the complete word `list` or `email` selects the
  corresponding trained structure/context when that detector is enabled.
  Mentioning either word later does not activate it.
- The app has no account, telemetry, runtime networking, updater, model
  download, dynamic backend discovery, or runtime shader compilation.

Cleanup adds a roughly 462 MiB bundled model and consumes additional local
memory and compute while enabled. Performance depends on the Mac, system load,
and transcript length. The feature is English-only in this release. Automated
coverage verifies the crash boundary and menu sizing contract, but it does not
replace multi-day manual AppKit/WindowServer observation.

## Verification performed

- 168 Swift tests, including fail-first self/external accessibility
  queue-affinity regressions and the menu sizing regression
- debug and release builds plus release-binary policy checks
- offline/privacy, model-manifest, attribution, and packaging checks
- real local Parakeet smoke coverage
- real S1-mini CPU and Metal semantic coverage with a bounded hosted deadline
- two byte-identical hosted Metal builds with an explicit target
- strict ad-hoc bundle signature, DMG, checksum, provenance, and attestation
  verification in the release workflow

## Install this unsigned development preview

1. Quit the currently running VoxHearth before replacing it.
2. Download `VoxHearth-v0.4.0-dev.8-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
3. Open the DMG and drag VoxHearth to Applications, replacing the older build.
4. This preview is ad-hoc signed and not notarized. Follow the per-app **Open
   Anyway** procedure in `Documentation/VERIFY_RELEASE.md`; never disable
   Gatekeeper globally.
5. Launch VoxHearth and run one dictation in the setup test field. Confirm text
   appears without a crash, then open the menu and confirm its stable height.

Source revision: `{{SOURCE_REVISION}}`

The workflow publishes the complete three-model DMG, sealed Metal library,
source archive, SPDX SBOM, provenance record, checksums, and GitHub attestations.
