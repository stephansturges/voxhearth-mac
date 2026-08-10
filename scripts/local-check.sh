#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

swift package resolve
swift test
swift build --configuration debug
swift build --configuration release

if rg -n -i 'typewhisper' Package.swift Sources Tests Brand README.md SECURITY.md NOTICE UPSTREAM.md \
  | rg -v 'NOTICE|UPSTREAM.md|README.md'; then
  echo "Unexpected upstream brand reference in active VoxHearth files" >&2
  exit 1
fi

echo "VoxHearth local checks passed"
