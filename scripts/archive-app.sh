#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: scripts/archive-app.sh APP_PATH OUTPUT_ZIP\n' >&2
  exit 2
fi

app_path="$1"
output_zip="$2"
[[ -d "$app_path" && "$app_path" == *.app ]] || {
  printf 'error: app bundle not found: %s\n' "$app_path" >&2
  exit 1
}
[[ "$output_zip" == *.zip ]] || { printf 'error: output must end in .zip\n' >&2; exit 2; }
[[ ! -e "$output_zip" ]] || {
  printf 'error: output already exists: %s\n' "$output_zip" >&2
  exit 1
}

mkdir -p "$(dirname "$output_zip")"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_zip"
printf 'app archive created: %s\n' "$output_zip"
