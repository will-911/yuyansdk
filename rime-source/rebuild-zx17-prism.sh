#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_BUILD_DIR="$ROOT_DIR/src/main/assets/rime/build"
SCHEMA_SOURCE="$ROOT_DIR/rime-source/double_pinyin_zx17.schema.yaml"
LX_PINYIN_SOURCE="$ROOT_DIR/src/main/java/com/yuyan/inputmethod/util/LX17PinYinUtils.kt"
ZX_PINYIN_SOURCE="$ROOT_DIR/src/main/java/com/yuyan/inputmethod/util/ZX17PinYinUtils.kt"
REFERENCE_PRISM="$ASSET_BUILD_DIR/pinyin.prism.bin"
OUTPUT_PATH="${1:-$ASSET_BUILD_DIR/double_pinyin_zx17.prism.bin}"
RIME_DEPLOYER="${RIME_DEPLOYER:-rime_deployer}"

command -v "$RIME_DEPLOYER" >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/build" "$(dirname "$OUTPUT_PATH")"

# Build from the exact 414-syllable inventory used by the packaged pinyin
# dictionary. Extra standalone initials would shift Rime's numeric syllable IDs
# and make the new prism unable to query pinyin.table.bin.
python3 - \
  "$LX_PINYIN_SOURCE" \
  "$ZX_PINYIN_SOURCE" \
  "$REFERENCE_PRISM" \
  "$tmp_dir/pinyin.dict.yaml" \
  "$SCHEMA_SOURCE" \
  "$tmp_dir/$(basename "$SCHEMA_SOURCE")" <<'PY'
from pathlib import Path
import re
import struct
import sys

lx_source = Path(sys.argv[1]).read_text()
zx_source = Path(sys.argv[2]).read_text()
reference = Path(sys.argv[3]).read_bytes()
values = re.findall(r'lx17PinyinMap\.put\("[^"]+",\s*"([^"]+)"\)', lx_source)
syllables = {item for value in values for item in value.split(",") if item}
syllables.update({"cei", "dia", "fiao", "kei", "nou", "qi", "rua", "yo", "zhei"})
syllables.difference_update({
    "b", "c", "ch", "d", "f", "g", "h", "i", "j", "k", "l", "m", "n",
    "p", "q", "r", "s", "sh", "t", "w", "x", "y", "z", "zh",
    "duang", "fuo", "hiu", "ja", "muo",
})

reference_count = struct.unpack_from("<I", reference, 40)[0]
if len(syllables) != reference_count:
    raise SystemExit(
        f"syllable inventory mismatch: source={len(syllables)}, reference={reference_count}"
    )

def kotlin_map_block(name):
    match = re.search(
        rf"private val {name} = mapOf\((.*?)\n    \)", zx_source, re.S
    )
    if not match:
        raise SystemExit(f"cannot find Kotlin map: {name}")
    return match.group(1)

letter_to_key = dict(
    re.findall(r"'([a-z])'\s+to\s+'([A-Z])'", kotlin_map_block("letterToKey"))
)
final_to_flypy = dict(
    re.findall(r'"([a-z]+)"\s+to\s+\'([a-z])\'', kotlin_map_block("finalToFlypyKey"))
)
zero_initial = dict(
    re.findall(r'"([a-z]+)"\s+to\s+"([a-z]+)"', kotlin_map_block("zeroInitialFlypyCode"))
)

def encode(pinyin):
    flypy = zero_initial.get(pinyin)
    if flypy is None:
        initial = next((value for value in ("zh", "ch", "sh") if pinyin.startswith(value)), "")
        if not initial and pinyin[0] in "bpmfdtnlgkhjqxrzcswy":
            initial = pinyin[0]
        final = pinyin[len(initial):]
        initial_key = {"zh": "v", "ch": "i", "sh": "u"}.get(initial, initial)
        final_key = final_to_flypy.get(final, final if len(final) == 1 else None)
        if not initial_key or not final_key:
            raise SystemExit(f"cannot encode pinyin syllable: {pinyin}")
        flypy = initial_key + final_key
    return "".join(letter_to_key[letter] for letter in flypy)

expected_samples = {"ni": "BI", "hao": "HC", "zhong": "VA", "shuang": "UL"}
for pinyin, expected in expected_samples.items():
    actual = encode(pinyin)
    if actual != expected:
        raise SystemExit(f"ZX17 encoder mismatch: {pinyin}={actual}, expected {expected}")

header = """---
name: pinyin
version: "zx17"
sort: by_weight
...
"""
entries = "\n".join(f"{syllable}\t{syllable}\t1" for syllable in sorted(syllables))
Path(sys.argv[4]).write_text(header + entries + "\n")

schema_template = Path(sys.argv[5]).read_text()
placeholder = "  algebra: []"
if schema_template.count(placeholder) != 1:
    raise SystemExit("ZX17 schema must contain exactly one algebra placeholder")
derive_rules = "\n".join(
    f"    - derive/^{syllable}$/{encode(syllable)}/" for syllable in sorted(syllables)
)
algebra = "\n".join((
    "    - abbrev/^([a-z]).+$/$1/",
    "    - abbrev/^(zh|ch|sh).+$/$1/",
    derive_rules,
))
Path(sys.argv[6]).write_text(
    schema_template.replace(placeholder, "  algebra:\n" + algebra)
)
PY

"$RIME_DEPLOYER" --compile \
  "$tmp_dir/$(basename "$SCHEMA_SOURCE")" \
  "$tmp_dir" \
  "$tmp_dir" \
  "$tmp_dir/build"

generated_prism="$tmp_dir/build/double_pinyin_zx17.prism.bin"
# Keep the dictionary checksum consistent with the packaged pinyin table/prism.
# The schema checksum remains specific to ZX17.
python3 - "$REFERENCE_PRISM" "$generated_prism" <<'PY'
from pathlib import Path
import struct
import sys

reference_path = Path(sys.argv[1])
generated_path = Path(sys.argv[2])
reference = reference_path.read_bytes()
generated = bytearray(generated_path.read_bytes())
reference_count = struct.unpack_from("<I", reference, 40)[0]
generated_count = struct.unpack_from("<I", generated, 40)[0]
if generated_count != reference_count:
    raise SystemExit(
        f"generated prism has {generated_count} syllables; expected {reference_count}"
    )
struct.pack_into("<I", generated, 32, struct.unpack_from("<I", reference, 32)[0])
generated_path.write_bytes(generated)
PY
test -s "$generated_prism"
if cmp -s "$generated_prism" "$ASSET_BUILD_DIR/double_pinyin_ls17.prism.bin"; then
  echo "ZX17 prism unexpectedly matches the LX17 prism" >&2
  exit 1
fi
cp "$generated_prism" "$OUTPUT_PATH"
echo "Generated $OUTPUT_PATH"
