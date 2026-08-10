#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'Usage: scripts/sign-release.sh APP_OR_DMG [KEYCHAIN_PATH]\n' >&2
  exit 2
fi

: "${MACOS_SIGNING_IDENTITY:?MACOS_SIGNING_IDENTITY is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"

artifact="$1"
keychain_path="${2:-}"
[[ -e "$artifact" ]] || { printf 'error: artifact not found: %s\n' "$artifact" >&2; exit 1; }

codesign_args=(--force --sign "$MACOS_SIGNING_IDENTITY" --timestamp)
if [[ -n "$keychain_path" ]]; then
  codesign_args+=(--keychain "$keychain_path")
fi

case "$artifact" in
  *.app)
    if [[ -d "$artifact/Contents/Frameworks" ]]; then
      while IFS= read -r -d '' nested_file; do
        codesign "${codesign_args[@]}" --options runtime "$nested_file"
      done < <(find "$artifact/Contents/Frameworks" -type f -name '*.dylib' -print0)
      while IFS= read -r -d '' nested_bundle; do
        codesign "${codesign_args[@]}" --options runtime "$nested_bundle"
      done < <(find "$artifact/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
    fi
    if [[ -d "$artifact/Contents/PlugIns" ]]; then
      while IFS= read -r -d '' nested_bundle; do
        codesign "${codesign_args[@]}" --options runtime "$nested_bundle"
      done < <(find "$artifact/Contents/PlugIns" -depth -type d \
        \( -name '*.xpc' -o -name '*.appex' \) -print0)
    fi

    codesign "${codesign_args[@]}" \
      --options runtime \
      --entitlements "$repo_root/Documentation/Distribution/VoxHearth.entitlements" \
      "$artifact"
    codesign --verify --deep --strict --verbose=2 "$artifact"
    ;;
  *.dmg)
    codesign "${codesign_args[@]}" "$artifact"
    codesign --verify --strict --verbose=2 "$artifact"
    ;;
  *)
    printf 'error: artifact must be an .app or .dmg\n' >&2
    exit 2
    ;;
esac

signature_details="$(codesign -dvvv "$artifact" 2>&1)"
if ! grep -Fq "TeamIdentifier=$APPLE_TEAM_ID" <<< "$signature_details"; then
  printf 'error: signed artifact does not have expected team ID %s\n' "$APPLE_TEAM_ID" >&2
  exit 1
fi
printf 'Developer ID signature verified: %s\n' "$artifact"
