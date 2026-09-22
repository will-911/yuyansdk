#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == *.bin ]]; then
  echo "Refusing a prism-only output: pass an asset directory and install the complete set." >&2
  exit 2
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "ZX17 is built together with the shared rime-frost table and every pinyin prism." >&2
exec "$SOURCE_DIR/build-rime-assets.sh" "$@"
