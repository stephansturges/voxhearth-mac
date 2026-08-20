#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/capture-diagnostics.sh [--pid PID] [--out DIRECTORY] [--last 15m] [--sample-seconds 3]

Captures bounded, privacy-safe diagnostics for exactly one VoxHearth process.
It does not install, terminate, modify, or relaunch the application.
EOF
  exit 2
}

target_pid=""
output_directory=""
log_window="15m"
sample_seconds="3"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid)
      [[ $# -ge 2 ]] || usage
      target_pid="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || usage
      output_directory="$2"
      shift 2
      ;;
    --last)
      [[ $# -ge 2 ]] || usage
      log_window="$2"
      shift 2
      ;;
    --sample-seconds)
      [[ $# -ge 2 ]] || usage
      sample_seconds="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ "$log_window" =~ ^[1-9][0-9]*[smhd]$ ]] || usage
[[ "$sample_seconds" =~ ^[1-9][0-9]*$ ]] || usage

if [[ -z "$target_pid" ]]; then
  matching_pids=( $(/usr/bin/pgrep -x VoxHearth || true) )
  [[ ${#matching_pids[@]} -eq 1 ]] || {
    printf 'error: expected exactly one VoxHearth process; pass --pid explicitly\n' >&2
    exit 1
  }
  target_pid="${matching_pids[0]}"
fi

[[ "$target_pid" =~ ^[1-9][0-9]*$ ]] || usage
/bin/kill -0 "$target_pid" 2>/dev/null || {
  printf 'error: process is not running: %s\n' "$target_pid" >&2
  exit 1
}

if [[ -z "$output_directory" ]]; then
  output_directory="$PWD/VoxHearth-diagnostics-$(date -u +%Y%m%dT%H%M%SZ)"
fi
[[ ! -e "$output_directory" ]] || {
  printf 'error: refusing to overwrite diagnostic directory: %s\n' "$output_directory" >&2
  exit 1
}
/bin/mkdir -p "$output_directory"

temporary_root="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-capture.XXXXXX")"
cleanup() {
  /bin/rm -rf -- "$temporary_root"
}
trap cleanup EXIT

record_unavailable() {
  printf 'unavailable\n' > "$1"
}

redact_paths() {
  /usr/bin/sed -E 's#(/[^[:space:]]+)+#<redacted-path>#g'
}

run_redacted() {
  local output_name="$1"
  shift
  local raw_output="$temporary_root/raw-output"
  if "$@" > "$raw_output" 2>/dev/null; then
    redact_paths < "$raw_output" > "$output_directory/$output_name"
  else
    record_unavailable "$output_directory/$output_name"
  fi
}

if /usr/bin/log show \
  --info \
  --last "$log_window" \
  --style compact \
  --predicate "subsystem == \"com.stephansturges.voxhearth\" AND processIdentifier == $target_pid" \
  > "$temporary_root/logs" 2>/dev/null; then
  redact_paths < "$temporary_root/logs" > "$output_directory/logs.txt"
else
  record_unavailable "$output_directory/logs.txt"
fi

run_redacted process.txt \
  /bin/ps -p "$target_pid" -o pid=,etime=,%cpu=,rss=,vsz=,state=
run_redacted threads.txt \
  /bin/ps -M -p "$target_pid" -o pid=,state=
run_redacted vmmap-summary.txt /usr/bin/vmmap -summary "$target_pid"
run_redacted heap-summary.txt /usr/bin/heap -q -H "$target_pid"
run_redacted sample.txt /usr/bin/sample "$target_pid" "$sample_seconds" 10

cat > "$output_directory/MANIFEST.txt" <<EOF
VoxHearth bounded latency diagnostics
target_pid=$target_pid
log_window=$log_window
sample_seconds=$sample_seconds

logs.txt: fixed subsystem predicate only
process.txt: one PID and fixed non-environment columns
threads.txt: one PID thread identifiers and states
vmmap-summary.txt: summary mode with filesystem paths redacted
heap-summary.txt: quiet aggregate class summary with paths redacted
sample.txt: bounded stack sample with paths redacted

Deliberately excluded: transcript text, audio, clipboard content, process environment,
unrelated processes, full filesystem paths, installation, termination, and mutation.
Unavailable tools or denied process inspection are recorded as unavailable.
EOF

printf 'diagnostics written: %s\n' "$output_directory"
printf '%s\n' 'the target application was not installed, terminated, or modified'
