#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_BUILD_DIR="$ROOT_DIR/src/main/assets/rime/build"
SCHEMA_SOURCE="$ROOT_DIR/rime-source/double_pinyin_zx17.schema.yaml"
PINYIN_SOURCE="$ROOT_DIR/src/main/java/com/yuyan/inputmethod/util/LX17PinYinUtils.kt"
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
python3 - "$PINYIN_SOURCE" "$REFERENCE_PRISM" "$tmp_dir/pinyin.dict.yaml" <<'PY'
from pathlib import Path
import re
import struct
import sys

source = Path(sys.argv[1]).read_text()
reference = Path(sys.argv[2]).read_bytes()
values = re.findall(r'lx17PinyinMap\.put\("[^"]+",\s*"([^"]+)"\)', source)
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

header = """---
name: pinyin
version: "zx17"
sort: by_weight
...
"""
entries = "\n".join(f"{syllable}\t{syllable}\t1" for syllable in sorted(syllables))
Path(sys.argv[3]).write_text(header + entries + "\n")
PY
cp "$SCHEMA_SOURCE" "$tmp_dir/"

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
