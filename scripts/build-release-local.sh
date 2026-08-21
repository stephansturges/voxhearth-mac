#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${VERSION:-0.3.0}"
build_number="${BUILD_NUMBER:-1}"
distribution="$repo_root/.build/distribution"
app="$distribution/VoxHearth.app"
dmg="$distribution/VoxHearth-v$version-unsigned.dmg"

[[ ! -e "$app" && ! -e "$dmg" ]] || {
  printf 'error: prior distribution output exists under %s; move it aside first\n' "$distribution" >&2
  exit 1
}

"$repo_root/scripts/local-check.sh"
"$repo_root/scripts/fetch-models.sh"
"$repo_root/scripts/build-metallib.sh"
"$repo_root/scripts/build-app-bundle.sh" --version "$version" --build "$build_number" --output "$app"
"$repo_root/scripts/create-dmg.sh" "$app" "$dmg"

printf 'local unsigned build complete: %s\n' "$dmg"
printf 'Gatekeeper-ready public releases must be built, signed, and notarized by the release workflow.\n'
