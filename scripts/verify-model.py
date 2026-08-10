#!/usr/bin/env python3
"""Validate the locked model manifest or a complete on-disk model payload."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys


REQUIRED_REVISION = "aed02740059203c4a87495924f685de3722ae9ce"
REQUIRED_TOP_LEVEL = {
    "Preprocessor.mlmodelc",
    "Encoder.mlmodelc",
    "Decoder.mlmodelc",
    "JointDecisionv3.mlmodelc",
    "parakeet_vocab.json",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise ValueError(message)


def load_manifest(path: Path) -> dict:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read model manifest {path}: {error}")

    if manifest.get("schemaVersion") != 1:
        fail("unsupported model manifest schema")
    if manifest.get("revision") != REQUIRED_REVISION:
        fail("model revision is not the approved immutable revision")
    if set(manifest.get("allowedTopLevel", [])) != REQUIRED_TOP_LEVEL:
        fail("allowedTopLevel does not match the approved five payloads")
    if manifest.get("bundleRoot") != "parakeet-tdt-0.6b-v3-coreml":
        fail("unexpected model bundleRoot")

    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        fail("manifest files must be a non-empty list")

    seen: set[str] = set()
    total_size = 0
    discovered_top_level: set[str] = set()
    for entry in files:
        if not isinstance(entry, dict):
            fail("every manifest file entry must be an object")
        relative = entry.get("path")
        size = entry.get("size")
        digest = entry.get("sha256")
        if not isinstance(relative, str):
            fail("manifest path must be a string")
        pure_path = PurePosixPath(relative)
        if pure_path.is_absolute() or ".." in pure_path.parts or str(pure_path) != relative:
            fail(f"unsafe or non-canonical manifest path: {relative}")
        if relative in seen:
            fail(f"duplicate manifest path: {relative}")
        seen.add(relative)
        discovered_top_level.add(pure_path.parts[0])
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            fail(f"invalid size for {relative}")
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            fail(f"invalid SHA-256 for {relative}")
        total_size += size

    if discovered_top_level != REQUIRED_TOP_LEVEL:
        fail("manifest file paths do not cover exactly the approved payloads")
    if total_size != manifest.get("totalSize"):
        fail("manifest totalSize does not equal the sum of file sizes")
    return manifest


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_payload(root: Path, manifest: dict) -> None:
    if not root.is_dir() or root.is_symlink():
        fail(f"model root is missing, not a directory, or a symlink: {root}")

    expected = {entry["path"]: entry for entry in manifest["files"]}
    actual_files: set[str] = set()
    expected_dirs = {"."}
    for relative in expected:
        parent = PurePosixPath(relative).parent
        while str(parent) != ".":
            expected_dirs.add(str(parent))
            parent = parent.parent

    actual_dirs = {"."}
    for current, directories, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        relative_current = current_path.relative_to(root)
        for directory in directories:
            path = current_path / directory
            if path.is_symlink():
                fail(f"symlink is forbidden in model payload: {path.relative_to(root)}")
            actual_dirs.add((relative_current / directory).as_posix())
        for filename in files:
            path = current_path / filename
            relative = (relative_current / filename).as_posix()
            if path.is_symlink() or not path.is_file():
                fail(f"non-regular file is forbidden in model payload: {relative}")
            actual_files.add(relative)

    missing = sorted(set(expected) - actual_files)
    extra = sorted(actual_files - set(expected))
    extra_dirs = sorted(actual_dirs - expected_dirs)
    if missing:
        fail("missing model files: " + ", ".join(missing))
    if extra:
        fail("unexpected model files: " + ", ".join(extra))
    if extra_dirs:
        fail("unexpected model directories: " + ", ".join(extra_dirs))

    for relative, entry in sorted(expected.items()):
        path = root / relative
        actual_size = path.stat().st_size
        if actual_size != entry["size"]:
            fail(f"size mismatch for {relative}: expected {entry['size']}, got {actual_size}")
        actual_digest = digest_file(path)
        if actual_digest != entry["sha256"]:
            fail(
                f"SHA-256 mismatch for {relative}: expected {entry['sha256']}, "
                f"got {actual_digest}"
            )


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument("model_root", nargs="?", type=Path)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=repo_root / "Models" / "parakeet-tdt-0.6b-v3-coreml.json",
    )
    parser.add_argument("--manifest-only", action="store_true")
    args = parser.parse_args()

    try:
        manifest = load_manifest(args.manifest)
        if args.manifest_only:
            print(
                f"model manifest valid: {len(manifest['files'])} files, "
                f"{manifest['totalSize']} bytes"
            )
            return 0
        if args.model_root is None:
            parser.error("model_root is required unless --manifest-only is used")
        verify_payload(args.model_root.resolve(), manifest)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"model payload verified: {args.model_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
