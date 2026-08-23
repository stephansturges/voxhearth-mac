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
inert_eval_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-inert-eval.XXXXXX")"
cleanup() {
  rm -rf "$python_cache" "$inert_eval_dir"
}
trap cleanup EXIT
PYTHONPYCACHEPREFIX="$python_cache" python3 -m py_compile scripts/*.py
python3 scripts/verify-model.py --self-test
python3 scripts/verify-model.py --manifest-only
python3 scripts/verify-model.py \
  --manifest Models/parakeet-tdt-ctc-110m-coreml.json \
  --manifest-only
python3 scripts/verify-model.py \
  --manifest Models/s1-mini-gguf.json \
  --manifest-only
python3 scripts/verify-model-bundle.py --self-test
python3 scripts/verify-metallib.py --self-test
python3 scripts/check-attribution.py
python3 scripts/check-attribution.py --self-test
scripts/s1-mini-eval.sh verify
python3 scripts/check-vendored-llama.py
python3 scripts/check-vendored-llama.py --self-test
plutil -lint Documentation/Distribution/Info.plist >/dev/null
plutil -lint Documentation/Distribution/VoxHearth.entitlements >/dev/null
[[ "$(plutil -extract LSMultipleInstancesProhibited raw -o - Documentation/Distribution/Info.plist)" == "true" ]] || {
  printf 'error: app bundle must prohibit multiple instances\n' >&2
  exit 1
}
./scripts/check-release-binary.sh --self-test
./scripts/verify-release.sh --self-test
[[ -f Brand/VoxHearth.icns ]] || {
  printf 'error: required application icon is missing: Brand/VoxHearth.icns\n' >&2
  exit 1
}
file Brand/VoxHearth.icns | grep -Fq 'Mac OS X icon' || {
  printf 'error: Brand/VoxHearth.icns is not a valid macOS icon file\n' >&2
  exit 1
}
zsh -n Brand/build-icon.sh
[[ -x scripts/capture-diagnostics.sh && -x scripts/soak-eval.sh ]] || {
  printf 'error: diagnostic scripts must be executable\n' >&2
  exit 1
}
grep -Fq -- 'subsystem == \"com.stephansturges.voxhearth\" AND processIdentifier ==' \
  scripts/capture-diagnostics.sh
grep -Fq -- '--info' scripts/capture-diagnostics.sh || {
  printf 'error: retrospective lifecycle capture must request info-level markers\n' >&2
  exit 1
}
if grep -En 'printenv|ps[[:space:]]+e(ww)?|^[[:space:]]*env[[:space:]]' \
  scripts/capture-diagnostics.sh; then
  printf 'error: capture script may not expose a process environment\n' >&2
  exit 1
fi
if grep -Fq 'symbolEffect' Sources/VoxHearthApp/*.swift; then
  printf 'error: persistent symbol effects are forbidden in the long-running menu agent\n' >&2
  exit 1
fi
if grep -Fq 'privacy: .private' Sources/VoxHearthCore/PrivacySafeLogger.swift; then
  printf 'error: lifecycle event identifiers must stay public and content-free\n' >&2
  exit 1
fi
python3 - <<'PY'
from pathlib import Path

source = Path("Sources/VoxHearthCore/PrivacySafeLogger.swift").read_text(encoding="utf-8")
if "func info(_ event: PrivacyLogEvent)" not in source:
    raise SystemExit("error: privacy-safe logger must accept only the closed event enum")
if "func info(_ value: String" in source or "func info(_ message: String" in source:
    raise SystemExit("error: privacy-safe logger must not accept freeform strings")
PY

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
  Documentation/LOCAL_RELEASE_0.3.0-dev.3.diag2.md \
  Documentation/VERIFY_RELEASE.md Documentation/RELEASE.md \
  LICENSES/S1-mini-LICENSE.txt LICENSES/Qwen3-0.6B-Apache-2.0.txt \
  .github/release-notes-v0.3.0-dev.3.md \
  .github/release-notes-v0.3.0.md \
  .github/release-notes-v0.4.0-dev.1.md \
  .github/release-notes-v0.4.0-dev.2.md \
  .github/release-notes-v0.4.0-dev.3.md \
  .github/release-notes-v0.4.0.md; do
  [[ -f "$required_file" ]] || {
    printf 'error: required project document is missing: %s\n' "$required_file" >&2
    exit 1
  }
done

if git ls-files | grep -E -i '(^|/)([^/]+\.(dmg|gguf|metallib|p12)|AuthKey_[^/]+\.p8)$|\.mlmodelc/' >/dev/null; then
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
  -- Sources Tests Vendor/FluidAudioLocal Vendor/LlamaLocal; then
  printf 'error: runtime or test source contains a forbidden networking, updater, or telemetry API\n' >&2
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
python3 - <<'PY'
from pathlib import Path

source = Path("Sources/VoxHearthCore/ParakeetEngine.swift").read_text(encoding="utf-8")
expected = """preprocessorConfiguration.computeUnits = model == .multilingual
                ? .cpuOnly
                : .cpuAndNeuralEngine"""
if source.count(expected) != 1:
    raise SystemExit(
        "error: multilingual preprocessor must retain the measured cpuOnly placement"
    )
PY

printf '%s\n' '==> Resolve, test, and build'
swift package resolve
env -u VOXHEARTH_LATENCY_EVAL swift test
inert_eval_output="$inert_eval_dir/result.json"
env -u VOXHEARTH_LATENCY_EVAL \
  VOXHEARTH_LATENCY_EVAL_OUTPUT="$inert_eval_output" \
  swift test --filter latencyEvaluator
[[ ! -e "$inert_eval_output" ]] || {
  printf 'error: latency evaluator must remain inert without its opt-in flag\n' >&2
  exit 1
}
inert_soak_output="$inert_eval_dir/soak-result.json"
env -u VOXHEARTH_LATENCY_EVAL -u VOXHEARTH_SOAK_EVAL \
  VOXHEARTH_SOAK_OUTPUT="$inert_soak_output" \
  swift test --filter lifecycleSoakEvaluator
[[ ! -e "$inert_soak_output" ]] || {
  printf 'error: lifecycle soak evaluator must remain inert without its opt-in flag\n' >&2
  exit 1
}
./scripts/latency-eval.sh verify
./scripts/soak-eval.sh verify
swift build --configuration debug
swift build --configuration release

binary_dir="$(swift build --configuration release --show-bin-path)"
./scripts/check-release-binary.sh "$binary_dir/VoxHearth"

metadata_dir="$inert_eval_dir/metadata"
mkdir -p "$metadata_dir"
metadata_artifact="$metadata_dir/artifact.bin"
printf 'local attribution fixture\n' > "$metadata_artifact"
source_revision="$(git rev-parse HEAD)"
SOURCE_DATE_EPOCH=1 ./scripts/generate-sbom.py \
  --version 0.4.0-dev.3 \
  --source-revision "$source_revision" \
  --artifact "$metadata_artifact" \
  --output "$metadata_dir/voxhearth.spdx.json"
SOURCE_DATE_EPOCH=1 ./scripts/generate-provenance.py \
  --version 0.4.0-dev.3 \
  --source-revision "$source_revision" \
  --source-tag v0.4.0-dev.3 \
  --release-channel development-prerelease \
  --signature 'anonymous ad-hoc signature; no publisher identity' \
  --notarization 'absent; development preview' \
  --artifact "$metadata_artifact" \
  --output "$metadata_dir/voxhearth-provenance.json"
python3 scripts/check-attribution.py \
  --sbom "$metadata_dir/voxhearth.spdx.json" \
  --provenance "$metadata_dir/voxhearth-provenance.json"

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
