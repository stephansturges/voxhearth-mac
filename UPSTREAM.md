# Upstream provenance

VoxHearth is a modified, independently branded fork of
[TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac).

## Exact fork point

- Upstream release: TypeWhisper v1.5.1
- Upstream commit: `ea2843f2d179b0f43941e0fb2d3ed92d363eb31e`
- Fork repository history retains that commit and its authorship.

The upstream `LICENSE-COMMERCIAL.md` at that exact commit (Git blob
`c4bb673add93c1fe1901126c58d6ae1dcd3eaacb`) provides the operative
open-source grant:

> Open-source usage is licensed under the GNU General Public License v3.0 or
> later (GPL-3.0-or-later).

It also says a separate commercial license is not required for compliant GPL
forking or redistribution. The upstream `LICENSE` (Git blob
`338d03c2b4276423d8c153ae8478438d1a516d89`) contains the complete GNU GPL
version 3 text. VoxHearth preserves that license and distributes the
combined work under GPL-3.0-or-later. This open-source license does not impose a
non-commercial-use restriction.

## Identity and trademark separation

The upstream trademark policy permits truthful origin references but requires
forks to use a different name and remove upstream logos and app icons.
VoxHearth therefore replaces the name, bundle identifier, icons, interface,
release metadata, screenshots, and distribution configuration. “TypeWhisper”
appears only where needed for provenance or license compliance.

TypeWhisper is a trademark of its respective owner. VoxHearth is not an
official TypeWhisper release and is not affiliated with or endorsed by the
TypeWhisper project.

## Material changes

Relative to the fork point, VoxHearth:

- removes cloud engines, accounts, plugins, downloaders, telemetry, appcasts,
  update code, and unrelated application surfaces;
- implements one menu bar, push-to-talk local dictation flow;
- keeps audio and transcript content in memory and does not create a history;
- bundles one exact, checksum-locked Core ML model in signed releases;
- uses a new bundle identifier and a new permissions/settings domain;
- replaces the upstream build and release pipeline with a SHA-pinned,
  signed/notarized GitHub release process; and
- adds privacy, threat-model, model-provenance, SBOM, and release-verification
  documentation.

See the Git history after the fork point for the complete, file-level changes.

## Corresponding source

Every binary release includes `VoxHearth-v<VERSION>-source.tar.gz`. It contains
the exact tagged VoxHearth source, including the reviewed FluidAudio subset
under `Vendor/FluidAudioLocal`.
The repository itself and GitHub's automatically generated tag archives remain
available as redundant source copies. Model files are separately licensed data,
not program source; their immutable revision, hashes, attribution, and license
are published under `Models/` and `Documentation/MODEL_PROVENANCE.md`.
