#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="VoxHearth"
bundle_id="com.stephansturges.voxhearth"
version="${VERSION:-0.4.0}"
build_number="${BUILD_NUMBER:-1}"
architecture="${ARCHITECTURE:-arm64}"
model_dir="${MODEL_DIR:-$repo_root/.build/models/parakeet-tdt-0.6b-v3-coreml}"
compact_model_dir="${COMPACT_MODEL_DIR:-$repo_root/.build/models/parakeet-tdt-ctc-110m-coreml}"
s1_model_dir="${S1_MODEL_DIR:-$repo_root/.build/models/s1-mini-gguf}"
metallib="${S1_METALLIB:-$repo_root/.build/s1-mini/Metal/ggml-llama.metallib}"
output="${APP_OUTPUT:-$repo_root/.build/distribution/VoxHearth.app}"

usage() {
  cat <<'EOF'
Usage: scripts/build-app-bundle.sh [options]

Options:
  --version VERSION       Marketing version (default: VERSION or 0.4.0)
  --build NUMBER          Integer build number (default: BUILD_NUMBER or 1)
  --model-dir PATH        Verified model directory
  --compact-model-dir PATH  Verified compact English model directory
  --s1-model-dir PATH     Verified S1-mini GGUF directory
  --metallib PATH         Verified sealed llama.cpp Metal library
  --output PATH           New .app path; an existing path is never overwritten
  --architecture ARCH     Swift target architecture (default: arm64)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --build) build_number="$2"; shift 2 ;;
    --model-dir) model_dir="$2"; shift 2 ;;
    --compact-model-dir) compact_model_dir="$2"; shift 2 ;;
    --s1-model-dir) s1_model_dir="$2"; shift 2 ;;
    --metallib) metallib="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --architecture) architecture="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'error: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  printf 'error: invalid version: %s\n' "$version" >&2
  exit 2
}
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || {
  printf 'error: build number must be a positive integer\n' >&2
  exit 2
}
[[ "$output" == *.app ]] || { printf 'error: output must end in .app\n' >&2; exit 2; }
[[ ! -e "$output" ]] || {
  printf 'error: output already exists; move it aside first: %s\n' "$output" >&2
  exit 1
}

"$repo_root/scripts/verify-model.py" "$model_dir"
"$repo_root/scripts/verify-model.py" \
  --manifest "$repo_root/Models/parakeet-tdt-ctc-110m-coreml.json" \
  "$compact_model_dir"
"$repo_root/scripts/verify-model.py" \
  --manifest "$repo_root/Models/s1-mini-gguf.json" \
  "$s1_model_dir"
"$repo_root/scripts/check-attribution.py"

metallib_manifest="$repo_root/Vendor/LlamaLocal/METALLIB.json"
python3 - "$metallib" "$metallib_manifest" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

artifact = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
if artifact.is_symlink() or not artifact.is_file():
    raise SystemExit("error: metallib is missing, non-regular, or a symlink")
digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
if artifact.stat().st_size != manifest["artifactBytes"] or digest != manifest["artifactSHA256"]:
    raise SystemExit("error: metallib does not match reviewed manifest")
PY

cd "$repo_root"
swift package resolve
swift build --configuration release --arch "$architecture"
bin_dir="$(swift build --configuration release --arch "$architecture" --show-bin-path)"
executable="$bin_dir/$app_name"
[[ -x "$executable" ]] || {
  printf 'error: release executable not found: %s\n' "$executable" >&2
  exit 1
}

output_parent="$(dirname "$output")"
mkdir -p "$output_parent"
required_payload_bytes="$(python3 - "$repo_root" "$executable" "$metallib" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
total = sum(
    json.loads((root / "Models" / name).read_text(encoding="utf-8"))["totalSize"]
    for name in (
        "parakeet-tdt-0.6b-v3-coreml.json",
        "parakeet-tdt-ctc-110m-coreml.json",
        "s1-mini-gguf.json",
    )
)
total += Path(sys.argv[2]).stat().st_size
total += Path(sys.argv[3]).stat().st_size
print(total + 64 * 1024 * 1024)
PY
)"
available_bytes="$(( $(df -Pk "$output_parent" | awk 'NR == 2 { print $4 }') * 1024 ))"
if (( available_bytes < required_payload_bytes )); then
  printf 'error: insufficient free space for exact app staging: need %s bytes, have %s bytes\n' \
    "$required_payload_bytes" "$available_bytes" >&2
  exit 1
fi
staging="$(mktemp -d "$output_parent/.voxhearth-app.XXXXXX")"
cleanup() {
  rm -rf "$staging"
}
trap cleanup EXIT

