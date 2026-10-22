"""M3 原味 UI：从原版 IMG/TGA 生成 Godot 可直接用的主题贴图。

只读 data/、out/ 与 ../dlz/ANTI-JAP，写到 godot/assets/ui/。
可重复执行；产物不入库（体积 + 版权）。

用法：
    python3 tools/prepare_m3.py
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out"
ASSETS = ROOT / "godot" / "assets"
UI = ASSETS / "ui"
AUDIO = ASSETS / "audio"
GODOT_DATA = ROOT / "godot" / "data"

# 原版 HUD 的 DirectDraw 色键：KUANG00/04 的绿色底
KEY = (32, 68, 0)


def load_img(name: str) -> Image.Image:
    return Image.open(OUT / "img" / f"{name}.png").convert("RGBA")


def save(img: Image.Image, name: str) -> str:
    UI.mkdir(parents=True, exist_ok=True)
    img.save(UI / name)
    return "res://assets/ui/" + name


def chroma_key(img: Image.Image, key=KEY, tolerance: int = 10) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a and abs(r - key[0]) <= tolerance and abs(g - key[1]) <= tolerance \
                    and abs(b - key[2]) <= tolerance:
                px[x, y] = (0, 0, 0, 0)
    return img


def crop_panel(name: str, box: tuple[int, int, int, int]) -> Image.Image:
    img = load_img(name).crop(box)
    return img


def make_button(w: int, h: int, state: str) -> Image.Image:
    """用原版 K00 的石板纹理拼一个 9-patch 按钮。"""
    stone = crop_panel("K00", (28, 80, 220, 200)).resize((w - 8, h - 8), Image.NEAREST)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    img.paste(stone, (4, 4))
    d = ImageDraw.Draw(img)
    if state == "normal":
        outer, inner, fill = (196, 150, 54, 255), (86, 66, 34, 255), (104, 100, 94, 255)
    elif state == "hover":
        outer, inner, fill = (255, 218, 106, 255), (130, 96, 40, 255), (126, 120, 110, 255)
    elif state == "pressed":
        outer, inner, fill = (128, 92, 32, 255), (50, 38, 20, 255), (76, 74, 72, 255)
    else:
        outer, inner, fill = (94, 88, 78, 255), (48, 44, 38, 255), (58, 56, 54, 255)
    # 外金边 + 内暗边 + 顶部高光
    d.rectangle((0, 0, w - 1, h - 1), outline=outer, width=2)
    d.rectangle((3, 3, w - 4, h - 4), outline=inner, width=1)
    d.line((5, 2, w - 6, 2), fill=(255, 245, 210, 110), width=1)
    d.line((2, 5, 2, h - 6), fill=(255, 245, 210, 70), width=1)
    if state == "pressed":
        d.line((4, h - 4, w - 5, h - 4), fill=(20, 16, 10, 160), width=2)
    # 细腻噪点，避免大块纯色
    for i in range(w * h // 14):
        x = (i * 73 + 11) % max(1, w - 8) + 4
        y = (i * 151 + 7) % max(1, h - 8) + 4
        r, g, b, a = img.getpixel((x, y))
        k = -8 if i % 3 else 8
        img.putpixel((x, y), (max(0, min(255, r + k)),
                              max(0, min(255, g + k)),
                              max(0, min(255, b + k)), a))
    return img


def make_panel(name: str, w: int, h: int, base: str) -> Image.Image:
    """生成 9-patch 面板：深色底 + 原版金边/石纹。"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    if base == "red":
        bg = (58, 6, 8, 242)
        mid = (92, 12, 14, 242)
    elif base == "blue":
        bg = (8, 24, 40, 242)
        mid = (12, 38, 62, 242)
    elif base == "dark":
        bg = (18, 18, 20, 245)
        mid = (34, 32, 30, 245)
    else:
        bg = (42, 38, 32, 242)
        mid = (74, 68, 58, 242)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), fill=bg)
    d.rectangle((5, 5, w - 6, h - 6), fill=mid)
    # 原版那种双线金框
    d.rectangle((0, 0, w - 1, h - 1), outline=(232, 186, 76, 255), width=2)
    d.rectangle((2, 2, w - 3, h - 3), outline=(96, 66, 24, 255), width=1)
    d.rectangle((7, 7, w - 8, h - 8), outline=(150, 108, 42, 180), width=1)
    for x, y in ((2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)):
        d.rectangle((x - 2, y - 2, x + 2, y + 2), fill=(232, 186, 76, 255),
                    outline=(70, 46, 16, 255))
    return img


def make_header() -> Image.Image:
    img = Image.new("RGBA", (640, 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 639, 29), fill=(44, 6, 8, 238))
    d.rectangle((0, 0, 639, 1), fill=(238, 196, 92, 255))
    d.rectangle((0, 28, 639, 29), fill=(112, 76, 28, 255))
    d.rectangle((0, 26, 639, 26), fill=(198, 148, 54, 180))
    for x in range(0, 640, 80):
        d.line((x, 4, x + 36, 4), fill=(144, 26, 22, 160), width=2)
    return img


def make_slot() -> Image.Image:
    img = Image.new("RGBA", (96, 34), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 95, 33), fill=(0, 0, 0, 238), outline=(202, 154, 58, 255), width=2)
    d.rectangle((3, 3, 92, 30), outline=(80, 58, 24, 255), width=1)
    return img


def make_target() -> Image.Image:
    img = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.line((16, 40, 16, 8), fill=(232, 186, 76, 255), width=3)
    d.polygon([(16, 8), (42, 16), (16, 24)], fill=(176, 24, 20, 230),
              outline=(240, 208, 120, 255))
    d.ellipse((4, 38, 28, 46), fill=(20, 16, 10, 160))
    return img


