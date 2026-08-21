#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: scripts/check-release-binary.sh BINARY | --self-test\n' >&2
}

contains_instrumentation() {
  grep -E '(^|[[:space:]])__llvm_(prf|cov)[[:alnum:]_]*([[:space:]]|$)' >/dev/null
}

contains_forbidden_network_symbol() {
  grep -Ei 'URLSession|CFNetwork|NW(Connection|Listener|Browser|Path|Endpoint)|WebSocket|_socket|_connect|_getaddrinfo|ModelHub|HFClient|FileDownloader|AssetDownloader|Downloader' >/dev/null
}

contains_forbidden_network_string() {
  grep -Ei 'https?://|huggingface\.co|api\.github\.com|URLSession|NWConnection|WebSocket|ModelHub|HFClient|FileDownloader|AssetDownloader|Downloader|downloadAndLoad' >/dev/null
}

unlisted_linked_libraries() {
  local path framework allowed
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      /usr/lib/libSystem.B.dylib|/usr/lib/libc++.1.dylib|/usr/lib/libobjc.A.dylib)
        continue
        ;;
      /usr/lib/swift/libswift*.dylib)
        continue
        ;;
      /System/Library/Frameworks/*.framework/Versions/*/*)
        framework="${path#/System/Library/Frameworks/}"
        framework="${framework%%.framework/*}"
        allowed=false
        for candidate in \
          Accelerate Foundation Metal MetalKit AVFAudio AVFoundation AppKit \
          ApplicationServices AudioToolbox Carbon CoreAudio CoreFoundation \
          CoreGraphics CoreML ServiceManagement SwiftUI; do
          if [[ "$framework" == "$candidate" ]]; then
            allowed=true
            break
          fi
        done
        [[ "$allowed" == true ]] && continue
        ;;
    esac
    printf '%s\n' "$path"
  done
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

if [[ "$1" == --self-test ]]; then
  clean_fixture=$'sectname __text\nsegname __TEXT\nsectname __swift5_types\nlocal_model_load'
  instrumented_fixture=$'sectname __llvm_prf_cnts\nsectname __llvm_covmap'
  network_symbol_fixture=$'U _$s10Foundation10URLSessionC\nU _connect'
  network_string_fixture=$'https://huggingface.co/example\nAssetDownloader'
  allowed_libraries_fixture=$'/System/Library/Frameworks/Metal.framework/Versions/A/Metal\n/usr/lib/libSystem.B.dylib\n/usr/lib/swift/libswiftCore.dylib'
  forbidden_library_fixture=$'/System/Library/Frameworks/WebKit.framework/Versions/A/WebKit'
  ! printf '%s\n' "$clean_fixture" | contains_instrumentation
  printf '%s\n' "$instrumented_fixture" | contains_instrumentation
  ! printf '%s\n' "$clean_fixture" | contains_forbidden_network_symbol
  ! printf '%s\n' "$clean_fixture" | contains_forbidden_network_string
  printf '%s\n' "$network_symbol_fixture" | contains_forbidden_network_symbol
  printf '%s\n' "$network_string_fixture" | contains_forbidden_network_string
  [[ -z "$(printf '%s\n' "$allowed_libraries_fixture" | unlisted_linked_libraries)" ]]
  [[ "$(printf '%s\n' "$forbidden_library_fixture" | unlisted_linked_libraries)" == "$forbidden_library_fixture" ]]
  printf 'release binary check self-test passed\n'
  exit 0
fi

binary="$1"
[[ -f "$binary" ]] || { printf 'error: binary not found: %s\n' "$binary" >&2; exit 1; }

file_description="$(file "$binary")"
grep -Fq 'arm64' <<< "$file_description" || {
  printf 'error: release binary is not arm64: %s\n' "$file_description" >&2
  exit 1
}

load_commands="$(otool -l "$binary")"
if printf '%s\n' "$load_commands" | contains_instrumentation; then
  printf 'error: release binary contains LLVM profile/coverage instrumentation\n' >&2
  exit 1
fi

linked_libraries="$(otool -L "$binary")"
if grep -Eiq 'Sparkle|Alamofire|Sentry|CFNetwork|Network\.framework|WebKit' \
  <<< "$linked_libraries"; then
  printf 'error: release binary links a forbidden updater/network SDK or framework\n' >&2
  printf '%s\n' "$linked_libraries" >&2
  exit 1
fi
linked_paths="$(awk 'NR > 1 { print $1 }' <<< "$linked_libraries")"
unexpected_libraries="$(unlisted_linked_libraries <<< "$linked_paths")"
if [[ -n "$unexpected_libraries" ]]; then
  printf 'error: release binary links libraries outside the reviewed allowlist:\n%s\n' \
    "$unexpected_libraries" >&2
  exit 1
fi

undefined_symbols="$(nm -u "$binary" 2>/dev/null || true)"
if contains_forbidden_network_symbol <<< "$undefined_symbols"; then
  printf 'error: release binary imports a forbidden network/downloader symbol\n' >&2
  grep -Ei 'URLSession|CFNetwork|NW(Connection|Listener|Browser|Path|Endpoint)|WebSocket|_socket|_connect|_getaddrinfo|ModelHub|HFClient|FileDownloader|AssetDownloader|Downloader' \
    <<< "$undefined_symbols" >&2
  exit 1
fi

binary_strings="$(strings "$binary")"
if contains_forbidden_network_string <<< "$binary_strings"; then
  printf 'error: release binary contains a forbidden network/downloader marker\n' >&2
  grep -Ei 'https?://|huggingface\.co|api\.github\.com|URLSession|NWConnection|WebSocket|ModelHub|HFClient|FileDownloader|AssetDownloader|Downloader|downloadAndLoad' \
    <<< "$binary_strings" | head -20 >&2
  exit 1
fi

printf 'release binary policy check passed: %s\n' "$binary"
