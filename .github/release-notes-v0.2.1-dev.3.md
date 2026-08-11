# VoxHearth 0.2.1 Development Preview 3

This preview makes replacing VoxHearth easier to understand and recover when
macOS treats an unsigned update as a different Accessibility client.

## What changed

- Setup opens and comes to the foreground once for every newly installed build,
  not only on the very first installation.
- Updated builds automatically invoke Apple's supported Accessibility request
  when setup appears.
- Update-specific guidance explains how to remove a stale entry, press `+`,
  select the current app from Applications, enable it, and relaunch.
- Setup and Settings can reveal the current VoxHearth app in Finder to make the
  manual `+` flow easier.
- Installation instructions now require quitting the old VoxHearth process
  before replacing the application bundle.
- The system-default microphone fallback from Development Preview 2 remains
  included.

macOS does not expose an API that lets an application add or approve itself in
the protected Accessibility list. This build requests access automatically,
but the documented user-controlled `+` step remains necessary when macOS does
not relist an unsigned replacement.

## Install this unsigned development preview

1. Quit the currently running VoxHearth from its menu before replacing it.
2. Download `VoxHearth-v0.2.1-dev.3-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
3. Open the DMG and drag VoxHearth to Applications, replacing the older build.
4. Because this preview is ad-hoc signed and not notarized, follow the documented
   **Open Anyway** procedure in `Documentation/VERIFY_RELEASE.md`.
5. Launch VoxHearth and follow the automatically presented update setup.

Source revision: `{{SOURCE_REVISION}}`

The release workflow publishes the source archive, SPDX SBOM, provenance record,
checksums, and GitHub attestations next to the DMG.
