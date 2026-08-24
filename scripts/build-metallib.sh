#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$repo_root/Vendor/LlamaLocal/ggml/src/ggml-metal/ggml-metal.metal"
output_file="${1:-$repo_root/.build/s1-mini/Metal/ggml-llama.metallib}"
provenance_file="${2:-$repo_root/.build/s1-mini/Metal/ggml-llama.metallib.json}"
metal_dir="$(dirname "$source_file")"
ggml_source_dir="$repo_root/Vendor/LlamaLocal/ggml/src"
toolchain_root="${VOXHEARTH_METAL_TOOLCHAIN_ROOT:-}"

for command_name in diff python3 shasum xcodebuild xcrun; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

[[ -f "$source_file" && ! -L "$source_file" ]] || {
  printf 'error: sealed Metal source is absent or is a symlink: %s\n' "$source_file" >&2
  exit 1
}

if [[ -n "$toolchain_root" ]]; then
  [[ "$toolchain_root" == /* && -d "$toolchain_root" && ! -L "$toolchain_root" ]] || {
    printf 'error: VOXHEARTH_METAL_TOOLCHAIN_ROOT must be an absolute, non-symlinked directory\n' >&2
    exit 1
  }
  metal_path="$toolchain_root/usr/bin/metal"
  metallib_path="$toolchain_root/usr/bin/metallib"
  [[ -x "$metal_path" && -x "$metallib_path" ]] || {
    printf 'error: explicit Metal toolchain is incomplete: %s\n' "$toolchain_root" >&2
    exit 1
  }
else
  metal_path="$(xcrun -sdk macosx --find metal)"
  metallib_path="$(xcrun -sdk macosx --find metallib 2>/dev/null || true)"
fi

if ! metal_version="$($metal_path --version 2>&1)"; then
  printf '%s\n' "$metal_version" >&2
  printf '%s\n' \
    'error: the selected Xcode lacks the optional Metal Toolchain component' \
    'install it explicitly with: xcodebuild -downloadComponent MetalToolchain' >&2
  exit 1
fi
if [[ ! -x "$metallib_path" ]]; then
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
mkdir -p "$(dirname "$provenance_file")"
air_file="$build_dir/ggml-llama.air"
sealed_file="$build_dir/ggml-llama.metallib"

"$metal_path" \
  -O3 \
  -c \
  -std=metal4.0 \
  -mmacosx-version-min=14.0 \
  -I"$metal_dir" \
  -I"$ggml_source_dir" \
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
compiler_version="$(printf '%s\n' "$metal_version" | sed -n '1p')"
compiler_target="$(printf '%s\n' "$metal_version" | sed -n '2p')"

python3 - \
  "$provenance_file" "$source_sha" "$output_sha" "$output_bytes" \
  "$sdk_version" "$compiler_version" "$compiler_target" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
document = {
    "schemaVersion": 1,
    "source": "Vendor/LlamaLocal/ggml/src/ggml-metal/ggml-metal.metal",
    "sourceSHA256": sys.argv[2],
    "artifact": "Metal/ggml-llama.metallib",
    "artifactSHA256": sys.argv[3],
    "artifactBytes": int(sys.argv[4]),
    "minimumMacOS": "14.0",
    "metalStandard": "metal4.0",
    "macOSSDK": sys.argv[5],
    "compiler": sys.argv[6],
    "compilerTarget": sys.argv[7],
    "defines": ["GGML_METAL_HAS_BF16=1", "GGML_METAL_HAS_TENSOR=1"],
}
path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
expected_manifest="$repo_root/Vendor/LlamaLocal/METALLIB.json"
[[ -f "$expected_manifest" && ! -L "$expected_manifest" ]] || {
  printf 'error: reviewed metallib manifest is missing\n' >&2
  exit 1
}
cmp "$expected_manifest" "$provenance_file" || {
  diff -u "$expected_manifest" "$provenance_file" >&2 || true
  printf 'error: rebuilt metallib does not match the reviewed manifest\n' >&2
  exit 1
}

printf 'xcode=%s\n' "$(xcodebuild -version | tr '\n' ' ')"
printf 'metal=%s\n' "$(printf '%s' "$metal_version" | tr '\n' ' ')"
printf 'macos_sdk=%s\n' "$sdk_version"
printf 'source=%s\n' "$source_file"
printf 'source_sha256=%s\n' "$source_sha"
printf 'metallib=%s\n' "$output_file"
printf 'metallib_bytes=%s\n' "$output_bytes"
printf 'metallib_sha256=%s\n' "$output_sha"
printf 'provenance=%s\n' "$provenance_file"
