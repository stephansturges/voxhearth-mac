#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/Models/parakeet-tdt-0.6b-v3-coreml.json"
destination=""

usage() {
  cat <<'EOF'
Usage: scripts/fetch-model.sh [--manifest PATH] [--destination PATH]

Download one exact, build-only Parakeet model revision recorded in Models/.
The destination must not already contain an incomplete or changed payload.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      manifest="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      destination="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -f "$manifest" ]] || {
  printf 'error: model manifest not found: %s\n' "$manifest" >&2
  exit 1
}

bundle_root="$(python3 - "$manifest" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(json.load(source)["bundleRoot"])
PY
)"
if [[ -z "$destination" ]]; then
  destination="$repo_root/.build/models/$bundle_root"
fi

for command_name in curl python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

"$repo_root/scripts/verify-model.py" --manifest "$manifest" --manifest-only

if [[ -e "$destination" ]]; then
  if "$repo_root/scripts/verify-model.py" --manifest "$manifest" "$destination"; then
    printf 'model already present and verified: %s\n' "$destination"
    exit 0
  fi
  printf 'error: destination exists but is not the locked model payload: %s\n' "$destination" >&2
  printf 'move it aside and retry; this script will not overwrite it\n' >&2
  exit 1
fi

destination_parent="$(dirname "$destination")"
mkdir -p "$destination_parent"
staging="$(mktemp -d "$destination_parent/.voxhearth-model.XXXXXX")"
cleanup() {
  rm -rf "$staging"
}
trap cleanup EXIT

revision="$(python3 - "$manifest" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(json.load(source)["revision"])
PY
)"
model_id="$(python3 - "$manifest" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(json.load(source)["modelId"])
PY
)"
staged_model="$staging/$bundle_root"
mkdir -p "$staged_model"

python3 - "$manifest" <<'PY' | while IFS=$'\t' read -r relative expected_size expected_sha; do
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
for entry in manifest["files"]:
    print(entry["path"], entry["size"], entry["sha256"], sep="\t")
PY
  target="$staged_model/$relative"
  mkdir -p "$(dirname "$target")"
  encoded_path="$(python3 - "$relative" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe="/"))
PY
)"
  url="https://huggingface.co/$model_id/resolve/$revision/$encoded_path?download=true"
  printf 'fetching %s (%s bytes)\n' "$relative" "$expected_size"
  curl \
    --proto '=https' \
    --tlsv1.2 \
    --fail \
    --location \
    --retry 3 \
    --retry-all-errors \
    --silent \
    --show-error \
    --output "$target" \
    "$url"

  actual_size="$(wc -c < "$target" | tr -d '[:space:]')"
  actual_sha="$(shasum -a 256 "$target" | awk '{print $1}')"
  if [[ "$actual_size" != "$expected_size" || "$actual_sha" != "$expected_sha" ]]; then
    printf 'error: downloaded file does not match lock: %s\n' "$relative" >&2
    exit 1
  fi
done

"$repo_root/scripts/verify-model.py" --manifest "$manifest" "$staged_model"
mv "$staged_model" "$destination"
printf 'model fetched and verified: %s\n' "$destination"
