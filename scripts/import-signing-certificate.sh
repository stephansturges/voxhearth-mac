#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: scripts/import-signing-certificate.sh KEYCHAIN_PATH KEYCHAIN_PASSWORD\n' >&2
  exit 2
fi

: "${MACOS_SIGNING_P12:?MACOS_SIGNING_P12 must contain a base64-encoded Developer ID Application certificate}"
: "${MACOS_SIGNING_P12_PASSWORD:?MACOS_SIGNING_P12_PASSWORD is required}"

keychain_path="$1"
keychain_password="$2"
certificate_file="$(mktemp "${RUNNER_TEMP:-/private/tmp}/voxhearth-certificate.XXXXXX.p12")"
cleanup() {
  rm -f "$certificate_file"
}
trap cleanup EXIT

printf '%s' "$MACOS_SIGNING_P12" | openssl base64 -d -A > "$certificate_file"
chmod 600 "$certificate_file"

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_file" \
  -k "$keychain_path" \
  -P "$MACOS_SIGNING_P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null
security list-keychains -d user -s "$keychain_path"
security default-keychain -d user -s "$keychain_path"
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$keychain_password" \
  "$keychain_path" >/dev/null

identity="$(security find-identity -v -p codesigning "$keychain_path" \
  | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
[[ -n "$identity" ]] || {
  printf 'error: imported archive contains no Developer ID Application identity\n' >&2
  exit 1
}

printf '%s\n' "$identity"
