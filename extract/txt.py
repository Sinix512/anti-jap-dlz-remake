"""抗日地雷战 TXT.DAT 解码器。

实测：整文件逐字节 XOR 0x51 后即 GB18030 文本。
记录结构（在 XOR 之后的明文里）：

    000 xx            记录号 + 结束符
    001 xx
    004 -1GG，八路军某营营长……   -1 开头是行标记
        ……
    xx                记录结束

也就是说每条记录是「三位十进制编号 + 若干行文本 + 'xx' 终止符」。
编号不连续，且有的记录是纯占位（只有 'xx'）。
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

KEY = 0x51
ENCODING = "gb18030"

RECORD_SPLIT = re.compile(r"\b(\d{3})\s")


@dataclass
class Record:
    number: int
    text: str


def decode_raw(path: Path) -> str:
    blob = path.read_bytes()
    return bytes(b ^ KEY for b in blob).decode(ENCODING, errors="replace")


def parse(plain: str) -> list[Record]:
    records: list[Record] = []
    for chunk in plain.split("xx"):
        m = RECORD_SPLIT.search(chunk)
        if not m:
            continue
        body = chunk[m.end():]
        lines = [ln[2:] if ln.startswith("-1") else ln
                 for ln in body.splitlines() if ln.strip()]
        if lines:
            records.append(Record(number=int(m.group(1)), text="\n".join(lines)))
    return records


def load(path: Path) -> list[Record]:
    return parse(decode_raw(path))