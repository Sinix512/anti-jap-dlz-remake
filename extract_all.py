"""一键抽取：原版 ANTI-JAP → out/（PNG/WAV）+ data/（引擎无关 JSON）。

M0 覆盖全部 15 个 DAT：

    IMG / TXT / PEOPLE / GAME / FIGHT / TOWN / MAP / BLK
    FACE / ARMY / MINE / FLM / GOODS / MATERIAL / PLACE / WAVE

数据管线的约定见 HANDOVER.md：
    Python 只产出 data/*.json + 图片/音频；Godot 只读这层，不直接解析原版 DAT。
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from PIL import Image

from extract import (blk, fight, game, img, mapdat, palette, people, sprites,
                     town, txt, wave)

ROOT = Path(__file__).resolve().parent
GAME_DIR = Path(os.environ.get("DLZ_GAME", ROOT.parent / "dlz" / "ANTI-JAP"))
OUT = ROOT / "out"
DATA = ROOT / "data"


def dump(rel: str, obj, indent: int | None = 1) -> Path:
    path = DATA / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=indent) + "\n",
                    encoding="utf-8")
    return path


def save_contact(image: Image.Image, rel: str) -> Path:
    path = OUT / "atlas" / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


def main() -> int:
    if not GAME_DIR.is_dir():
        print(f"找不到原版资源目录：{GAME_DIR}", file=sys.stderr)
        return 1

    # ---------------- IMG ----------------
    ok = bad = 0
    fails: list[tuple[str, str]] = []
    quirks: list[tuple[str, img.Geometry]] = []
    for p in sorted(GAME_DIR.glob("*.IMG")):
        try:
            geom = img.save_png(p, OUT / "img" / (p.stem + ".png"))
            ok += 1
            if geom.kind != "plain":
                quirks.append((p.name, geom))
        except Exception as exc:  # noqa: BLE001 - 汇总后统一报告
            bad += 1
            fails.append((p.name, str(exc)))
    print(f"IMG: {ok} 成功, {bad} 失败")
    for name, geom in quirks:
        print(f"  {name}: 头部 640×480 → 实际 {geom.width}×{geom.height}"
              f"（{geom.kind}）")
    for name, err in fails:
        print(f"  FAIL {name}: {err}")

    # ---------------- TXT ----------------
    recs = txt.load(GAME_DIR / "TXT.DAT")
    dialogue = "\n\n".join(f"#{r.number}\n{r.text}" for r in recs)
    (OUT / "txt").mkdir(parents=True, exist_ok=True)
    (OUT / "txt" / "dialogue.txt").write_text(dialogue, encoding="utf-8")
    dump("txt.json", {
        "source": "TXT.DAT",
        "count": len(recs),
        "chars": sum(len(r.text) for r in recs),
        "records": [{"n": r.number, "text": r.text} for r in recs],
    })
    print(f"TXT: {len(recs)} 条, {sum(len(r.text) for r in recs)} 字")

    # ---------------- PEOPLE ----------------
    roster = people.load(GAME_DIR / "PEOPLE.DAT")
    dump("people.json", {
        "source": "PEOPLE.DAT",
        "record_size": people.RECORD_SIZE,
        "count": len(roster),
        "records": [p.as_dict() for p in roster],
    })
    print(f"PEOPLE: {len(roster)} 人")

    # ---------------- GAME ----------------
    g = game.load(GAME_DIR / "GAME.DAT")
    payload = g.as_dict()
    payload.update({
        "source": "GAME.DAT",
        "unit_size": game.UNIT_SIZE,
        "item_size": game.ITEM_SIZE,
        "what0_size": game.WHAT0_SIZE,
        "terrain_count": game.TERRAIN_COUNT,
        "terrain_modifier_size": game.TERRAIN_MOD_SIZE,
    })
    dump("game.json", payload)
    print(f"GAME: {len(g.units)} 兵种, {len(g.items)} 物品, "
          f"{len(g.materials)} 材料, {len(g.mines)} 地雷, "
          f"{len(g.skills)} 技能, 地形修正 16×5, 可埋矩阵 10×16")

    # ---------------- TOWN ----------------
    towns = town.load(GAME_DIR / "TOWN.DAT")
    dump("town.json", {
        "source": "TOWN.DAT",
        "record_size": town.RECORD_SIZE,
        "count": len(towns),
        "towns": [t.as_dict() for t in towns],
    })
    print(f"TOWN: {len(towns)} 城镇")

    # ---------------- MAP + BLK ----------------
    map_file = mapdat.load(GAME_DIR / "MAP.DAT")
    blk_file = blk.load(GAME_DIR / "BLK.DAT")
    pal = palette.global_palette(GAME_DIR)

    # ---------------- FIGHT ----------------
    levels = fight.load(GAME_DIR / "FIGHT.DAT")
    fight_payload = {
        "source": "FIGHT.DAT",
        "level_size": fight.LEVEL_SIZE,
        "intro_size": fight.INTRO_SIZE,
        "fighter_offset": fight.FIGHTER_OFFSET,
        "fighter_count": fight.FIGHTER_COUNT,
        "fighter_size": fight.FIGHTER_SIZE,
        "people_offset": fight.PEOPLE_OFFSET,
        "people_count": fight.PEOPLE_COUNT,
        "chest_count": fight.CHEST_COUNT,
        "chest_size": fight.CHEST_SIZE,
        "special_count": fight.SPECIAL_COUNT,
        "special_size": fight.SPECIAL_SIZE,
        "count": len(levels),
        "levels": [],
    }
    fighter_levels = []
    active_total = 0
    chest_total = 0
    special_total = 0
    for lv in levels:
        mrec = map_file.maps[lv.index]
        width, height = mrec.width, mrec.height
        names = lv.roster_names(roster)
        level_dict = lv.as_dict()
        level_dict.pop("fighters", None)
        level_dict["map"] = {
            "index": mrec.index,
            "width": width,
            "height": height,
            "pixel_width": width * mapdat.TILE_SIZE,
            "pixel_height": height * mapdat.TILE_SIZE,
            "blk": mrec.blk_name,
            "pal": mrec.pal_name,
        }
        level_dict["named_slots"] = [
            {"slot": i, "name": roster[i].name if i < len(roster) else ""}
            for i in range(fight.NAMED_SLOTS)
        ]
        # 宝箱 / 特殊位置加地图边界信息
        for c in level_dict["intro"]["chests"]:
            c["in_bounds"] = (
                not c["empty"] and 0 <= c["x"] < width and 0 <= c["y"] < height
            )
            if not c["empty"]:
                chest_total += 1
        for s in level_dict["intro"]["special_positions"]:
            s["in_bounds"] = (
                not s["empty"] and 0 <= s["x"] < width and 0 <= s["y"] < height
            )
            count = level_dict["intro"]["special_count_raw"]
            s["within_count"] = (s["index"] < count) if 0 <= count <= fight.SPECIAL_COUNT else None
            if s["in_bounds"]:
                special_total += 1
        fight_payload["levels"].append(level_dict)

        fighters = []
        for f in lv.fighters:
            d = f.as_dict()
            d["unit"] = names[f.slot]
            d["unit_source"] = "PEOPLE.DAT" if f.slot < fight.NAMED_SLOTS else "FIGHT.People"
            d["in_map"] = d["active"] and 0 <= d["pos_x"] < width and 0 <= d["pos_y"] < height
            if d["active"]:
                active_total += 1
            fighters.append(d)
        fighter_levels.append({
            "index": lv.index,
            "name": lv.name,
            "map": level_dict["map"],
            "count": len(fighters),
            "fighters": fighters,
        })

    dump("fight.json", fight_payload)
    dump("fighter.json", {
        "source": "FIGHT.DAT",
        "fighter_offset": fight.FIGHTER_OFFSET,
        "fighter_size": fight.FIGHTER_SIZE,
        "named_slots": fight.NAMED_SLOTS,
        "count": len(fighter_levels),
        "levels": fighter_levels,
    }, indent=None)
    print(f"FIGHT: {len(levels)} 关, {active_total} 个出场单位, "
          f"{chest_total} 个宝箱, {special_total} 个特殊位置")

    # ---------------- MAP + BLK ----------------
    maps_payload = []
    (OUT / "map" / "thumb").mkdir(parents=True, exist_ok=True)
    for rec in map_file.maps:
        lv = levels[rec.index]
        item = rec.as_dict()
        item["name"] = lv.name
        item["map_png"] = f"out/map/map_{rec.index:02d}.png"
        maps_payload.append(item)
        blk.save_map_png(rec, blk_file, pal,
                         OUT / "map" / f"map_{rec.index:02d}.png")
        thumb = blk.render_map(rec, blk_file, pal)
        thumb.thumbnail((320, 320), Image.NEAREST)
        thumb.save(OUT / "map" / "thumb" / f"map_{rec.index:02d}.png")
    dump("map.json", {
        "source": "MAP.DAT",
        "index_size": mapdat.INDEX_SIZE,
        "index_slots": mapdat.INDEX_SLOTS,
        "header_size": mapdat.HEADER_SIZE,
        "tile_size": mapdat.TILE_SIZE,
        "count": len(map_file.maps),
        "maps": maps_payload,
    })
    blk_payload = blk_file.as_dict()
    blk_payload["source"] = "BLK.DAT"
    dump("blk.json", blk_payload)
    for s in blk_file.sets:
        if not s.tile_count:
            continue
        blk.save_tilesheet(blk_file, s.index, pal,
                           OUT / "blk" / f"dlz-{s.index:02d}.png")
    print(f"MAP: {len(map_file.maps)} 张, 尺寸 "
          f"{min(m.width for m in map_file.maps)}..{max(m.width for m in map_file.maps)}"
          f"×{min(m.height for m in map_file.maps)}..{max(m.height for m in map_file.maps)}; "
          f"BLK: {len(blk_file.sets)} 套 / "
          f"{sum(s.tile_count for s in blk_file.sets)} tiles")

    # ---------------- 纯像素容器 ----------------
    bank_data = {b.name: sprites.load_bank(GAME_DIR, b) for b in sprites.BANKS}
    bank = sprites.BANK_BY_NAME

    # FACE：170 张头像，附 PEOPLE.DAT / FIGHT.People 里用到该脸的名字
    face_names: dict[int, list[str]] = {i: [] for i in range(bank["face"].count)}
    for p in roster:
        if 0 <= p.face < bank["face"].count and p.name not in face_names[p.face]:
            face_names[p.face].append(p.name)
    for lv in levels:
        for p in lv.people:
            if 0 <= p.face < bank["face"].count and p.name not in face_names[p.face]:
                face_names[p.face].append(p.name)
    for i in range(bank["face"].count):
        sprites.save_frame(sprites.frame_bytes(bank_data["face"], bank["face"], i),
                           bank["face"], pal,
                           OUT / "face" / f"face_{i:03d}.png")
    save_contact(sprites.contact_sheet(bank_data["face"], bank["face"], pal,
                                      columns=10),
                 "face.png")
    dump("face.json", {
        "source": "FACE.DAT",
        "bank": bank["face"].as_dict(),
        "records": [{"index": i, "names": face_names[i]}
                    for i in range(bank["face"].count)],
    })

    # ARMY：91 兵种 × 19 帧
    army_names: dict[int, list[str]] = {i: [] for i in range(bank["army"].groups)}
    for u in g.units:
        if 0 <= u.img_index < bank["army"].groups and u.name and u.name not in army_names[u.img_index]:
            army_names[u.img_index].append(u.name)
    sprites.save_group_sheets(bank_data["army"], bank["army"], pal, OUT / "army")
    save_contact(sprites.contact_sheet(bank_data["army"], bank["army"], pal,
                                      columns=10),
                 "army.png")
    dump("army.json", {
        "source": "ARMY.DAT",
        "bank": bank["army"].as_dict(),
        "records": [{"index": i, "frames": bank["army"].group_size,
                     "names": army_names[i]}
                    for i in range(bank["army"].groups)],
    })

    # MINE：10 雷 × 4 帧
    sprites.save_group_sheets(bank_data["mine"], bank["mine"], pal, OUT / "mine")
    save_contact(sprites.contact_sheet(bank_data["mine"], bank["mine"], pal,
                                      columns=10, scale=2),
                 "mine.png")
    dump("mine.json", {
        "source": "MINE.DAT",
        "bank": bank["mine"].as_dict(),
        "records": [{"index": m.index, "name": m.name, "price": m.price,
                     "weili": m.weili, "shiqi_or_tili": m.shiqi_or_tili,
                     "apply_fw": m.apply_fw, "flm_index": m.flm_index,
                     "audio_index": m.audio_index}
                    for m in g.mines],
    })

    # FLM：32 动画 × 16 帧，标出被技能/地雷引用
    flm_uses: dict[int, list[str]] = {i: [] for i in range(bank["flm"].groups)}
    for s in g.skills:
        if 0 <= s.flm_index < bank["flm"].groups:
            flm_uses[s.flm_index].append(f"技能:{s.name}")
    for m in g.mines:
        if 0 <= m.flm_index < bank["flm"].groups:
            flm_uses[m.flm_index].append(f"地雷:{m.name}")
    sprites.save_group_sheets(bank_data["flm"], bank["flm"], pal, OUT / "flm")
    save_contact(sprites.contact_sheet(bank_data["flm"], bank["flm"], pal,
                                      columns=16),
                 "flm.png")
    dump("flm.json", {
        "source": "FLM.DAT",
        "bank": bank["flm"].as_dict(),
        "records": [{"index": i, "frames": bank["flm"].group_size,
                     "used_by": flm_uses[i]}
                    for i in range(bank["flm"].groups)],
    })

    # GOODS / MATERIAL：图标
    goods_items: dict[int, list[str]] = {i: [] for i in range(bank["goods"].count)}
    for it in g.items:
        if 0 <= it.goods < bank["goods"].count:
            goods_items[it.goods].append(it.name)
    for i in range(bank["goods"].count):
        sprites.save_frame(sprites.frame_bytes(bank_data["goods"], bank["goods"], i),
                           bank["goods"], pal,
                           OUT / "goods" / f"goods_{i:03d}.png")
    save_contact(sprites.contact_sheet(bank_data["goods"], bank["goods"], pal,
                                      columns=16),
                 "goods.png")
    dump("goods.json", {
        "source": "GOODS.DAT",
        "bank": bank["goods"].as_dict(),
        "records": [{"index": i, "item_names": goods_items[i]}
                    for i in range(bank["goods"].count)],
    })

    for i in range(bank["material"].count):
        sprites.save_frame(
            sprites.frame_bytes(bank_data["material"], bank["material"], i),
            bank["material"], pal, OUT / "material" / f"material_{i:02d}.png")
    save_contact(sprites.contact_sheet(bank_data["material"], bank["material"],
                                      pal, columns=10, scale=2),
                 "material.png")
    dump("material.json", {
        "source": "MATERIAL.DAT",
        "bank": bank["material"].as_dict(),
        "records": [{"index": m.index, "name": m.name, "unit": m.unit,
                     "price": m.price}
                    for m in g.materials],
    })

    # PLACE：19 张城镇背景，自带调色板
    place_paths = sprites.save_places(bank_data["place"], bank["place"],
                                      palette.place_palette, OUT / "place")
    save_contact(sprites.place_contact_sheet(bank_data["place"], bank["place"],
                                             palette.place_palette),
                 "place.png")
    dump("place.json", {
        "source": "PLACE.DAT",
        "bank": bank["place"].as_dict(),
        "records": [{"index": i, "name": town.TOWN_NAMES[i],
                     "png": f"out/place/place_{i:02d}.png"}
                    for i in range(bank["place"].count)],
    })
    dump("sprites.json", {
        "palette_source": palette.GLOBAL_PALETTE_SOURCE,
        "banks": [b.as_dict() for b in sprites.BANKS],
        "counts": {
            "face": bank["face"].count,
            "army": bank["army"].groups,
            "mine": bank["mine"].groups,
            "flm": bank["flm"].groups,
            "goods": bank["goods"].count,
            "material": bank["material"].count,
            "place": len(place_paths),
        },
    })
    print(f"SPRITES: FACE {bank['face'].count}; ARMY {bank['army'].groups}×"
          f"{bank['army'].group_size}; MINE {bank['mine'].groups}×"
          f"{bank['mine'].group_size}; FLM {bank['flm'].groups}×"
          f"{bank['flm'].group_size}; GOODS {bank['goods'].count}; "
          f"MATERIAL {bank['material'].count}; PLACE {len(place_paths)}")

    # ---------------- WAVE ----------------
    wave_file = wave.load(GAME_DIR / "WAVE.DAT")
    wavs = wave.export_wavs(wave_file, OUT / "wave")
    wave_payload = wave_file.as_dict()
    wave_payload["source"] = "WAVE.DAT"
    wave_payload["wav_dir"] = "out/wave"
    dump("wave.json", wave_payload)
    print(f"WAVE: {len(wavs)} 段音效, "
          f"{sum(e.duration for e in wave_file.nonzero):.1f} 秒")

    return 0 if bad == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
