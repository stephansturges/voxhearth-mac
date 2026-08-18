#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture_manifest="$repo_root/Research/latency/fixtures.manifest.json"
fixture_root="$repo_root/Research/latency/fixtures"
evaluator_lock="$repo_root/Research/latency/evaluator.lock.json"
capability_file="$repo_root/Research/latency/model-capabilities.json"
multilingual_manifest="$repo_root/Models/parakeet-tdt-0.6b-v3-coreml.json"
compact_manifest="$repo_root/Models/parakeet-tdt-ctc-110m-coreml.json"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/latency-eval.sh fixtures
  scripts/latency-eval.sh verify
  scripts/latency-eval.sh run OUTPUT.json [P0|P1|P2|P3|P4|P5] [REPEATS]
  scripts/latency-eval.sh compare BASE.json CANDIDATE.json [NOISE.json]

run requires externally supplied, already-local model roots:
  VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT
  VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT
EOF
  exit 2
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

verify_fixtures() {
  python3 - "$fixture_manifest" "$fixture_root" <<'PY'
import hashlib
import json
import math
from pathlib import Path
import sys

manifest_path = Path(sys.argv[1])
fixture_root = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
if manifest.get("schemaVersion") != 1:
    raise SystemExit("error: unsupported fixture-manifest schema")
fixtures = manifest.get("fixtures")
if not isinstance(fixtures, list) or len(fixtures) != 14:
    raise SystemExit("error: fixture manifest must contain exactly 14 fixtures")
if sum(item.get("role") == "scored" for item in fixtures) != 10:
    raise SystemExit("error: fixture manifest must contain exactly 10 scored fixtures")
if sum(item.get("role") == "guardrail" for item in fixtures) != 4:
    raise SystemExit("error: fixture manifest must contain exactly 4 guardrail fixtures")

expected = set()
seen_ids = set()
for item in fixtures:
    name = item.get("file")
    fixture_id = item.get("id")
    if not isinstance(name, str) or Path(name).name != name or not name.endswith(".aiff"):
        raise SystemExit(f"error: unsafe fixture path: {name!r}")
    if fixture_id in seen_ids:
        raise SystemExit(f"error: duplicate fixture id: {fixture_id}")
    seen_ids.add(fixture_id)
    expected.add(name)
    path = fixture_root / name
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"error: missing, non-regular, or symlinked fixture: {name}")
    if path.stat().st_size != item.get("size"):
        raise SystemExit(f"error: fixture size mismatch: {name}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != item.get("sha256"):
        raise SystemExit(f"error: fixture digest mismatch: {name}")
    duration = item.get("durationSeconds")
    if not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0:
        raise SystemExit(f"error: invalid fixture duration: {name}")

actual = {path.name for path in fixture_root.iterdir() if path.is_file()}
if actual != expected:
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    raise SystemExit(f"error: fixture file set mismatch; missing={missing}, extra={extra}")
print(f"fixture dataset verified: {len(fixtures)} files")
PY
}

verify_evaluator_lock() {
  python3 - "$repo_root" "$evaluator_lock" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1])
lock_path = Path(sys.argv[2])
lock = json.loads(lock_path.read_text(encoding="utf-8"))
if lock.get("schemaVersion") != 1 or lock.get("hashAlgorithm") != "sha256":
    raise SystemExit("error: unsupported evaluator lock")
files = lock.get("files")
if not isinstance(files, list) or not files:
    raise SystemExit("error: evaluator lock has no files")
seen = set()
for item in files:
    relative = item.get("path")
    digest = item.get("sha256")
    pure = PurePosixPath(relative) if isinstance(relative, str) else None
    if pure is None or pure.is_absolute() or ".." in pure.parts or str(pure) != relative:
        raise SystemExit(f"error: unsafe evaluator-lock path: {relative!r}")
    if relative in seen:
        raise SystemExit(f"error: duplicate evaluator-lock path: {relative}")
    seen.add(relative)
    path = root / relative
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"error: locked file missing, non-regular, or symlinked: {relative}")
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != digest:
        raise SystemExit(f"error: evaluator lock mismatch: {relative}")
print(f"evaluator lock verified: {len(files)} files")
PY
}

