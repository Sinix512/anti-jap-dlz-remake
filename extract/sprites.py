"""纯像素容器：FACE / ARMY / MINE / FLM / GOODS / MATERIAL / PLACE。

每个文件都是无头部的 8bpp 索引像素流，尺寸由文件长度整除确认：

| 文件 | 单帧 | 数量 | 分组 |
|---|---|---|---|
| `FACE.DAT` | 80×100 | 170 | 1 |
| `ARMY.DAT` | 48×48 | 91×19=1729 | 19 帧/兵种 |
| `MINE.DAT` | 48×48 | 10×4=40 | 4 帧/雷 |
| `FLM.DAT` | 48×48 | 32×16=512 | 16 帧/动画 |
| `GOODS.DAT` | 48×48 | 128 | 1（物品图标） |
| `MATERIAL.DAT` | 48×48 | 10 | 1（材料图标） |
| `PLACE.DAT` | 640×480 | 19 | 1（城镇背景，尾部 1024 B 调色板） |

前 6 个用 IMG 通用调色板；索引 0 按透明色处理（ARMY/MINE/FLM/GOODS/MATERIAL）。
PLACE 每条记录自带 256 × RGBA 调色板。
"""

from __future__ import annotations

import math
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


@dataclass(frozen=True)
class SpriteBank:
    name: str
    file_name: str
    frame_w: int
    frame_h: int
    count: int
    group_size: int = 1
    transparent: bool = False
    per_record_palette: bool = False

    @property
    def frame_bytes(self) -> int:
        return self.frame_w * self.frame_h

    @property
    def groups(self) -> int:
        return self.count // self.group_size

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "file": self.file_name,
            "frame": [self.frame_w, self.frame_h],
            "count": self.count,
            "group_size": self.group_size,
            "groups": self.groups,
            "transparent_index": 0 if self.transparent else None,
            "per_record_palette": self.per_record_palette,
        }


BANKS: tuple[SpriteBank, ...] = (
    SpriteBank("face", "FACE.DAT", 80, 100, 170),
    SpriteBank("army", "ARMY.DAT", 48, 48, 91 * 19, 19, True),
    SpriteBank("mine", "MINE.DAT", 48, 48, 10 * 4, 4, True),
    SpriteBank("flm", "FLM.DAT", 48, 48, 32 * 16, 16, True),
    SpriteBank("goods", "GOODS.DAT", 48, 48, 128, 1, True),
    SpriteBank("material", "MATERIAL.DAT", 48, 48, 10, 1, True),
    SpriteBank("place", "PLACE.DAT", 640, 480, 19, 1, False, True),
)
BANK_BY_NAME = {b.name: b for b in BANKS}

PLACE_RECORD_SIZE = 640 * 480 + 1024


def load_bank(game_dir: Path, bank: SpriteBank) -> bytes:
    blob = (game_dir / bank.file_name).read_bytes()
    if bank.per_record_palette:
        need = bank.count * PLACE_RECORD_SIZE
    else:
        need = bank.count * bank.frame_bytes
    if len(blob) != need:
        raise ValueError(
            f"{bank.file_name}: {len(blob)} B != {bank.count}×"
            f"{bank.frame_bytes} B ({need})"
        )
    return blob


def frame_bytes(blob: bytes, bank: SpriteBank, index: int) -> bytes:
    if not 0 <= index < bank.count:
        raise ValueError(f"{bank.name} 帧 {index} 越界 0..{bank.count - 1}")
    start = index * bank.frame_bytes
    return blob[start:start + bank.frame_bytes]


def frame_image(raw: bytes, bank: SpriteBank, palette: bytes) -> Image.Image:
    image = Image.frombytes("P", (bank.frame_w, bank.frame_h), raw)
    image.putpalette(palette)
    if bank.transparent:
        image.info["transparency"] = 0
    return image


def frame_rgba(raw: bytes, bank: SpriteBank, palette: bytes) -> Image.Image:
    image = frame_image(raw, bank, palette)
    if bank.transparent:
        return image.convert("RGBA")
    return image.convert("RGB")


