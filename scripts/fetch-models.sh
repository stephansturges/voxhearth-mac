#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for manifest in \
  "$repo_root/Models/parakeet-tdt-0.6b-v3-coreml.json" \
  "$repo_root/Models/parakeet-tdt-ctc-110m-coreml.json" \
  "$repo_root/Models/s1-mini-gguf.json"; do
  "$repo_root/scripts/fetch-model.sh" --manifest "$manifest"
done

printf '%s\n' 'all bundled models fetched and verified'