verify_model_manifests() {
  "$repo_root/scripts/verify-model.py" --manifest "$multilingual_manifest" --manifest-only
  "$repo_root/scripts/verify-model.py" --manifest "$compact_manifest" --manifest-only
}

verify_model_payloads() {
  : "${VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT:?set VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT}"
  : "${VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT:?set VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT}"
  "$repo_root/scripts/verify-model.py" \
    --manifest "$multilingual_manifest" \
    "$VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT"
  "$repo_root/scripts/verify-model.py" \
    --manifest "$compact_manifest" \
    "$VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT"
}

verify_model_capabilities() {
  python3 - \
    "$capability_file" \
    "$VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT" \
    "$VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT" <<'PY'
import json
from pathlib import Path
import sys

expected = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
roots = {
    "parakeet-tdt-0.6b-v3-coreml": Path(sys.argv[2]),
    "parakeet-tdt-ctc-110m-coreml": Path(sys.argv[3]),
}
for model, root in roots.items():
    metadata_path = root / "Preprocessor.mlmodelc" / "metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))[0]
    audio = next(item for item in metadata["inputSchema"] if item["name"] == "audio_signal")
    recorded = expected["models"][model]["preprocessor"]
    actual_shape = json.loads(audio["shape"])
    actual_flexible = audio["hasShapeFlexibility"] != "0"
    if actual_shape != recorded["audioInputShape"]:
        raise SystemExit(f"error: preprocessor shape drift for {model}: {actual_shape}")
    if actual_flexible != recorded["hasShapeFlexibility"]:
        raise SystemExit(f"error: preprocessor flexibility drift for {model}")
print("model capability fingerprint verified: fixed [1, 240000] inputs")
PY
}

refuse_dirty_tree() {
  local dirty
  dirty="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all \
    | grep -Ev '^\?\? \.graph-worker/' || true)"
  if [[ -n "$dirty" ]]; then
    printf 'error: latency evaluation requires a clean candidate commit:\n%s\n' "$dirty" >&2
    exit 1
  fi
}

aggregate_partials() {
  local output_path="$1"
  local profile="$2"
  local repeat_count="$3"
  shift 3
  python3 - "$output_path" "$profile" "$repeat_count" "$capability_file" "$@" <<'PY'
import hashlib
import json
import math
from pathlib import Path
import sys

output = Path(sys.argv[1])
profile = sys.argv[2]
repeat_count = int(sys.argv[3])
capabilities = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
partials = [json.loads(Path(path).read_text(encoding="utf-8")) for path in sys.argv[5:]]
if len(partials) != repeat_count:
    raise SystemExit("error: partial result count does not match requested repeats")

commit = partials[0]["gitCommit"]
digests = partials[0]["digests"]
if any(item["gitCommit"] != commit or item["dirty"] for item in partials):
    raise SystemExit("error: partial results are dirty or come from different commits")
if any(item["digests"] != digests for item in partials):
    raise SystemExit("error: partial result digest stamps differ")

samples = [sample for item in partials for sample in item["samples"]]
scored = [sample for sample in samples if sample["profile"] == "P0" and sample["scored"]]
if profile == "P0":
    if len(samples) != 10 * repeat_count or len(scored) != 9 * repeat_count:
        raise SystemExit("error: P0 must contain 10 samples/repeat with one excluded warm-up")

def finite(value):
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise SystemExit("error: non-finite numeric result")
    elif isinstance(value, dict):
        for nested in value.values():
            finite(nested)
    elif isinstance(value, list):
        for nested in value:
            finite(nested)

def percentile(values, probability):
    ordered = sorted(values)
    if not ordered:
        raise SystemExit("error: cannot compute percentile of an empty distribution")
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)

