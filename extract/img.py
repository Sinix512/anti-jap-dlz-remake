"""抗日地雷战 IMG 解码器。

格式（公开研究 dlzr/img_loader + 本地逐字节校验一致）：

    偏移 0x00  4B   'IMGV'
    偏移 0x04  2B   pad (=1)
    偏移 0x06  2B   宽 - 1 (LE)
    偏移 0x08  2B   高 - 1 (LE)
    偏移 0x0A  6B   pad
    偏移 0x10  w*h  8bpp 像素索引，逐行、无压缩
    随后      768B  调色板，256 × RGB，每分量 6 位（×4 才是 0-255）

校验方式：16 + w*h + 768 必须等于文件长度（86 个 IMG 里 85 个成立；
END04.IMG 只有 64784 字节，属于另一种压缩变体，单独处理）。
"""
from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

HEADER = 16
PALETTE = 768
COMPONENT_SCALE = 4  # 6 位 → 8 位


@dataclass(frozen=True)
class ImgHeader:
    width: int
    height: int

    @property
    def pixel_offset(self) -> int:
        return HEADER

    @property
    def palette_offset(self) -> int:
        return HEADER + self.width * self.height

    @property
    def size(self) -> int:
        return self.palette_offset + PALETTE


def read_header(path: Path) -> ImgHeader:
    blob = path.read_bytes()[:HEADER]
    if blob[:4] != b"IMGV":
        raise ValueError(f"{path.name}: 不是 IMGV 文件（头 {blob[:4]!r}）")
    w1, h1 = struct.unpack_from("<HH", blob, 6)
    return ImgHeader(width=w1 + 1, height=h1 + 1)


def palette_bytes(blob: bytes, head: ImgHeader) -> bytes:
    raw = blob[head.palette_offset:head.size]
    return bytes(min(255, c * COMPONENT_SCALE) for c in raw)


def decode(path: Path) -> Image.Image:
    blob = path.read_bytes()
    head = read_header(path)
    if len(blob) != head.size:
        raise ValueError(
            f"{path.name}: 长度 {len(blob)} != 预期 {head.size}"
            f"（{head.width}×{head.height}），可能是压缩变体"
        )
    img = Image.frombytes("P", (head.width, head.height),
                          blob[head.pixel_offset:head.palette_offset])
    img.putpalette(palette_bytes(blob, head))
    return img


def save_png(path: Path, dest: Path) -> ImgHeader:
    head = read_header(path)
    dest.parent.mkdir(parents=True, exist_ok=True)
    decode(path).save(dest)
    return head