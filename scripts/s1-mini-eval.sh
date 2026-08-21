#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixtures="$repo_root/Research/s1-mini/evaluation/fixtures.json"
ratchet="$repo_root/Research/s1-mini/evaluation/RATCHET.json"
product="VoxHearthS1MiniEval"
binary="$repo_root/.build/arm64-apple-macosx/release/$product"
evaluation_staging=""

cleanup_staging() {
  if [[ -n "$evaluation_staging" ]]; then
    rm -rf "$evaluation_staging"
  fi
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

verify_contract() {
  jq -e '
    .schemaVersion == 1 and
    (.fixtures | type == "array" and length > 0) and
    ([.fixtures[].id] | length == (unique | length))
  ' "$fixtures" >/dev/null || fail "invalid S1-mini fixture corpus"
  jq -e --argjson count "$(jq '.fixtures | length' "$fixtures")" '
    .schemaVersion == 1 and
    .fixtureCount == $count and
    .requiredFixturePasses == $count and
    .requiredDeterministicRepeat == true and
    .maximumModelLoads == 1 and
    .maximumContextCreations == 1 and
    .requiredWarmups == 1
  ' "$ratchet" >/dev/null || fail "invalid S1-mini ratchet"
}

verify_payload() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha="$3"
  [[ -f "$path" && ! -L "$path" ]] || fail "payload is absent, non-regular, or a symlink: $path"
  [[ "$(stat -f '%z' "$path")" == "$expected_bytes" ]] || fail "payload size mismatch: $path"
  [[ "$(shasum -a 256 "$path" | awk '{print $1}')" == "$expected_sha" ]] || fail "payload digest mismatch: $path"
}

stage_app() {
  local app="$1"
  local metallib="$2"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Metal"
  cp "$binary" "$app/Contents/MacOS/$product"
  cp "$metallib" "$app/Contents/Resources/Metal/ggml-llama.metallib"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string "$product" "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string com.stephansturges.voxhearth.s1eval "$app/Contents/Info.plist"
  plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
}

run_measured() {
  local backend="$1"
  local executable="$2"
  local model="$3"
  local output="$4"
  local repeats="$5"
  local interval="$6"
  local metrics="${output%.json}.metrics.json"
  local stderr="${output%.json}.stderr.txt"
  local maximum_rss_kb=0
  local maximum_threads=0
  "$executable" \
    --backend "$backend" \
    --model "$model" \
    --fixtures "$fixtures" \
    --repeats "$repeats" \
    --interval-ms "$interval" \
    >"$output" 2>"$stderr" &
  local eval_pid=$!
  while kill -0 "$eval_pid" 2>/dev/null; do
    local rss_kb
    local threads
    rss_kb="$(ps -o rss= -p "$eval_pid" 2>/dev/null | tr -d ' ' || true)"
    threads="$(ps -M -p "$eval_pid" 2>/dev/null | awk 'NR > 1 { count += 1 } END { print count + 0 }')"
    [[ "$rss_kb" =~ ^[0-9]+$ ]] && (( rss_kb > maximum_rss_kb )) && maximum_rss_kb=$rss_kb
    [[ "$threads" =~ ^[0-9]+$ ]] && (( threads > maximum_threads )) && maximum_threads=$threads
    sleep 0.02
  done
  local eval_status=0
  wait "$eval_pid" || eval_status=$?
  [[ "$eval_status" == 0 ]] || fail "$backend evaluator failed with status $eval_status"
  jq -n \
    --argjson maximumRSSBytes "$((maximum_rss_kb * 1024))" \
    --argjson maximumThreads "$maximum_threads" \
    '{maximumRSSBytes: $maximumRSSBytes, maximumThreads: $maximumThreads}' >"$metrics"
}

assert_report() {
  local backend="$1"
  local report="$2"
  local metrics="$3"
  jq -e --arg backend "$backend" --slurpfile ratchet "$ratchet" '
    .schemaVersion == 1 and
    .backend == $backend and
    .fixtureCount == $ratchet[0].fixtureCount and
    .passedFixtureCount == $ratchet[0].requiredFixturePasses and
    .deterministicRepeat == $ratchet[0].requiredDeterministicRepeat and
    .latenciesMilliseconds.p95 <= $ratchet[0].maximumP95Milliseconds[$backend] and
    .counters.modelLoads <= $ratchet[0].maximumModelLoads and
    .counters.contextCreations <= $ratchet[0].maximumContextCreations and
    .counters.warmups == $ratchet[0].requiredWarmups and
    ([.fixtures[].passed] | all)
  ' "$report" >/dev/null || fail "$backend semantic/performance ratchet failed"
  jq -e --arg backend "$backend" --slurpfile ratchet "$ratchet" '
    .maximumRSSBytes > 0 and
    .maximumRSSBytes <= $ratchet[0].maximumPeakRSSBytes[$backend] and
    .maximumThreads > 0
  ' "$metrics" >/dev/null || fail "$backend resource ratchet failed"
}

