#!/usr/bin/env python3
"""Verify the sealed, reviewed llama.cpp Metal library resource."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import tempfile


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(root: Path, reviewed_manifest: Path) -> None:
    if root.is_symlink() or not root.is_dir():
        raise ValueError("Metal resource root is missing, not a directory, or a symlink")
    actual = {entry.name for entry in root.iterdir()}
    if actual != {"ggml-llama.metallib", "manifest.json"}:
        raise ValueError(f"Metal resource inventory mismatch: {sorted(actual)}")
    artifact = root / "ggml-llama.metallib"
    bundled_manifest = root / "manifest.json"
    for path in (artifact, bundled_manifest, reviewed_manifest):
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Metal resource is missing or unsafe: {path}")
    if sha256(bundled_manifest) != sha256(reviewed_manifest):
        raise ValueError("bundled metallib manifest differs from reviewed source")
    document = json.loads(reviewed_manifest.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != 1:
        raise ValueError("unsupported metallib manifest schema")
    if document.get("artifact") != "Metal/ggml-llama.metallib":
        raise ValueError("unexpected metallib artifact path")
    if artifact.stat().st_size != document.get("artifactBytes"):
        raise ValueError("metallib size mismatch")
    if sha256(artifact) != document.get("artifactSHA256"):
        raise ValueError("metallib digest mismatch")


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="voxhearth-metallib-") as temporary:
        base = Path(temporary)
        reviewed = base / "reviewed.json"
        root = base / "Metal"
        root.mkdir()
        artifact = root / "ggml-llama.metallib"
        artifact.write_bytes(b"sealed")
        document = {
            "schemaVersion": 1,
            "artifact": "Metal/ggml-llama.metallib",
            "artifactBytes": artifact.stat().st_size,
            "artifactSHA256": sha256(artifact),
        }
        encoded = json.dumps(document, sort_keys=True) + "\n"
        reviewed.write_text(encoded, encoding="utf-8")
        (root / "manifest.json").write_text(encoded, encoding="utf-8")
        verify(root, reviewed)
        artifact.write_bytes(b"changed")
        try:
            verify(root, reviewed)
        except ValueError:
            pass
        else:
            raise ValueError("self-test accepted a changed metallib")
        artifact.write_bytes(b"sealed")
        (root / "extra").write_text("unexpected", encoding="utf-8")
        try:
            verify(root, reviewed)
        except ValueError:
            pass
        else:
            raise ValueError("self-test accepted an extra Metal resource")


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument("metal_root", nargs="?", type=Path)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=repo_root / "Vendor" / "LlamaLocal" / "METALLIB.json",
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            print("metallib verifier self-test passed")
            return 0
        if args.metal_root is None:
            parser.error("metal_root is required unless --self-test is used")
        verify(args.metal_root, args.manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"metallib verified: {args.metal_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
