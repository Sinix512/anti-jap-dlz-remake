"""格式校验：把 README/HANDOVER 里的每条结论都跑一遍。

用法：python3 verify.py
任一断言失败即退出码 1；全部通过退出码 0。
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from extract import (blk, fight, game, img, mapdat, palette, people, sprites,
                     town, txt, wave)

ROOT = Path(__file__).resolve().parent
GAME_DIR = Path(os.environ.get("DLZ_GAME", ROOT.parent / "dlz" / "ANTI-JAP"))

checks = 0
failures: list[str] = []


def check(cond: bool, msg: str) -> None:
    global checks
    checks += 1
    if not cond:
        failures.append(msg)
        print(f"  FAIL  {msg}")


def section(title: str) -> None:
    print(f"\n[{title}]")


def main() -> int:
    if not GAME_DIR.is_dir():
        print(f"找不到原版资源目录：{GAME_DIR}", file=sys.stderr)
        return 1

    # ---------------- IMG ----------------
    section("IMG")
    imgs = sorted(GAME_DIR.glob("*.IMG"))
    check(len(imgs) == 86, f"IMG 数量 {len(imgs)} != 86")
    kinds: dict[str, int] = {}
    for p in imgs:
        blob = p.read_bytes()
        geom = img.resolve_geometry(p, blob)
        kinds[geom.kind] = kinds.get(geom.kind, 0) + 1
        check(img.HEADER + geom.width * geom.height + img.PALETTE == len(blob),
              f"{p.name}: 16 + {geom.width}*{geom.height} + 768 != {len(blob)}")
        check(len(img.palette_bytes(blob)) == img.PALETTE,
              f"{p.name}: 调色板长度异常")
    pal_kinds = {"6bit": 0, "8bit": 0, "zero": 0}
    for p in imgs:
        raw = p.read_bytes()[-img.PALETTE:]
        if not any(raw):
            pal_kinds["zero"] += 1
        elif max(raw) > 63:
            pal_kinds["8bit"] += 1
        else:
            pal_kinds["6bit"] += 1
    check(pal_kinds == {"6bit": 83, "8bit": 1, "zero": 2},
          f"IMG 调色板类型统计 {pal_kinds} != 83/1/2")
    check(max(img.palette_bytes((GAME_DIR / "DLZ00.IMG").read_bytes())) == 255,
          "DLZ00 8 位调色板被错误放大")
    check(set(img.palette_bytes((GAME_DIR / "BUTTON00.IMG").read_bytes())) == {0},
          "BUTTON00 空调色板处理异常")
    check(kinds.get("quirk") == 1, f"quirk 数量 {kinds.get('quirk')} != 1")
    check(kinds.get("strip") == 1, f"strip 数量 {kinds.get('strip')} != 1")
    check(kinds.get("plain") == 84, f"常规 IMG 数量 {kinds.get('plain')} != 84")
    e = img.resolve_geometry(GAME_DIR / "END04.IMG")
    check((e.width, e.height) == (320, 200), f"END04 实际尺寸 {e.width}×{e.height} != 320×200")
    z = img.resolve_geometry(GAME_DIR / "ZYB.IMG")
    check((z.width, z.height) == (640, 7562), f"ZYB 实际尺寸 {z.width}×{z.height} != 640×7562")
    print(f"  86 个文件：plain {kinds.get('plain')}, quirk {kinds.get('quirk')}, "
          f"strip {kinds.get('strip')}")

    # ---------------- TXT ----------------
    section("TXT")
    recs = txt.load(GAME_DIR / "TXT.DAT")
    check(len(recs) == 478, f"TXT 记录数 {len(recs)} != 478")
    check(sum(len(r.text) for r in recs) == 55005,
          f"TXT 字数 {sum(len(r.text) for r in recs)} != 55005")
    check(recs[0].number == 4, f"TXT 首条编号 {recs[0].number} != 4")
    check(recs[-1].number == 592, f"TXT 末条编号 {recs[-1].number} != 592")
    print(f"  {len(recs)} 条, {sum(len(r.text) for r in recs)} 字")

    # ---------------- PEOPLE ----------------
    section("PEOPLE")
    roster = people.load(GAME_DIR / "PEOPLE.DAT")
    check(len(roster) == 40, f"PEOPLE 记录数 {len(roster)} != 40")
    check(roster[0].name == "孙悟空", f"PEOPLE[0] 是 {roster[0].name!r}，不是孙悟空")
    for i, p in enumerate(roster):
        check(0 <= p.face <= 169, f"PEOPLE[{i}] face={p.face} 越界 0..169")
        check(0 <= p.bingzhong <= 95, f"PEOPLE[{i}] bingzhong={p.bingzhong} 越界 0..95")
        check(all(0 <= v <= 159 for v in p.wupin),
              f"PEOPLE[{i}] wupin 越界：{p.wupin}")
        check(all(0 <= v <= 9 for v in p.dilei),
              f"PEOPLE[{i}] dilei 越界：{p.dilei}")
    print(f"  40 人；face {min(p.face for p in roster)}..{max(p.face for p in roster)}；"
          f"bingzhong {min(p.bingzhong for p in roster)}..{max(p.bingzhong for p in roster)}")

    # ---------------- GAME ----------------
    section("GAME")
    g = game.load(GAME_DIR / "GAME.DAT")
    check(len(g.units) == 96, f"兵种槽位 {len(g.units)} != 96")
    check(sum(1 for u in g.units if u.name) == 90,
          f"有名兵种 {sum(1 for u in g.units if u.name)} != 90")
    check(len(g.items) == 160, f"物品 {len(g.items)} != 160")
    check(len(g.materials) == 10, f"材料 {len(g.materials)} != 10")
    check(len(g.mines) == 10, f"地雷 {len(g.mines)} != 10")
    check(len(g.skills) == 16, f"技能 {len(g.skills)} != 16")
    check(len(g.item_valid) == 160, f"WuPinValid 行 {len(g.item_valid)} != 160")
    check(all(len(row) == 96 for row in g.item_valid), "WuPinValid 列 != 96")
    check(g.units[0].name == "神仙队", f"兵种[0] 是 {g.units[0].name!r}，不是神仙队")
    check(g.units[1].name == "手枪队", f"兵种[1] 是 {g.units[1].name!r}，不是手枪队")
    check(g.items[0].name == "蟠　桃", f"物品[0] 是 {g.items[0].name!r}，不是蟠桃")
    check(g.materials[0].name == "粘土", f"材料[0] 是 {g.materials[0].name!r}，不是粘土")
    check(g.mines[0].name == "土　雷", f"地雷[0] 是 {g.mines[0].name!r}，不是土雷")
    check(g.skills[0].name == "补给", f"技能[0] 是 {g.skills[0].name!r}，不是补给")
    print(f"  兵种 {len(g.units)}（有名 90）, 物品 {len(g.items)}, "
          f"材料 {len(g.materials)}, 地雷 {len(g.mines)}, 技能 {len(g.skills)}")

    # ---------------- FIGHT ----------------
    section("FIGHT")
    levels = fight.load(GAME_DIR / "FIGHT.DAT")
    check(len(levels) == 47, f"关卡 {len(levels)} != 47")
    check(levels[0].name == "穿越封锁线", f"第 0 关名 {levels[0].name!r} != 穿越封锁线")
    check(levels[0].success.startswith("到达东北角"), f"第 0 关胜利文本异常：{levels[0].success!r}")
    for lv in levels:
        check(bool(lv.name), f"关卡 {lv.index} 名称为空")
        check(len(lv.people) == 88, f"关卡 {lv.index} 人物 {len(lv.people)} != 88")
        for j, p in enumerate(lv.people):
            check(0 <= p.face <= 169, f"关卡 {lv.index} 人物 {j} face={p.face} 越界")
            check(0 <= p.bingzhong <= 95,
                  f"关卡 {lv.index} 人物 {j} bingzhong={p.bingzhong} 越界")
    nonempty = sum(1 for lv in levels for p in lv.people if p.name != "孙悟空")
    check(nonempty == 2210, f"非空战场人物 {nonempty} != 2210")
    print(f"  47 关；非空战场人物 {nonempty}")

    # ---------------- TOWN ----------------
    section("TOWN")
    towns = town.load(GAME_DIR / "TOWN.DAT")
    check(len(towns) == 19, f"城镇 {len(towns)} != 19")
    for t in towns:
        check(len(t.raw_u32) == 81, f"TOWN[{t.index}] u32 段长度 {len(t.raw_u32)} != 81")
        check(len(t.flags) == 11, f"TOWN[{t.index}] flags 长度 {len(t.flags)} != 11")
        check(all(v == -1 or 81 <= v <= 142 for v in t.goods_junxie),
              f"TOWN[{t.index}] goods_junxie 越界：{t.goods_junxie}")
        check(all(v == -1 or 1 <= v <= 80 for v in t.goods_zahuo),
              f"TOWN[{t.index}] goods_zahuo 越界：{t.goods_zahuo}")
        check(all(v == -1 or 0 <= v <= 9 for v in t.goods_material),
              f"TOWN[{t.index}] goods_material 越界：{t.goods_material}")
    print("  19 城镇；商品 ID 分别落在武器 81..142 / 杂货 1..80 / 材料 0..9")

    # ---------------- MAP + BLK ----------------
    section("MAP")
    map_file = mapdat.load(GAME_DIR / "MAP.DAT")
    check(len(map_file.maps) == 47, f"MAP 地图 {len(map_file.maps)} != 47")
    check(len(map_file.slots) == 64, f"MAP 索引槽 {len(map_file.slots)} != 64")
    check(mapdat.INDEX_SIZE == 512, f"MAP 索引区 {mapdat.INDEX_SIZE} != 512")
    used = [(off, length) for off, length in map_file.slots if length]
    check(len(used) == 47, f"MAP 有效索引 {len(used)} != 47")
    end = sum(length for _, length in used)
    check(end == len((GAME_DIR / "MAP.DAT").read_bytes()) - mapdat.INDEX_SIZE,
          f"MAP Data 区 {end} B 与文件长度不符")
    for i in range(47, 64):
        check(map_file.slots[i] == (end, 0),
              f"MAP 空索引槽 {i}={map_file.slots[i]} != ({end}, 0)")
    widths = [m.width for m in map_file.maps]
    heights = [m.height for m in map_file.maps]
    check(min(widths) == 18 and max(widths) == 65,
          f"MAP 宽度范围 {min(widths)}..{max(widths)} != 18..65")
    check(min(heights) == 10 and max(heights) == 60,
          f"MAP 高度范围 {min(heights)}..{max(heights)} != 10..60")
    for rec in map_file.maps:
        check(rec.length == mapdat.HEADER_SIZE + rec.width * rec.height * 2,
              f"地图 {rec.index} length={rec.length} 与 {rec.width}×{rec.height} 不符")
        check(rec.blk_name == f"dlz-{rec.tileset_index:02d}.blk",
              f"地图 {rec.index} blk={rec.blk_name!r} 与 tileset={rec.tileset_index} 不符")
    print(f"  47 张；{min(widths)}..{max(widths)} × {min(heights)}..{max(heights)}；"
          f"Data 区 {end} B")

    section("BLK")
    blk_file = blk.load(GAME_DIR / "BLK.DAT")
    check(len(blk_file.sets) == 16, f"BLK 套 {len(blk_file.sets)} != 16")
    check(blk_file.data_offset == 512, f"BLK Data 起点 {blk_file.data_offset} != 512")
    check(len(blk_file.data) == 15805952, f"BLK 文件长度 {len(blk_file.data)} != 15805952")
    counts = [s.tile_count for s in blk_file.sets]
    check(counts == [512, 512, 512, 468, 468, 468, 512, 468, 0,
                     512, 0, 512, 468, 468, 468, 512],
          f"BLK 各套 tile 数异常：{counts}")
    check(sum(counts) == 6860, f"BLK tile 总数 {sum(counts)} != 6860")
    for rec in map_file.maps:
        s = blk_file.sets[rec.tileset_index]
        check(all((tile & 0x0FFF) < s.tile_count for tile in rec.tiles),
              f"地图 {rec.index} 的 tile 低 12 位超出 {s.name}（{s.tile_count}）")
    print(f"  16 套（7×512 + 7×468 + 2 空），共 {sum(counts)} tiles")

    # ---------------- 纯像素容器 ----------------
    section("SPRITES")
    pal = palette.global_palette(GAME_DIR)
    check(len(pal) == 768, f"通用调色板 {len(pal)} B != 768")
    bank_blobs = {}
    for b in sprites.BANKS:
        blob = sprites.load_bank(GAME_DIR, b)
        bank_blobs[b.name] = blob
        need = (b.count * sprites.PLACE_RECORD_SIZE if b.per_record_palette
                else b.count * b.frame_bytes)
        check(len(blob) == need, f"{b.file_name} 长度 {len(blob)} != {need}")
        check(b.count % b.group_size == 0,
              f"{b.name} 帧数 {b.count} 不是组大小 {b.group_size} 的倍数")
    face = sprites.BANK_BY_NAME["face"]
    army = sprites.BANK_BY_NAME["army"]
    check(face.count == 170, f"FACE 帧数 {face.count} != 170")
    check(army.groups == 91, f"ARMY 组数 {army.groups} != 91")
    check(sprites.BANK_BY_NAME["mine"].groups == 10, "MINE 组数 != 10")
    check(sprites.BANK_BY_NAME["flm"].groups == 32, "FLM 组数 != 32")
    check(sprites.BANK_BY_NAME["goods"].count == 128, "GOODS 数量 != 128")
    check(sprites.BANK_BY_NAME["material"].count == 10, "MATERIAL 数量 != 10")
    check(sprites.BANK_BY_NAME["place"].count == 19, "PLACE 数量 != 19")
    # 抽样确认像素不是全 0、也不是全 255
    for name in ("face", "army", "goods", "place"):
        b = sprites.BANK_BY_NAME[name]
        raw = bank_blobs[name]
        sample = raw[:b.frame_bytes] if not b.per_record_palette else raw[:640 * 480]
        check(len(set(sample)) > 3, f"{b.file_name} 首帧颜色种类过少（可能解码错）")
    print("  FACE 170 / ARMY 91×19 / MINE 10×4 / FLM 32×16 / "
          "GOODS 128 / MATERIAL 10 / PLACE 19")

    # ---------------- WAVE ----------------
    section("WAVE")
    wave_file = wave.load(GAME_DIR / "WAVE.DAT")
    check(len(wave_file.entries) == 1024, f"WAVE 索引项 {len(wave_file.entries)} != 1024")
    check(len(wave_file.nonzero) == 152, f"WAVE 非空段 {len(wave_file.nonzero)} != 152")
    check(len(wave_file.data) == 12992170, f"WAVE 文件长度 {len(wave_file.data)} != 12992170")
    check(sum(e.length for e in wave_file.nonzero) == 12983978,
          "WAVE PCM 总长度 != 12983978")
    check(all(e.offset + e.length <= 12983978 for e in wave_file.nonzero),
          "WAVE 存在越界的 PCM 段")
    check(abs(sum(e.duration for e in wave_file.nonzero) - 294.42) < 0.1,
          f"WAVE 总时长 {sum(e.duration for e in wave_file.nonzero):.2f}s 异常")
    print(f"  1024 索引项，152 段有效，{sum(e.duration for e in wave_file.nonzero):.1f} 秒")

    # ---------------- FIGHT 扩展 ----------------
    section("FIGHT 扩展")
    check(fight.FIGHTER_OFFSET == 700, "Fighter 偏移 != 700")
    check(fight.PEOPLE_OFFSET == 8892, "People 偏移 != 8892")
    check(fight.FIGHTER_SIZE == 64, "Fighter 记录长度 != 64")
    active = 0
    low_active = 0
    chests = 0
    specials = 0
    for lv in levels:
        mrec = map_file.maps[lv.index]
        w, h = mrec.width, mrec.height
        check(len(lv.intro.chests) == 4, f"关卡 {lv.index} 宝箱槽 {len(lv.intro.chests)} != 4")
        check(len(lv.intro.special_positions) == 32,
              f"关卡 {lv.index} 特殊位置 {len(lv.intro.special_positions)} != 32")
        check(len(lv.fighters) == 128, f"关卡 {lv.index} Fighter {len(lv.fighters)} != 128")
        for c in lv.intro.chests:
            if c.empty:
                continue
            chests += 1
            check(0 <= c.x < w and 0 <= c.y < h,
                  f"关卡 {lv.index} 宝箱 {c.index} 坐标越界 ({c.x},{c.y}) / {w}×{h}")
            check(0 <= c.appearance <= 2,
                  f"关卡 {lv.index} 宝箱 {c.index} appearance={c.appearance}")
            check(all(-1 <= v <= 159 for v in (c.wupin, c.wupin0, c.wupin1, c.wupin2)),
                  f"关卡 {lv.index} 宝箱 {c.index} 物品 ID 越界")
        for s in lv.intro.special_positions:
            if s.empty or not (0 <= s.x < w and 0 <= s.y < h):
                continue
            specials += 1
            check(0 <= s.type <= 3, f"关卡 {lv.index} 特殊位置 {s.index} type={s.type}")
        for f in lv.fighters:
            if not f.active:
                continue
            active += 1
            check(0 <= f.pos_x < w and 0 <= f.pos_y < h,
                  f"关卡 {lv.index} 槽 {f.slot} 坐标越界 ({f.pos_x},{f.pos_y}) / {w}×{h}")
            check(0 <= f.direction <= 3,
                  f"关卡 {lv.index} 槽 {f.slot} direction={f.direction}")
            check(f.dest_x == f.pos_x and f.dest_y == f.pos_y,
                  f"关卡 {lv.index} 槽 {f.slot} 初始 dest != pos")
            check(f.dest_direction == f.direction,
                  f"关卡 {lv.index} 槽 {f.slot} dest_direction != direction")
            check(0 <= f.target_x < w and 0 <= f.target_y < h,
                  f"关卡 {lv.index} 槽 {f.slot} target 坐标越界")
            if f.slot < fight.NAMED_SLOTS:
                low_active += 1
                p = roster[f.slot]
                if p.name == "孙悟空":
                    # 彩蛋角色不走兵种公式，基地数据固定 80 HP。
                    check(f.tili == 80,
                          f"关卡 {lv.index} 孙悟空 HP {f.tili} != 80")
                else:
                    u = g.units[p.bingzhong]
                    expect = u.tili + (p.level - 1) * u.tili_plus
                    check(f.tili == expect,
                          f"关卡 {lv.index} 槽 {f.slot} {p.name} HP {f.tili} != {expect}")
    all_fighters = [f for lv in levels for f in lv.fighters]
    sentinel = sum(1 for f in all_fighters if f.tili == 4500)
    sentinel_active = sum(1 for f in all_fighters if f.active and f.tili == 4500)
    check(sentinel == 3807, f"4500 哨兵值 {sentinel} != 3807")
    check(sentinel_active == 1052, f"4500 哨兵值（active）{sentinel_active} != 1052")
    check(all(f.tili_is_sentinel == (f.tili == 4500) for f in all_fighters),
          "tili_is_sentinel 与 tili 不一致")
    check(active == 1377, f"出场单位 {active} != 1377")
    check(low_active == 29, f"出场有名角色 {low_active} != 29")
    check(chests == 102, f"有效宝箱 {chests} != 102")
    check(specials == 440, f"地图内特殊位置 {specials} != 440")
    check(levels[44].name == "中国象棋", f"第 44 关名 {levels[44].name!r}")
    check(levels[45].name == "龟兔赛跑", f"第 45 关名 {levels[45].name!r}")
    check(levels[46].name == "鬼子进村", f"第 46 关名 {levels[46].name!r}")
    print(f"  {active} 个出场单位（其中 {low_active} 个有名角色）；"
          f"{chests} 个宝箱、{specials} 个特殊位置")

    # ---------------- GAME / TOWN 扩展 ----------------
    section("GAME/TOWN 扩展")
    check(len(g.what0) == 160, f"GAME.What0 长度 {len(g.what0)} != 160")
    check(set(g.what0) <= {0, 1}, f"GAME.What0 取值 {sorted(set(g.what0))}")
    check(sum(g.what0) == 118, f"GAME.What0 1 的个数 {sum(g.what0)} != 118")
    check(len(g.mine_terrain) == 10 and all(len(r) == 16 for r in g.mine_terrain),
          "GAME.mine_terrain 不是 10×16")
    check([sum(r) for r in g.mine_terrain] == [8, 10, 9, 15, 15, 15, 14, 14, 9, 9],
          "GAME.mine_terrain 行和不符")
    check(len(g.terrain_modifiers) == 16, "GAME.terrain_modifiers 不是 16 行")
    check(g.terrain_modifiers[0] == [40, -20, 10, 0, 0],
          f"GAME.terrain_modifiers[0]={g.terrain_modifiers[0]}")
    check(g.terrain_modifiers[9] == [20, 0, 15, 20, 10],
          f"GAME.terrain_modifiers[9]={g.terrain_modifiers[9]}")

    wave_ids = {e.index for e in wave_file.nonzero}
    for t in towns:
        check(len(t.sound_hotspots) == 3,
              f"TOWN[{t.index}] 环境音热点 {len(t.sound_hotspots)} != 3")
        check(all(h["wave"] == -1 or 800 <= h["wave"] < 900 for h in t.sound_hotspots),
              f"TOWN[{t.index}] 音效 ID 不在 800 段：{t.sound_hotspots}")
        check(len(t.buildings) == 6, f"TOWN[{t.index}] 建筑槽 {len(t.buildings)} != 6")
        for b in t.buildings:
            for key, limit in (("label_x", 640), ("offset_x", 640),
                               ("label_y", 480), ("offset_y", 480)):
                v = b[key]
                check(v == 999 or 0 <= v <= limit,
                      f"TOWN[{t.index}] 建筑 {b['slot']} {key}={v} 越界")
    check(len(town.TOWN_NAMES) == 19, "城镇名表不是 19 项")
    check(towns[0].as_dict()["name"] == "桃花岭", f"T0 名称 {towns[0].as_dict()['name']!r}")
    check(towns[18].as_dict()["name"] == "天池山", f"T18 名称 {towns[18].as_dict()['name']!r}")
    print("  What0 10×16 可埋矩阵；地形修正 16×5；城镇 3 音热点 + 6 建筑槽；19 个地名")

    # ---------------- data 产物 ----------------
    section("data/ 产物")
    expected = {
        "people.json": (40, lambda d: d["count"]),
        "game.json": (96, lambda d: len(d["units"])),
        "fight.json": (47, lambda d: d["count"]),
        "town.json": (19, lambda d: d["count"]),
        "txt.json": (478, lambda d: d["count"]),
        "map.json": (47, lambda d: d["count"]),
        "blk.json": (16, lambda d: len(d["sets"])),
        "fighter.json": (47, lambda d: d["count"]),
        "wave.json": (152, lambda d: d["nonzero_count"]),
        "face.json": (170, lambda d: len(d["records"])),
        "army.json": (91, lambda d: len(d["records"])),
        "mine.json": (10, lambda d: len(d["records"])),
        "flm.json": (32, lambda d: len(d["records"])),
        "goods.json": (128, lambda d: len(d["records"])),
        "material.json": (10, lambda d: len(d["records"])),
        "place.json": (19, lambda d: len(d["records"])),
        "sprites.json": (7, lambda d: len(d["banks"])),
    }
    import json
    for name, (count, get) in expected.items():
        path = ROOT / "data" / name
        if not path.exists():
            check(False, f"缺文件 data/{name}（先运行 python3 extract_all.py）")
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        actual = get(payload)
        check(actual == count, f"data/{name} count={actual} != {count}")
    print(f"  {len(expected)} 个 JSON 均存在且条数正确")

    # ---------------- out/ 产物 ----------------
    section("out/ 产物")
    pngs = sorted((ROOT / "out" / "img").glob("*.png"))
    check(len(pngs) == 86, f"out/img PNG 数量 {len(pngs)} != 86")
    if len(pngs) == 86:
        from PIL import Image
        with Image.open(ROOT / "out" / "img" / "END04.png") as im:
            check(im.size == (320, 200), f"END04.png 尺寸 {im.size} != (320, 200)")
        with Image.open(ROOT / "out" / "img" / "ZYB.png") as im:
            check(im.size == (640, 7562), f"ZYB.png 尺寸 {im.size} != (640, 7562)")

    from PIL import Image
    expected_counts = {
        "map": 47, "map/thumb": 47, "face": 170, "army": 91, "mine": 10,
        "flm": 32, "goods": 128, "material": 10, "place": 19, "wave": 152,
        "blk": 14, "atlas": 7,
    }
    for sub, count in expected_counts.items():
        actual = len(list((ROOT / "out" / sub).glob("*.png" if sub != "wave" else "*.wav")))
        check(actual == count, f"out/{sub} 文件数 {actual} != {count}")

    for rec in map_file.maps:
        path = ROOT / "out" / "map" / f"map_{rec.index:02d}.png"
        if not path.exists():
            check(False, f"缺地图 PNG {path}")
            continue
        with Image.open(path) as im:
            check(im.size == (rec.width * 48, rec.height * 48),
                  f"map_{rec.index:02d} 尺寸 {im.size} != "
                  f"({rec.width * 48}, {rec.height * 48})")

    samples = {
        "face/face_000.png": (80, 100),
        "army/army_000.png": (912, 48),
        "mine/mine_000.png": (192, 48),
        "flm/flm_000.png": (768, 48),
        "goods/goods_000.png": (48, 48),
        "material/material_00.png": (48, 48),
        "place/place_00.png": (640, 480),
    }
    for rel, size in samples.items():
        path = ROOT / "out" / rel
        if not path.exists():
            check(False, f"缺 sprite {path}")
            continue
        with Image.open(path) as im:
            check(im.size == size, f"{rel} 尺寸 {im.size} != {size}")
    print("  86 张 IMG；47 张地图 / 170 头像 / 91 兵种 / 152 音效等产物齐全；"
          "END04 320×200、ZYB 640×7562")

    print(f"\n共 {checks} 项断言，失败 {len(failures)} 项")
    if failures:
        for f in failures:
            print(f"  - {f}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())