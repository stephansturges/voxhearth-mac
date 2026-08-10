#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: scripts/create-dmg.sh APP_PATH OUTPUT_DMG\n' >&2
  exit 2
fi

app_path="$1"
output_dmg="$2"
[[ -d "$app_path" && "$app_path" == *.app ]] || {
  printf 'error: app bundle not found: %s\n' "$app_path" >&2
  exit 1
}
[[ "$output_dmg" == *.dmg ]] || { printf 'error: output must end in .dmg\n' >&2; exit 2; }
[[ ! -e "$output_dmg" ]] || {
  printf 'error: output already exists: %s\n' "$output_dmg" >&2
  exit 1
}

mkdir -p "$(dirname "$output_dmg")"
staging="$(mktemp -d "$(dirname "$output_dmg")/.voxhearth-dmg.XXXXXX")"
cleanup() {
  rm -rf "$staging"
}
trap cleanup EXIT

ditto "$app_path" "$staging/VoxHearth.app"
ln -s /Applications "$staging/Applications"
hdiutil create \
  -quiet \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -volname VoxHearth \
  -srcfolder "$staging" \
  "$output_dmg"

printf 'disk image created: %s\n' "$output_dmg"
