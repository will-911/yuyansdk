#!/usr/bin/env python3
"""Adapt a pinned rime-frost checkout to Yuyan's stable schema IDs."""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path


COMMON_SCHEMAS = {
    "rime_frost_double_pinyin.schema.yaml": "double_pinyin_natural",
    "rime_frost_double_pinyin_abc.schema.yaml": "double_pinyin_abc",
    "rime_frost_double_pinyin_flypy.schema.yaml": "double_pinyin_flypy",
    "rime_frost_double_pinyin_mspy.schema.yaml": "double_pinyin_mspy",
    "rime_frost_double_pinyin_sogou.schema.yaml": "double_pinyin_sogou",
    "rime_frost_double_pinyin_ziguang.schema.yaml": "double_pinyin_ziguang",
}


def replace_dictionary_name(text: str) -> str:
    updated, count = re.subn(
        r"(?m)^(\s*dictionary:\s*)rime_frost(\s*(?:#.*)?)$",
        r"\1pinyin\2",
        text,
    )
    if count == 0:
        raise ValueError("schema does not reference dictionary rime_frost")
    return updated


def adapt_schema(source: Path, destination: Path, old_id: str, new_id: str) -> None:
    text = source.read_text(encoding="utf-8")
    old_schema_id = f"schema_id: {old_id}"
    if old_schema_id not in text:
        raise ValueError(f"missing schema id {old_id} in {source}")
    text = replace_dictionary_name(text)
    text = text.replace(old_schema_id, f"schema_id: {new_id}", 1)
    text = re.sub(
        rf"(?m)^(\s*prism:\s*){re.escape(old_id)}(\s*(?:#.*)?)$",
        rf"\1{new_id}\2",
        text,
    )
    destination.write_text(text, encoding="utf-8")


def collect_codes(frost_root: Path) -> set[str]:
    sources = [frost_root / "rime_frost.dict.yaml"]
    sources.extend(sorted((frost_root / "cn_dicts").glob("*.dict.yaml")))
    sources.extend(sorted((frost_root / "cn_dicts_cell").glob("*.dict.yaml")))
    codes: set[str] = set()
    for source in sources:
        if not source.is_file():
            continue
        for line in source.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#") or "\t" not in line:
                continue
            fields = line.split("\t")
            if len(fields) < 2:
                continue
            for code in fields[1].split():
                if re.fullmatch(r"[a-z]+", code):
                    codes.add(code)
    if len(codes) < 400:
        raise ValueError(f"unexpectedly small pinyin code inventory: {len(codes)}")
    return codes


def kotlin_map_block(source: str, name: str) -> str:
    match = re.search(rf"private val {name} = mapOf\((.*?)\n    \)", source, re.S)
    if not match:
        raise ValueError(f"cannot find Kotlin map {name}")
    return match.group(1)


def zx17_encoder(sdk_root: Path):
    source = (sdk_root / "src/main/java/com/yuyan/inputmethod/util/ZX17PinYinUtils.kt").read_text(
        encoding="utf-8"
    )
    letter_to_key = dict(
        re.findall(r"'([a-z])'\s+to\s+'([A-Z])'", kotlin_map_block(source, "letterToKey"))
    )
    final_to_flypy = dict(
        re.findall(r'"([a-z]+)"\s+to\s+\'([a-z])\'', kotlin_map_block(source, "finalToFlypyKey"))
    )
    zero_initial = dict(
        re.findall(r'"([a-z]+)"\s+to\s+"([a-z]+)"', kotlin_map_block(source, "zeroInitialFlypyCode"))
    )

    def encode(pinyin: str) -> str | None:
        flypy = zero_initial.get(pinyin)
        if flypy is None:
            initial = next((item for item in ("zh", "ch", "sh") if pinyin.startswith(item)), "")
            if not initial and pinyin[0] in "bpmfdtnlgkhjqxrzcswy":
                initial = pinyin[0]
            final = pinyin[len(initial) :]
            initial_key = {"zh": "v", "ch": "i", "sh": "u"}.get(initial, initial)
            final_key = final_to_flypy.get(final, final if len(final) == 1 else None)
            if not initial_key or not final_key:
                return None
            flypy = initial_key + final_key
        try:
            return "".join(letter_to_key[letter] for letter in flypy)
        except KeyError:
            return None

    return encode


def t9_encoder(sdk_root: Path):
    source = (sdk_root / "src/main/java/com/yuyan/inputmethod/util/T9PinYinUtils.kt").read_text(
        encoding="utf-8"
    )
    block_match = re.search(r"private val t9KeyMap = mapOf\((.*?)\n    \)", source, re.S)
    if not block_match:
        raise ValueError("cannot find Kotlin map t9KeyMap")
    letter_to_key = dict(re.findall(r"'([a-z])'\s+to\s+'([A-Z])'", block_match.group(1)))
    if len(letter_to_key) != 26:
        raise ValueError(f"T9 map must contain 26 letters, found {len(letter_to_key)}")

    def encode(code: str) -> str:
        return "".join(letter_to_key[letter] for letter in code)

    return encode


