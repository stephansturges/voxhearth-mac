#!/usr/bin/env python3
"""Generate the release SPDX 2.3 JSON bill of materials."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import quote


FLUIDAUDIO_REVISION = "19600a485baa4998812e4654b70d2bab8f2c9949"
MULTILINGUAL_MODEL_REVISION = "aed02740059203c4a87495924f685de3722ae9ce"
COMPACT_MODEL_REVISION = "9bc92ead6e8f17eca92a869fd578ae76842b82ba"


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
    parser.add_argument("--artifact", action="append", default=[], type=Path)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    package_source = (repo_root / "Package.swift").read_text(encoding="utf-8")
    vendor_provenance_path = repo_root / "Vendor" / "FluidAudioLocal" / "UPSTREAM.md"
    if "FluidAudioLocal" not in package_source or not vendor_provenance_path.is_file():
        print("error: Package.swift does not use the reviewed FluidAudioLocal target", file=sys.stderr)
        return 1
    vendor_provenance = vendor_provenance_path.read_text(encoding="utf-8")
    if FLUIDAUDIO_REVISION not in vendor_provenance:
        print("error: vendored FluidAudio provenance is not at the approved revision", file=sys.stderr)
        return 1

    manifests = {
        "multilingual": repo_root / "Models" / "parakeet-tdt-0.6b-v3-coreml.json",
        "compact": repo_root / "Models" / "parakeet-tdt-ctc-110m-coreml.json",
    }
    for manifest_path in manifests.values():
        subprocess.run(
            [
                str(repo_root / "scripts" / "verify-model.py"),
                "--manifest",
                str(manifest_path),
                "--manifest-only",
            ],
            check=True,
        )
    multilingual_manifest = json.loads(manifests["multilingual"].read_text(encoding="utf-8"))
    compact_manifest = json.loads(manifests["compact"].read_text(encoding="utf-8"))
    if multilingual_manifest["revision"] != MULTILINGUAL_MODEL_REVISION:
        print("error: multilingual model revision changed unexpectedly", file=sys.stderr)
        return 1
    if compact_manifest["revision"] != COMPACT_MODEL_REVISION:
        print("error: compact model revision changed unexpectedly", file=sys.stderr)
        return 1

    repository = os.environ.get("GITHUB_REPOSITORY", "VoxHearth/voxhearth-mac")
    source_url = f"https://github.com/{repository}"
    namespace_version = quote(args.version, safe="")
    document = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"VoxHearth-{args.version}",
        "documentNamespace": (
            f"https://github.com/{repository}/spdx/VoxHearth-"
            f"{namespace_version}-{args.source_revision}"
        ),
        "creationInfo": {
            "created": created_time(),
            "creators": ["Tool: VoxHearth scripts/generate-sbom.py"],
            "licenseListVersion": "3.26",
        },
        "packages": [
            {
                "name": "VoxHearth",
                "SPDXID": "SPDXRef-Package-VoxHearth",
                "versionInfo": args.version,
                "downloadLocation": f"{source_url}/tree/{args.source_revision}",
                "filesAnalyzed": False,
                "licenseConcluded": "GPL-3.0-or-later",
                "licenseDeclared": "GPL-3.0-or-later",
                "copyrightText": "Copyright (c) 2026 VoxHearth contributors and TypeWhisper contributors",
                "externalRefs": [
                    {
                        "referenceCategory": "PACKAGE-MANAGER",
                        "referenceType": "purl",
                        "referenceLocator": f"pkg:github/{repository}@{args.source_revision}",
                    }
                ],
            },
            {
                "name": "FluidAudioLocal",
                "SPDXID": "SPDXRef-Package-FluidAudio",
                "versionInfo": "0.15.5",
                "downloadLocation": (
                    "git+https://github.com/FluidInference/FluidAudio.git@"
                    + FLUIDAUDIO_REVISION
                ),
                "filesAnalyzed": False,
                "licenseConcluded": "Apache-2.0",
                "licenseDeclared": "Apache-2.0",
                "copyrightText": "NOASSERTION",
                "comment": (
                    "VoxHearth-vendored, network-free subset adapted from FluidAudio 0.15.5; "
                    "see Vendor/FluidAudioLocal/UPSTREAM.md for changed-file provenance."
                ),
                "externalRefs": [
                    {
                        "referenceCategory": "PACKAGE-MANAGER",
                        "referenceType": "purl",
                        "referenceLocator": (
                            "pkg:github/FluidInference/FluidAudio@"
                            + FLUIDAUDIO_REVISION
                        ),
                    }
                ],
            },
            {
                "name": "Parakeet-TDT-0.6B-v3 Core ML",
                "SPDXID": "SPDXRef-Package-ParakeetModel",
                "versionInfo": MULTILINGUAL_MODEL_REVISION,
                "downloadLocation": (
                    "https://huggingface.co/FluidInference/"
                    "parakeet-tdt-0.6b-v3-coreml/tree/" + MULTILINGUAL_MODEL_REVISION
                ),
                "filesAnalyzed": False,
                "licenseConcluded": "CC-BY-4.0",
                "licenseDeclared": "CC-BY-4.0",
                "copyrightText": "Copyright NVIDIA Corporation; Core ML conversion by FluidInference",
                "externalRefs": [
                    {
                        "referenceCategory": "PACKAGE-MANAGER",
                        "referenceType": "purl",
                        "referenceLocator": (
                            "pkg:huggingface/FluidInference/"
                            "parakeet-tdt-0.6b-v3-coreml@" + MULTILINGUAL_MODEL_REVISION
                        ),
                    }
                ],
            },
            {
                "name": "Parakeet-TDT-CTC-110M Core ML",
                "SPDXID": "SPDXRef-Package-ParakeetCompactModel",
                "versionInfo": COMPACT_MODEL_REVISION,
                "downloadLocation": (
                    "https://huggingface.co/FluidInference/"
                    "parakeet-tdt-ctc-110m-coreml/tree/" + COMPACT_MODEL_REVISION
                ),
                "filesAnalyzed": False,
                "licenseConcluded": "CC-BY-4.0",
                "licenseDeclared": "CC-BY-4.0",
                "copyrightText": "Copyright NVIDIA Corporation; Core ML conversion by FluidInference",
                "externalRefs": [
                    {
                        "referenceCategory": "PACKAGE-MANAGER",
                        "referenceType": "purl",
                        "referenceLocator": (
                            "pkg:huggingface/FluidInference/"
                            "parakeet-tdt-ctc-110m-coreml@" + COMPACT_MODEL_REVISION
                        ),
                    }
                ],
            },
        ],
        "relationships": [
            {
                "spdxElementId": "SPDXRef-DOCUMENT",
                "relationshipType": "DESCRIBES",
                "relatedSpdxElement": "SPDXRef-Package-VoxHearth",
            },
            {
                "spdxElementId": "SPDXRef-Package-VoxHearth",
                "relationshipType": "DEPENDS_ON",
                "relatedSpdxElement": "SPDXRef-Package-FluidAudio",
            },
            {
                "spdxElementId": "SPDXRef-Package-VoxHearth",
                "relationshipType": "CONTAINS",
                "relatedSpdxElement": "SPDXRef-Package-ParakeetModel",
            },
            {
                "spdxElementId": "SPDXRef-Package-VoxHearth",
                "relationshipType": "CONTAINS",
                "relatedSpdxElement": "SPDXRef-Package-ParakeetCompactModel",
            },
        ],
    }

    files = []
    for index, artifact in enumerate(args.artifact, start=1):
        if not artifact.is_file():
            print(f"error: SBOM artifact not found: {artifact}", file=sys.stderr)
            return 1
        file_id = f"SPDXRef-File-ReleaseArtifact-{index}"
        files.append(
            {
                "fileName": artifact.name,
                "SPDXID": file_id,
                "checksums": [{"algorithm": "SHA256", "checksumValue": sha256(artifact)}],
                "licenseConcluded": "NOASSERTION",
                "copyrightText": "NOASSERTION",
            }
        )
        document["relationships"].append(
            {
                "spdxElementId": "SPDXRef-Package-VoxHearth",
                "relationshipType": "GENERATES",
                "relatedSpdxElement": file_id,
            }
        )
    if files:
        document["files"] = files

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"SPDX SBOM written: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
