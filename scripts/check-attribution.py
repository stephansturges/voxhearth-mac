#!/usr/bin/env python3
"""Fail-closed attribution, license, SBOM, provenance, and app checks."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import urllib.request


S1_MODEL_CARD_REVISION = "65f84bcda1d13df582c4a8443c1c5aa53c0c66db"
S1_GGUF_REVISION = "8eab4779866f477ae6e7f237ca45fc2c65153f50"
S1_LICENSE_BYTES = 11878
S1_LICENSE_SHA256 = "d956d2d305a0639211c9cbde71501accb0e1474cc9ddf79a47820a522aff6f98"
S1_LICENSE_EXPRESSION = "Apache-2.0 AND LicenseRef-S1-mini-Naming-Clause"
S1_NAME = "S1-mini by Superwhisper"
S1_ADDITIONAL_TERM = (
    "In addition to the terms of the Apache License, Version 2.0 above: any\n"
    "   use, distribution, or integration of this model, whether unmodified or\n"
    "   as part of a derivative work or product, must continue to identify it\n"
    "   by its original name, \"S1-mini\" by \"Superwhisper\", using that exact\n"
    "   capitalization, regardless of any other name under which the model or\n"
    "   a product incorporating it is marketed or distributed."
)
QWEN_REVISION = "c1899de289a04d12100db370d81485cdf75e47ca"
QWEN_UPSTREAM_LICENSE_SHA256 = "832dd9e00a68dd83b3c3fb9f5588dad7dcf337a0db50f7d9483f310cd292e92e"
QWEN_SHIPPED_LICENSE_SHA256 = "c156170b718ec29139d3653d40ed1986fd92fb7e0959b5c71f3c48f62e6636f4"
LLAMA_REVISION = "9ee9fc04c136ef2ae729bfc60d18961b23c13ddf"

S1_LICENSE_URLS = (
    "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/"
    + S1_GGUF_REVISION
    + "/LICENSE",
    "https://huggingface.co/superwhisper/s1-mini/resolve/"
    + S1_MODEL_CARD_REVISION
    + "/LICENSE",
)
QWEN_LICENSE_URL = (
    "https://huggingface.co/Qwen/Qwen3-0.6B/resolve/" + QWEN_REVISION + "/LICENSE"
)

REQUIRED_TEXT = {
    "NOTICE": (S1_NAME, "Qwen3-0.6B", LLAMA_REVISION),
    "THIRD_PARTY_NOTICES.md": (
        S1_NAME,
        S1_LICENSE_EXPRESSION,
        "Qwen/Qwen3-0.6B",
        QWEN_REVISION,
        LLAMA_REVISION,
    ),
    "Documentation/MODEL_PROVENANCE.md": (
        S1_NAME,
        S1_MODEL_CARD_REVISION,
        S1_GGUF_REVISION,
        QWEN_REVISION,
        "484,219,808",
        "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634",
        S1_LICENSE_EXPRESSION,
    ),
    "Documentation/PRIVACY.md": (
        S1_NAME,
        "text only after final English transcription",
        "no runtime model download",
    ),
    "Documentation/THREAT_MODEL.md": (
        S1_NAME,
        "sealed precompiled Metal library",
        "command-stripped raw transcript",
    ),
    "README.md": (S1_NAME, "semi-formal", "session-leading `list`", "session-leading `email`"),
}

LEGAL_FILES = (
    "LICENSE",
    "NOTICE",
    "UPSTREAM.md",
    "SECURITY.md",
    "THIRD_PARTY_NOTICES.md",
)
LEGAL_DOCUMENTS = ("PRIVACY.md", "THREAT_MODEL.md", "MODEL_PROVENANCE.md")


class AttributionError(ValueError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def require_regular(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        raise AttributionError(f"required regular file is missing or unsafe: {path}")


def load_json(path: Path) -> dict:
    require_regular(path)
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AttributionError(f"expected JSON object: {path}")
    return value


def verify_repo(root: Path) -> None:
    s1_license = root / "LICENSES" / "S1-mini-LICENSE.txt"
    require_regular(s1_license)
    if s1_license.stat().st_size != S1_LICENSE_BYTES or sha256(s1_license) != S1_LICENSE_SHA256:
        raise AttributionError("S1-mini license is not the complete pinned 11878-byte file")
    if S1_ADDITIONAL_TERM.encode() not in s1_license.read_bytes():
        raise AttributionError("S1-mini additional naming term is missing or changed")

    qwen_license = root / "LICENSES" / "Qwen3-0.6B-Apache-2.0.txt"
    require_regular(qwen_license)
    if sha256(qwen_license) != QWEN_SHIPPED_LICENSE_SHA256:
        raise AttributionError("Qwen3-0.6B license resource changed unexpectedly")
    if b"Copyright 2024 Alibaba Cloud" not in qwen_license.read_bytes():
        raise AttributionError("Qwen3-0.6B attribution is missing")

    llama_license = root / "LICENSES" / "llama.cpp-MIT.txt"
    require_regular(llama_license)
    if "MIT License" not in llama_license.read_text(encoding="utf-8"):
        raise AttributionError("llama.cpp MIT license resource is invalid")

    s1_manifest = load_json(root / "Models" / "s1-mini-gguf.json")
    if s1_manifest.get("revision") != S1_GGUF_REVISION:
        raise AttributionError("S1-mini GGUF manifest revision changed")
    upstream = (root / "Vendor" / "LlamaLocal" / "UPSTREAM.md").read_text(encoding="utf-8")
    if LLAMA_REVISION not in upstream:
        raise AttributionError("llama.cpp upstream revision changed")

    for relative, needles in REQUIRED_TEXT.items():
        path = root / relative
        require_regular(path)
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                raise AttributionError(f"required attribution text missing from {relative}: {needle}")


def verify_upstream() -> None:
    downloaded: list[bytes] = []
    for url in S1_LICENSE_URLS:
        with urllib.request.urlopen(url, timeout=30) as response:
            data = response.read(S1_LICENSE_BYTES + 1)
        if len(data) != S1_LICENSE_BYTES or sha256_bytes(data) != S1_LICENSE_SHA256:
            raise AttributionError(f"pinned upstream S1-mini license mismatch: {url}")
        downloaded.append(data)
    if downloaded[0] != downloaded[1]:
        raise AttributionError("the two pinned S1-mini repositories have different license bytes")

    with urllib.request.urlopen(QWEN_LICENSE_URL, timeout=30) as response:
        qwen = response.read(12000)
    if sha256_bytes(qwen) != QWEN_UPSTREAM_LICENSE_SHA256:
        raise AttributionError("pinned upstream Qwen3-0.6B license mismatch")


def package_by_id(document: dict, package_id: str) -> dict:
    matches = [item for item in document.get("packages", []) if item.get("SPDXID") == package_id]
    if len(matches) != 1:
        raise AttributionError(f"expected exactly one SBOM package: {package_id}")
    return matches[0]


def verify_sbom(path: Path) -> None:
    document = load_json(path)
    s1 = package_by_id(document, "SPDXRef-Package-S1Mini")
    qwen = package_by_id(document, "SPDXRef-Package-Qwen3")
    llama = package_by_id(document, "SPDXRef-Package-LlamaCpp")
    if s1.get("name") != S1_NAME or s1.get("versionInfo") != S1_GGUF_REVISION:
        raise AttributionError("SBOM S1-mini identity or revision mismatch")
    if s1.get("licenseDeclared") != S1_LICENSE_EXPRESSION:
        raise AttributionError("SBOM S1-mini composite license expression mismatch")
    if qwen.get("versionInfo") != QWEN_REVISION or qwen.get("licenseDeclared") != "Apache-2.0":
        raise AttributionError("SBOM Qwen package mismatch")
    if llama.get("versionInfo") != LLAMA_REVISION or llama.get("licenseDeclared") != "MIT":
        raise AttributionError("SBOM llama.cpp package mismatch")
    extracted = [
        item for item in document.get("hasExtractedLicensingInfos", [])
        if item.get("licenseId") == "LicenseRef-S1-mini-Naming-Clause"
    ]
    if len(extracted) != 1 or S1_ADDITIONAL_TERM not in extracted[0].get("extractedText", ""):
        raise AttributionError("SBOM extracted S1-mini naming clause mismatch")
    relationships = {
        (item.get("spdxElementId"), item.get("relationshipType"), item.get("relatedSpdxElement"))
        for item in document.get("relationships", [])
    }
    required = {
        ("SPDXRef-Package-VoxHearth", "CONTAINS", "SPDXRef-Package-S1Mini"),
        ("SPDXRef-Package-S1Mini", "DESCENDANT_OF", "SPDXRef-Package-Qwen3"),
        ("SPDXRef-Package-VoxHearth", "DEPENDS_ON", "SPDXRef-Package-LlamaCpp"),
    }
    if not required.issubset(relationships):
        raise AttributionError("SBOM S1-mini/Qwen/llama.cpp relationships are incomplete")


def verify_provenance(path: Path) -> None:
    document = load_json(path)
    materials = {item.get("name"): item for item in document.get("materials", [])}
    required = {
        "S1-mini by Superwhisper GGUF": S1_GGUF_REVISION,
        "S1-mini by Superwhisper model card": S1_MODEL_CARD_REVISION,
        "Qwen3-0.6B base model": QWEN_REVISION,
        "llama.cpp local runtime": LLAMA_REVISION,
    }
    for name, revision in required.items():
        item = materials.get(name)
        if item is None or revision not in json.dumps(item, sort_keys=True):
            raise AttributionError(f"release provenance material is missing or unpinned: {name}")
    license_material = materials.get("S1-mini by Superwhisper license")
    if license_material is None or license_material.get("digest", {}).get("sha256") != S1_LICENSE_SHA256:
        raise AttributionError("release provenance does not pin the S1-mini license")
    metal = materials.get("llama.cpp sealed Metal library")
    if metal is None or metal.get("digest", {}).get("sha256") != "925c4db276d4459780420282e6f20a221d3b9f35f44b26b7ba55d82d5e381b74":
        raise AttributionError("release provenance does not pin the sealed Metal library")


def verify_app(root: Path, app: Path) -> None:
    legal = app / "Contents" / "Resources" / "Legal"
    if legal.is_symlink() or not legal.is_dir():
        raise AttributionError("app Legal resource root is missing or unsafe")
    expected_top = set(LEGAL_FILES) | set(LEGAL_DOCUMENTS) | {"LICENSES"}
    actual_top = {item.name for item in legal.iterdir()}
    if actual_top != expected_top:
        raise AttributionError(f"app Legal inventory mismatch: {sorted(actual_top)}")
    for name in LEGAL_FILES:
        require_regular(legal / name)
        if (legal / name).read_bytes() != (root / name).read_bytes():
            raise AttributionError(f"app legal resource differs from source: {name}")
    for name in LEGAL_DOCUMENTS:
        require_regular(legal / name)
        if (legal / name).read_bytes() != (root / "Documentation" / name).read_bytes():
            raise AttributionError(f"app legal document differs from source: {name}")
    source_licenses = root / "LICENSES"
    bundled_licenses = legal / "LICENSES"
    if bundled_licenses.is_symlink() or not bundled_licenses.is_dir():
        raise AttributionError("app LICENSES resource is missing or unsafe")
    if {p.name for p in source_licenses.iterdir()} != {p.name for p in bundled_licenses.iterdir()}:
        raise AttributionError("app LICENSES inventory differs from source")
    for source in source_licenses.iterdir():
        bundled = bundled_licenses / source.name
        if (
            source.is_symlink()
            or not source.is_file()
            or bundled.is_symlink()
            or not bundled.is_file()
            or bundled.read_bytes() != source.read_bytes()
        ):
            raise AttributionError(f"app license differs from source: {source.name}")


def self_test(root: Path) -> None:
    verify_repo(root)
    with tempfile.TemporaryDirectory(prefix="voxhearth-attribution-") as temporary:
        fixture = Path(temporary) / "repo"
        for relative in tuple(REQUIRED_TEXT) + (
            "LICENSES/S1-mini-LICENSE.txt",
            "LICENSES/Qwen3-0.6B-Apache-2.0.txt",
            "LICENSES/llama.cpp-MIT.txt",
            "Models/s1-mini-gguf.json",
            "Vendor/LlamaLocal/UPSTREAM.md",
        ):
            source = root / relative
            target = fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        verify_repo(fixture)

        mutations = (
            ("THIRD_PARTY_NOTICES.md", S1_NAME, "S1-mini"),
            ("Documentation/MODEL_PROVENANCE.md", S1_LICENSE_EXPRESSION, "Apache-2.0"),
            ("LICENSES/S1-mini-LICENSE.txt", "S1-mini", "S1-minx"),
        )
        for relative, old, new in mutations:
            path = fixture / relative
            original = path.read_bytes()
            path.write_bytes(original.replace(old.encode(), new.encode()))
            try:
                verify_repo(fixture)
            except AttributionError:
                pass
            else:
                raise AttributionError(f"self-test accepted mutation: {relative}")
            path.write_bytes(original)
        qwen = fixture / "LICENSES/Qwen3-0.6B-Apache-2.0.txt"
        held = qwen.with_suffix(".held")
        qwen.rename(held)
        try:
            verify_repo(fixture)
        except AttributionError:
            pass
        else:
            raise AttributionError("self-test accepted missing Qwen license")

        app = Path(temporary) / "VoxHearth.app"
        legal = app / "Contents" / "Resources" / "Legal"
        legal.mkdir(parents=True)
        for name in LEGAL_FILES:
            shutil.copyfile(root / name, legal / name)
        for name in LEGAL_DOCUMENTS:
            shutil.copyfile(root / "Documentation" / name, legal / name)
        shutil.copytree(root / "LICENSES", legal / "LICENSES")
        verify_app(root, app)
        removed_license = legal / "LICENSES" / "S1-mini-LICENSE.txt"
        removed_license.unlink()
        try:
            verify_app(root, app)
        except AttributionError:
            pass
        else:
            raise AttributionError("self-test accepted app without S1-mini license")

        sbom = Path(temporary) / "fixture.spdx.json"
        sbom_document = {
            "packages": [
                {
                    "name": S1_NAME,
                    "SPDXID": "SPDXRef-Package-S1Mini",
                    "versionInfo": S1_GGUF_REVISION,
                    "licenseDeclared": S1_LICENSE_EXPRESSION,
                },
                {
                    "SPDXID": "SPDXRef-Package-Qwen3",
                    "versionInfo": QWEN_REVISION,
                    "licenseDeclared": "Apache-2.0",
                },
                {
                    "SPDXID": "SPDXRef-Package-LlamaCpp",
                    "versionInfo": LLAMA_REVISION,
                    "licenseDeclared": "MIT",
                },
            ],
            "hasExtractedLicensingInfos": [
                {
                    "licenseId": "LicenseRef-S1-mini-Naming-Clause",
                    "extractedText": S1_ADDITIONAL_TERM,
                }
            ],
            "relationships": [
                {
                    "spdxElementId": "SPDXRef-Package-VoxHearth",
                    "relationshipType": "CONTAINS",
                    "relatedSpdxElement": "SPDXRef-Package-S1Mini",
                },
                {
                    "spdxElementId": "SPDXRef-Package-S1Mini",
                    "relationshipType": "DESCENDANT_OF",
                    "relatedSpdxElement": "SPDXRef-Package-Qwen3",
                },
                {
                    "spdxElementId": "SPDXRef-Package-VoxHearth",
                    "relationshipType": "DEPENDS_ON",
                    "relatedSpdxElement": "SPDXRef-Package-LlamaCpp",
                },
            ],
        }
        sbom.write_text(json.dumps(sbom_document), encoding="utf-8")
        verify_sbom(sbom)
        sbom_document["packages"][0]["licenseDeclared"] = "Apache-2.0"
        sbom.write_text(json.dumps(sbom_document), encoding="utf-8")
        try:
            verify_sbom(sbom)
        except AttributionError:
            pass
        else:
            raise AttributionError("self-test accepted SBOM without composite license")

        provenance = Path(temporary) / "fixture-provenance.json"
        provenance_document = {
            "materials": [
                {"name": "S1-mini by Superwhisper GGUF", "revision": S1_GGUF_REVISION},
                {"name": "S1-mini by Superwhisper model card", "revision": S1_MODEL_CARD_REVISION},
                {"name": "Qwen3-0.6B base model", "revision": QWEN_REVISION},
                {"name": "llama.cpp local runtime", "revision": LLAMA_REVISION},
                {
                    "name": "S1-mini by Superwhisper license",
                    "digest": {"sha256": S1_LICENSE_SHA256},
                },
                {
                    "name": "llama.cpp sealed Metal library",
                    "digest": {
                        "sha256": "925c4db276d4459780420282e6f20a221d3b9f35f44b26b7ba55d82d5e381b74"
                    },
                },
            ]
        }
        provenance.write_text(json.dumps(provenance_document), encoding="utf-8")
        verify_provenance(provenance)
        provenance_document["materials"].pop()
        provenance.write_text(json.dumps(provenance_document), encoding="utf-8")
        try:
            verify_provenance(provenance)
        except AttributionError:
            pass
        else:
            raise AttributionError("self-test accepted incomplete provenance")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--sbom", type=Path)
    parser.add_argument("--provenance", type=Path)
    parser.add_argument("--verify-upstream", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = (args.root or Path(__file__).resolve().parent.parent).resolve()
    try:
        verify_repo(root)
        if args.verify_upstream:
            verify_upstream()
        if args.app:
            verify_app(root, args.app.resolve())
        if args.sbom:
            verify_sbom(args.sbom.resolve())
        if args.provenance:
            verify_provenance(args.provenance.resolve())
        if args.self_test:
            self_test(root)
    except (AttributionError, OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print("attribution and licensing verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
