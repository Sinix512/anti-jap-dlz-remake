"""抗日地雷战 TXT.DAT 解码器。

实测：整文件逐字节 XOR 0x51 后即 GB18030 文本。
记录结构（在 XOR 之后的明文里）：

    000 xx            记录号 + 结束符
    001 xx
    004 -1GG，八路军某营营长……   -1 开头是行标记
        ……
    xx                记录结束

也就是说每条记录是「三位十进制编号 + 若干行文本 + x 终止符」。
通常写作 xx，但 TXT552 是 x\r\nx，原 loader 在首 x 就结束。
原编号000..592连续；parse只导出非空记录，因此返回的编号不连续。
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

KEY = 0x51
ENCODING = "gb18030"

# 000..592 printed headers are sequential and match the engine's pointer slots.
# Do not split on literal 'xx': TXT552 ends with x\r\nx, which the original
# 43C9EC loader accepts (the first x terminates a record, then one byte is skipped).
RECORD_SPLIT = re.compile(r"(?m)^[ \t]*(\d{3})[ \t]+")


@dataclass
class Record:
    number: int
    text: str
    native_stream: str = ""


def decode_raw(path: Path) -> str:
    blob = path.read_bytes()
    return bytes(b ^ KEY for b in blob).decode(ENCODING, errors="replace")


def parse(plain: str) -> list[Record]:
    records: list[Record] = []
    headers = list(RECORD_SPLIT.finditer(plain))
    for i, m in enumerate(headers):
        end = headers[i + 1].start() if i + 1 < len(headers) else len(plain)
        # The original engine terminates at the first ASCII x, not an xx pair.
        body = plain[m.end():end].split("x", 1)[0]
        lines = [ln[2:] if ln.startswith("-1") else ln
                 for ln in body.splitlines() if ln.strip()]
        if lines:
            #43C9EC discards CR/LF and only their following ASCII spaces.
            native_stream = re.sub(r"[\r\n]+ *", "", body)
            records.append(Record(number=int(m.group(1)), text="\n".join(lines),
                                  native_stream=native_stream))
    return records


def load(path: Path) -> list[Record]:
    return parse(decode_raw(path))
