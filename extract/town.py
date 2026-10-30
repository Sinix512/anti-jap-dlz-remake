"""TOWN.DAT 解码器。

19 个城镇 × 346 B（6,574 = 19 × 346）。

346 B = 81 个 int32（324 B）+ 11 个 u16（22 B）。

本机已复核：
  * `goods_junxie[12]` 的取值都在 81..142，正好落在 GAME.DAT WuPin 的武器区；
  * `goods_zahuo[12]` 的取值都在 1..80，落在食物/书籍区；
  * `goods_material[10]` 对应原杂货铺的 5×2 材料货单。此前仅按值域
    错推为 12 项，把后面两个零 DWORD 当作 material0，产生两份粘土。
    K01 合同已确认只读 10 项（原版 K01 商店读取契约）；
    尾部两 DWORD 的语义未定，仍完整保留在 raw_u32 中；
  * `goods_what[10]` 19 个城镇全是 -1（GAME.DAT 里也只有 10 种材料，
    模板注释称「代码里没有使用」，与本机一致）。

前 35 个 int32 的布局（模板推导 + 本机值域复核）：

    0x00  i32 pad0（恒 0）
    0x04  i32 pad1（恒 -1）
    0x08  3 × (i32 wave_id, i32 x, i32 y)   3 个环境音热点，wave_id 落在
                                             WAVE.DAT 的 800 段（803/808/812 等）
    0x2C  6 × i32 building_label_x
    0x44  6 × i32 building_label_y
    0x5C  6 × i32 building_offset_x
    0x74  6 × i32 building_offset_y

6 个建筑槽位的模板顺序是 民房 / 指挥部 / 军械部 / 杂货铺 / 出口 / 作坊；
本机只能证明「槽位数量 = 6、坐标在 640×480 内、小城镇只启用部分槽位」，
顺序本身未独立验证，所以 JSON 里保留 `slot` 数字，同时给出候选名。
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

# 商品字段宽度：军械/杂货各 12 项，材料 10 项；不可仅凭尾部零值推宽。
GOODS_WHAT = slice(35, 45)
GOODS_JUNXIE = slice(45, 57)
GOODS_ZAHUO = slice(57, 69)
GOODS_MATERIAL = slice(69, 79)

# 前 35 个 int32
PAD = slice(0, 2)
SOUND_HOTSPOTS = slice(2, 11)
BUILDING_LABEL_X = slice(11, 17)
BUILDING_LABEL_Y = slice(17, 23)
BUILDING_OFFSET_X = slice(23, 29)
BUILDING_OFFSET_Y = slice(29, 35)
BUILDING_SLOTS = ("民房", "指挥部", "军械部", "杂货铺", "出口", "作坊")

# DLZ.exe 0x45058 起的 19 个地名，顺序与 TOWN.DAT / PLACE.DAT 的 19 条记录一致；
# 已用 PLACE 背景图里烧进画面的地名逐条比对。
TOWN_NAMES = (
    "桃花岭", "赵　村", "花坪镇", "李　村", "土　桥", "白洋淀",
    "萧家庄", "冉　庄", "枣　庄", "阳　村", "清风寨", "鸡公山",
    "太平镇", "黑风寨", "长　湾", "施南镇", "红岩镇", "平阳县", "天池山",
)


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

    @property
    def sound_hotspots(self) -> list[dict]:
        values = self.raw_u32[SOUND_HOTSPOTS]
        return [
            {"wave": values[i * 3], "x": values[i * 3 + 1], "y": values[i * 3 + 2]}
            for i in range(3)
        ]

    @property
    def buildings(self) -> list[dict]:
        label_x = self.raw_u32[BUILDING_LABEL_X]
        label_y = self.raw_u32[BUILDING_LABEL_Y]
        offset_x = self.raw_u32[BUILDING_OFFSET_X]
        offset_y = self.raw_u32[BUILDING_OFFSET_Y]
        return [
            {
                "slot": i,
                "name_guess": BUILDING_SLOTS[i],
                "label_x": label_x[i],
                "label_y": label_y[i],
                "offset_x": offset_x[i],
                "offset_y": offset_y[i],
            }
            for i in range(6)
        ]

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "name": TOWN_NAMES[self.index],
            "sound_hotspots": self.sound_hotspots,
            "buildings": self.buildings,
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