def write_alias_schema(
    destination: Path,
    schema_id: str,
    name: str,
    codes: set[str],
    encode,
) -> int:
    aliases = []
    for code in sorted(codes):
        alias = encode(code)
        if alias and alias != code:
            aliases.append((code, alias))
    rules = "\n".join(f"    - derive/^{code}$/{alias}/" for code, alias in aliases)
    destination.write_text(
        f"""# Generated by prepare-rime-source.py; edit the Kotlin layout maps instead.
# Full-pinyin aliases are retained for Yuyan's pinyin-selection protocol.
schema:
  schema_id: {schema_id}
  name: \"{name}\"
  version: \"1.0\"

speller:
  alphabet: \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`/\"
  delimiter: \"''\"
  algebra:
    - abbrev/^([a-z]).+$/$1/
    - abbrev/^(zh|ch|sh).+$/$1/
{rules}

translator:
  dictionary: pinyin
  prism: {schema_id}
""",
        encoding="utf-8",
    )
    return len(aliases)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frost-root", type=Path, required=True)
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    frost_root = args.frost_root.resolve()
    sdk_root = args.sdk_root.resolve()
    output = args.output.resolve()
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(frost_root, output)

    dictionary = (output / "rime_frost.dict.yaml").read_text(encoding="utf-8")
    dictionary, count = re.subn(r"(?m)^name:\s*rime_frost\s*$", "name: pinyin", dictionary)
    # Keep Yuyan's existing large-dictionary profile by enabling Frost's optional
    # cleaned Tencent vector vocabulary. It is compiled in CI; the app still only
    # loads the resulting table and never deploys the source dictionary on-device.
    dictionary, tencent_count = re.subn(
        r"(?m)^(\s*)#\s*-\s*cn_dicts/tencent(\s*(?:#.*)?)$",
        r"\1- cn_dicts/tencent\2",
        dictionary,
    )
    if tencent_count != 1:
        raise ValueError("expected exactly one optional cn_dicts/tencent import")
    if count != 1:
        raise ValueError("rime_frost.dict.yaml must contain exactly one dictionary name")
    (output / "pinyin.dict.yaml").write_text(dictionary, encoding="utf-8")

    adapt_schema(
        output / "rime_frost.schema.yaml",
        output / "pinyin.schema.yaml",
        "rime_frost",
        "pinyin",
    )
    for source_name, schema_id in COMMON_SCHEMAS.items():
        adapt_schema(
            output / source_name,
            output / f"{schema_id}.schema.yaml",
            source_name.removesuffix(".schema.yaml"),
            schema_id,
        )

    ls17 = (sdk_root / "rime-source/double_pinyin_ls17.schema.yaml").read_text(encoding="utf-8")
    # Preserve lowercase full-pinyin aliases so pinyin filtering uses the same
    # protocol as T9 and ZX17 while keeping the original shuffled key codes.
    ls17 = ls17.replace("    - xform/^", "    - derive/^")
    (output / "double_pinyin_ls17.schema.yaml").write_text(ls17, encoding="utf-8")

    codes = collect_codes(frost_root)
    t9_encode = t9_encoder(sdk_root)
    zx17_encode = zx17_encoder(sdk_root)
    expected_t9 = {"ni": "MG", "hao": "GAM", "zhong": "WGMMG"}
    expected_zx17 = {"ni": "BI", "hao": "HC", "zhong": "VA", "shuang": "UL"}
    for code, expected in expected_t9.items():
        if t9_encode(code) != expected:
            raise ValueError(f"T9 encoder mismatch: {code}={t9_encode(code)}, expected {expected}")
    for code, expected in expected_zx17.items():
        if zx17_encode(code) != expected:
            raise ValueError(
                f"ZX17 encoder mismatch: {code}={zx17_encode(code)}, expected {expected}"
            )

    t9_count = write_alias_schema(
        output / "t9_pinyin.schema.yaml",
        "t9_pinyin",
        "语燕九键拼音",
        codes,
        t9_encode,
    )
    zx17_count = write_alias_schema(
        output / "double_pinyin_zx17.schema.yaml",
        "double_pinyin_zx17",
        "语燕正序17键小鹤双拼",
        codes,
        zx17_encode,
    )
    if zx17_count < 400:
        raise ValueError(f"unexpectedly small ZX17 alias inventory: {zx17_count}")

    print(f"Prepared {len(codes)} dictionary codes ({t9_count} T9 aliases, {zx17_count} ZX17 aliases)")


if __name__ == "__main__":
    main()