app="$staging/$app_name.app"
contents="$app/Contents"
resources="$contents/Resources"
mkdir -p \
  "$contents/MacOS" \
  "$resources/Models/Manifests" \
  "$resources/Metal" \
  "$resources/Legal"
ditto "$executable" "$contents/MacOS/$app_name"
chmod 755 "$contents/MacOS/$app_name"

ditto "$repo_root/Documentation/Distribution/Info.plist" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$contents/Info.plist"

icon="$repo_root/Brand/VoxHearth.icns"
[[ -f "$icon" ]] || { printf 'error: required app icon is missing: %s\n' "$icon" >&2; exit 1; }
file "$icon" | grep -Fq 'Mac OS X icon' || {
  printf 'error: app icon is not a valid ICNS file: %s\n' "$icon" >&2
  exit 1
}
ditto "$icon" "$resources/VoxHearth.icns"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string VoxHearth' "$contents/Info.plist"

ditto "$model_dir" "$resources/Models/parakeet-tdt-0.6b-v3-coreml"
ditto "$compact_model_dir" "$resources/Models/parakeet-tdt-ctc-110m-coreml"
ditto "$s1_model_dir" "$resources/Models/s1-mini-gguf"
ditto "$repo_root/Models/parakeet-tdt-0.6b-v3-coreml.json" \
  "$resources/Models/Manifests/parakeet-tdt-0.6b-v3-coreml.json"
ditto "$repo_root/Models/parakeet-tdt-ctc-110m-coreml.json" \
  "$resources/Models/Manifests/parakeet-tdt-ctc-110m-coreml.json"
ditto "$repo_root/Models/s1-mini-gguf.json" \
  "$resources/Models/Manifests/s1-mini-gguf.json"
ditto "$metallib" "$resources/Metal/ggml-llama.metallib"
ditto "$metallib_manifest" "$resources/Metal/manifest.json"

for legal_file in LICENSE NOTICE UPSTREAM.md SECURITY.md THIRD_PARTY_NOTICES.md; do
  [[ -f "$repo_root/$legal_file" ]] || {
    printf 'error: required legal file is missing: %s\n' "$legal_file" >&2
    exit 1
  }
  ditto "$repo_root/$legal_file" "$resources/Legal/$legal_file"
done
ditto "$repo_root/LICENSES" "$resources/Legal/LICENSES"
for document in PRIVACY.md THREAT_MODEL.md MODEL_PROVENANCE.md; do
  ditto "$repo_root/Documentation/$document" "$resources/Legal/$document"
done

plutil -lint "$contents/Info.plist" >/dev/null
"$repo_root/scripts/check-release-binary.sh" "$contents/MacOS/$app_name"
"$repo_root/scripts/verify-model-bundle.py" "$resources/Models"
"$repo_root/scripts/verify-metallib.py" "$resources/Metal"
"$repo_root/scripts/check-attribution.py" --app "$app"

# Exercise both structural failure directions against the exact pre-signing
# tree, then restore it before signing. No payload bytes are duplicated.
negative_manifest="$resources/Models/Manifests/unexpected.json"
ditto "$repo_root/Models/s1-mini-gguf.json" "$negative_manifest"
if "$repo_root/scripts/verify-model-bundle.py" "$resources/Models" >/dev/null 2>&1; then
  printf 'error: bundle verifier accepted an extra manifest\n' >&2
  exit 1
fi
unlink "$negative_manifest"
held_manifest="$staging/s1-mini-gguf.json.held"
mv "$resources/Models/Manifests/s1-mini-gguf.json" "$held_manifest"
if "$repo_root/scripts/verify-model-bundle.py" "$resources/Models" >/dev/null 2>&1; then
  printf 'error: bundle verifier accepted a missing manifest\n' >&2
  exit 1
fi
mv "$held_manifest" "$resources/Models/Manifests/s1-mini-gguf.json"
"$repo_root/scripts/verify-model-bundle.py" "$resources/Models"
"$repo_root/scripts/check-attribution.py" --app "$app"

# Seal the complete development bundle so LaunchServices can validate its
# Info.plist and resources. This anonymous ad-hoc signature carries no trusted
# publisher identity and is replaced by the Developer ID signature in release
# builds.
codesign --force \
  --sign - \
  --options runtime \
  --entitlements "$repo_root/Documentation/Distribution/VoxHearth.entitlements" \
  "$app"
codesign --verify --deep --strict --verbose=2 "$app"

mv "$app" "$output"
printf 'ad-hoc signed development app bundle created: %s\n' "$output"
