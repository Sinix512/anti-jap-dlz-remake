"""从 M0/M1 产物生成 M2 战略层数据与资产。

只读 data/、out/ 与 ../dlz/ANTI-JAP，写到 godot/data/m2.json + godot/assets。
可重复执行；产物不入库。

用法：
    python3 tools/prepare_m1.py   # 先保证 m1.json/assets/font 存在
    python3 tools/prepare_m2.py
"""
from __future__ import annotations

import importlib.util
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT.parent / "dlz" / "ANTI-JAP"
DATA = ROOT / "data"
OUT = ROOT / "out"
GODOT = ROOT / "godot"
ASSETS = GODOT / "assets"
GODOT_DATA = GODOT / "data"
TILE = 48

STARTING_PARTY = [3, 2, 1, 4, 7]          # 张嘎 / 赵虎 / 朱老忠 / 李向阳 / 柳忻
STARTING_MONEY = 6000
STARTING_DAY = 1
MAX_PARTY = 10
STARTING_TOWN = 0
RECRUIT_BASE = 200
RECRUIT_PER_LEVEL = 80
BATTLE_REWARD = 800
BATTLE_LEVELS = [14, 8]

STARTING_ITEMS = {68: 1, 69: 1, 71: 1, 79: 1, 1: 2, 14: 2, 21: 1, 81: 1}
# 武功/野战/战术/红巾 + 复刻初始补给（核桃/干粮/米酒）+ 钢刀
STARTING_MATERIALS = {0: 30, 1: 30, 2: 20, 3: 15, 4: 15,
                      5: 15, 6: 15, 7: 6, 8: 6, 9: 3}
STARTING_MINES = {0: 1}


