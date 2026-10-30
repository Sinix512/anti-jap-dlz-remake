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
FLM = ASSETS / "flm"
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

    # MENU30 is a numeric slider handle, not a mouse cursor (42D7BE/42DAD5).
    # Remove the obsolete generated alias so stale installs cannot reuse it.
    (UI / "cursor.png").unlink(missing_ok=True)

    # 原版整屏 / 面板
    copies = {
        "BG03": "title_bg.png",
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
        "MENU30": "menu30_slider.png",
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

    # 战斗HUD实际为KUANG04；只清精确432x432地图窗，不猜绿色色键。
    hud = load_img("KUANG04")
    hud.paste((0,0,0,0), (14,32,446,464))
    for name in ("hud_battle.png", "hud_battle_clean.png"):
        manifest[name] = save(hud,name)
    # 426202自定义TGA loader：EOF起逐行逆序读；忽略TGA自带palette。
    original = ROOT.parent / "dlz" / "ANTI-JAP"
    palette = bytes(min(255,v*4) for v in (original / "KUANG04.IMG").read_bytes()[-768:])
    # 42C620: overlays use active BG03 palette, not their own palette tails.
    title_palette = bytes(v*4 for v in (original / "BG03.IMG").read_bytes()[-768:])
    # The generic extraction preview does not establish the live palette.
    # Reconstruct the background from the same original bytes as its overlays.
    raw = (original / "BG03.IMG").read_bytes()[16:16+640*480]
    im = Image.frombytes("P", (640,480), raw); im.putpalette(title_palette)
    manifest["title_bg.png"] = save(im.convert("RGBA"), "title_bg.png")
    for index in range(5):
        raw = (original / f"MENU{50+index}.IMG").read_bytes()[16:16+232*56]
        im = Image.frombytes("P", (232,56), raw); im.putpalette(title_palette)
        manifest[f"title_selected_{index}.png"] = save(im.convert("RGBA"), f"title_selected_{index}.png")
    raw = (original / "MINE02.IMG").read_bytes()[16:16+56*48*30]
    im = Image.frombytes("P", (56,48*30), raw); im.putpalette(title_palette)
    im = im.convert("RGBA")
    im.putalpha(Image.frombytes("L", (56,48*30), bytes(0 if v==4 else 255 for v in raw)))
    manifest["title_mine02.png"] = save(im, "title_mine02.png")
    raw_bg01 = (original / "BG01.IMG").read_bytes()
    transition_palette = bytes(v*4 for v in raw_bg01[-768:])
    im = Image.frombytes("P", (640,480), raw_bg01[16:16+640*480]); im.putpalette(transition_palette)
    manifest["title_transition.png"] = save(im.convert("RGBA"), "title_transition.png")
    # ZYB has a 640x480 nominal header, but 7082 extra scanlines. The native
    # reader uses the fixed palette offset and shifts exactly two rows/tick.
    zyb = (original / "ZYB.IMG").read_bytes()
    zyb_palette = bytes(v*4 for v in zyb[0x49D910:0x49D910+768])
    im = Image.frombytes("P", (640,7562), zyb[16:0x49D910]); im.putpalette(zyb_palette)
    manifest["title_supporters.png"] = save(im.convert("RGBA"), "title_supporters.png")
    (GODOT_DATA / "title_pages.json").write_text(json.dumps({
        "source": "42CFEA/42D217/430253; research_title_subpages_contract_20261025",
        "bg01_palette": [list(transition_palette[i:i+3]) for i in range(0,768,3)],
        "battle_palette": [list(palette[i:i+3]) for i in range(0,768,3)],
    }, indent=1)+"\n", encoding="utf-8")
    # Shared native overlays are indices in the caller's current palette.
    # Store the raw index raster, not one incorrectly fixed RGB skin.
    (UI / "menu09_indices.bin").write_bytes((original / "MENU09.IMG").read_bytes()[16:16+456*227])
    overlay_palettes = {}
    for source in ("BG01","BG02","BIGMAP","KUANG04","K00","K01","K02","K03","K04","BACK19"):
        path = original / (source + ".IMG")
        if path.exists(): overlay_palettes[source] = [v*4 for v in path.read_bytes()[-768:]]
    place = (original / "PLACE.DAT").read_bytes()
    for index in range(19):
        # PLACE stores a 1024-byte RGB0 palette, already in 8-bit components.
        raw = place[index*0x4B400+0x4B000:(index+1)*0x4B400]
        overlay_palettes[f"PLACE{index:02d}"] = [v for i in range(256) for v in raw[i*4:i*4+3]]
    (GODOT_DATA / "native_ui_palettes.json").write_text(json.dumps(overlay_palettes)+"\n", encoding="utf-8")
    # 42D686: all creation sprites use the current MENU01 palette, not the
    # battle palette embedded in the generic sprite-bank PNGs.
    creation_palette = bytes(v*4 for v in (original / "MENU01.IMG").read_bytes()[-768:])
    def creation_image(raw: bytes, size: tuple[int, int], name: str, key=None):
        im = Image.frombytes("P", size, raw)
        im.putpalette(creation_palette)
        im = im.convert("RGBA")
        if key is not None:
            im.putalpha(Image.frombytes("L", size, bytes(0 if v == key else 255 for v in raw)))
        manifest[name] = save(im, name)
    faces = (original / "FACE.DAT").read_bytes()
    for index in range(103, 109):
        creation_image(faces[index*8000:(index+1)*8000], (80,100), f"creation_face_{index}.png")
    armies = (original / "ARMY.DAT").read_bytes()
    for index in (30,40,32,54):
        start = index * 19 * 48 * 48
        creation_image(armies[start:start+48*48], (48,48), f"creation_army_{index}.png", 0)
    buttons = (original / "BUTTON22.IMG").read_bytes()[16:16+5632]
    for index, state in enumerate(("normal","pressed")):
        creation_image(buttons[index*2816:(index+1)*2816], (88,32), f"creation_button_{state}.png")
    creation_image((original / "MENU30.IMG").read_bytes()[16:16+425], (17,25), "creation_slider.png", 0xF0)
    offsets = [0,36,220,453,637,659,784,939,1120,1415,1515,1763,1914,1995,2003,2125,2282,2341,2627,2783,2903,3126,3432,3756]
    # The last original table entry is raw D7FA, not a Unicode GBK character.
    # Preserve its native HZK slot via a private-use carrier, not U+FFFD or a
    # dropped cell (which would shift the original grid/count).
    groups = ["".join("\ue000" if n == 3755 else bytes((0xB0+n//94,0xA1+n%94)).decode("gbk") for n in range(a,b)) for a,b in zip(offsets,offsets[1:])]
    (GODOT_DATA / "character_creation.json").write_text(json.dumps({
        "source": "42D686/42E2D6/42F938/42FACA; research_character_create_contract_20261025",
        "palette": [list(creation_palette[i:i+3]) for i in range(0,768,3)],
        "name_palette": [list(palette[i:i+3]) for i in range(0,768,3)],
        "name_groups": groups,
    }, ensure_ascii=False, indent=1)+"\n", encoding="utf-8")
    # 4248D9 / 42738A: MENU03 IMG indices are drawn using the battle palette.
    # The two selected rows use the original 4760F8 LUT, not a solid tint.
    retry_pixels = (original / "MENU03.IMG").read_bytes()[16:16 + 128 * 88]
    retry = Image.frombytes("P", (128, 88), retry_pixels)
    retry.putpalette(palette)
    manifest["retry_original.png"] = save(retry.convert("RGBA"), "retry_original.png")
    controls = json.loads((ROOT / "extract/contracts/ui_controls.json").read_text())
    selection_lut = bytes(controls["menu13"]["selected_background_lut"])
    assert len(selection_lut) == 256
    for row in range(2):
        selected = retry.crop((4, 32 + row * 24, 124, 56 + row * 24))
        selected = Image.frombytes("P", selected.size, selected.tobytes().translate(selection_lut))
        selected.putpalette(palette)
        name = f"retry_selected_{row}.png"
        manifest[name] = save(selected.convert("RGBA"), name)
    for name,width,height,transparent in [("FRAME00",404,127,True),("BUTTON00",28,312,False),("BUTTON01",28,312,False),("MENU",88,120,True),("DLZ00",40,360,False),("DLZ01",40,360,False)]:
        src = original / (name + ".TGA")
        if not src.exists():
            continue
        blob = src.read_bytes()
        if len(blob) < width*height:
            continue
        raster = b"".join(blob[len(blob)-(row+1)*width:len(blob)-row*width] for row in range(height))
        indexed = Image.frombytes("P",(width,height),raster)
        indexed.putpalette(palette)
        im = indexed.convert("RGBA")
        if transparent:
            im.putalpha(Image.frombytes("L",(width,height),bytes(0 if v==0 else 255 for v in raster)))
        manifest[name.lower()+"_original.png"] = save(im,name.lower()+"_original.png")

    # 41F935 carries the actual eight-slot item picker, not a modern list.
    pixels = (original / "MENU08.IMG").read_bytes()[16:16+304*227]
    picker = Image.frombytes("P", (304,227), pixels)
    picker.putpalette(palette)
    manifest["item_picker_original.png"] = save(picker.convert("RGBA"), "item_picker_original.png")
    # 426A05 / 426844 share MENU.TGA; single-row uses the last32 rows.
    blob = (original / "MENU.TGA").read_bytes()
    raster = b"".join(blob[len(blob)-(row+1)*88:len(blob)-row*88] for row in range(120))
    source = Image.frombytes("P", (88,120), raster)
    source.putpalette(palette)
    for count in range(1,17):
        if count == 1:
            frame = source.crop((0,88,88,120))
        else:
            frame = Image.new("P", (88,24*count+16)); frame.putpalette(palette)
            frame.paste(source.crop((0,0,88,32)), (0,0))
            for row in range(count-2):frame.paste(source.crop((0,32,88,56)), (0,32+24*row))
            frame.paste(source.crop((0,56,88,88)), (0,32+24*(count-2)))
        name = f"choice_{count}_original.png"
        manifest[name] = save(frame.convert("RGBA"), name)
        if count == 1:continue  # single-row never runs the highlight LUT
        for row in range(count):
            strip = frame.crop((4,8+24*row,84,32+24*row))
            strip = Image.frombytes("P",strip.size,strip.tobytes().translate(selection_lut));strip.putpalette(palette)
            name = f"choice_{count}_selected_{row}.png"
            manifest[name] = save(strip.convert("RGBA"), name)

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
    FLM.mkdir(parents=True, exist_ok=True)
    from native_sprite_assets import generate as native_sprites
    native_sprites(("flm",))
    for index in range(32):
        name = f"flm_{index:03d}.png"
        manifest["flm/" + name] = "res://assets/flm/" + name
    for src in ("MENU01", "MENU02", "K00", "K01", "K02", "K03", "K04", "BG02", "BG03"):
        p = OUT / "img" / f"{src}.png"
        if p.exists():
            shutil.copyfile(p, UI / f"{src.lower()}.png")
            manifest[f"{src.lower()}.png"] = f"res://assets/ui/{src.lower()}.png"
    for num in (1, 2, 3, 4, 5, 6, 7, 8, 18, 19, 20, 21, 22, 25, 29):
        src = OUT / "img" / f"NPIC{num:02d}.png"
        if src.exists():
            dst = UI / f"npic_{num:02d}.png"
            shutil.copyfile(src, dst)
            manifest[dst.name] = "res://assets/ui/" + dst.name
    # 原版历史照片轮播：918-2/918-3/77-1/77-2 + NPIC，
    # 文件名表在 DLZ.exe 0x447DB0，切换循环在 0x42DC9E。
    for src, dst in (("918-2", "history_918_2.png"),
                     ("918-3", "history_918_3.png"),
                     ("77-1", "history_77_1.png"),
                     ("77-2", "history_77_2.png")):
        p = OUT / "img" / f"{src}.png"
        if p.exists():
            shutil.copyfile(p, UI / dst)
            manifest[dst] = "res://assets/ui/" + dst

    (GODOT_DATA / "m3.json").write_text(json.dumps({
        "meta": {
            "title": "抗日：地雷战",
            "font": "res://assets/font/hzk16.fnt",
            "cursor_mode": "system_arrow",
            "viewport": [640, 480],
        },
        "assets": manifest,
    }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    from prepare_native_strategy import prepare as prepare_strategy
    prepare_strategy()
    print("m3 ui assets", len(manifest))
    print("m3.json", (GODOT_DATA / "m3.json").stat().st_size, "bytes")


if __name__ == "__main__":
    main()
