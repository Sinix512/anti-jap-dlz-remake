"""PEOPLE.DAT 解码器。

结构：40 条 × 132 B（5,280 = 40 × 132）。

字段表来源：dlz_research 的 `template/dlz_people.bt`（MIT，作者 ltg1831，2022-04），
本机已复核的部分：
  * 40 条记录的名字全部是合法 GBK，且顺序与模板注释一致（第 0 条是彩蛋「孙悟空」）；
  * face ∈ 0..169，与 FACE.DAT 的 170 张头像一致；
  * bingzhong ∈ 0..89，落在 GAME.DAT BingZhong[96] 内；
  * wupin[8] / dilei[8] 的取值都落在 GAME.DAT WuPin[160] / DiLei[10] 内。

⚠️ 0x18 字段语义未定：模板写作 enemy（0 我方 / 1 敌方），但本机数据里
我方角色是 1、张长庚是 2、孙悟空是 0；FIGHT.DAT 里日军/伪军也都是 1，
因此没有采信模板的枚举，JSON 里保留为 `unknown_18`。
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

NAME_SIZE = 16
RECORD_SIZE = 132
COUNT = 40

# 0x34..0x70：16 个技能等级，顺序与 GAME.DAT JiNeng[16] / BingZhong.jineng 一致
SKILL_NAMES = (
    "buji", "jili", "yiliao", "huogong",
    "gunmu", "leishi", "weishe", "saorao",
    "pohuai", "lueduo", "fanjian", "yibing",
    "duzhan", "ansha", "shidu", "kongxi",
)

# 132 B = 33 个 int32；0x00 是 name[16]（4 个 int），0x74/0x7C 是两段 u8[8]
_HEAD = struct.Struct("<16s25i")
# 0x74..0x84：wupin[8] + dilei[8]
_TAIL = struct.Struct("<8B8B")


def decode_name(raw: bytes) -> str:
    """GBK 名字，读到 NUL 为止；保留全角空格（如「张　嘎」）。"""
    return raw.split(b"\x00", 1)[0].decode("gb18030", errors="replace")


@dataclass
class Person:
    name: str
    face: int
    pad2: int
    unknown_18: int
    wuli: int
    zhili: int
    level: int
    jingyan: int
    bingzhong: int
    gongji: int
    skills: dict[str, int] = field(default_factory=dict)
    wupin: list[int] = field(default_factory=list)
    dilei: list[int] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "face": self.face,
            "pad2": self.pad2,
            "unknown_18": self.unknown_18,
            "wuli": self.wuli,
            "zhili": self.zhili,
            "level": self.level,
            "jingyan": self.jingyan,
            "bingzhong": self.bingzhong,
            "gongji": self.gongji,
            "skills": dict(self.skills),
            "wupin": list(self.wupin),
            "dilei": list(self.dilei),
        }


def parse_record(rec: bytes) -> Person:
    if len(rec) != RECORD_SIZE:
        raise ValueError(f"人物记录长度 {len(rec)} != {RECORD_SIZE}")
    (name_raw, face, pad2, unknown_18, wuli, zhili, level, jingyan,
     bingzhong, gongji, *skills) = _HEAD.unpack_from(rec, 0)
    tail = _TAIL.unpack_from(rec, 0x74)
    wupin, dilei = list(tail[:8]), list(tail[8:])
    return Person(
        name=decode_name(name_raw),
        face=face,
        pad2=pad2,
        unknown_18=unknown_18,
        wuli=wuli,
        zhili=zhili,
        level=level,
        jingyan=jingyan,
        bingzhong=bingzhong,
        gongji=gongji,
        skills=dict(zip(SKILL_NAMES, skills)),
        wupin=wupin,
        dilei=dilei,
    )


def load(path: Path) -> list[Person]:
    blob = path.read_bytes()
    if len(blob) % RECORD_SIZE:
        raise ValueError(f"{path.name}: {len(blob)} 不是 {RECORD_SIZE} 的整数倍")
    return [parse_record(blob[i:i + RECORD_SIZE])
            for i in range(0, len(blob), RECORD_SIZE)]