def load(name: str):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def _m1_module():
    spec = importlib.util.spec_from_file_location(
        "prepare_m1", Path(__file__).with_name("prepare_m1.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def copy_asset(src: Path, rel: str) -> str:
    dst = ASSETS / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    return "res://assets/" + rel


def main():
    m1 = _m1_module()
    game = load("game.json")
    people = load("people.json")["records"]
    towns_raw = load("town.json")["towns"]
    m1_data = (json.loads((GODOT_DATA / "m1.json").read_text(encoding="utf-8"))
                if (GODOT_DATA / "m1.json").exists() else {})

    ASSETS.mkdir(parents=True, exist_ok=True)
    GODOT_DATA.mkdir(parents=True, exist_ok=True)

    # 全量资产（M2 的角色/商店可能用到任意图标）
    for i in range(19):
        copy_asset(OUT / "place" / f"place_{i:02d}.png",
                   f"place/place_{i:02d}.png")
    for i in range(170):
        p = OUT / "face" / f"face_{i:03d}.png"
        if p.exists():
            copy_asset(p, f"face/face_{i:03d}.png")
    for i in range(91):
        p = OUT / "army" / f"army_{i:03d}.png"
        if p.exists():
            copy_asset(p, f"army/army_{i:03d}.png")
    for i in range(128):
        p = OUT / "goods" / f"goods_{i:03d}.png"
        if p.exists():
            copy_asset(p, f"goods/goods_{i:03d}.png")
    for i in range(10):
        p = OUT / "material" / f"material_{i:02d}.png"
        if p.exists():
            copy_asset(p, f"material/material_{i:02d}.png")
    for i in range(10):
        p = OUT / "mine" / f"mine_{i:03d}.png"
        if p.exists():
            copy_asset(p, f"mine/mine_{i:03d}.png")
    bigmap = ""
    if (OUT / "img" / "BIGMAP.png").exists():
        bigmap = copy_asset(OUT / "img" / "BIGMAP.png", "ui/bigmap.png")

    units = {str(u["index"]): u for u in game["units"]}
    items = {}
    for it in game["items"]:
        icon = f"res://assets/goods/goods_{it['goods']:03d}.png"
        items[str(it["index"])] = {
            **it,
            "icon": icon,
        }
    materials = {}
    for m in game["materials"]:
        materials[str(m["index"])] = {
            **m,
            "icon": f"res://assets/material/material_{m['index']:02d}.png",
        }
    mines = {}
    for m in game["mines"]:
        mines[str(m["index"])] = {
            **m,
            "icon": f"res://assets/mine/mine_{m['index']:03d}.png",
            "recipe": game["mine_recipes"][m["index"]],
        }

    people_out = []
    for pid, p in enumerate(people):
        u = units[str(p["bingzhong"])]
        target = int(u.get("zhuanzhi", -1))
        item_id = int(u.get("zhuanzhidaoju", -1))
        promo_item = items.get(str(item_id)) if item_id >= 0 else None
        max_hp = max(1, int(u["tili"]) + (int(p["level"]) - 1) * int(u["tili_plus"]))
        people_out.append({
            "pid": pid,
            "name": p["name"],
            "face": p["face"],
            "face_png": f"res://assets/face/face_{p['face']:03d}.png",
            "bingzhong": p["bingzhong"],
            "unit_name": u["name"],
            "level": p["level"],
            "wuli": p["wuli"],
            "zhili": p["zhili"],
            "unknown_18": p["unknown_18"],
            "wupin": p["wupin"],
            "dilei": p["dilei"],
            "skills": p["skills"],
            "max_hp": max_hp,
            "army_png": f"res://assets/army/army_{u['img_index']:03d}.png",
            "unit": u,
            "recruit_cost": RECRUIT_BASE + int(p["level"]) * RECRUIT_PER_LEVEL,
            "promotion": {
                "target": target,
                "target_name": units.get(str(target), {}).get("name", ""),
                "item_id": item_id,
                "item_name": promo_item["name"] if promo_item else "",
                "item_price": promo_item["price"] if promo_item else 0,
            },
        })

    towns_out = []
    for t in towns_raw:
        town = {
            "index": t["index"],
            "name": t["name"],
            "bg": f"res://assets/place/place_{t['index']:02d}.png",
            "buildings": t["buildings"],
            "sound_hotspots": t["sound_hotspots"],
            "shops": {
                "junxie": [items[str(i)] for i in t["goods_junxie"]
                            if str(i) in items],
                "zahuo": [items[str(i)] for i in t["goods_zahuo"]
                           if str(i) in items],
                "material": [materials[str(i)] for i in t["goods_material"]
                             if str(i) in materials],
            },
        }
        towns_out.append(town)

    battle_tables = {
        "unit_types": units,
        "unit_move": {str(i): game["unit_move"][i] for i in range(96)},
        "select_ranges": {str(i): game["select_ranges"][i] for i in range(16)},
        "terrain_modifiers": game["terrain_modifiers"],
        "mines": game["mines"],
        "mine_terrain": game["mine_terrain"],
        "meta": {
            "tile": TILE,
            "mine_type": 0,
            "mines": 3,
            "font": "res://assets/font/hzk16.fnt",
            "font_size": 16,
            "mine_png": "res://assets/mine/mine_000.png",
        },
    }

    payload = {
        "meta": {
            "title": "抗日：地雷战 / M2 战略层",
            "version": 1,
            "tile": TILE,
            "font": "res://assets/font/hzk16.fnt",
            "font_size": 16,
            "bigmap": bigmap,
            "starting_town": STARTING_TOWN,
            "starting_money": STARTING_MONEY,
            "starting_day": STARTING_DAY,
            "max_party": MAX_PARTY,
            "recruit_base": RECRUIT_BASE,
            "recruit_per_level": RECRUIT_PER_LEVEL,
            "battle_reward": BATTLE_REWARD,
            "battle_levels": BATTLE_LEVELS,
            "save_prefix": "dlz_m2_save_",
            "save_slots": 3,
        },
        "towns": towns_out,
        "people": people_out,
        "items": items,
        "materials": materials,
        "mines": mines,
        "units": units,
        "skills": game["skills"],
        "mine_recipes": game["mine_recipes"],
        "starting": {
            "party": STARTING_PARTY,
            "items": {str(k): v for k, v in STARTING_ITEMS.items()},
            "materials": {str(k): v for k, v in STARTING_MATERIALS.items()},
            "mines": {str(k): v for k, v in STARTING_MINES.items()},
        },
        "battle": battle_tables,
    }
    (GODOT_DATA / "m2.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    # 字库：M2 脚本 + M2 全部数据 + M1 数据
    texts = [json.dumps(payload, ensure_ascii=False)]
    if m1_data:
        texts.append(json.dumps(m1_data, ensure_ascii=False))
    for gd in sorted((GODOT / "scripts").rglob("*.gd")):
        texts.append(gd.read_text(encoding="utf-8"))
    glyphs, atlas = m1.build_font(texts)
    print("towns", len(towns_out), "people", len(people_out),
          "items", len(items), "materials", len(materials), "mines", len(mines))
    print("font", glyphs, "glyphs", atlas)
    print("m2.json", (GODOT_DATA / "m2.json").stat().st_size, "bytes")


if __name__ == "__main__":
    main()
