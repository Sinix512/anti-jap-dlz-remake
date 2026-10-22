"""格式校验：把 README/HANDOVER 里的每条结论都跑一遍。

用法：python3 verify.py
任一断言失败即退出码 1；全部通过退出码 0。
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from extract import fight, game, img, people, town, txt

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

    # ---------------- data 产物 ----------------
    section("data/ 产物")
    expected = {
        "people.json": (40, lambda d: d["count"]),
        "game.json": (96, lambda d: len(d["units"])),
        "fight.json": (47, lambda d: d["count"]),
        "town.json": (19, lambda d: d["count"]),
        "txt.json": (478, lambda d: d["count"]),
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
    print("  5 个 JSON 均存在且条数正确")

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
    print("  86 张 PNG；END04 320×200、ZYB 640×7562")

    print(f"\n共 {checks} 项断言，失败 {len(failures)} 项")
    if failures:
        for f in failures:
            print(f"  - {f}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())