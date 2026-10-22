"""GAME.DAT 解码器。

整文件 56,588 B，分段布局（段偏移来自 dlz_research 的 `dlz_game.bt`，MIT；
本机用「逐段长度累加 == 文件长度」和「每段首记录 GBK 名字」两条独立证据复核）：

    0x0000   160 B   What0（未解析）
    0x00A0   320 B   DiXingModifier[16] × 20 B（未导出）
    0x01E0 15360 B   BingZhong[96] × 160 B      —— 兵种
    0x3DE0  1536 B   BingZhongYiDong[96] × 16 B —— 每兵种 16 地形移动消耗
    0x43E0 11520 B   WuPin[160] × 72 B          —— 物品
    0x70E0   280 B   Material[10] × 28 B        —— 材料
    0x71F8   100 B   DiLeiRecipe[10] × 10 B     —— 地雷配方
    0x725C   480 B   DiLei[10] × 48 B           —— 地雷
    0x743C   768 B   JiNeng[16] × 48 B          —— 技能
    0x773C  1296 B   SelectFanwei[16] × 81 B    —— 9×9 选择范围
    0x7C4C  9408 B   ApplyFanWei[48] × 196 B    —— 7×7 应用范围
    0xA10C 15360 B   WuPinValid[160] × 96 B     —— 物品×兵种可用矩阵

校验：0xA10C + 15360 = 56,588 = 文件长度。
每段第一条的名字分别是「神仙队」「蟠桃」「粘土」「补给」「土雷」。

注意：`dlzr`（同一项目的 C++ 重写）里 Material / DiLeiRecipe 的偏移自相矛盾，
本解码器以模板推导 + 本机长度校验为准，不采用其代码里的偏移。
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

# 段偏移
WHAT0_OFFSET = 0x0000
TERRAIN_MOD_OFFSET = 0x00A0
UNIT_OFFSET = 0x01E0
UNIT_COUNT = 96
UNIT_SIZE = 160
UNIT_MOVE_OFFSET = 0x3DE0
UNIT_MOVE_COUNT = 96
UNIT_MOVE_SIZE = 16
ITEM_OFFSET = 0x43E0
ITEM_COUNT = 160
ITEM_SIZE = 72
MATERIAL_OFFSET = 0x70E0
MATERIAL_COUNT = 10
MATERIAL_SIZE = 28
RECIPE_OFFSET = 0x71F8
RECIPE_COUNT = 10
RECIPE_SIZE = 10
MINE_OFFSET = 0x725C
MINE_COUNT = 10
MINE_SIZE = 48
SKILL_OFFSET = 0x743C
SKILL_COUNT = 16
SKILL_SIZE = 48
SELECT_OFFSET = 0x773C
SELECT_COUNT = 16
SELECT_SIZE = 81
APPLY_OFFSET = 0x7C4C
APPLY_COUNT = 48
APPLY_SIZE = 196
VALID_OFFSET = 0xA10C
VALID_COUNT = 160
VALID_SIZE = 96

# 0x90 起的技能开关，顺序与 JiNeng[16] 一致
SKILL_NAMES = (
    "buji", "jili", "yiliao", "huogong",
    "gunmu", "leishi", "weishe", "saorao",
    "pohuai", "lueduo", "fanjian", "yibing",
    "duzhan", "ansha", "shidu", "kongxi",
)

_UNIT = struct.Struct("<16s16i16I16B")
_ITEM = struct.Struct("<16s8s12i")
_MATERIAL = struct.Struct("<16s8sI")
_MINE = struct.Struct("<16s8i")
_SKILL = struct.Struct("<16s8i")


def _text(raw: bytes) -> str:
    return raw.split(b"\x00", 1)[0].decode("gb18030", errors="replace")


@dataclass
class Unit:
    index: int
    name: str
    img_index: int
    tili: int
    tili_plus: int
    gongji_plus: int
    fangyu_plus: int
    yidong: int
    gongji: int
    fangyu: int
    select: int
    apply: int
    zhuanzhi: int
    zhuanzhidaoju: int
    pad1: int
    flm_gongji: int
    audio_gongji: int
    audio_yidong: int
    reserved: list[int] = field(default_factory=list)
    skills: dict[str, int] = field(default_factory=dict)

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "name": self.name,
            "img_index": self.img_index,
            "tili": self.tili,
            "tili_plus": self.tili_plus,
            "gongji_plus": self.gongji_plus,
            "fangyu_plus": self.fangyu_plus,
            "yidong": self.yidong,
            "gongji": self.gongji,
            "fangyu": self.fangyu,
            "select": self.select,
            "apply": self.apply,
            "zhuanzhi": self.zhuanzhi,
            "zhuanzhidaoju": self.zhuanzhidaoju,
            "pad1": self.pad1,
            "flm_gongji": self.flm_gongji,
            "audio_gongji": self.audio_gongji,
            "audio_yidong": self.audio_yidong,
            "reserved": list(self.reserved),
            "skills": dict(self.skills),
        }


@dataclass
class Item:
    index: int
    name: str
    unit: str
    goods: int
    price: int
    para1: int
    para2: int
    para3: int
    para4: int
    select_fw: int
    apply_fw: int
    pad7: int
    pad8: int
    audio_get: int
    audio_apply: int

    def as_dict(self) -> dict:
        d = dict(self.__dict__)
        return d


@dataclass
class Material:
    index: int
    name: str
    unit: str
    price: int

    def as_dict(self) -> dict:
        return dict(self.__dict__)


@dataclass
class Mine:
    index: int
    name: str
    price: int
    weili: int
    shiqi_or_tili: int
    apply_fw: int
    pad3: int
    pad4: int
    flm_index: int
    audio_index: int

    def as_dict(self) -> dict:
        return dict(self.__dict__)


@dataclass
class Skill:
    index: int
    name: str
    para1: int
    para2: int
    type: int
    select_fw: int
    apply_fw: int
    anm_index: int
    flm_index: int
    audio_index: int

    def as_dict(self) -> dict:
        return dict(self.__dict__)


@dataclass
class Game:
    units: list[Unit]
    unit_move: list[list[int]]
    items: list[Item]
    materials: list[Material]
    mine_recipes: list[list[int]]
    mines: list[Mine]
    skills: list[Skill]
    select_ranges: list[list[list[int]]]
    apply_ranges: list[list[list[int]]]
    item_valid: list[list[int]]

    def as_dict(self) -> dict:
        return {
            "units": [u.as_dict() for u in self.units],
            "unit_move": self.unit_move,
            "items": [i.as_dict() for i in self.items],
            "materials": [m.as_dict() for m in self.materials],
            "mine_recipes": self.mine_recipes,
            "mines": [m.as_dict() for m in self.mines],
            "skills": [s.as_dict() for s in self.skills],
            "select_ranges": self.select_ranges,
            "apply_ranges": self.apply_ranges,
            "item_valid": self.item_valid,
        }


def parse(blob: bytes) -> Game:
    units = []
    for i in range(UNIT_COUNT):
        off = UNIT_OFFSET + i * UNIT_SIZE
        name, *rest = _UNIT.unpack_from(blob, off)
        stats = rest[:16]
        reserved = rest[16:32]
        skills = rest[32:]
        units.append(Unit(i, _text(name), *stats, list(reserved),
                          dict(zip(SKILL_NAMES, skills))))

    unit_move = [list(blob[UNIT_MOVE_OFFSET + i * UNIT_MOVE_SIZE:
                           UNIT_MOVE_OFFSET + (i + 1) * UNIT_MOVE_SIZE])
                 for i in range(UNIT_MOVE_COUNT)]

    items = []
    for i in range(ITEM_COUNT):
        off = ITEM_OFFSET + i * ITEM_SIZE
        name, unit, *vals = _ITEM.unpack_from(blob, off)
        items.append(Item(i, _text(name), _text(unit), *vals))

    materials = []
    for i in range(MATERIAL_COUNT):
        off = MATERIAL_OFFSET + i * MATERIAL_SIZE
        name, unit, price = _MATERIAL.unpack_from(blob, off)
        materials.append(Material(i, _text(name), _text(unit), price))

    mine_recipes = [list(blob[RECIPE_OFFSET + i * RECIPE_SIZE:
                              RECIPE_OFFSET + (i + 1) * RECIPE_SIZE])
                    for i in range(RECIPE_COUNT)]

    mines = []
    for i in range(MINE_COUNT):
        off = MINE_OFFSET + i * MINE_SIZE
        name, *vals = _MINE.unpack_from(blob, off)
        mines.append(Mine(i, _text(name), *vals))

    skills = []
    for i in range(SKILL_COUNT):
        off = SKILL_OFFSET + i * SKILL_SIZE
        name, *vals = _SKILL.unpack_from(blob, off)
        skills.append(Skill(i, _text(name), *vals))

    select_ranges = []
    for i in range(SELECT_COUNT):
        raw = blob[SELECT_OFFSET + i * SELECT_SIZE:
                   SELECT_OFFSET + (i + 1) * SELECT_SIZE]
        select_ranges.append([list(raw[r * 9:(r + 1) * 9]) for r in range(9)])

    apply_ranges = []
    for i in range(APPLY_COUNT):
        raw = blob[APPLY_OFFSET + i * APPLY_SIZE:
                   APPLY_OFFSET + (i + 1) * APPLY_SIZE]
        flat = struct.unpack("<49i", raw)
        apply_ranges.append([list(flat[r * 7:(r + 1) * 7]) for r in range(7)])

    item_valid = [list(blob[VALID_OFFSET + i * VALID_SIZE:
                            VALID_OFFSET + (i + 1) * VALID_SIZE])
                  for i in range(VALID_COUNT)]

    return Game(units, unit_move, items, materials, mine_recipes,
                mines, skills, select_ranges, apply_ranges, item_valid)


def load(path: Path) -> Game:
    blob = path.read_bytes()
    if len(blob) != VALID_OFFSET + VALID_COUNT * VALID_SIZE:
        raise ValueError(
            f"{path.name}: 长度 {len(blob)} != 预期 "
            f"{VALID_OFFSET + VALID_COUNT * VALID_SIZE}"
        )
    return parse(blob)