component_keys = {
    "cueDispatchMs": "cueDispatchMs",
    "captureStartCompletionMs": "captureStartCompletionMs",
    "audioStopEntryMs": "audioStopEntryMs",
    "visibleTextDispatchMs": "visibleTextDispatchMs",
}
components = {}
weighted_score = None
if scored:
    for name, key in component_keys.items():
        values = [sample[key] for sample in scored]
        components[name] = {
            "values": values,
            "median": percentile(values, 0.5),
            "p95": percentile(values, 0.95),
            "maximum": max(values),
        }
    weighted_score = (
        0.10 * components["cueDispatchMs"]["p95"]
        + 0.10 * components["captureStartCompletionMs"]["p95"]
        + 0.20 * components["audioStopEntryMs"]["p95"]
        + 0.60 * components["visibleTextDispatchMs"]["p95"]
    )

transcripts = {}
for sample in samples:
    key = f'{sample["fixtureID"]}:{sample["model"]}:{sample["language"]}'
    digest = hashlib.sha256(sample["transcript"].encode("utf-8")).hexdigest()
    previous = transcripts.setdefault(key, digest)
    if previous != digest:
        raise SystemExit(f"error: transcript changed between repeats: {key}")

result = {
    "schemaVersion": 1,
    "gitCommit": commit,
    "dirty": False,
    "profile": profile,
    "repeatCount": repeat_count,
    "digests": digests,
    "environment": [item["environment"] for item in partials],
    "samples": samples,
    "components": components,
    "weightedScoreMs": weighted_score,
    "coldSamples": [sample for sample in samples if sample["classification"].startswith("cold-")],
    "resources": {
        "processes": [item["resources"] for item in partials],
        "peakResidentBytes": max(item["resources"]["peakResidentBytes"] for item in partials),
        "cpuSeconds": sum(item["resources"]["cpuSeconds"] for item in partials),
    },
    "transcriptDigests": transcripts,
    "counts": [item["counts"] for item in partials],
    "modelCapabilities": capabilities,
    "objective": {
        "p95Method": "R-7 linear interpolation",
        "weights": {
            "cueDispatchMs": 0.10,
            "captureStartCompletionMs": 0.10,
            "audioStopEntryMs": 0.20,
            "visibleTextDispatchMs": 0.60,
        },
        "scoredProfile": "P0",
        "warmOnly": True,
    },
}
finite(result)
output.parent.mkdir(parents=True, exist_ok=True)
temporary = output.with_suffix(output.suffix + ".tmp")
temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
temporary.replace(output)
print(f"latency result written: {output}")
if weighted_score is not None:
    print(f"weighted p95 score: {weighted_score:.3f} ms over {len(scored)} warm samples")
PY
}

