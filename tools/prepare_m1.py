"""从 M0 的 data/out 生成 Godot M1 所需的紧凑数据与资产。

只读 dlz-remake/data 与 dlz-remake/out，写到 godot/data 与 godot/assets。
可重复执行；产物不入库（体积 + 版权）。

用法：
    python3 tools/prepare_m1.py
"""
from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT.parent / "dlz" / "ANTI-JAP"
DATA = ROOT / "data"
OUT = ROOT / "out"
GODOT = ROOT / "godot"
ASSETS = GODOT / "assets"
GODOT_DATA = GODOT / "data"

# M1 先做两关：默认 L14 地道战；L08 救援白洋淀 作为第二张图。
LEVELS = (14, 8)
DEFAULT_LEVEL = 14
TILE = 48
MINE_TYPE = 0
MINES = 3

CN_DIGITS = {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
             "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def load(name: str):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def cn_number(text: str) -> int:
    text = text.replace(" ", "").replace("\u3000", "")
    if not text:
        return 0
    if text.isdigit():
        return int(text)
    if "十" in text:
        left, _, right = text.partition("十")
        tens = CN_DIGITS.get(left, 1) if left else 1
        ones = CN_DIGITS.get(right, 0) if right else 0
        return tens * 10 + ones
    return CN_DIGITS.get(text, 0)


def turn_limit(failure: str) -> int:
    key = "超过"
    pos = failure.find(key)
    if pos < 0:
        return 0
    tail = failure[pos + len(key):]
    end = tail.find("个回合")
    if end < 0:
        return 0
    return cn_number(tail[:end])


def parse_fail_units(failure: str, player_names: list[str]) -> list[str]:
    out = []
    for name in player_names:
        if name and name in failure and "阵亡" in failure:
            out.append(name)
    return out


def hzk_glyph(ch: str) -> bytes | None:
    try:
        b = ch.encode("gb2312")
    except UnicodeEncodeError:
        return None
    if len(b) != 2:
        return None
    q, w = b[0] - 0xA1, b[1] - 0xA1
    if not (0 <= q < 94 and 0 <= w < 94):
        return None
    off = (q * 94 + w) * 32
    return HZK[off:off + 32]


def ascii_glyph(ch: str) -> bytes | None:
    o = ord(ch)
    if not 32 <= o < 127:
        return None
    off = o * 16
    return ASC[off:off + 16]


def build_font(texts: list[str]):
    hzk_path = GAME / "HZK16"
    asc_path = GAME / "ASC16"
    global HZK, ASC
    HZK = hzk_path.read_bytes()
    ASC = asc_path.read_bytes()

    chars = set()
    for t in texts:
        chars.update(t)
    for c in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" \
             " .,:;!?+-*/()[]%<>=\"'":
        chars.add(c)
    chars.add("?")
    chars.add(" ")

    glyphs = []
    seen = set()
    for ch in sorted(chars, key=ord):
        if ord(ch) < 32:
            continue
        if ord(ch) < 127:
            data = ascii_glyph(ch)
            w = 8
        else:
            data = hzk_glyph(ch)
            w = 16
        if data is None:
            if ch in seen:
                continue
            ch = "?"
            data = ascii_glyph("?")
            w = 8
        cp = ord(ch)
        if cp in seen:
            continue
        seen.add(cp)
        glyphs.append((cp, w, data))

    cols = 16
    cell = 20
    rows = max(1, math.ceil(len(glyphs) / cols))
    atlas = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
    px = atlas.load()
    for i, (cp, w, data) in enumerate(glyphs):
        x0 = (i % cols) * cell
        y0 = (i // cols) * cell
        if w == 8:
            for y in range(16):
                byte = data[y]
                for x in range(8):
                    if byte & (0x80 >> x):
                        px[x0 + x, y0 + y] = (255, 255, 255, 255)
        else:
            for y in range(16):
                bits = (data[y * 2] << 8) | data[y * 2 + 1]
                for x in range(16):
                    if bits & (0x8000 >> x):
                        px[x0 + x, y0 + y] = (255, 255, 255, 255)

    font_dir = ASSETS / "font"
    font_dir.mkdir(parents=True, exist_ok=True)
    atlas.save(font_dir / "hzk16_0.png")
    lines = [
        'info face="HZK16" size=16 bold=0 italic=0 charset="" unicode=1 '
        'stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1',
        f'common lineHeight=18 base=14 scaleW={atlas.width} '
        f'scaleH={atlas.height} pages=1 packed=0',
        'page id=0 file="hzk16_0.png"',
        f'chars count={len(glyphs)}',
    ]
    for i, (cp, w, data) in enumerate(glyphs):
        x0 = (i % cols) * cell
        y0 = (i // cols) * cell
        lines.append(
            f'char id={cp} x={x0} y={y0} width={w} height=16 xoffset=0 '
            f'yoffset=0 xadvance={w} page=0 chnl=15'
        )
    (font_dir / "hzk16.fnt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(glyphs), atlas.size


def copy_asset(src: Path, rel: str) -> str:
    dst = ASSETS / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    return "res://assets/" + rel


def main():
    maps = load("map.json")["maps"]
    levels = load("fight.json")["levels"]
    fighters = load("fighter.json")["levels"]
    game = load("game.json")
    people = load("people.json")["records"]

    ASSETS.mkdir(parents=True, exist_ok=True)
    GODOT_DATA.mkdir(parents=True, exist_ok=True)
    (ASSETS / "map").mkdir(parents=True, exist_ok=True)

    used_types: set[int] = set()
    used_select: set[int] = set()
    out_levels = []
    font_texts: list[str] = []

    for lidx in LEVELS:
        m = maps[lidx]
        lv = levels[lidx]
        fl = fighters[lidx]
        w, h = m["width"], m["height"]
        terrain = [((v >> 12) & 0xF) for v in m["tiles"]]
        map_png = copy_asset(OUT / "map" / f"map_{lidx:02d}.png",
                             f"map/map_{lidx:02d}.png")
        units = []
        player_names = []
        for f in fl["fighters"]:
            if not f["active"]:
                continue
            slot = f["slot"]
            if slot < 40:
                p = people[slot]
                side = "player"
            else:
                p = lv["people"][slot - 40]
                side = "enemy"
            bz = p["bingzhong"]
            u = game["units"][bz]
            raw_hp = f["tili"]
            if raw_hp == 4500:
                hp = u["tili"] + (p["level"] - 1) * u["tili_plus"]
                hp_source = "formula"
            else:
                hp = raw_hp
                hp_source = "explicit"
            hp = max(1, int(hp))
            if side == "player":
                player_names.append(f["unit"])
            face_png = ""
            if 0 <= p["face"] < 170:
                face_png = copy_asset(OUT / "face" / f"face_{p['face']:03d}.png",
                                      f"face/face_{p['face']:03d}.png")
            army_png = ""
            if 0 <= u["img_index"] < 91:
                army_png = copy_asset(OUT / "army" / f"army_{u['img_index']:03d}.png",
                                      f"army/army_{u['img_index']:03d}.png")
            used_types.add(bz)
            used_select.add(u["select"])
            units.append({
                "slot": slot,
                "side": side,
                "name": f["unit"],
                "unit_name": u["name"],
                "bingzhong": bz,
                "level": p["level"],
                "wuli": p["wuli"],
                "zhili": p["zhili"],
                "hp": hp,
                "raw_hp": raw_hp,
                "hp_source": hp_source,
                "x": f["pos_x"],
                "y": f["pos_y"],
                "direction": f["direction"],
                "face": p["face"],
                "face_png": face_png,
                "army_png": army_png,
                "select": u["select"],
                "apply": u["apply"],
                "move": u["yidong"],
                "gongji": u["gongji"],
                "fangyu": u["fangyu"],
                "tili": u["tili"],
                "tili_plus": u["tili_plus"],
                "is_boss": hp >= 1000,
            })
        players = [u for u in units if u["side"] == "player"]
        enemies = [u for u in units if u["side"] == "enemy"]
        px = sum(u["x"] for u in players) / max(1, len(players))
        py = sum(u["y"] for u in players) / max(1, len(players))
        tl = turn_limit(lv["failure"])
        fail_units = parse_fail_units(lv["failure"], player_names)
        out_levels.append({
            "index": lidx,
            "name": lv["name"],
            "success": lv["success"].strip(),
            "failure": lv["failure"].strip(),
            "turn_limit": tl,
            "fail_units": fail_units,
            "map": {
                "width": w,
                "height": h,
                "tile": TILE,
                "png": map_png,
                "blk": m["blk"],
                "terrain": terrain,
                "player_focus": [px, py],
            },
            "players": len(players),
            "enemies": len(enemies),
            "units": units,
            "chests": [c for c in lv["intro"]["chests"] if not c["empty"]],
        })
        font_texts.extend([lv["name"], lv["success"], lv["failure"]])

    for lv in out_levels:
        for u in lv["units"]:
            font_texts.extend([u["name"], u["unit_name"]])
    for t in game["units"]:
        if t["index"] in used_types and t["name"]:
            font_texts.append(t["name"])
    for m in game["mines"]:
        font_texts.append(m["name"])

    mine_png = copy_asset(OUT / "mine" / "mine_000.png", "mine/mine_000.png")
    font_texts += [
        "抗日：地雷战", "M1 单关试玩", "选择关卡", "开始", "返回", "重来",
        "回合", "我方回合", "敌方回合", "敌方行动中", "胜利", "失败",
        "目标", "全歼敌人", "体力", "攻击", "防御", "移动", "攻击范围",
        "待机", "埋雷", "结束回合", "取消", "剩余地雷", "伤害", "等级",
        "点击我方单位", "左键选择 / 移动 / 攻击", "方向键平移 / 滚轮缩放",
        "右键取消", "已行动", "地雷", "土雷", "敌军", "我军", "关卡",
        "超过三十个回合", "李霜泗阵亡", "战斗结束", "按任意键继续",
        "M1 演示：地图/单位/移动/攻击/地雷",
    ]
    # 把 Godot 脚本里的 UI 文案也收进字库，避免“第/颗/状态/待命”等漏字。
    for gd in sorted((GODOT / "scripts").glob("*.gd")):
        font_texts.append(gd.read_text(encoding="utf-8"))

    glyph_count, atlas_size = build_font(font_texts)

    used_types_js = {str(k): game["units"][k] for k in sorted(used_types)}
    used_move = {str(k): game["unit_move"][k] for k in sorted(used_types)}
    used_ranges = {str(k): game["select_ranges"][k] for k in sorted(used_select)}
    used_ranges.setdefault("1", game["select_ranges"][1])

    payload = {
        "meta": {
            "title": "抗日：地雷战 / M1",
            "tile": TILE,
            "default_level": DEFAULT_LEVEL,
            "mine_type": MINE_TYPE,
            "mines": MINES,
            "font": "res://assets/font/hzk16.fnt",
            "font_size": 16,
            "font_glyphs": glyph_count,
            "font_atlas": list(atlas_size),
        },
        "levels": out_levels,
        "unit_types": used_types_js,
        "unit_move": used_move,
        "select_ranges": used_ranges,
        "terrain_modifiers": game["terrain_modifiers"],
        "mines": game["mines"],
        "mine_terrain": game["mine_terrain"],
        "mine_png": mine_png,
    }
    (GODOT_DATA / "m1.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
    )
    print("levels", [(l["index"], l["name"], l["players"], l["enemies"]) for l in out_levels])
    print("unit_types", len(used_types_js), "select_ranges", len(used_ranges))
    print("font", glyph_count, "glyphs", atlas_size)
    print("m1.json", (GODOT_DATA / 'm1.json').stat().st_size, "bytes")


if __name__ == "__main__":
    main()
