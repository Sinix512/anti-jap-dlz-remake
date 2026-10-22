"""TOWN.DAT 解码器。

19 个城镇 × 346 B（6,574 = 19 × 346）。

346 B = 81 个 int32（324 B）+ 11 个 u16（22 B）。

本机已复核：
  * `goods_junxie[12]` 的取值都在 81..142，正好落在 GAME.DAT WuPin 的武器区；
  * `goods_zahuo[12]` 的取值都在 1..80，落在食物/书籍区；
  * `goods_material[12]` 的取值都在 0..9，正好是 Material[10] 的索引；
  * `goods_what[10]` 19 个城镇全是 -1（GAME.DAT 里也只有 10 种材料，
    模板注释称「代码里没有使用」，与本机一致）。

⚠️ 前 11 个 int32（0, -1 和 3 组三元组）与 name_x/name_y/offset_x/offset_y
的语义未验证，JSON 里只以 `raw_u32` 原样导出，不冒充坐标/音效。
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

RECORD_SIZE = 346
COUNT = 19
U32_COUNT = 81
FLAG_COUNT = 11

_RAW = struct.Struct("<81i")
_FLAGS = struct.Struct("<11H")

# 各商品列表在 raw_u32 里的切片（模板推算，且已被上面的 ID 范围印证）
GOODS_WHAT = slice(35, 45)
GOODS_JUNXIE = slice(45, 57)
GOODS_ZAHUO = slice(57, 69)
GOODS_MATERIAL = slice(69, 81)


@dataclass
class Town:
    index: int
    raw_u32: list[int] = field(default_factory=list)
    flags: list[int] = field(default_factory=list)

    @property
    def goods_what(self) -> list[int]:
        return self.raw_u32[GOODS_WHAT]

    @property
    def goods_junxie(self) -> list[int]:
        return self.raw_u32[GOODS_JUNXIE]

    @property
    def goods_zahuo(self) -> list[int]:
        return self.raw_u32[GOODS_ZAHUO]

    @property
    def goods_material(self) -> list[int]:
        return self.raw_u32[GOODS_MATERIAL]

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "goods_what": self.goods_what,
            "goods_junxie": self.goods_junxie,
            "goods_zahuo": self.goods_zahuo,
            "goods_material": self.goods_material,
            "flags": list(self.flags),
            "raw_u32": list(self.raw_u32),
        }


def parse_record(index: int, rec: bytes) -> Town:
    if len(rec) != RECORD_SIZE:
        raise ValueError(f"城镇记录长度 {len(rec)} != {RECORD_SIZE}")
    raw = list(_RAW.unpack_from(rec, 0))
    flags = list(_FLAGS.unpack_from(rec, U32_COUNT * 4))
    return Town(index=index, raw_u32=raw, flags=flags)


def load(path: Path) -> list[Town]:
    blob = path.read_bytes()
    if len(blob) % RECORD_SIZE:
        raise ValueError(f"{path.name}: {len(blob)} 不是 {RECORD_SIZE} 的整数倍")
    return [parse_record(i, blob[i * RECORD_SIZE:(i + 1) * RECORD_SIZE])
            for i in range(len(blob) // RECORD_SIZE)]