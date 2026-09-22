# Reproducible Rime assets

Yuyan uses the upstream [rime-frost](https://github.com/gaboolic/rime-frost) dictionary. The generated files retain Yuyan's stable schema IDs (`pinyin`, `t9_pinyin`, the standard double-pinyin IDs, `double_pinyin_ls17`, and `double_pinyin_zx17`).

The adapter uses Frost's complete mobile profile: all dictionaries enabled by upstream plus the optional cleaned `cn_dicts/tencent` vocabulary, preserving Yuyan's existing large-dictionary coverage.

## Reproducibility contract

- `frost.lock` pins the exact upstream commit, archive SHA-256, and librime version.
- `pinyin.table.bin` and every pinyin `*.prism.bin` are compiled in one invocation from the same source tree.
- T9/LX17/ZX17 keep lowercase full-pinyin aliases for Yuyan's pinyin-selection protocol.
- `verify-rime-assets.py` rejects mixed dictionary checksums, mixed syllable inventories, wrong compiler versions, and an accidentally copied LX17 prism.
- `rime-assets-manifest.json` records the source revision and every generated artifact hash.

The pinned compiler environment is Alpine 3.20 with `librime-tools=1.11.2-r0`, matching the librime 1.11.2 format reported by Yuyan's packaged schemas. GitHub Actions is the canonical build environment; do not commit artifacts made by an unpinned local librime.

## Build

Inside the pinned container:

```bash
apk add --no-cache bash curl python3 librime-tools=1.11.2-r0
cd yuyansdk
./rime-source/build-rime-assets.sh
```

Or from a Linux host with Docker:

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  -w /workspace/yuyansdk \
  alpine:3.20 \
  sh -c 'apk add --no-cache bash curl python3 librime-tools=1.11.2-r0 && ./rime-source/build-rime-assets.sh'
```

The default output directory is `src/main/assets/rime/build`. An alternate output directory can be supplied as the first argument.

## Update rime-frost

```bash
./rime-source/update-frost-lock.sh
```

This resolves current `rime-frost/master`, downloads the commit archive, verifies it locally, and rewrites `frost.lock`. Review the upstream changes and commit the lock update. CI always builds the pinned revision; it never silently follows a moving branch.

## Licensing and source availability

rime-frost is distributed under GPL-3.0. Its exact Corresponding Source is the commit and verified archive URL in `frost.lock`. See `THIRD_PARTY.md` for attribution. YuyanIme itself is GPL-3.0; the SDK's other source files retain their existing licenses.
