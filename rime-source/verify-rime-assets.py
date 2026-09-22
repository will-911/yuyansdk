#!/usr/bin/env python3
"""Structural checks for the generated shared table and pinyin prisms."""

from __future__ import annotations

import argparse
import json
import re
import struct
from pathlib import Path


PRISMS = (
    "pinyin.prism.bin",
    "t9_pinyin.prism.bin",
    "double_pinyin_abc.prism.bin",
    "double_pinyin_flypy.prism.bin",
    "double_pinyin_ls17.prism.bin",
    "double_pinyin_mspy.prism.bin",
    "double_pinyin_natural.prism.bin",
    "double_pinyin_sogou.prism.bin",
    "double_pinyin_ziguang.prism.bin",
    "double_pinyin_zx17.prism.bin",
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--expected-rime-version", required=True)
    args = parser.parse_args()

    assets = args.assets.resolve()
    table = (assets / "pinyin.table.bin").read_bytes()
    if not table.startswith(b"Rime::Table/"):
        raise SystemExit("pinyin.table.bin has an invalid Rime table header")

    reference_checksum = None
    reference_syllables = None
    payloads: dict[str, bytes] = {}
    for name in PRISMS:
        payload = (assets / name).read_bytes()
        payloads[name] = payload
        if not payload.startswith(b"Rime::Prism/"):
            raise SystemExit(f"{name} has an invalid Rime prism header")
        if len(payload) < 44:
            raise SystemExit(f"{name} is too small")
        dictionary_checksum = struct.unpack_from("<I", payload, 32)[0]
        syllable_count = struct.unpack_from("<I", payload, 40)[0]
        if reference_checksum is None:
            reference_checksum = dictionary_checksum
            reference_syllables = syllable_count
        if dictionary_checksum != reference_checksum:
            raise SystemExit(
                f"{name} dictionary checksum {dictionary_checksum:#x} does not match "
                f"pinyin.prism.bin {reference_checksum:#x}"
            )
        if syllable_count != reference_syllables:
            raise SystemExit(
                f"{name} syllable inventory {syllable_count} does not match "
                f"pinyin.prism.bin {reference_syllables}"
            )

    if payloads["double_pinyin_zx17.prism.bin"] == payloads["double_pinyin_ls17.prism.bin"]:
        raise SystemExit("ZX17 prism unexpectedly matches LX17 prism")

    compiled_schema_path = assets / "pinyin.schema.yaml"
    if compiled_schema_path.is_file():
        compiled_schema = compiled_schema_path.read_text(encoding="utf-8")
        match = re.search(r"(?m)^\s*rime_version:\s*['\"]?([^'\"\s]+)", compiled_schema)
        if not match:
            raise SystemExit("compiled pinyin schema does not report the librime version")
        actual_version = match.group(1)
    else:
        manifest_path = assets / "rime-assets-manifest.json"
        if not manifest_path.is_file():
            raise SystemExit("neither compiled pinyin schema nor asset manifest is available")
        actual_version = json.loads(manifest_path.read_text(encoding="utf-8"))["librime_version"]
    if actual_version != args.expected_rime_version:
        raise SystemExit(
            f"librime version mismatch: expected {args.expected_rime_version}, got {actual_version}"
        )

    print(
        f"Verified {len(PRISMS)} prisms: dictionary checksum={reference_checksum:#x}, "
        f"syllables={reference_syllables}, librime={actual_version}"
    )


if __name__ == "__main__":
    main()
