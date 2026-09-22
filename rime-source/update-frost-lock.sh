#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frost.lock
source "$SOURCE_DIR/frost.lock"

commit_info="$(python3 - <<'PY'
import json
import os
import urllib.request

request = urllib.request.Request(
    "https://api.github.com/repos/gaboolic/rime-frost/commits/master",
    headers={"Accept": "application/vnd.github+json", "User-Agent": "yuyan-rime-builder"},
)
token = os.environ.get("GITHUB_TOKEN")
if token:
    request.add_header("Authorization", f"Bearer {token}")
with urllib.request.urlopen(request) as response:
    commit = json.load(response)
print(commit["sha"], commit["commit"]["committer"]["date"])
PY
)"

commit="${commit_info%% *}"
commit_date="${commit_info#* }"
archive_url="https://github.com/gaboolic/rime-frost/archive/$commit.tar.gz"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/yuyan-rime"
archive="$cache_root/rime-frost-$commit.tar.gz"
mkdir -p "$cache_root"
curl --fail --location --retry 3 --output "$archive.tmp" "$archive_url"
mv "$archive.tmp" "$archive"
archive_sha="$(sha256sum "$archive" | cut -d' ' -f1)"

cat > "$SOURCE_DIR/frost.lock" <<EOF
# Pinned upstream used to build Yuyan's pinyin table and prisms.
# Run update-frost-lock.sh to resolve a newer rime-frost master commit.
FROST_REPOSITORY="$FROST_REPOSITORY"
FROST_COMMIT="$commit"
FROST_ARCHIVE_SHA256="$archive_sha"
FROST_ARCHIVE_URL="$archive_url"
FROST_COMMIT_DATE="$commit_date"
RIME_BUILD_CONTAINER="$RIME_BUILD_CONTAINER"
RIME_COMPILER_PACKAGE="$RIME_COMPILER_PACKAGE"
RIME_COMPILER_VERSION="$RIME_COMPILER_VERSION"
EOF

printf 'Pinned rime-frost %s (%s)\n' "$commit" "$commit_date"
