"""调色板来源。

本机确认的两类调色板：

* IMG 文件尾部 768 B：256 × RGB，每分量 6 位，×4 扩成 0..255。
  86 个 IMG 一共只有 19 组不同调色板，其中 29 个文件共用一组；
  这组“通用调色板”用于 FACE / ARMY / MINE / FLM / GOODS / MATERIAL
  以及 MAP / BLK 的 8bpp 索引渲染，目视与原始画面一致。
* PLACE.DAT 每条记录尾部 1024 B：256 × RGBA（第 4 字节恒 0），
  每个城镇背景自带一份。

原版目录里没有 `dlz-01.pal` / `dlz-11.pal` / `dlz-13.pal` 文件，
EXE 里也没有对应字面量；因此地图调色板用上面的 IMG 通用调色板代替。
"""

from __future__ import annotations

from pathlib import Path

PALETTE_BYTES = 768
COMPONENT_SCALE = 4
# 29 个 IMG 共用这组调色板，作为全局 8bpp 索引图的调色板。
GLOBAL_PALETTE_SOURCE = "BOX.IMG"


def img_palette(path: Path) -> bytes:
    """IMG 尾部 768 B，6 位分量 ×4 → 768 B RGB。"""
    blob = path.read_bytes()
    if len(blob) < PALETTE_BYTES:
        raise ValueError(f"{path.name}: 文件太短，取不到调色板")
    raw = blob[-PALETTE_BYTES:]
    if not any(raw):
        return bytes(PALETTE_BYTES)
    scale = 1 if max(raw) > 63 else COMPONENT_SCALE
    return bytes(min(255, c * scale) for c in raw)


def global_palette(game_dir: Path) -> bytes:
    return img_palette(game_dir / GLOBAL_PALETTE_SOURCE)


def place_palette(record: bytes) -> bytes:
    """PLACE.DAT 单条记录尾部 1024 B：256 × RGBA → 768 B RGB。"""
    if len(record) != 640 * 480 + 1024:
        raise ValueError(f"PLACE 记录长度 {len(record)} != 308224")
    raw = record[-1024:]
    return bytes(c for i in range(0, 1024, 4) for c in raw[i:i + 3])