def save_frame(raw: bytes, bank: SpriteBank, palette: bytes, dest: Path) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    frame_rgba(raw, bank, palette).save(dest)
    return dest


def group_sheet(blob: bytes, bank: SpriteBank, group: int, palette: bytes,
                scale: int = 1) -> Image.Image:
    if not 0 <= group < bank.groups:
        raise ValueError(f"{bank.name} 组 {group} 越界 0..{bank.groups - 1}")
    size = bank.group_size
    sheet = Image.new("RGBA", (bank.frame_w * size, bank.frame_h),
                      (0, 0, 0, 0))
    for i in range(size):
        raw = frame_bytes(blob, bank, group * size + i)
        sheet.alpha_composite(frame_rgba(raw, bank, palette),
                              (i * bank.frame_w, 0))
    if scale != 1:
        sheet = sheet.resize(
            (sheet.width * scale, sheet.height * scale), Image.NEAREST
        )
    return sheet


def save_group_sheets(blob: bytes, bank: SpriteBank, palette: bytes,
                      out_dir: Path, scale: int = 1) -> list[Path]:
    paths: list[Path] = []
    for group in range(bank.groups):
        dest = out_dir / f"{bank.name}_{group:03d}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        group_sheet(blob, bank, group, palette, scale=scale).save(dest)
        paths.append(dest)
    return paths


def contact_sheet(blob: bytes, bank: SpriteBank, palette: bytes,
                  columns: int = 16, scale: int = 1,
                  background=(40, 40, 40, 255)) -> Image.Image:
    """每组取第 0 帧，排成 contact sheet。FACE 用 RGB，其余用 RGBA 合成到深色底。"""
    n = bank.groups
    rows = max(1, math.ceil(n / columns))
    sheet = Image.new("RGBA", (columns * bank.frame_w * scale,
                               rows * bank.frame_h * scale), background)
    for group in range(n):
        raw = frame_bytes(blob, bank, group * bank.group_size)
        image = frame_rgba(raw, bank, palette)
        if image.mode == "RGB":
            image = image.convert("RGBA")
        if scale != 1:
            image = image.resize(
                (bank.frame_w * scale, bank.frame_h * scale), Image.NEAREST
            )
        sheet.alpha_composite(image, ((group % columns) * bank.frame_w * scale,
                                      (group // columns) * bank.frame_h * scale))
    return sheet.convert("RGB")


def place_image(blob: bytes, bank: SpriteBank, index: int,
                palette_of: Callable[[bytes], bytes]) -> Image.Image:
    if not 0 <= index < bank.count:
        raise ValueError(f"PLACE 记录 {index} 越界")
    start = index * PLACE_RECORD_SIZE
    record = blob[start:start + PLACE_RECORD_SIZE]
    image = Image.frombytes("P", (640, 480), record[:640 * 480])
    image.putpalette(palette_of(record))
    return image.convert("RGB")


def save_places(blob: bytes, bank: SpriteBank, palette_of: Callable[[bytes], bytes],
                out_dir: Path) -> list[Path]:
    paths: list[Path] = []
    for i in range(bank.count):
        dest = out_dir / f"place_{i:02d}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        place_image(blob, bank, i, palette_of).save(dest)
        paths.append(dest)
    return paths


def place_contact_sheet(blob: bytes, bank: SpriteBank, palette_of: Callable[[bytes], bytes],
                        columns: int = 4, thumb_w: int = 320) -> Image.Image:
    thumb_h = thumb_w * 480 // 640
    rows = max(1, math.ceil(bank.count / columns))
    sheet = Image.new("RGB", (columns * thumb_w, rows * thumb_h), (30, 30, 30))
    for i in range(bank.count):
        image = place_image(blob, bank, i, palette_of).resize(
            (thumb_w, thumb_h), Image.LANCZOS
        )
        sheet.paste(image, ((i % columns) * thumb_w, (i // columns) * thumb_h))
    return sheet
