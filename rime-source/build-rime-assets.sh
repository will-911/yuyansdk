#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$(cd "$SOURCE_DIR/.." && pwd)"
# shellcheck source=frost.lock
source "$SOURCE_DIR/frost.lock"

OUTPUT_DIR="${1:-$SDK_ROOT/src/main/assets/rime/build}"
RIME_DEPLOYER="${RIME_DEPLOYER:-rime_deployer}"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/yuyan-rime"
ARCHIVE="$CACHE_ROOT/rime-frost-$FROST_COMMIT.tar.gz"

command -v curl >/dev/null
command -v python3 >/dev/null
command -v sha256sum >/dev/null
command -v "$RIME_DEPLOYER" >/dev/null
mkdir -p "$CACHE_ROOT" "$OUTPUT_DIR"

if [[ ! -f "$ARCHIVE" ]] || ! echo "$FROST_ARCHIVE_SHA256  $ARCHIVE" | sha256sum -c - >/dev/null 2>&1; then
  rm -f "$ARCHIVE"
  curl --fail --location --retry 3 --output "$ARCHIVE" "$FROST_ARCHIVE_URL"
fi
echo "$FROST_ARCHIVE_SHA256  $ARCHIVE" | sha256sum -c -

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
frost_dir="$work_dir/frost"
source_workspace="$work_dir/source"
build_dir="$work_dir/build"
mkdir -p "$frost_dir" "$build_dir"
tar -xzf "$ARCHIVE" -C "$frost_dir" --strip-components=1

python3 "$SOURCE_DIR/prepare-rime-source.py" \
  --frost-root "$frost_dir" \
  --sdk-root "$SDK_ROOT" \
  --output "$source_workspace"

schemas=(
  pinyin
  t9_pinyin
  double_pinyin_abc
  double_pinyin_flypy
  double_pinyin_ls17
  double_pinyin_mspy
  double_pinyin_natural
  double_pinyin_sogou
  double_pinyin_ziguang
  double_pinyin_zx17
)

export LC_ALL=C
export TZ=UTC
for schema in "${schemas[@]}"; do
  echo "Compiling $schema"
  "$RIME_DEPLOYER" --compile \
    "$source_workspace/$schema.schema.yaml" \
    "$source_workspace" \
    "$source_workspace" \
    "$build_dir"
done

required=(pinyin.table.bin)
for schema in "${schemas[@]}"; do
  required+=("$schema.prism.bin")
done
for file in "${required[@]}"; do
  test -s "$build_dir/$file"
done

python3 "$SOURCE_DIR/verify-rime-assets.py" \
  --assets "$build_dir" \
  --expected-rime-version "$RIME_COMPILER_VERSION"

for file in "${required[@]}"; do
  cp "$build_dir/$file" "$OUTPUT_DIR/$file"
done

python3 - \
  "$OUTPUT_DIR" \
  "$FROST_REPOSITORY" \
  "$FROST_COMMIT" \
  "$FROST_COMMIT_DATE" \
  "$FROST_ARCHIVE_SHA256" \
  "$RIME_COMPILER_VERSION" \
  "${required[@]}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

output = Path(sys.argv[1])
repository, commit, commit_date, archive_sha, compiler = sys.argv[2:7]
files = sys.argv[7:]
manifest = {
    "format": 1,
    "dictionary": "rime-frost",
    "repository": repository,
    "commit": commit,
    "commit_date": commit_date,
    "archive_sha256": archive_sha,
    "librime_version": compiler,
    "source_date": commit_date,
    "files": {},
}
for name in files:
    path = output / name
    manifest["files"][name] = {
        "size": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }
(output / "rime-assets-manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

printf 'Built rime-frost %s assets in %s\n' "$FROST_COMMIT" "$OUTPUT_DIR"
