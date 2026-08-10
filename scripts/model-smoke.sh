#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/Models/parakeet-tdt-0.6b-v3-coreml.json"
model_dir=""

if [[ "${1:-}" == "--manifest" ]]; then
  [[ $# -ge 2 ]] || { printf 'error: --manifest requires a path\n' >&2; exit 2; }
  manifest="$2"
  shift 2
fi
if [[ $# -gt 1 ]]; then
  printf 'Usage: scripts/model-smoke.sh [--manifest PATH] [MODEL_DIR]\n' >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  model_dir="$1"
else
  bundle_root="$(python3 - "$manifest" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(json.load(source)["bundleRoot"])
PY
)"
  model_dir="$repo_root/.build/models/$bundle_root"
fi

for command_name in say sandbox-exec swift; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

"$repo_root/scripts/verify-model.py" --manifest "$manifest" "$model_dir"
model_dir="$(cd "$model_dir" && pwd -P)"
model_id="$(python3 - "$manifest" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(json.load(source)["modelId"])
PY
)"

smoke_root="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-model-smoke.XXXXXX")"
cleanup() {
  rm -rf "$smoke_root"
}
trap cleanup EXIT

audio_file="$smoke_root/fixture.aiff"
say \
  --output-file="$audio_file" \
  --file-format=AIFF \
  'Vox Hearth keeps every spoken word private and local.'

[[ -s "$audio_file" ]] || {
  printf 'error: say did not create the model smoke fixture\n' >&2
  exit 1
}

mkdir -p \
  "$smoke_root/home" \
  "$smoke_root/clang-module-cache" \
  "$smoke_root/swift-module-cache"

sandbox_profile=$'(version 1)\n(allow default)\n(deny network*)'
sandbox-exec -p "$sandbox_profile" \
  env \
    HOME="$smoke_root/home" \
    CLANG_MODULE_CACHE_PATH="$smoke_root/clang-module-cache" \
    SWIFT_MODULE_CACHE_PATH="$smoke_root/swift-module-cache" \
    VOXHEARTH_MODEL_SMOKE=1 \
    VOXHEARTH_MODEL_SMOKE_MODEL_ID="$model_id" \
    VOXHEARTH_MODEL_SMOKE_MODEL_DIR="$model_dir" \
    VOXHEARTH_MODEL_SMOKE_AUDIO_FILE="$audio_file" \
    swift test \
      --disable-sandbox \
      --package-path "$repo_root" \
      --scratch-path "$smoke_root/swift-build" \
      --filter realModelSmokeTranscribesGeneratedSpeech

printf 'offline real-model transcription smoke test passed\n'
