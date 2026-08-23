#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
lock_file="$repo_root/Research/lifecycle-latency/evaluator.lock.json"
multilingual_manifest="$repo_root/Models/parakeet-tdt-0.6b-v3-coreml.json"
compact_manifest="$repo_root/Models/parakeet-tdt-ctc-110m-coreml.json"
soak_run_root=""

cleanup() {
  if [[ -n "$soak_run_root" && -d "$soak_run_root" ]]; then
    /bin/rm -rf -- "$soak_run_root"
  fi
}
trap cleanup EXIT

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/soak-eval.sh lock
  scripts/soak-eval.sh verify
  scripts/soak-eval.sh quick OUTPUT.json
  scripts/soak-eval.sh full OUTPUT.json

Optional already-local model roots:
  VOXHEARTH_SOAK_MULTILINGUAL_MODEL_ROOT
  VOXHEARTH_SOAK_COMPACT_MODEL_ROOT
EOF
  exit 2
}

write_lock() {
  python3 - "$repo_root" "$lock_file" <<'PY'
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1])
lock_path = Path(sys.argv[2])
lock = json.loads(lock_path.read_text(encoding="utf-8"))
roots = lock.get("roots")
if lock.get("schemaVersion") != 1 or lock.get("hashAlgorithm") != "sha256-tree-v1":
    raise SystemExit("error: unsupported lifecycle evaluator lock")
if not isinstance(roots, list) or not roots:
    raise SystemExit("error: lifecycle evaluator lock is incomplete")
files = set()
for relative in roots:
    pure = PurePosixPath(relative) if isinstance(relative, str) else None
    if pure is None or pure.is_absolute() or ".." in pure.parts or str(pure) != relative:
        raise SystemExit(f"error: unsafe lifecycle lock root: {relative!r}")
    path = root / relative
    if path.is_symlink() or not path.exists():
        raise SystemExit(f"error: missing lifecycle lock root: {relative}")
    if path.is_file():
        files.add(path)
    else:
        for child in path.rglob("*"):
            if child.is_symlink():
                raise SystemExit(f"error: symlink in lifecycle lock root: {child}")
            if child.is_file():
                files.add(child)
digest = hashlib.sha256()
for path in sorted(files):
    relative = path.relative_to(root).as_posix()
    digest.update(relative.encode("utf-8") + b"\0")
    digest.update(hashlib.sha256(path.read_bytes()).digest())
updated = {
    "schemaVersion": 1,
    "hashAlgorithm": "sha256-tree-v1",
    "fileCount": len(files),
    "treeSha256": digest.hexdigest(),
    "roots": roots,
}
temporary = lock_path.with_suffix(".json.tmp")
temporary.write_text(json.dumps(updated, indent=2) + "\n", encoding="utf-8")
os.replace(temporary, lock_path)
print(f"lifecycle evaluator lock updated: {len(files)} files")
PY
}

verify_lock() {
  python3 - "$repo_root" "$lock_file" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1])
lock_path = Path(sys.argv[2])
lock = json.loads(lock_path.read_text(encoding="utf-8"))
if lock.get("schemaVersion") != 1 or lock.get("hashAlgorithm") != "sha256-tree-v1":
    raise SystemExit("error: unsupported lifecycle evaluator lock")
roots = lock.get("roots")
if not isinstance(roots, list) or not roots:
    raise SystemExit("error: lifecycle evaluator lock is incomplete")
files = set()
for relative in roots:
    pure = PurePosixPath(relative) if isinstance(relative, str) else None
    if pure is None or pure.is_absolute() or ".." in pure.parts or str(pure) != relative:
        raise SystemExit(f"error: unsafe lifecycle lock root: {relative!r}")
    path = root / relative
    if path.is_symlink() or not path.exists():
        raise SystemExit(f"error: missing lifecycle lock root: {relative}")
    if path.is_file():
        files.add(path)
    else:
        for child in path.rglob("*"):
            if child.is_symlink():
                raise SystemExit(f"error: symlink in lifecycle lock root: {child}")
            if child.is_file():
                files.add(child)
digest = hashlib.sha256()
for path in sorted(files):
    relative = path.relative_to(root).as_posix()
    digest.update(relative.encode("utf-8") + b"\0")
    digest.update(hashlib.sha256(path.read_bytes()).digest())
if len(files) != lock.get("fileCount") or digest.hexdigest() != lock.get("treeSha256"):
    raise SystemExit("error: lifecycle evaluator tree lock mismatch")
print(f"lifecycle evaluator lock verified: {len(files)} files")
PY
}

