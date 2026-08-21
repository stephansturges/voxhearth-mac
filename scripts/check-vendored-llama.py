#!/usr/bin/env python3
"""Fail-closed provenance and security checks for the vendored LlamaLocal target."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


UPSTREAM_COMMIT = "9ee9fc04c136ef2ae729bfc60d18961b23c13ddf"
UPSTREAM_TAG = "b10524"
LICENSE_BYTES = 1_078
LICENSE_SHA256 = "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d"
METADATA = {"FILES.json", "PATCHES.md", "UPSTREAM.md"}

PATCHED = {
    "ggml/src/ggml-backend-meta.cpp",
    "ggml/src/ggml-backend-reg.cpp",
    "ggml/src/ggml-backend.cpp",
    "ggml/src/ggml-cpu/ggml-cpu.c",
    "ggml/src/ggml-cpu/ggml-cpu.cpp",
    "ggml/src/ggml-cpu/arch/arm/quants.c",
    "ggml/src/ggml-cpu/unary-ops.cpp",
    "ggml/src/ggml-cpu/vec.h",
    "ggml/src/ggml-metal/ggml-metal-context.m",
    "ggml/src/ggml-metal/ggml-metal-device.m",
    "ggml/src/ggml-metal/ggml-metal-ops.cpp",
    "ggml/src/ggml-metal/ggml-metal.cpp",
    "ggml/src/ggml.c",
    "ggml/src/ggml.cpp",
    "ggml/src/gguf.cpp",
    "src/llama-batch.cpp",
    "src/llama-context.cpp",
    "src/llama-graph.cpp",
    "src/llama-graph.h",
    "src/llama-grammar.cpp",
    "src/llama-kv-cache-dsv4.cpp",
    "src/llama-kv-cache-iswa.cpp",
    "src/llama-kv-cache.cpp",
    "src/llama-model-loader.cpp",
    "src/llama-model.cpp",
    "src/llama-mmap.cpp",
    "src/llama.cpp",
}
LOCAL = {
    "include/LlamaLocal.h",
    "include/ggml.h",
    "include/ggml-alloc.h",
    "include/ggml-backend.h",
    "include/ggml-blas.h",
    "include/ggml-cpu.h",
    "include/ggml-metal.h",
    "include/ggml-opt.h",
    "include/gguf.h",
}

FORBIDDEN_SOURCE = {
    "process environment read": re.compile(rb"(?:std::)?getenv\s*\("),
    "process environment write": re.compile(rb"(?:setenv|_putenv)\s*\("),
    "dynamic loader": re.compile(rb"(?:dlopen|dlsym)\s*\("),
    "socket header": re.compile(rb"[<\"](?:sys/)?socket\.h[>\"]"),
    "DNS lookup": re.compile(rb"\bgetaddrinfo\s*\("),
    "socket call": re.compile(rb"\bsocket\s*\("),
    "connect call": re.compile(rb"\bconnect\s*\("),
    "runtime Metal compilation": re.compile(rb"newLibraryWithSource"),
    "environment-selected Metal resource": re.compile(rb"GGML_METAL_PATH_RESOURCES"),
    "default Metal library fallback": re.compile(rb"default\.metallib"),
    "curl integration": re.compile(rb"(?:\blibcurl\b|\bCURLOPT_|\bcurl_[a-zA-Z0-9_]+\s*\()"),
    "subprocess launch": re.compile(rb"(?:\bpopen\s*\(|\bsystem\s*\(|\bposix_spawn\s*\()"),
    "filesystem write": re.compile(rb"(?:\bfwrite\s*\(|\bfputc\s*\(|\bWriteFile\s*\(|\bstd::ofstream\b)"),
}


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def runtime_files(vendor: Path) -> list[Path]:
    return sorted(
        path for path in vendor.rglob("*")
        if path.is_file() and path.relative_to(vendor).as_posix() not in METADATA
    )


def origin(relative: str) -> str:
    if relative in PATCHED:
        return "patched"
    if relative in LOCAL:
        return "local"
    return "upstream"


def package_sources(package: Path) -> list[str]:
    text = package.read_text(encoding="utf-8")
    match = re.search(
        r"let llamaLocalSources = \[(.*?)\n\]",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        raise ValueError("Package.swift has no llamaLocalSources array")
    return re.findall(r'^\s*"([^"]+)",\s*$', match.group(1), flags=re.MULTILINE)


def manifest_payload(root: Path) -> dict[str, object]:
    vendor = root / "Vendor/LlamaLocal"
    files = []
    for path in runtime_files(vendor):
        relative = path.relative_to(vendor).as_posix()
        files.append({
            "path": relative,
            "bytes": path.stat().st_size,
            "sha256": digest(path),
            "origin": origin(relative),
        })
    license_path = root / "LICENSES/llama.cpp-MIT.txt"
    return {
        "schemaVersion": 1,
        "upstream": {
            "repository": "https://github.com/ggml-org/llama.cpp",
            "tag": UPSTREAM_TAG,
            "commit": UPSTREAM_COMMIT,
        },
        "compiledSources": package_sources(root / "Package.swift"),
        "files": files,
        "license": {
            "path": "LICENSES/llama.cpp-MIT.txt",
            "bytes": license_path.stat().st_size,
            "sha256": digest(license_path),
        },
    }


def scan_security(vendor: Path) -> list[str]:
    failures: list[str] = []
    for path in runtime_files(vendor):
        relative = path.relative_to(vendor).as_posix()
        data = path.read_bytes()
        # Pinned patches retain a few ABI declarations while compile-time
        # excluding their upstream implementation. Scan the compiled branch.
        data = re.sub(
            rb"(?ms)^#if\s+0\b.*?^#else\s*$",
            b"",
            data,
        )
        data = re.sub(
            rb"(?ms)^#if\s+0\b.*?^#endif\s*$",
            b"",
            data,
        )
        data = re.sub(rb"(?s)/\*.*?\*/", b"", data)
        data = re.sub(rb"(?m)//[^\n]*$", b"", data)
        for label, pattern in FORBIDDEN_SOURCE.items():
            if pattern.search(data):
                failures.append(f"{relative}: forbidden {label}")

    loader = vendor / "ggml/src/ggml-metal/ggml-metal-device.m"
    loader_text = loader.read_text(encoding="utf-8")
    required = [
        '@"Metal/ggml-llama.metallib"',
        "NSFileTypeRegular",
        "newLibraryWithURL",
    ]
    for marker in required:
        if marker not in loader_text:
            failures.append(f"sealed Metal loader marker missing: {marker}")
    return failures


def verify(root: Path, *, quiet: bool = False) -> list[str]:
    manifest_path = root / "Vendor/LlamaLocal/FILES.json"
    failures: list[str] = []
    try:
        actual = manifest_payload(root)
        expected = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        return [f"manifest unavailable or invalid: {error}"]

    if expected != actual:
        failures.append("FILES.json does not match the exact runtime bytes/source list")
    if actual["upstream"]["commit"] != UPSTREAM_COMMIT:
        failures.append("unexpected upstream commit")

    license_info = actual["license"]
    if license_info["bytes"] != LICENSE_BYTES or license_info["sha256"] != LICENSE_SHA256:
        failures.append("llama.cpp MIT license is not the pinned upstream file")

    files = actual["files"]
    paths = {entry["path"] for entry in files}
    if not PATCHED.issubset(paths):
        failures.append("documented patched file is absent")
    if not LOCAL.issubset(paths):
        failures.append("documented local file is absent")
    if any(entry["origin"] == "upstream" and entry["path"] in PATCHED | LOCAL for entry in files):
        failures.append("manifest origin classification is inconsistent")

    compiled = actual["compiledSources"]
    if len(compiled) != len(set(compiled)):
        failures.append("llamaLocalSources contains a duplicate")
    for relative in compiled:
        if relative not in paths:
            failures.append(f"compiled source is not in manifest: {relative}")

    failures.extend(scan_security(root / "Vendor/LlamaLocal"))
    if not quiet and not failures:
        print(
            "vendored llama check passed: "
            f"{len(files)} files, {len(compiled)} compiled sources, "
            f"commit {UPSTREAM_COMMIT}"
        )
    return failures


def verify_upstream(root: Path, upstream: Path) -> list[str]:
    failures: list[str] = []
    try:
        commit = subprocess.run(
            ["git", "-C", str(upstream), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        return [f"unable to resolve upstream checkout: {error}"]
    if commit != UPSTREAM_COMMIT:
        failures.append(f"upstream checkout is {commit}, expected {UPSTREAM_COMMIT}")

    manifest = json.loads((root / "Vendor/LlamaLocal/FILES.json").read_text(encoding="utf-8"))
    vendor = root / "Vendor/LlamaLocal"
    for entry in manifest["files"]:
        relative = entry["path"]
        vendored = vendor / relative
        source = upstream / relative
        if entry["origin"] == "upstream":
            if not source.is_file() or digest(vendored) != digest(source):
                failures.append(f"upstream-origin byte mismatch: {relative}")
        elif entry["origin"] == "patched":
            if not source.is_file():
                failures.append(f"patched file absent upstream: {relative}")
            elif digest(vendored) == digest(source):
                failures.append(f"patched file unexpectedly matches upstream: {relative}")
        elif entry["origin"] == "local" and source.exists():
            failures.append(f"local file unexpectedly exists upstream: {relative}")

    upstream_license = upstream / "LICENSE"
    local_license = root / "LICENSES/llama.cpp-MIT.txt"
    if not upstream_license.is_file() or digest(upstream_license) != digest(local_license):
        failures.append("vendored MIT license differs from pinned upstream LICENSE")
    return failures


def self_test(root: Path) -> None:
    baseline = verify(root, quiet=True)
    if baseline:
        raise SystemExit("error: self-test requires a valid baseline: " + "; ".join(baseline))

    fixture = root / "Vendor/LlamaLocal/include/LlamaLocal.h"
    original = fixture.read_bytes()
    mutations = {
        "getenv": b"\nvoid * forbidden_environment(void) { return getenv(\"X\"); }\n",
        "socket": b"\n#include <sys/socket.h>\n",
    }
    try:
        for label, mutation in mutations.items():
            fixture.write_bytes(original + mutation)
            failures = verify(root, quiet=True)
            if not any("forbidden" in failure for failure in failures):
                raise SystemExit(f"error: {label} mutation was not rejected")
            fixture.write_bytes(original)
    finally:
        fixture.write_bytes(original)
    if verify(root, quiet=True):
        raise SystemExit("error: self-test did not restore the baseline")
    print("vendored llama mutation self-test passed: getenv and socket rejected")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-manifest", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--upstream", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    manifest_path = root / "Vendor/LlamaLocal/FILES.json"

    if args.write_manifest:
        payload = manifest_payload(root)
        manifest_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {manifest_path}: {len(payload['files'])} files")

    failures = verify(root)
    if args.upstream is not None:
        failures.extend(verify_upstream(root, args.upstream.resolve()))
    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1
    if args.self_test:
        self_test(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
