"""FIGHT.DAT 解码器。

47 关 × 20,508 B（963,876 = 47 × 20,508），每关三段：

    0x0000  700 B    Intro：关卡名 / 胜负文本 / 宝箱（后段未拆）
    0x02BC  8192 B   Fighter[128] × 64 B —— 本轮不导出（字段未验证）
    0x22BC  11616 B  People[88] × 132 B —— 与 PEOPLE.DAT 同构，本轮导出

校验方式：`20508 == 700 + 128*64 + 88*132`，三段首尾相接正好铺满一关；
47 关的关卡名、胜利/失败文本全部是合法 GBK；People 段每条记录的名字/face
都能按 132 B 对齐解出。

⚠️ Intro 的 0x20 / 0x24 两个 int 语义未证实（模板称 difficulty / fight_txt），
本机数据无法自洽解释，因此不导出。宝箱区（0xA8 起）同理留待下一轮。

⚠️ FIGHT 的 People[88] 不是 PEOPLE.DAT 的拷贝：它是每关的战场名册
（伪军 / 日军 / 碉堡 / 维持会 …，空位填「孙悟空」）。两表同构，但内容不同。
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

from . import people

LEVEL_COUNT = 47
LEVEL_SIZE = 20508
INTRO_SIZE = 700
FIGHTER_COUNT = 128
FIGHTER_SIZE = 64
PEOPLE_OFFSET = INTRO_SIZE + FIGHTER_COUNT * FIGHTER_SIZE  # 8892 = 0x22BC
PEOPLE_COUNT = 88

NAME_SIZE = 0x20
SUCCESS_OFFSET = 0x28
SUCCESS_SIZE = 0x40
FAILURE_OFFSET = 0x68
FAILURE_SIZE = 0x40


def _text(raw: bytes) -> str:
    return raw.split(b"\x00", 1)[0].decode("gb18030", errors="replace")


@dataclass
class Level:
    index: int
    name: str
    success: str
    failure: str
    people: list[people.Person]

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "name": self.name,
            "success": self.success,
            "failure": self.failure,
            "people": [p.as_dict() for p in self.people],
        }


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
    return Level(index=index, name=name, success=success,
                 failure=failure, people=people_recs)


def load(path: Path) -> list[Level]:
    blob = path.read_bytes()
    if len(blob) % LEVEL_SIZE:
        raise ValueError(f"{path.name}: {len(blob)} 不是 {LEVEL_SIZE} 的整数倍")
    return [parse_level(i, blob[i * LEVEL_SIZE:(i + 1) * LEVEL_SIZE])
            for i in range(len(blob) // LEVEL_SIZE)]