run_evaluation() {
  local model="${VOXHEARTH_S1_MODEL_PATH:-}"
  local metallib="${VOXHEARTH_S1_METALLIB_PATH:-}"
  local output_dir="${VOXHEARTH_S1_EVAL_OUTPUT_DIR:-$repo_root/.build/s1-mini-evaluation}"
  local repeats="${VOXHEARTH_S1_EVAL_REPEATS:-20}"
  local interval="${VOXHEARTH_S1_EVAL_INTERVAL_MS:-100}"
  [[ -n "$model" ]] || fail "VOXHEARTH_S1_MODEL_PATH is required"
  [[ -n "$metallib" ]] || fail "VOXHEARTH_S1_METALLIB_PATH is required"
  [[ "$repeats" =~ ^[1-9][0-9]*$ ]] || fail "repeats must be positive"
  [[ "$interval" =~ ^[0-9]+$ ]] || fail "interval must be non-negative"
  verify_payload "$model" 484219808 3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634
  verify_payload "$metallib" 8445733 97897d540709e3819756049c07d67ed5653136d28638e17159c4940ccaf42ea8

  swift build -c release --product "$product"
  mkdir -p "$output_dir"
  evaluation_staging="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-s1-eval.XXXXXX")"
  trap cleanup_staging EXIT
  local staging="$evaluation_staging"
  local app="$staging/$product.app"
  stage_app "$app" "$metallib"
  local executable="$app/Contents/MacOS/$product"

  run_measured cpu "$executable" "$model" "$output_dir/cpu.json" "$repeats" "$interval"
  run_measured metal "$executable" "$model" "$output_dir/metal.json" "$repeats" "$interval"
  assert_report cpu "$output_dir/cpu.json" "$output_dir/cpu.metrics.json"
  assert_report metal "$output_dir/metal.json" "$output_dir/metal.metrics.json"

  local sandbox_profile="$staging/network-denied.sb"
  printf '%s\n' '(version 1)' '(allow default)' '(deny network*)' >"$sandbox_profile"
  for backend in cpu metal; do
    sandbox-exec -f "$sandbox_profile" "$executable" \
      --backend "$backend" --model "$model" --fixtures "$fixtures" \
      --repeats 1 --interval-ms 0 \
      >"$output_dir/$backend.network-denied.json" \
      2>"$output_dir/$backend.network-denied.stderr.txt"
    env \
      GGML_METAL_PATH_RESOURCES=/private/tmp/hostile \
      GGML_METAL_DEVICES=0 \
      GGML_METAL_FUSION_DISABLE=1 \
      "$executable" \
      --backend "$backend" --model "$model" --fixtures "$fixtures" \
      --repeats 1 --interval-ms 0 \
      >"$output_dir/$backend.hostile-environment.json" \
      2>"$output_dir/$backend.hostile-environment.stderr.txt"
    jq -e --arg digest "$(jq -r '.resultDigest' "$output_dir/$backend.json")" '
      .passedFixtureCount == .fixtureCount and .resultDigest == $digest
    ' "$output_dir/$backend.network-denied.json" >/dev/null || fail "$backend network-denied result changed"
    jq -e --arg digest "$(jq -r '.resultDigest' "$output_dir/$backend.json")" '
      .passedFixtureCount == .fixtureCount and .resultDigest == $digest
    ' "$output_dir/$backend.hostile-environment.json" >/dev/null || fail "$backend hostile environment changed behavior"
  done

  local bad_model="$staging/bad.gguf"
  printf 'invalid' >"$bad_model"
  if "$executable" --backend cpu --model "$bad_model" --fixtures "$fixtures" --repeats 1 --interval-ms 0 >/dev/null 2>&1; then
    fail "invalid model payload was accepted"
  fi
  local linked_model="$staging/linked.gguf"
  ln -s "$model" "$linked_model"
  if "$executable" --backend cpu --model "$linked_model" --fixtures "$fixtures" --repeats 1 --interval-ms 0 >/dev/null 2>&1; then
    fail "symlink model payload was accepted"
  fi
  if rg -l 'ZXQ-VOXHEARTH-PRIVATE-9F7B' "$output_dir" >/dev/null; then
    fail "private fixture canary appeared in evaluator output or logs"
  fi

  jq -n \
    --slurpfile cpu "$output_dir/cpu.json" \
    --slurpfile metal "$output_dir/metal.json" \
    --slurpfile cpuMetrics "$output_dir/cpu.metrics.json" \
    --slurpfile metalMetrics "$output_dir/metal.metrics.json" \
    --arg fixtureSHA256 "$(shasum -a 256 "$fixtures" | awk '{print $1}')" \
    --arg ratchetSHA256 "$(shasum -a 256 "$ratchet" | awk '{print $1}')" \
    '{
      schemaVersion: 1,
      fixtureSHA256: $fixtureSHA256,
      ratchetSHA256: $ratchetSHA256,
      cpu: $cpu[0],
      metal: $metal[0],
      resources: {cpu: $cpuMetrics[0], metal: $metalMetrics[0]},
      networkDenied: true,
      hostileEnvironmentEquivalent: true,
      privateCanaryAbsent: true,
      invalidAssetRejection: true
    }' >"$output_dir/aggregate.json"
  printf 'S1-mini evaluation passed: %s\n' "$output_dir/aggregate.json"
}

case "${1:-verify}" in
  verify)
    verify_contract
    printf 'S1-mini evaluation contract verified\n'
    ;;
  run)
    verify_contract
    run_evaluation
    ;;
  *)
    fail "usage: $0 [verify|run]"
    ;;
esac
