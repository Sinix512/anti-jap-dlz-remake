"""FIGHT.DAT 解码器。

47 关 × 20,508 B（963,876 = 47 × 20,508），每关三段：

    0x0000  700 B    Intro：关卡名 / 难度 / 胜负文本 / 宝箱 / 特殊位置
    0x02BC  8192 B   Fighter[128] × 64 B
    0x22BC  11616 B  People[88] × 132 B —— 与 PEOPLE.DAT 同构

本机已解出的 Intro 布局（700 B 全部有着落）：

    0x000  char[32]   关卡名
    0x020  u32        模板称 difficulty（未独立验证）
    0x024  u32        模板称 fight_txt（未独立验证）
    0x028  char[64]   胜利文本
    0x068  char[64]   失败文本
    0x0A8  Chest[4] × 28 B：
           x, y, appearance(0..2), wupin, wupin0, wupin1, wupin2
    0x118  u32        special_count（多数关卡等于特殊位置条数；0/999 例外）
    0x11C  u8[32]     未解析
    0x13C  Special[32] × 12 B：x, y, type(0..3)

Fighter[128] 的槽位映射（本机强验证）：

* `Fighter[0..39]`   ↔ `PEOPLE.DAT[0..39]`（40 个有名角色）
* `Fighter[40..127]` ↔ `People[0..87]`（每关 88 个战场名册）

29 个出场的 `PEOPLE.DAT` 槽中，28 个 `tili`（除孙悟空固定 80）等于
`GAME.BingZhong[people.bingzhong].tili + (people.level - 1) * tili_plus`。
`FIGHT.People` 槽（40..127）的 `tili == 4500` 在 47 关出现 3,807 次
（其中 1,052 条 stage=1），极可能是“HP 未显式设置”的哨兵，不能当作真实 4500 HP；
只有 96/80/1376/212 等少数显式值可直接用，M1 需从战斗初始化代码确认。

Fighter 64 B 字段（本机用 47 张地图边界反推）：

    0x00 i32 pad0（恒 0）
    0x04 i32 tili                 当前体力；4500 在 40..127 槽多为哨兵，见下文
    0x08 i32 unknown_08（恒 100）
    0x0C i32 unknown_0c（恒 100）
    0x10 i32 unknown_10（恒 100）
    0x14 i32 pos_x                0..地图宽-1
    0x18 i32 pos_y                0..地图高-1
    0x1C i32 direction            0..3
    0x20 i32 dest_x               == pos_x（初始态）
    0x24 i32 dest_y               == pos_y
    0x28 i32 dest_direction       == direction
    0x2C i32 target_slot          0 或某个出场槽位
    0x30 i32 target_x             0..地图宽-1
    0x34 i32 target_y             0..地图高-1
    0x38 i32 pad38（恒 -1）
    0x3C u8  stage                1 = 出场
    0x3D u8  behavior             0..13
    0x3E u8  pad3e
    0x3F u8  moveable             基地数据里恒 0（运行时字段）
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

from . import people

LEVEL_COUNT = 47
LEVEL_SIZE = 20508
INTRO_SIZE = 700
FIGHTER_OFFSET = 700
FIGHTER_COUNT = 128
FIGHTER_SIZE = 64
PEOPLE_OFFSET = INTRO_SIZE + FIGHTER_COUNT * FIGHTER_SIZE  # 8892 = 0x22BC
PEOPLE_COUNT = 88

NAME_SIZE = 0x20
DIFFICULTY_OFFSET = 0x20
FIGHT_TXT_OFFSET = 0x24
SUCCESS_OFFSET = 0x28
SUCCESS_SIZE = 0x40
FAILURE_OFFSET = 0x68
FAILURE_SIZE = 0x40

CHEST_OFFSET = 0xA8
CHEST_COUNT = 4
CHEST_SIZE = 28
SPECIAL_COUNT_OFFSET = 0x118
SPECIAL_UNKNOWN_OFFSET = 0x11C
SPECIAL_UNKNOWN_SIZE = 32
SPECIAL_OFFSET = 0x13C
SPECIAL_COUNT = 32
SPECIAL_SIZE = 12

# Fighter 槽位分界：前 40 个对应 PEOPLE.DAT，后 88 个对应 People[88]
NAMED_SLOTS = 40

_FIGHTER = struct.Struct("<15i4B")
_CHEST = struct.Struct("<7i")
_SPECIAL = struct.Struct("<3i")


def _text(raw: bytes) -> str:
    return raw.split(b"\x00", 1)[0].decode("gb18030", errors="replace")


@dataclass
class Chest:
    index: int
    x: int
    y: int
    appearance: int
    wupin: int
    wupin0: int
    wupin1: int
    wupin2: int

    @property
    def empty(self) -> bool:
        # 真实宝箱坐标都在 0..65 内；99/97/94/999 都是空槽哨兵。
        return self.x >= 90 or self.y >= 90 or not 0 <= self.appearance <= 2

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "x": self.x,
            "y": self.y,
            "appearance": self.appearance,
            "wupin": self.wupin,
            "wupin0": self.wupin0,
            "wupin1": self.wupin1,
            "wupin2": self.wupin2,
            "empty": self.empty,
        }


@dataclass
class SpecialPos:
    index: int
    x: int
    y: int
    type: int

    @property
    def empty(self) -> bool:
        return self.x in (99, 999) and self.y in (99, 999)

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "x": self.x,
            "y": self.y,
            "type": self.type,
            "empty": self.empty,
        }


@dataclass
class Intro:
    difficulty_raw: int
    fight_txt_raw: int
    chests: list[Chest]
    special_count_raw: int
    unknown_11c: list[int]
    special_positions: list[SpecialPos]

    def as_dict(self) -> dict:
        return {
            "difficulty_raw": self.difficulty_raw,
            "fight_txt_raw": self.fight_txt_raw,
            "chests": [c.as_dict() for c in self.chests],
            "special_count_raw": self.special_count_raw,
            "unknown_11c": list(self.unknown_11c),
            "special_positions": [s.as_dict() for s in self.special_positions],
        }


@dataclass
class Fighter:
    slot: int
    pad0: int
    tili: int
    unknown_08: int
    unknown_0c: int
    unknown_10: int
    pos_x: int
    pos_y: int
    direction: int
    dest_x: int
    dest_y: int
    dest_direction: int
    target_slot: int
    target_x: int
    target_y: int
    pad38: int
    stage: int
    behavior: int
    pad3e: int
    moveable: int

    @property
    def active(self) -> bool:
        return self.stage == 1

    @property
    def roster(self) -> str:
        return "people" if self.slot < NAMED_SLOTS else "fight_people"

    @property
    def tili_is_sentinel(self) -> bool:
        """4500 在 40..127 槽大量出现，疑为“HP 未显式设置”的哨兵值。

        47 关共 3,807 条 4500（其中 1,052 条 stage=1）；真实 HP 要等
        战斗初始化代码确认后再解析，不能直接当成 4500 血。
        """
        return self.tili == 4500

    def as_dict(self) -> dict:
        return {
            "slot": self.slot,
            "active": self.active,
            "roster": self.roster,
            "pad0": self.pad0,
            "tili": self.tili,
            "tili_is_sentinel": self.tili_is_sentinel,
            "pos_x": self.pos_x,
            "pos_y": self.pos_y,
            "direction": self.direction,
            "dest_x": self.dest_x,
            "dest_y": self.dest_y,
            "dest_direction": self.dest_direction,
            "target_slot": self.target_slot,
            "target_x": self.target_x,
            "target_y": self.target_y,
            "stage": self.stage,
            "behavior": self.behavior,
            "moveable": self.moveable,
            "unknown_08": self.unknown_08,
            "unknown_0c": self.unknown_0c,
            "unknown_10": self.unknown_10,
            "pad38": self.pad38,
            "pad3e": self.pad3e,
        }


@dataclass
class Level:
    index: int
    name: str
    success: str
    failure: str
    intro: Intro
    people: list[people.Person]
    fighters: list[Fighter] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "name": self.name,
            "success": self.success,
            "failure": self.failure,
            "intro": self.intro.as_dict(),
            "fighters": [f.as_dict() for f in self.fighters],
            "people": [p.as_dict() for p in self.people],
        }

    def roster_names(self, named: list[people.Person] | None = None) -> list[str]:
        """按槽位返回单位名；named 为 PEOPLE.DAT 的 40 人。"""
        if named is None:
            named = []
        names: list[str] = []
        for i in range(FIGHTER_COUNT):
            if i < NAMED_SLOTS:
                names.append(named[i].name if i < len(named) else "")
            else:
                names.append(self.people[i - NAMED_SLOTS].name)
        return names


def parse_intro(rec: bytes) -> Intro:
    if len(rec) < INTRO_SIZE:
        raise ValueError(f"Intro 长度 {len(rec)} < {INTRO_SIZE}")
    difficulty, fight_txt = struct.unpack_from("<II", rec, DIFFICULTY_OFFSET)
    chests = [
        Chest(i, *_CHEST.unpack_from(rec, CHEST_OFFSET + i * CHEST_SIZE))
        for i in range(CHEST_COUNT)
    ]
    special_count = struct.unpack_from("<i", rec, SPECIAL_COUNT_OFFSET)[0]
    unknown = list(rec[SPECIAL_UNKNOWN_OFFSET:
                       SPECIAL_UNKNOWN_OFFSET + SPECIAL_UNKNOWN_SIZE])
    specials = [
        SpecialPos(i, *_SPECIAL.unpack_from(rec, SPECIAL_OFFSET + i * SPECIAL_SIZE))
        for i in range(SPECIAL_COUNT)
    ]
    return Intro(difficulty, fight_txt, chests, special_count, unknown, specials)


def parse_fighters(rec: bytes) -> list[Fighter]:
    fighters: list[Fighter] = []
    for i in range(FIGHTER_COUNT):
        vals = _FIGHTER.unpack_from(rec, FIGHTER_OFFSET + i * FIGHTER_SIZE)
        fighters.append(Fighter(i, *vals))
    return fighters


def parse_level(index: int, rec: bytes) -> Level:
    if len(rec) != LEVEL_SIZE:
        raise ValueError(f"关卡记录长度 {len(rec)} != {LEVEL_SIZE}")
    name = _text(rec[:NAME_SIZE])
    success = _text(rec[SUCCESS_OFFSET:SUCCESS_OFFSET + SUCCESS_SIZE])
    failure = _text(rec[FAILURE_OFFSET:FAILURE_OFFSET + FAILURE_SIZE])
    people_recs = [
        people.parse_record(rec[PEOPLE_OFFSET + i * people.RECORD_SIZE:
                                PEOPLE_OFFSET + (i + 1) * people.RECORD_SIZE])
        for i in range(PEOPLE_COUNT)
    ]
    return Level(index=index, name=name, success=success, failure=failure,
                 intro=parse_intro(rec), people=people_recs,
                 fighters=parse_fighters(rec))


def load(path: Path) -> list[Level]:
    blob = path.read_bytes()
    if len(blob) % LEVEL_SIZE:
        raise ValueError(f"{path.name}: {len(blob)} 不是 {LEVEL_SIZE} 的整数倍")
    return [parse_level(i, blob[i * LEVEL_SIZE:(i + 1) * LEVEL_SIZE])
            for i in range(len(blob) // LEVEL_SIZE)]