verify_result() {
  python3 - "$1" <<'PY'
import json
import math
from pathlib import Path
import sys

path = Path(sys.argv[1])
result = json.loads(path.read_text(encoding="utf-8"))
if result.get("schemaVersion") != 1 or result.get("soakSchema") != "voxhearth.soak.v1":
    raise SystemExit("error: invalid lifecycle soak schema")
environment = result.get("environment", {})
if environment.get("buildConfiguration") != "release":
    raise SystemExit("error: lifecycle soak was not compiled in release configuration")
if environment.get("testabilityEnabled") != "true":
    raise SystemExit("error: lifecycle soak did not record its testability mode")
windows = result.get("windows")
if not isinstance(windows, list) or not windows:
    raise SystemExit("error: lifecycle soak has no windows")
if [item.get("index") for item in windows] != list(range(len(windows))):
    raise SystemExit("error: lifecycle soak windows are not monotonic")
for window in windows:
    for cycle in window.get("cycles", []):
        for key in (
            "pressToRecordingMs",
            "releaseToInsertDispatchMs",
            "pressToVisibleTextDispatchMs",
        ):
            value = cycle.get(key)
            if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                raise SystemExit(f"error: invalid lifecycle soak value: {key}")
if result.get("verdict", {}).get("degraded"):
    raise SystemExit("error: lifecycle soak reported sustained degradation")
print(f"lifecycle soak verified: {len(windows)} windows")
PY
}

run_soak() {
  [[ $# -eq 2 ]] || usage
  local profile="$1"
  local output_path="$2"
  local windows cycles
  case "$profile" in
    quick) windows=2; cycles=5 ;;
    full) windows=6; cycles=25 ;;
    *) usage ;;
  esac

  printf '%s\n' \
    'warning: lifecycle soak performs sustained real-model inference.' \
    'Do not use VoxHearth concurrently; Core ML contention can delay the live app.' >&2

  [[ ! -e "$output_path" ]] || {
    printf 'error: refusing to overwrite soak output: %s\n' "$output_path" >&2
    exit 1
  }
  output_path="$(cd "$(dirname "$output_path")" && pwd -P)/$(basename "$output_path")"

  local multilingual_root compact_root
  multilingual_root="${VOXHEARTH_SOAK_MULTILINGUAL_MODEL_ROOT:-$repo_root/.build/models/parakeet-tdt-0.6b-v3-coreml}"
  compact_root="${VOXHEARTH_SOAK_COMPACT_MODEL_ROOT:-$repo_root/.build/models/parakeet-tdt-ctc-110m-coreml}"

  verify_lock
  "$repo_root/scripts/verify-model.py" \
    --manifest "$multilingual_manifest" \
    "$multilingual_root"
  "$repo_root/scripts/verify-model.py" \
    --manifest "$compact_manifest" \
    "$compact_root"

  soak_run_root="$(mktemp -d "${TMPDIR:-/private/tmp}/voxhearth-soak.XXXXXX")"
  /bin/mkdir -p \
    "$soak_run_root/home" \
    "$soak_run_root/clang-cache" \
    "$soak_run_root/swift-cache"

  local git_commit git_dirty
  git_commit="$(git -C "$repo_root" rev-parse HEAD)"
  if [[ -n "$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)" ]]; then
    git_dirty=1
  else
    git_dirty=0
  fi

  sandbox-exec -p $'(version 1)\n(allow default)\n(deny network*)' \
    env \
      HOME="$soak_run_root/home" \
      CLANG_MODULE_CACHE_PATH="$soak_run_root/clang-cache" \
      SWIFT_MODULE_CACHE_PATH="$soak_run_root/swift-cache" \
      VOXHEARTH_SOAK_EVAL=1 \
      VOXHEARTH_SOAK_REPO_ROOT="$repo_root" \
      VOXHEARTH_SOAK_OUTPUT="$output_path" \
      VOXHEARTH_SOAK_MULTILINGUAL_MODEL_ROOT="$multilingual_root" \
      VOXHEARTH_SOAK_COMPACT_MODEL_ROOT="$compact_root" \
      VOXHEARTH_SOAK_WINDOWS="$windows" \
      VOXHEARTH_SOAK_CYCLES_PER_WINDOW="$cycles" \
      VOXHEARTH_SOAK_GIT_COMMIT="$git_commit" \
      VOXHEARTH_SOAK_GIT_DIRTY="$git_dirty" \
      swift test \
        --configuration release \
        -Xswiftc -enable-testing \
        --disable-sandbox \
        --package-path "$repo_root" \
        --scratch-path "$repo_root/.build/lifecycle-soak-evaluator" \
        --filter lifecycleSoakEvaluator

  verify_result "$output_path"
  printf 'lifecycle soak complete: %s (%s windows x %s cycles)\n' \
    "$output_path" "$windows" "$cycles"
}

case "${1:-}" in
  lock)
    [[ $# -eq 1 ]] || usage
    write_lock
    ;;
  verify)
    [[ $# -eq 1 ]] || usage
    verify_lock
    ;;
  quick|full)
    run_soak "$@"
    ;;
  *) usage ;;
esac
