#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$repo_root/Vendor/LlamaLocal/ggml/src/ggml-metal/ggml-metal.metal"
output_file="${1:-$repo_root/.build/s1-mini/Metal/ggml-llama.metallib}"
metal_dir="$(dirname "$source_file")"

for command_name in shasum xcodebuild xcrun; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

[[ -f "$source_file" && ! -L "$source_file" ]] || {
  printf 'error: sealed Metal source is absent or is a symlink: %s\n' "$source_file" >&2
  exit 1
}

metal_path="$(xcrun -sdk macosx --find metal)"

if ! metal_version="$($metal_path --version 2>&1)"; then
  printf '%s\n' "$metal_version" >&2
  printf '%s\n' \
    'error: the selected Xcode lacks the optional Metal Toolchain component' \
    'install it explicitly with: xcodebuild -downloadComponent MetalToolchain' >&2
  exit 1
fi
if ! metallib_path="$(xcrun -sdk macosx --find metallib 2>/dev/null)"; then
  printf '%s\n' \
    'error: the selected Xcode lacks the optional Metal Toolchain component' \
    'install it explicitly with: xcodebuild -downloadComponent MetalToolchain' >&2
  exit 1
fi

build_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-metallib.XXXXXX")"
cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT

mkdir -p "$(dirname "$output_file")"
air_file="$build_dir/ggml-llama.air"
sealed_file="$build_dir/ggml-llama.metallib"

"$metal_path" \
  -c \
  -std=metal3.2 \
  -mmacosx-version-min=14.0 \
  -I"$metal_dir" \
  -DGGML_METAL_HAS_TENSOR=1 \
  -DGGML_METAL_HAS_BF16=1 \
  "$source_file" \
  -o "$air_file"
"$metallib_path" "$air_file" -o "$sealed_file"

[[ -s "$sealed_file" ]] || {
  printf 'error: Metal compiler produced an empty library\n' >&2
  exit 1
}
mv "$sealed_file" "$output_file"

source_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
output_sha="$(shasum -a 256 "$output_file" | awk '{print $1}')"
output_bytes="$(stat -f '%z' "$output_file")"
sdk_version="$(xcrun -sdk macosx --show-sdk-version)"

printf 'xcode=%s\n' "$(xcodebuild -version | tr '\n' ' ')"
printf 'metal=%s\n' "$(printf '%s' "$metal_version" | tr '\n' ' ')"
printf 'macos_sdk=%s\n' "$sdk_version"
printf 'source=%s\n' "$source_file"
printf 'source_sha256=%s\n' "$source_sha"
printf 'metallib=%s\n' "$output_file"
printf 'metallib_bytes=%s\n' "$output_bytes"
printf 'metallib_sha256=%s\n' "$output_sha"
