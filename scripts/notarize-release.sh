#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: scripts/notarize-release.sh SUBMISSION_ARTIFACT STAPLE_TARGET\n' >&2
  exit 2
fi

: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_PRIVATE_KEY_PATH:?ASC_PRIVATE_KEY_PATH is required}"

submission="$1"
staple_target="$2"
[[ -f "$submission" ]] || { printf 'error: submission not found: %s\n' "$submission" >&2; exit 1; }
[[ -e "$staple_target" ]] || { printf 'error: staple target not found: %s\n' "$staple_target" >&2; exit 1; }
[[ -f "$ASC_PRIVATE_KEY_PATH" ]] || {
  printf 'error: App Store Connect private key file not found\n' >&2
  exit 1
}

xcrun notarytool submit "$submission" \
  --key "$ASC_PRIVATE_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait
xcrun stapler staple "$staple_target"
xcrun stapler validate "$staple_target"
printf 'notarization accepted and ticket stapled: %s\n' "$staple_target"