def make_glow() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r in range(30, 4, -2):
        a = int(22 * (1 - r / 32.0))
        d.ellipse((32 - r, 32 - r, 32 + r, 32 + r), fill=(255, 208, 96, a))
    return img


def main() -> None:
    UI.mkdir(parents=True, exist_ok=True)
    GODOT_DATA.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, str] = {}

    # 原版整屏 / 面板
    copies = {
        "BG01": "title_bg.png",
        "BG02": "story_bg.png",
        "MENU00": "report_red.png",
        "MENU10": "report_blue.png",
        "BG03": "chapter_bg.png",
        "MENU02": "panel_blue.png",
        "MENU09": "panel_blue_wide.png",
        "MENU08": "party_grid8.png",
        "MENU34": "party_grid8_alt.png",
        "MENU03": "panel_stone_small.png",
        "K00": "screen_party.png",
        "K01": "screen_town.png",
        "K02": "screen_inventory.png",
        "K03": "screen_system.png",
        "K04": "screen_dialog.png",
        "MENU30": "cursor.png",
        "BOX": "chest_sheet.png",
        "BUTTON3": "target_flag.png",
        "MINE": "mine_marker.png",
        "DLZ00": "scrollbar.png",
    }
    for src, dst in copies.items():
        shutil.copyfile(OUT / "img" / f"{src}.png", UI / dst)
        manifest[dst] = "res://assets/ui/" + dst

    # 勋章/评价
    for i in range(5):
        shutil.copyfile(OUT / "img" / f"MENU{20 + i}.png", UI / f"medal_{i}.png")
        shutil.copyfile(OUT / "img" / f"MENU{50 + i}.png", UI / f"grade_{i}.png")

    # 战斗 HUD：左侧地图区绿色色键透明；右侧/上/下的绿色填成深石色，
    # 否则 KUANG00 的侧栏会漏出地图，文字不可读。
    for src, dst in (("KUANG00", "hud_battle.png"), ("KUANG04", "hud_battle_clean.png")):
        img = load_img(src)
        px = img.load()
        for y in range(img.height):
            for x in range(img.width):
                r, g, b, a = px[x, y]
                if a and abs(r - KEY[0]) <= 10 and abs(g - KEY[1]) <= 10 \
                        and abs(b - KEY[2]) <= 10:
                    if x < 442 and 28 < y < 456:
                        px[x, y] = (0, 0, 0, 0)
                    else:
                        px[x, y] = (44, 39, 32, 255)
        img.save(UI / dst)
        manifest[dst] = "res://assets/ui/" + dst

    # 对话框：取 KUANG01 的深蓝面板，去掉灰底
    dialog = crop_panel("KUANG01", (4, 4, 452, 310))
    dialog.save(UI / "dialog_panel.png")
    manifest["dialog_panel.png"] = "res://assets/ui/dialog_panel.png"
    # 全屏暗底对话框
    full = Image.new("RGBA", (640, 480), (0, 0, 0, 0))
    full.alpha_composite(dialog.resize((640, 440), Image.NEAREST), (0, 36))
    full.save(UI / "dialog_full.png")
    manifest["dialog_full.png"] = "res://assets/ui/dialog_full.png"

    # 9-patch 按钮
    for name, w, h in (("button", 120, 34), ("button_small", 72, 26),
                       ("button_wide", 220, 36)):
        for state in ("normal", "hover", "pressed", "disabled"):
            img = make_button(w, h, state)
            img.save(UI / f"{name}_{state}.png")
            manifest[f"{name}_{state}.png"] = f"res://assets/ui/{name}_{state}.png"

    # 面板
    for name, w, h, base in (
        ("panel_red", 64, 64, "red"),
        ("panel_blue_dark", 64, 64, "blue"),
        ("panel_dark", 64, 64, "dark"),
        ("panel_stone", 64, 64, "stone"),
    ):
        img = make_panel(name, w, h, base)
        img.save(UI / f"{name}.png")
        manifest[f"{name}.png"] = f"res://assets/ui/{name}.png"

    make_header().save(UI / "header.png")
    make_slot().save(UI / "slot.png")
    make_target().save(UI / "target.png")
    make_glow().save(UI / "glow.png")
    for n in ("header.png", "slot.png", "target.png", "glow.png"):
        manifest[n] = "res://assets/ui/" + n

    # 常用原版音效
    sfx = {
        "click": "wave_0002.wav",
        "confirm": "wave_0006.wav",
        "cancel": "wave_0003.wav",
        "open": "wave_0001.wav",
    }
    for dst, src in sfx.items():
        p = OUT / "wave" / src
        if p.exists():
            shutil.copyfile(p, UI / f"sfx_{dst}.wav")
            manifest[f"sfx_{dst}.wav"] = f"res://assets/ui/sfx_{dst}.wav"

    # WAVE.DAT 全量音效：攻击/移动/地雷/物品等按原版索引播放
    AUDIO.mkdir(parents=True, exist_ok=True)
    for p in sorted((OUT / "wave").glob("wave_*.wav")):
        shutil.copyfile(p, AUDIO / p.name)
        manifest["audio/" + p.name] = "res://assets/audio/" + p.name

    (GODOT_DATA / "m3.json").write_text(json.dumps({
        "meta": {
            "title": "抗日：地雷战",
            "font": "res://assets/font/hzk16.fnt",
            "cursor": "res://assets/ui/cursor.png",
            "viewport": [640, 480],
        },
        "assets": manifest,
    }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("m3 ui assets", len(manifest))
    print("m3.json", (GODOT_DATA / "m3.json").stat().st_size, "bytes")


if __name__ == "__main__":
    main()
