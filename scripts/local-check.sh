#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for command_name in file git grep python3 swift zsh; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

printf '%s\n' '==> Validate scripts and distribution metadata'
while IFS= read -r shell_script; do
  bash -n "$shell_script"
done < <(find scripts -maxdepth 1 -type f -name '*.sh' -print | sort)

python_cache="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-pycache.XXXXXX")"
cleanup() {
  rm -rf "$python_cache"
}
trap cleanup EXIT
PYTHONPYCACHEPREFIX="$python_cache" python3 -m py_compile scripts/*.py
python3 scripts/verify-model.py --self-test
python3 scripts/verify-model.py --manifest-only
python3 scripts/verify-model.py \
  --manifest Models/parakeet-tdt-ctc-110m-coreml.json \
  --manifest-only
plutil -lint Documentation/Distribution/Info.plist >/dev/null
plutil -lint Documentation/Distribution/VoxHearth.entitlements >/dev/null
[[ "$(plutil -extract LSMultipleInstancesProhibited raw -o - Documentation/Distribution/Info.plist)" == "true" ]] || {
  printf 'error: app bundle must prohibit multiple instances\n' >&2
  exit 1
}
./scripts/check-release-binary.sh --self-test
[[ -f Brand/VoxHearth.icns ]] || {
  printf 'error: required application icon is missing: Brand/VoxHearth.icns\n' >&2
  exit 1
}
file Brand/VoxHearth.icns | grep -Fq 'Mac OS X icon' || {
  printf 'error: Brand/VoxHearth.icns is not a valid macOS icon file\n' >&2
  exit 1
}
zsh -n Brand/build-icon.sh

if unpinned_actions="$(git grep -n -E '^[[:space:]]*uses:[[:space:]]*[^ ]+@' -- .github/workflows \
  | grep -Ev '@[0-9a-f]{40}([[:space:]]+#.*)?$' || true)"; then
  if [[ -n "$unpinned_actions" ]]; then
    printf 'error: GitHub Actions must use full 40-character commit pins:\n%s\n' \
      "$unpinned_actions" >&2
    exit 1
  fi
fi

printf '%s\n' '==> Validate source and artifact policy'
for required_file in \
  README.md SECURITY.md NOTICE UPSTREAM.md THIRD_PARTY_NOTICES.md CHANGELOG.md \
  Documentation/PRIVACY.md Documentation/THREAT_MODEL.md \
  Documentation/PEBBLE_INDEX.md \
  Documentation/MODEL_PROVENANCE.md Documentation/BUILDING.md \
  Documentation/VERIFY_RELEASE.md Documentation/RELEASE.md \
  .github/release-notes-v0.2.1-dev.3.md \
  .github/release-notes-v0.2.1.md; do
  [[ -f "$required_file" ]] || {
    printf 'error: required project document is missing: %s\n' "$required_file" >&2
    exit 1
  }
done

if git ls-files | grep -E -i '(^|/)([^/]+\.dmg|[^/]+\.p12|AuthKey_[^/]+\.p8)$|\.mlmodelc/' >/dev/null; then
  printf 'error: release/model/signing binaries must not be tracked by Git\n' >&2
  git ls-files | grep -E -i '(^|/)([^/]+\.dmg|[^/]+\.p12|AuthKey_[^/]+\.p8)$|\.mlmodelc/' >&2
  exit 1
fi

if git grep -n -E -i \
  'com\.typewhisper|TypeWhisper\.app|typewhisper-cli|TypeWhisperApp|import[[:space:]]+TypeWhisper' \
  -- Package.swift Sources Tests Brand; then
  printf 'error: unexpected upstream product identity in active VoxHearth files\n' >&2
  exit 1
fi

if git grep -n -E \
  'URLSession|URLRequest|URLProtocol|NW(Connection|Listener|Browser|PathMonitor)|import[[:space:]]+Network|CFSocket|CFStream|NSStream|NetworkExtension|WebSocket|(^|[^[:alnum:]_])socket[[:space:]]*\(|getaddrinfo|Sparkle|SUUpdater|SUFeedURL|Alamofire|Sentry|Telemetry|Analytics|HFClient|FileDownloader|AssetDownloader|downloadAndLoad|ModelHub' \
  -- Sources Vendor/FluidAudioLocal; then
  printf 'error: runtime source contains a forbidden networking, updater, or telemetry API\n' >&2
  exit 1
fi

if git grep -n -E \
  'FileHandle|FileManager|temporaryDirectory|NSTemporaryDirectory|\.write\(' \
  -- Vendor/FluidAudioLocal/Sources; then
  printf 'error: vendored runtime source contains a durable file/audio API\n' >&2
  exit 1
fi

if git grep -n -E \
  'import[[:space:]]+OSLog|OSLog\.Logger|standard(Error|Output)|print\(' \
  -- Vendor/FluidAudioLocal/Sources/FluidAudioLocal/Shared/AppLogger.swift; then
  printf 'error: vendored logger must remain a no-op sink\n' >&2
  exit 1
fi

if git grep -n -E '^[[:space:]]*\.package\(' -- Package.swift; then
  printf 'error: Package.swift must not contain a remote runtime dependency\n' >&2
  exit 1
fi
grep -Fq 'FluidAudioLocal' Package.swift
grep -Fq '19600a485baa4998812e4654b70d2bab8f2c9949' Vendor/FluidAudioLocal/UPSTREAM.md

printf '%s\n' '==> Resolve, test, and build'
swift package resolve
swift test
swift build --configuration debug
swift build --configuration release

binary_dir="$(swift build --configuration release --show-bin-path)"
./scripts/check-release-binary.sh "$binary_dir/VoxHearth"

for manifest in \
  Models/parakeet-tdt-0.6b-v3-coreml.json \
  Models/parakeet-tdt-ctc-110m-coreml.json; do
  bundle_root="$(python3 - "$manifest" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(json.load(source)["bundleRoot"])
PY
)"
  model_dir="$repo_root/.build/models/$bundle_root"
  if ./scripts/verify-model.py --manifest "$manifest" "$model_dir" >/dev/null 2>&1; then
    ./scripts/model-smoke.sh --manifest "$manifest" "$model_dir"
  else
    printf 'verified local model absent; skipping opt-in smoke test: %s\n' "$bundle_root"
  fi
done

git diff --check
printf '%s\n' 'VoxHearth local checks passed'
