#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 3 ]]; then
  printf 'Usage: scripts/create-source-bundle.sh GIT_REF VERSION OUTPUT_TAR_GZ\n' >&2
  exit 2
fi

git_ref="$1"
version="$2"
output="$3"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  printf 'error: invalid version: %s\n' "$version" >&2
  exit 2
}
[[ "$output" == *.tar.gz ]] || { printf 'error: output must end in .tar.gz\n' >&2; exit 2; }
[[ ! -e "$output" ]] || { printf 'error: output already exists: %s\n' "$output" >&2; exit 1; }

source_revision="$(git -C "$repo_root" rev-parse "$git_ref^{commit}")"
[[ "$source_revision" == "$(git -C "$repo_root" rev-parse HEAD)" ]] || {
  printf 'error: source ref does not resolve to checked-out HEAD\n' >&2
  exit 1
}

vendor_provenance="$repo_root/Vendor/FluidAudioLocal/UPSTREAM.md"
[[ -f "$vendor_provenance" ]] || {
  printf 'error: vendored FluidAudioLocal provenance is missing\n' >&2
  exit 1
}
grep -Fq '19600a485baa4998812e4654b70d2bab8f2c9949' "$vendor_provenance" || {
  printf 'error: vendored FluidAudioLocal provenance has the wrong revision\n' >&2
  exit 1
}
git -C "$repo_root" cat-file -e \
  "$source_revision:Vendor/FluidAudioLocal/UPSTREAM.md" || {
  printf 'error: release ref does not contain the vendored FluidAudioLocal source\n' >&2
  exit 1
}
release_vendor_provenance="$(git -C "$repo_root" show \
  "$source_revision:Vendor/FluidAudioLocal/UPSTREAM.md")"
grep -Fq '19600a485baa4998812e4654b70d2bab8f2c9949' \
  <<< "$release_vendor_provenance" || {
  printf 'error: release ref contains the wrong vendored FluidAudio revision\n' >&2
  exit 1
}

mkdir -p "$(dirname "$output")"
git -C "$repo_root" archive \
  --format=tar.gz \
  --prefix="VoxHearth-$version/" \
  --output="$output" \
  "$source_revision"
printf 'complete source bundle created: %s\n' "$output"
