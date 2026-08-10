#!/usr/bin/env python3
"""Create human-auditable release metadata alongside GitHub's signed attestation."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def created_time() -> str:
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    instant = datetime.fromtimestamp(int(epoch), timezone.utc) if epoch else datetime.now(timezone.utc)
    return instant.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--source-tag", required=True)
    parser.add_argument("--workflow", default=".github/workflows/release.yml")
    parser.add_argument("--signature", default="Developer ID Application")
    parser.add_argument(
        "--notarization",
        default="Apple notary service with stapled ticket",
    )
    parser.add_argument("--release-channel", default="official")
    parser.add_argument("--artifact", action="append", required=True, type=Path)
    args = parser.parse_args()

    if len(args.source_revision) != 40 or any(c not in "0123456789abcdef" for c in args.source_revision):
        print("error: source revision must be a full lowercase Git object ID", file=sys.stderr)
        return 1

    repo_root = Path(__file__).resolve().parent.parent
    model_manifest_path = repo_root / "Models" / "parakeet-tdt-0.6b-v3-coreml.json"
    model_manifest = json.loads(model_manifest_path.read_text(encoding="utf-8"))
    subjects = []
    for artifact in args.artifact:
        if not artifact.is_file():
            print(f"error: release artifact not found: {artifact}", file=sys.stderr)
            return 1
        subjects.append({"name": artifact.name, "digest": {"sha256": sha256(artifact)}})

    repository = os.environ.get("GITHUB_REPOSITORY", "VoxHearth/voxhearth-mac")
    metadata = {
        "schemaVersion": 1,
        "subject": subjects,
        "build": {
            "repository": f"https://github.com/{repository}",
            "sourceRevision": args.source_revision,
            "sourceTag": args.source_tag,
            "version": args.version,
            "builder": "GitHub Actions",
            "workflow": args.workflow,
            "runnerImage": "macos-26",
            "xcodeVersion": "26.2",
            "createdAt": created_time(),
        },
        "materials": [
            {
                "name": "VoxHearth source",
                "uri": f"git+https://github.com/{repository}.git@{args.source_revision}",
                "digest": {"sha1": args.source_revision},
            },
            {
                "name": "FluidAudioLocal",
                "uri": (
                    "git+https://github.com/FluidInference/FluidAudio.git@"
                    "19600a485baa4998812e4654b70d2bab8f2c9949"
                ),
                "digest": {"sha1": "19600a485baa4998812e4654b70d2bab8f2c9949"},
                "localPath": "Vendor/FluidAudioLocal",
                "adaptedSubset": True,
            },
            {
                "name": "Parakeet-TDT-0.6B-v3 Core ML",
                "uri": (
                    "https://huggingface.co/FluidInference/"
                    "parakeet-tdt-0.6b-v3-coreml/tree/"
                    + model_manifest["revision"]
                ),
                "digest": {"sha256": sha256(model_manifest_path)},
                "manifest": "Models/parakeet-tdt-0.6b-v3-coreml.json",
            },
        ],
        "releaseContract": {
            "runtimeNetwork": "forbidden",
            "modelDelivery": "bundled-and-hash-locked",
            "automaticUpdates": "absent",
            "telemetry": "absent",
            "releaseChannel": args.release_channel,
            "signature": args.signature,
            "notarization": args.notarization,
        },
        "attestation": {
            "provider": "GitHub actions/attest",
            "modes": ["SLSA build provenance", "SPDX SBOM"],
            "verification": "gh attestation verify <artifact> --repo <owner/repository>",
        },
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"release metadata written: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
