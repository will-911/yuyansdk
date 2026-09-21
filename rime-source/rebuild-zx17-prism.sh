#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_BUILD_DIR="$ROOT_DIR/src/main/assets/rime/build"
SCHEMA_SOURCE="$ROOT_DIR/rime-source/double_pinyin_zx17.schema.yaml"
PINYIN_SOURCE="$ROOT_DIR/src/main/java/com/yuyan/inputmethod/util/LX17PinYinUtils.kt"
OUTPUT_PATH="${1:-$ASSET_BUILD_DIR/double_pinyin_zx17.prism.bin}"
RIME_DEPLOYER="${RIME_DEPLOYER:-rime_deployer}"

command -v "$RIME_DEPLOYER" >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/build" "$(dirname "$OUTPUT_PATH")"

# A prism only needs the dictionary's syllable inventory. Generate a tiny source
# dictionary from the same syllable set used by the ZX17 filter UI instead of
# decompiling the app's newer pinyin.table.bin with an older distro librime.
python3 - "$PINYIN_SOURCE" "$tmp_dir/pinyin.dict.yaml" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
values = re.findall(r'lx17PinyinMap\.put\("[^"]+",\s*"([^"]+)"\)', source)
syllables = {item for value in values for item in value.split(",") if item}
syllables.update({"cei", "dia", "fiao", "kei", "nou", "qi", "rua", "yo", "zhei"})

header = """---
name: pinyin
version: "zx17"
sort: by_weight
...
"""
entries = "\n".join(f"{syllable}\t{syllable}\t1" for syllable in sorted(syllables))
Path(sys.argv[2]).write_text(header + entries + "\n")
PY
cp "$SCHEMA_SOURCE" "$tmp_dir/"

"$RIME_DEPLOYER" --compile \
  "$tmp_dir/$(basename "$SCHEMA_SOURCE")" \
  "$tmp_dir" \
  "$tmp_dir" \
  "$tmp_dir/build"

generated_prism="$tmp_dir/build/double_pinyin_zx17.prism.bin"
test -s "$generated_prism"
if cmp -s "$generated_prism" "$ASSET_BUILD_DIR/double_pinyin_ls17.prism.bin"; then
  echo "ZX17 prism unexpectedly matches the LX17 prism" >&2
  exit 1
fi
cp "$generated_prism" "$OUTPUT_PATH"
echo "Generated $OUTPUT_PATH"
