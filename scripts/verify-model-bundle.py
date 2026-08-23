#!/usr/bin/env python3
"""Verify the exact multi-model resource layout staged into VoxHearth."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


APPROVED_MANIFESTS = (
    "parakeet-tdt-0.6b-v3-coreml.json",
    "parakeet-tdt-ctc-110m-coreml.json",
    "s1-mini-gguf.json",
)


def fail(message: str) -> None:
    raise ValueError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifests(source: Path, names: tuple[str, ...]) -> list[tuple[Path, dict]]:
    loaded: list[tuple[Path, dict]] = []
    for name in names:
        path = source / name
        if path.is_symlink() or not path.is_file():
            fail(f"approved source manifest is missing or unsafe: {name}")
        document = json.loads(path.read_text(encoding="utf-8"))
        loaded.append((path, document))
    roots = [item[1].get("bundleRoot") for item in loaded]
    if any(not isinstance(root, str) or Path(root).name != root for root in roots):
        fail("manifest has an unsafe bundleRoot")
    if len(roots) != len(set(roots)):
        fail("model bundle roots are not unique")
    return loaded


def verify_layout(
    models_root: Path,
    manifest_source: Path,
    manifest_names: tuple[str, ...] = APPROVED_MANIFESTS,
    verify_payloads: bool = True,
) -> None:
    if models_root.is_symlink() or not models_root.is_dir():
        fail("Models resource root is missing, not a directory, or a symlink")
    loaded = load_manifests(manifest_source, manifest_names)
    expected_roots = {document["bundleRoot"] for _, document in loaded}
    expected_top_level = expected_roots | {"Manifests"}
    actual_top_level = {entry.name for entry in models_root.iterdir()}
    if actual_top_level != expected_top_level:
        fail(
            "model resource roots mismatch: "
            f"expected={sorted(expected_top_level)} actual={sorted(actual_top_level)}"
        )
    for entry in models_root.iterdir():
        if entry.is_symlink() or not entry.is_dir():
            fail(f"model resource root is not a regular directory: {entry.name}")

    bundled_manifests = models_root / "Manifests"
    actual_manifest_names = {entry.name for entry in bundled_manifests.iterdir()}
    if actual_manifest_names != set(manifest_names):
        fail(
            "bundled manifest set mismatch: "
            f"expected={sorted(manifest_names)} actual={sorted(actual_manifest_names)}"
        )

    digest_owners: dict[str, str] = {}
    for source_path, document in loaded:
        bundled_path = bundled_manifests / source_path.name
        if bundled_path.is_symlink() or not bundled_path.is_file():
            fail(f"bundled manifest is missing or unsafe: {source_path.name}")
        if sha256(source_path) != sha256(bundled_path):
            fail(f"bundled manifest differs from source: {source_path.name}")
        root = document["bundleRoot"]
        for item in document.get("files", []):
            digest = item.get("sha256")
            owner = digest_owners.get(digest)
            if owner is not None and owner != root:
                fail(f"payload digest is duplicated across roots: {owner}, {root}")
            digest_owners[digest] = root
        if verify_payloads:
            subprocess.run(
                [
                    str(Path(__file__).resolve().parent / "verify-model.py"),
                    "--manifest",
                    str(source_path),
                    str(models_root / root),
                ],
                check=True,
            )


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="voxhearth-model-bundle-") as temporary:
        root = Path(temporary)
        source = root / "source"
        models = root / "Models"
        manifests = models / "Manifests"
        source.mkdir()
        manifests.mkdir(parents=True)
        names = ("a.json", "b.json")
        for name, bundle_root, digest in (
            ("a.json", "a", "a" * 64),
            ("b.json", "b", "b" * 64),
        ):
            document = {
                "bundleRoot": bundle_root,
                "files": [{"path": "payload", "sha256": digest}],
            }
            encoded = json.dumps(document, sort_keys=True) + "\n"
            (source / name).write_text(encoded, encoding="utf-8")
            (manifests / name).write_text(encoded, encoding="utf-8")
            (models / bundle_root).mkdir()
        verify_layout(models, source, names, verify_payloads=False)

        (manifests / "extra.json").write_text("{}\n", encoding="utf-8")
        try:
            verify_layout(models, source, names, verify_payloads=False)
        except ValueError:
            pass
        else:
            fail("self-test accepted an extra bundled manifest")
        (manifests / "extra.json").unlink()

        removed = manifests / "b.json"
        removed.unlink()
        try:
            verify_layout(models, source, names, verify_payloads=False)
        except ValueError:
            pass
        else:
            fail("self-test accepted a missing bundled manifest")
        removed.write_text((source / "b.json").read_text(encoding="utf-8"), encoding="utf-8")

        duplicate = json.loads((source / "b.json").read_text(encoding="utf-8"))
        duplicate["files"][0]["sha256"] = "a" * 64
        encoded = json.dumps(duplicate, sort_keys=True) + "\n"
        (source / "b.json").write_text(encoded, encoding="utf-8")
        (manifests / "b.json").write_text(encoded, encoding="utf-8")
        try:
            verify_layout(models, source, names, verify_payloads=False)
        except ValueError:
            pass
        else:
            fail("self-test accepted a cross-root duplicate payload digest")


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument("models_root", nargs="?", type=Path)
    parser.add_argument("--manifest-source", type=Path, default=repo_root / "Models")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            print("multi-model bundle verifier self-test passed")
            return 0
        if args.models_root is None:
            parser.error("models_root is required unless --self-test is used")
        verify_layout(args.models_root, args.manifest_source)
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"multi-model bundle verified: {args.models_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
