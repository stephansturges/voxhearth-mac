#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected_bundle_id="com.stephansturges.voxhearth"
expected_team_id="${APPLE_TEAM_ID:-}"

if [[ $# -ne 1 ]]; then
  printf 'Usage: scripts/verify-release.sh VOXHEARTH_DMG\n' >&2
  exit 2
fi

dmg="$1"
[[ -f "$dmg" && "$dmg" == *.dmg ]] || {
  printf 'error: DMG not found: %s\n' "$dmg" >&2
  exit 1
}

codesign --verify --strict --verbose=2 "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

mountpoint="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-verify.XXXXXX")"
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then
    hdiutil detach -quiet "$mountpoint" || true
  fi
  rmdir "$mountpoint" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach -quiet -readonly -nobrowse -mountpoint "$mountpoint" "$dmg"
mounted=true
app="$mountpoint/VoxHearth.app"
[[ -d "$app" ]] || { printf 'error: VoxHearth.app is missing from DMG\n' >&2; exit 1; }
[[ -L "$mountpoint/Applications" && "$(readlink "$mountpoint/Applications")" == /Applications ]] || {
  printf 'error: DMG is missing the Applications symlink\n' >&2
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

info="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/VoxHearth"
bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$info")"
minimum_system="$(plutil -extract LSMinimumSystemVersion raw -o - "$info")"
ui_element="$(plutil -extract LSUIElement raw -o - "$info")"
[[ "$bundle_id" == "$expected_bundle_id" ]] || {
  printf 'error: unexpected bundle identifier: %s\n' "$bundle_id" >&2
  exit 1
}
[[ "$minimum_system" == "14.0" ]] || {
  printf 'error: unexpected minimum macOS version: %s\n' "$minimum_system" >&2
  exit 1
}
[[ "$ui_element" == "true" ]] || { printf 'error: app is not configured as a menu bar app\n' >&2; exit 1; }
[[ -x "$binary" ]] || { printf 'error: app executable missing\n' >&2; exit 1; }

for forbidden_key in SUFeedURL NSAppTransportSecurity; do
  if plutil -extract "$forbidden_key" raw -o - "$info" >/dev/null 2>&1; then
    printf 'error: forbidden Info.plist key present: %s\n' "$forbidden_key" >&2
    exit 1
  fi
done

entitlements="$(mktemp "${TMPDIR:-/private/tmp}/voxhearth-entitlements.XXXXXX.plist")"
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
for forbidden_entitlement in \
  com.apple.security.network.client \
  com.apple.security.network.server \
  com.apple.developer.associated-domains \
  com.apple.developer.icloud-container-identifiers \
  com.apple.security.application-groups \
  com.apple.security.get-task-allow; do
  if plutil -extract "$forbidden_entitlement" raw -o - "$entitlements" >/dev/null 2>&1; then
    printf 'error: forbidden entitlement present: %s\n' "$forbidden_entitlement" >&2
    rm -f "$entitlements"
    exit 1
  fi
done
rm -f "$entitlements"

signature_details="$(codesign -dvvv "$app" 2>&1)"
if [[ -n "$expected_team_id" ]] && ! grep -Fq "TeamIdentifier=$expected_team_id" <<< "$signature_details"; then
  printf 'error: release team ID does not match APPLE_TEAM_ID\n' >&2
  exit 1
fi
"$repo_root/scripts/check-release-binary.sh" "$binary"

cmp "$repo_root/Models/parakeet-tdt-0.6b-v3-coreml.json" \
  "$app/Contents/Resources/Models/manifest.json"
"$repo_root/scripts/verify-model.py" \
  "$app/Contents/Resources/Models/parakeet-tdt-0.6b-v3-coreml"

printf 'release verified: %s\n' "$dmg"
