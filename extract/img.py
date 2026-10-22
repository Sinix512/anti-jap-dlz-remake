"""抗日地雷战 IMG 解码器。

基本格式（84/86 个文件直接成立）：

    0x00  4B   'IMGV'
    0x04  2B   pad (=1)
    0x06  2B   宽 - 1 (LE)
    0x08  2B   高 - 1 (LE)
    0x0A  6B   pad
    0x10  w*h  8bpp 索引像素，逐行、自上而下、无压缩
    随后  768B 调色板，256 × RGB，每分量 6 位（×4 → 0-255）

例外：`DLZ00.IMG` 的调色板是 8 位分量（0..255，不再 ×4）；
`BUTTON00/01.IMG` 尾部 768 B 全 0，是发行版里的空占位（对应 TGA 另有文件）。

两个异类（本机逐字节定位，见下方 resolve_geometry）：

* `END04.IMG`：头部声明 640×480，但像素区只有 64,000 B。
  64,000 = 320×200，且 `16 + 320*200 + 768 == 64,784` 正好等于文件长度；
  按 320×200 解码得到完整的「两人背影」结局图。→ 头部尺寸只是显示尺寸，
  像素实际是 320×200（游戏里拉伸到 640×480）。
* `ZYB.IMG`：像素区 4,839,680 B = 640 × 7,562，调色板同样在文件尾部。
  按 640×7,562 解码后，第 5/6 屏交界处「袁世辉」三字的上半截与下半截
  正好接上 → 它是一张**纵向滚动字幕长图**，不是 16 帧动画。
  `16 + 640*7562 + 768 == 4,840,464` 正好等于文件长度。

校验方式：所有分支都必须满足 `16 + w*h + 768 == 文件长度`。
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

HEADER = 16
PALETTE = 768
COMPONENT_SCALE = 4  # 6 位 → 8 位

# END04.IMG 的像素区是 320×200（64,000 B），头部却写着 640×480。
# 这个尺寸无法从头部推出来，只能按文件长度 + 解码结果确认，所以单独列出。
_QUIRKS = {
    "END04.IMG": (320, 200),
}


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


@dataclass(frozen=True)
class Geometry:
    width: int
    height: int
    kind: str  # plain / quirk / strip


def read_header(path: Path) -> ImgHeader:
    blob = path.read_bytes()[:HEADER]
    if blob[:4] != b"IMGV":
        raise ValueError(f"{path.name}: 不是 IMGV 文件（头 {blob[:4]!r}）")
    w1, h1 = struct.unpack_from("<HH", blob, 6)
    return ImgHeader(width=w1 + 1, height=h1 + 1)


def _pixel_bytes(blob: bytes) -> int:
    return len(blob) - HEADER - PALETTE


def resolve_geometry(path: Path, blob: bytes | None = None) -> Geometry:
    """返回真实像素网格；三条分支都以「16 + w*h + 768 == 文件长度」为准。"""
    blob = path.read_bytes() if blob is None else blob
    head = read_header(path)
    n = _pixel_bytes(blob)
    if n <= 0:
        raise ValueError(f"{path.name}: 文件太短（{len(blob)} B）")

    if n == head.width * head.height:
        return Geometry(head.width, head.height, "plain")

    if path.name in _QUIRKS:
        w, h = _QUIRKS[path.name]
        if n != w * h:
            raise ValueError(
                f"{path.name}: 像素区 {n} B != 约定的 {w}×{h} = {w * h} B"
            )
        return Geometry(w, h, "quirk")

    # 纵向长图：像素区恰好是 640 的整数倍，高度由文件长度反推
    if n % head.width == 0:
        return Geometry(head.width, n // head.width, "strip")

    raise ValueError(
        f"{path.name}: 像素区 {n} B 无法用 {head.width}×{head.height} "
        f"或 {head.width} 宽的长图解释，可能是未见过的压缩变体"
    )


def palette_bytes(blob: bytes) -> bytes:
    """尾部 768 B 调色板。

    83 个 IMG 是 6 位分量（0..63），需要 ×4；
    `DLZ00.IMG` 是唯一的 8 位分量（0..255），不能再乘；
    `BUTTON00/01.IMG` 尾部 768 B 全 0（发行版里的空占位，对应 TGA 另有文件），
    保持全黑并在 README 里记一笔。
    """
    raw = blob[-PALETTE:]
    if not any(raw):
        return bytes(PALETTE)
    scale = 1 if max(raw) > 63 else COMPONENT_SCALE
    return bytes(min(255, c * scale) for c in raw)


def decode(path: Path) -> Image.Image:
    blob = path.read_bytes()
    geom = resolve_geometry(path, blob)
    pixels = blob[HEADER:HEADER + geom.width * geom.height]
    img = Image.frombytes("P", (geom.width, geom.height), pixels)
    img.putpalette(palette_bytes(blob))
    return img


def save_png(path: Path, dest: Path) -> Geometry:
    blob = path.read_bytes()
    geom = resolve_geometry(path, blob)
    dest.parent.mkdir(parents=True, exist_ok=True)
    pixels = blob[HEADER:HEADER + geom.width * geom.height]
    img = Image.frombytes("P", (geom.width, geom.height), pixels)
    img.putpalette(palette_bytes(blob))
    img.save(dest)
    return geom