"""MAP.DAT 解码器。

文件结构（本机 47 张图全部逐字节验证）：

    0x0000  512 B   Index[64] × (u32 offset, u32 length)
    0x0200   ...    Data[47]：
                    u16 width
                    u16 height
                    char blk_name[12]   GBK，如 "dlz-11.blk"
                    char pal_name[12]   GBK，如 "dlz-01.pal"
                    u16 tiles[width * height]

关键点：**Index 里的 offset 是相对 Data 区（0x200）的偏移**，不是文件绝对偏移。
第 0 张图 offset=0、length=1068；第 47 项起 offset=120178 (= 文件长度 - 512)、
length=0。

校验：每张图 `length == 28 + width * height * 2`，47 张首尾相接地铺满 Data 区
（120,178 B）。尺寸范围 width 18..65、height 15..60。

tile 值：高 4 位 = 地形号（模板结论），低 12 位 = 对应 BLK 套内的 tile 索引；
47 张图的低 12 位全部小于对应 BLK 套的 tile 数。
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

INDEX_ENTRY = struct.Struct("<II")
INDEX_SLOTS = 64
INDEX_SIZE = INDEX_SLOTS * INDEX_ENTRY.size  # 512
MAP_COUNT = 47
NAME_SIZE = 12
HEADER_SIZE = 4 + NAME_SIZE + NAME_SIZE  # 28
TILE_SIZE = 48
TILE_BYTES = TILE_SIZE * TILE_SIZE


def _text(raw: bytes) -> str:
    return raw.split(b"\x00", 1)[0].decode("gb18030", errors="replace")


@dataclass(frozen=True)
class MapRecord:
    index: int
    offset: int
    length: int
    width: int
    height: int
    blk_name: str
    pal_name: str
    tiles: tuple[int, ...]

    @property
    def tileset_index(self) -> int:
        """`dlz-11.blk` → 11。"""
        stem = self.blk_name.rsplit(".", 1)[0]
        return int(stem.rsplit("-", 1)[1])

    @property
    def tile_count(self) -> int:
        return self.width * self.height

    def as_dict(self, include_tiles: bool = True) -> dict:
        data = {
            "index": self.index,
            "offset": self.offset,
            "length": self.length,
            "width": self.width,
            "height": self.height,
            "pixel_width": self.width * TILE_SIZE,
            "pixel_height": self.height * TILE_SIZE,
            "blk": self.blk_name,
            "pal": self.pal_name,
            "tileset": self.tileset_index,
        }
        if include_tiles:
            data["tiles"] = list(self.tiles)
        return data


@dataclass(frozen=True)
class MapFile:
    slots: tuple[tuple[int, int], ...]
    maps: tuple[MapRecord, ...]

    def __len__(self) -> int:
        return len(self.maps)


def parse(blob: bytes) -> MapFile:
    if len(blob) < INDEX_SIZE:
        raise ValueError(f"MAP.DAT 太短：{len(blob)} B")
    slots = tuple(INDEX_ENTRY.unpack_from(blob, i * INDEX_ENTRY.size)
                  for i in range(INDEX_SLOTS))
    used = [(i, off, length) for i, (off, length) in enumerate(slots) if length]
    if len(used) != MAP_COUNT:
        raise ValueError(f"有效索引 {len(used)} != {MAP_COUNT}")

    maps: list[MapRecord] = []
    expected = 0
    for i, rel, length in used:
        if rel != expected:
            raise ValueError(f"第 {i} 张图 offset={rel}，期望 {expected}（索引不连续）")
        expected += length
        start = INDEX_SIZE + rel
        end = start + length
        if end > len(blob):
            raise ValueError(f"第 {i} 张图越过文件尾：{end} > {len(blob)}")
        width, height = struct.unpack_from("<HH", blob, start)
        blk_name = _text(blob[start + 4:start + 4 + NAME_SIZE])
        pal_name = _text(blob[start + 4 + NAME_SIZE:start + HEADER_SIZE])
        need = HEADER_SIZE + width * height * 2
        if need != length:
            raise ValueError(
                f"第 {i} 张图 {width}×{height} 需要 {need} B，索引写 {length} B"
            )
        tiles = struct.unpack_from(f"<{width * height}H", blob, start + HEADER_SIZE)
        maps.append(MapRecord(i, rel, length, width, height,
                              blk_name, pal_name, tuple(tiles)))

    if INDEX_SIZE + expected != len(blob):
        raise ValueError(f"Data 区 {expected} B 与文件剩余 {len(blob) - INDEX_SIZE} B 不符")
    return MapFile(slots=slots, maps=tuple(maps))


def load(path: Path) -> MapFile:
    return parse(path.read_bytes())
