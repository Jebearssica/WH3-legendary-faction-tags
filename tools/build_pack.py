#!/usr/bin/env python3
"""把 src/ 打包成 Total War: WARHAMMER III 可读的 .pack (PFH5)。

游戏未安装也能用：这是纯 Python 的 PFH5 写入器，不需要 RPFM。
格式依据 rpfm_lib 的 read_pfh5/write_pfh5
(rpfm_lib/src/files/pack/pack_versions/pfh5.rs)：

    header (28 bytes, little-endian)
        "PFH5"      4s
        bitmask     u32   (3 = Mod)
        packs_count u32
        packs_size  u32
        files_count u32
        files_size  u32
        timestamp   u32
    file index
        per file: size u32, is_compressed u8(0), path utf-8 + NUL  (反斜杠, 按小写路径排序)
    file data
        与 index 同序拼接的原始字节

用法:
    python tools/build_pack.py
    python tools/build_pack.py --src src --out build/legendary_faction_tags.pack
"""

from __future__ import annotations

import argparse
import struct
import sys
import time
from pathlib import Path

PFH5_MAGIC = b"PFH5"
PACK_TYPE_MOD = 3
HEADER_SIZE = 28


def collect(src: Path) -> list[tuple[str, Path]]:
    """返回 [(包内路径, 磁盘路径)]，按包内路径小写排序（与 RPFM 一致）。"""
    files: list[tuple[str, Path]] = []
    for disk_path in src.rglob("*"):
        if not disk_path.is_file():
            continue
        rel = disk_path.relative_to(src).as_posix()
        files.append((rel, disk_path))
    files.sort(key=lambda item: item[0].lower())
    return files


def encode(files: list[tuple[str, Path]]) -> bytes:
    index = bytearray()
    payloads: list[bytes] = []
    for rel, disk_path in files:
        data = disk_path.read_bytes()
        payloads.append(data)
        index += struct.pack("<I", len(data))
        index += b"\x00"  # is_compressed = false
        index += rel.replace("/", "\\").encode("utf-8") + b"\x00"

    header = PFH5_MAGIC + struct.pack(
        "<6I",
        PACK_TYPE_MOD,      # bitmask: Mod
        0,                  # 依赖包数量
        0,                  # 依赖索引字节数
        len(files),         # 文件数量
        len(index),         # 文件索引字节数
        int(time.time()),
    )
    assert len(header) == HEADER_SIZE
    return bytes(header) + bytes(index) + b"".join(payloads)


def verify(pack_path: Path, files: list[tuple[str, Path]]) -> None:
    """独立重读一遍产物，逐文件比对内容。"""
    blob = pack_path.read_bytes()
    if blob[:4] != PFH5_MAGIC:
        raise SystemExit(f"FAIL: 不是 PFH5 容器 ({blob[:4]!r})")
    bitmask, dep_count, dep_size, file_count, index_size, _ts = struct.unpack_from("<6I", blob, 4)
    if dep_count or dep_size:
        raise SystemExit("FAIL: 本工具不写依赖包，但头部出现依赖索引")
    if file_count != len(files):
        raise SystemExit(f"FAIL: 文件数量不一致 ({file_count} != {len(files)})")

    data_start = HEADER_SIZE + index_size
    expected = {rel.replace("/", "\\"): (disk.read_bytes(), None) for rel, disk in files}
    seen = set()
    pos = HEADER_SIZE
    cursor = data_start
    for _ in range(file_count):
        (size,) = struct.unpack_from("<I", blob, pos)
        pos += 4
        compressed = blob[pos]
        pos += 1
        end = blob.index(b"\x00", pos)
        path = blob[pos:end].decode("utf-8")
        pos = end + 1
        if compressed:
            raise SystemExit(f"FAIL: {path} 标记为压缩，本工具不应写入压缩数据")
        if path not in expected:
            raise SystemExit(f"FAIL: 包内出现未知路径 {path}")
        content = expected[path][0]
        if size != len(content):
            raise SystemExit(f"FAIL: {path} 大小不一致 ({size} != {len(content)})")
        if blob[cursor:cursor + size] != content:
            raise SystemExit(f"FAIL: {path} 内容不一致")
        cursor += size
        seen.add(path)
    if len(seen) != len(expected):
        raise SystemExit("FAIL: 有源文件没有写进包")
    if cursor != len(blob):
        raise SystemExit("FAIL: 数据区长度与索引不符")
    print(f"OK: {pack_path.name}  {len(blob):,} bytes  {file_count} files  bitmask={bitmask}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", default="src")
    parser.add_argument("--out", default="build/legendary_faction_tags.pack")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    src = (root / args.src).resolve()
    out = (root / args.out).resolve()
    if not src.is_dir():
        raise SystemExit(f"FAIL: 源目录不存在 {src}")

    files = collect(src)
    if not files:
        raise SystemExit(f"FAIL: {src} 下没有文件")
    print(f"源文件 {len(files)} 个:")
    for rel, _ in files:
        print(f"  + {rel}")

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(encode(files))
    verify(out, files)
    return 0


if __name__ == "__main__":
    sys.exit(main())
