"""BLK.DAT 解码器与地图渲染。

BLK.DAT 结构（本机验证）：

    0x0000  512 B   Index[16] × (u32 offset, u32 length)
    0x0200   ...    Data：16 套 tile 位图

* offset 同样相对 Data 区（0x200）。
* 每套 tile 是 48×48×1 B = 2,304 B，8bpp 索引。
* 16 套中 7 套各 512 tiles、7 套各 468 tiles、2 套为空（dlz-08 / dlz-10）；
  共 6,860 tiles，Data 区 15,805,440 B。
* MAP.DAT 的 `dlz-XX.blk` 指向第 XX 套；47 张图的 tile 低 12 位全部落在
  对应套的 tile 数内（强校验）。

渲染：用 IMG 的通用调色板（见 palette.py）。MAP 的 tile 高 4 位是地形号，
低 12 位是 tile 索引；当前渲染只用低 12 位。
"""

from __future__ import annotations

import math
import struct
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from .mapdat import MapRecord, TILE_BYTES, TILE_SIZE

INDEX_ENTRY = struct.Struct("<II")
INDEX_SLOTS = 64
INDEX_SIZE = INDEX_SLOTS * INDEX_ENTRY.size  # 512
SET_COUNT = 16


@dataclass(frozen=True)
class BlkSet:
    index: int
    offset: int
    length: int

    @property
    def tile_count(self) -> int:
        return self.length // TILE_BYTES

    @property
    def name(self) -> str:
        return f"dlz-{self.index:02d}.blk"

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "name": self.name,
            "offset": self.offset,
            "length": self.length,
            "tile_count": self.tile_count,
        }


@dataclass(frozen=True)
class BlkFile:
    sets: tuple[BlkSet, ...]
    data_offset: int
    data: bytes

    def __len__(self) -> int:
        return len(self.sets)

    def tile(self, set_index: int, tile_index: int) -> bytes:
        if not 0 <= set_index < len(self.sets):
            raise ValueError(f"BLK 套 {set_index} 越界")
        s = self.sets[set_index]
        if not 0 <= tile_index < s.tile_count:
            raise ValueError(
                f"BLK {s.name} tile {tile_index} 越界（0..{s.tile_count - 1}）"
            )
        start = self.data_offset + s.offset + tile_index * TILE_BYTES
        return self.data[start:start + TILE_BYTES]

    def as_dict(self) -> dict:
        return {
            "index_size": INDEX_SIZE,
            "index_slots": INDEX_SLOTS,
            "set_count": SET_COUNT,
            "data_offset": self.data_offset,
            "data_length": len(self.data) - self.data_offset,
            "tile_size": [TILE_SIZE, TILE_SIZE],
            "tile_bytes": TILE_BYTES,
            "sets": [s.as_dict() for s in self.sets],
        }


def parse(blob: bytes) -> BlkFile:
    if len(blob) < INDEX_SIZE:
        raise ValueError(f"BLK.DAT 太短：{len(blob)} B")
    slots = [INDEX_ENTRY.unpack_from(blob, i * INDEX_ENTRY.size)
             for i in range(INDEX_SLOTS)]
    pairs = slots[:SET_COUNT]
    expected = 0
    sets: list[BlkSet] = []
    for i, (rel, length) in enumerate(pairs):
        if rel != expected:
            raise ValueError(f"BLK 第 {i} 套 offset={rel}，期望 {expected}")
        if length % TILE_BYTES:
            raise ValueError(f"BLK 第 {i} 套长度 {length} 不是 {TILE_BYTES} 的整数倍")
        if INDEX_SIZE + rel + length > len(blob):
            raise ValueError(f"BLK 第 {i} 套越过文件尾")
        sets.append(BlkSet(i, rel, length))
        expected += length

    if INDEX_SIZE + expected != len(blob):
        raise ValueError(
            f"BLK Data 区 {expected} B 与文件剩余 {len(blob) - INDEX_SIZE} B 不符"
        )
    for i, (rel, length) in enumerate(slots[SET_COUNT:], start=SET_COUNT):
        if length or rel not in (0, expected):
            raise ValueError(
                f"BLK 未使用的索引槽 {i} 异常：({rel}, {length})，"
                f"期望 (0 或 {expected}, 0)"
            )
    return BlkFile(tuple(sets), INDEX_SIZE, blob)


def load(path: Path) -> BlkFile:
    return parse(path.read_bytes())


def render_map(map_rec: MapRecord, blk: BlkFile, palette: bytes,
               scale: int = 1) -> Image.Image:
    """把一张 MAP 渲染成 P 模式索引图（palette 为 768 B RGB）。"""
    set_index = map_rec.tileset_index
    if not 0 <= set_index < len(blk.sets):
        raise ValueError(f"地图 {map_rec.index} 引用不存在的 BLK 套 {set_index}")
    tile_set = blk.sets[set_index]
    width = map_rec.width * TILE_SIZE
    height = map_rec.height * TILE_SIZE
    image = Image.new("P", (width, height))
    image.putpalette(palette)
    for ty in range(map_rec.height):
        for tx in range(map_rec.width):
            tile_id = map_rec.tiles[ty * map_rec.width + tx] & 0x0FFF
            if tile_id >= tile_set.tile_count:
                raise ValueError(
                    f"地图 {map_rec.index} ({tx},{ty}) tile {tile_id} "
                    f"越界 {tile_set.name}（{tile_set.tile_count}）"
                )
            raw = blk.tile(set_index, tile_id)
            tile = Image.frombytes("P", (TILE_SIZE, TILE_SIZE), raw)
            tile.putpalette(palette)
            image.paste(tile, (tx * TILE_SIZE, ty * TILE_SIZE))
    if scale != 1:
        image = image.resize((width * scale, height * scale), Image.NEAREST)
    return image


def save_map_png(map_rec: MapRecord, blk: BlkFile, palette: bytes,
                 dest: Path, scale: int = 1) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    render_map(map_rec, blk, palette, scale=scale).save(dest)
    return dest


def save_tilesheet(blk: BlkFile, set_index: int, palette: bytes, dest: Path,
                   columns: int = 32, scale: int = 1) -> Path:
    """把一套 BLK 的全部 tile 排成 contact sheet。"""
    s = blk.sets[set_index]
    count = s.tile_count
    rows = max(1, math.ceil(count / columns))
    sheet = Image.new("P", (columns * TILE_SIZE, rows * TILE_SIZE))
    sheet.putpalette(palette)
    for i in range(count):
        tile = Image.frombytes("P", (TILE_SIZE, TILE_SIZE),
                               blk.tile(set_index, i))
        tile.putpalette(palette)
        sheet.paste(tile, ((i % columns) * TILE_SIZE,
                           (i // columns) * TILE_SIZE))
    if scale != 1:
        sheet = sheet.resize(
            (sheet.width * scale, sheet.height * scale), Image.NEAREST
        )
    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dest)
    return dest
