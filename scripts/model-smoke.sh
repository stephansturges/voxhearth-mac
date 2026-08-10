#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model_dir="${1:-$repo_root/.build/models/parakeet-tdt-0.6b-v3-coreml}"

for command_name in say sandbox-exec swift; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

"$repo_root/scripts/verify-model.py" "$model_dir"
model_dir="$(cd "$model_dir" && pwd -P)"

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
    VOXHEARTH_MODEL_SMOKE_MODEL_DIR="$model_dir" \
    VOXHEARTH_MODEL_SMOKE_AUDIO_FILE="$audio_file" \
    swift test \
      --disable-sandbox \
      --package-path "$repo_root" \
      --scratch-path "$smoke_root/swift-build" \
      --filter realModelSmokeTranscribesGeneratedSpeech

printf 'offline real-model transcription smoke test passed\n'
