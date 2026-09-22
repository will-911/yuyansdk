# Third-party dictionary notice

## rime-frost（白霜拼音）

- Project: https://github.com/gaboolic/rime-frost
- Author/maintainer: gaboolic and contributors
- License: GNU General Public License v3.0
- Exact source revision and verified archive: [`frost.lock`](frost.lock)
- Local modifications: the build adapter renames the main dictionary to `pinyin`, enables the optional cleaned `cn_dicts/tencent` vocabulary, maps upstream schemas to Yuyan's stable schema IDs, and generates T9/LX17/ZX17 aliases from Yuyan's keyboard maps.

The generated `pinyin.table.bin` and related prisms must be distributed together with access to this Corresponding Source and the build scripts in this directory. No warranty is provided by the upstream authors or contributors.