run_evaluator() {
  [[ $# -ge 1 && $# -le 3 ]] || usage
  local output_path="$1"
  local profile="${2:-P0}"
  local repeats="${3:-3}"
  [[ "$profile" =~ ^P[0-5]$ ]] || usage
  [[ "$repeats" =~ ^[1-9][0-9]*$ ]] || usage
  [[ ! -e "$output_path" ]] || {
    printf 'error: refusing to overwrite result: %s\n' "$output_path" >&2
    exit 1
  }

  verify_fixtures
  verify_evaluator_lock
  verify_model_manifests
  verify_model_payloads
  verify_model_capabilities
  refuse_dirty_tree

  local git_commit evaluator_digest fixture_digest multilingual_digest compact_digest
  git_commit="$(git -C "$repo_root" rev-parse HEAD)"
  evaluator_digest="$(sha256_file "$evaluator_lock")"
  fixture_digest="$(sha256_file "$fixture_manifest")"
  multilingual_digest="$(sha256_file "$multilingual_manifest")"
  compact_digest="$(sha256_file "$compact_manifest")"

  local run_root
  run_root="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-latency.XXXXXX")"
  local cleanup_command
  printf -v cleanup_command '/bin/rm -rf -- %q' "$run_root"
  trap "$cleanup_command" EXIT
  mkdir -p "$run_root/home" "$run_root/clang-cache" "$run_root/swift-cache"

  local partials=()
  local repeat_index partial
  for ((repeat_index = 0; repeat_index < repeats; repeat_index += 1)); do
    partial="$run_root/partial-$repeat_index.json"
    partials+=("$partial")
    sandbox-exec -p $'(version 1)\n(allow default)\n(deny network*)' \
      env \
        HOME="$run_root/home" \
        CLANG_MODULE_CACHE_PATH="$run_root/clang-cache" \
        SWIFT_MODULE_CACHE_PATH="$run_root/swift-cache" \
        VOXHEARTH_LATENCY_EVAL=1 \
        VOXHEARTH_LATENCY_REPO_ROOT="$repo_root" \
        VOXHEARTH_LATENCY_EVAL_OUTPUT="$partial" \
        VOXHEARTH_LATENCY_PROFILE="$profile" \
        VOXHEARTH_LATENCY_REPEAT_INDEX="$repeat_index" \
        VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT="$VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT" \
        VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT="$VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT" \
        VOXHEARTH_LATENCY_GIT_COMMIT="$git_commit" \
        VOXHEARTH_LATENCY_GIT_DIRTY=0 \
        VOXHEARTH_LATENCY_EVALUATOR_DIGEST="$evaluator_digest" \
        VOXHEARTH_LATENCY_FIXTURE_DIGEST="$fixture_digest" \
        VOXHEARTH_LATENCY_MULTILINGUAL_MANIFEST_DIGEST="$multilingual_digest" \
        VOXHEARTH_LATENCY_COMPACT_MANIFEST_DIGEST="$compact_digest" \
        swift test \
          --disable-sandbox \
          --package-path "$repo_root" \
          --scratch-path "$repo_root/.build/latency-evaluator" \
          --filter latencyEvaluator
    [[ -s "$partial" ]] || {
      printf 'error: evaluator did not emit partial result %s\n' "$partial" >&2
      exit 1
    }
  done
  aggregate_partials "$output_path" "$profile" "$repeats" "${partials[@]}"
}

compare_results() {
  [[ $# -ge 2 && $# -le 3 ]] || usage
  python3 - "$@" <<'PY'
import json
import math
from pathlib import Path
import sys

baseline = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
candidate = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
noise = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8")) if len(sys.argv) == 4 else None
if baseline["digests"] != candidate["digests"]:
    raise SystemExit("REJECT: evaluator, fixture, or model digest differs")
if baseline["weightedScoreMs"] is None or candidate["weightedScoreMs"] is None:
    raise SystemExit("REJECT: compare requires scored P0 results")

noise_score = 0.0
noise_components = {key: 0.0 for key in baseline["components"]}
if noise is not None:
    noise_score = abs(baseline["weightedScoreMs"] - noise["weightedScoreMs"])
    for key in noise_components:
        noise_components[key] = abs(
            baseline["components"][key]["p95"] - noise["components"][key]["p95"]
        )

improvement = baseline["weightedScoreMs"] - candidate["weightedScoreMs"]
threshold = max(noise_score, min(0.10 * baseline["weightedScoreMs"], 100.0))
component_ok = all(
    candidate["components"][key]["p95"]
    <= baseline["components"][key]["p95"] + noise_components[key]
    for key in noise_components
)
transcripts_ok = baseline["transcriptDigests"] == candidate["transcriptDigests"]
resource_limit = 1.05
cpu_ok = candidate["resources"]["cpuSeconds"] <= baseline["resources"]["cpuSeconds"] * resource_limit
memory_ok = candidate["resources"]["peakResidentBytes"] <= baseline["resources"]["peakResidentBytes"] * resource_limit
promote = improvement >= threshold and component_ok and transcripts_ok and cpu_ok and memory_ok
print(f"weighted improvement: {improvement:.3f} ms; required: {threshold:.3f} ms")
print(f"components: {'PASS' if component_ok else 'FAIL'}")
print(f"transcripts: {'PASS' if transcripts_ok else 'FAIL'}")
print(f"resources: {'PASS' if cpu_ok and memory_ok else 'FAIL'}")
print("PROMOTE" if promote else "REJECT")
raise SystemExit(0 if promote else 1)
PY
}

case "${1:-}" in
fixtures)
  [[ $# -eq 1 ]] || usage
  verify_fixtures
  verify_evaluator_lock
  ;;
verify)
  [[ $# -eq 1 ]] || usage
  verify_fixtures
  verify_evaluator_lock
  verify_model_manifests
  ;;
run)
  shift
  run_evaluator "$@"
  ;;
compare)
  shift
  compare_results "$@"
  ;;
*)
  usage
  ;;
esac
