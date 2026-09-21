#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_BUILD_DIR="$ROOT_DIR/src/main/assets/rime/build"
SCHEMA_SOURCE="$ROOT_DIR/rime-source/double_pinyin_zx17.schema.yaml"
OUTPUT_PATH="${1:-$ASSET_BUILD_DIR/double_pinyin_zx17.prism.bin}"
RIME_TABLE_DECOMPILER="${RIME_TABLE_DECOMPILER:-rime_table_decompiler}"
RIME_DEPLOYER="${RIME_DEPLOYER:-rime_deployer}"

command -v "$RIME_TABLE_DECOMPILER" >/dev/null
command -v "$RIME_DEPLOYER" >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/build" "$(dirname "$OUTPUT_PATH")"

"$RIME_TABLE_DECOMPILER" \
  "$ASSET_BUILD_DIR/pinyin.table.bin" \
  "$tmp_dir/pinyin.dict.yaml"
# The decompiler derives the dictionary name from pinyin.table.bin.
# The schema references it as "pinyin", so normalize the generated header.
python3 - "$tmp_dir/pinyin.dict.yaml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
for index, line in enumerate(lines):
    if line.startswith("name: "):
        lines[index] = "name: pinyin"
        break
else:
    raise SystemExit("decompiled dictionary has no name header")
path.write_text("\n".join(lines) + "\n")
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
