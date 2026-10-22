"""一键抽取：原版 ANTI-JAP → out/（PNG、对话文本）+ data/（引擎无关 JSON）。

数据管线的约定见 HANDOVER.md：
    Python 只产出 data/*.json + 图片；Godot 只读这层，不直接解析原版 DAT。
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from extract import fight, game, img, people, town, txt

ROOT = Path(__file__).resolve().parent
GAME_DIR = Path(os.environ.get("DLZ_GAME", ROOT.parent / "dlz" / "ANTI-JAP"))
OUT = ROOT / "out"
DATA = ROOT / "data"


def dump(rel: str, obj) -> Path:
    path = DATA / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1) + "\n",
                    encoding="utf-8")
    return path


def main() -> int:
    if not GAME_DIR.is_dir():
        print(f"找不到原版资源目录：{GAME_DIR}", file=sys.stderr)
        return 1

    # --- IMG ---
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

    # --- TXT ---
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

    # --- PEOPLE ---
    roster = people.load(GAME_DIR / "PEOPLE.DAT")
    dump("people.json", {
        "source": "PEOPLE.DAT",
        "record_size": people.RECORD_SIZE,
        "count": len(roster),
        "records": [p.as_dict() for p in roster],
    })
    print(f"PEOPLE: {len(roster)} 人")

    # --- GAME ---
    g = game.load(GAME_DIR / "GAME.DAT")
    payload = g.as_dict()
    payload.update({
        "source": "GAME.DAT",
        "unit_size": game.UNIT_SIZE,
        "item_size": game.ITEM_SIZE,
    })
    dump("game.json", payload)
    print(f"GAME: {len(g.units)} 兵种, {len(g.items)} 物品, "
          f"{len(g.materials)} 材料, {len(g.mines)} 地雷, "
          f"{len(g.skills)} 技能")

    # --- FIGHT ---
    levels = fight.load(GAME_DIR / "FIGHT.DAT")
    dump("fight.json", {
        "source": "FIGHT.DAT",
        "level_size": fight.LEVEL_SIZE,
        "people_offset": fight.PEOPLE_OFFSET,
        "count": len(levels),
        "levels": [lv.as_dict() for lv in levels],
    })
    print(f"FIGHT: {len(levels)} 关, "
          f"{sum(1 for lv in levels for p in lv.people if p.name != '孙悟空')} 个非空战场人物")

    # --- TOWN ---
    towns = town.load(GAME_DIR / "TOWN.DAT")
    dump("town.json", {
        "source": "TOWN.DAT",
        "record_size": town.RECORD_SIZE,
        "count": len(towns),
        "towns": [t.as_dict() for t in towns],
    })
    print(f"TOWN: {len(towns)} 城镇")

    return 0 if bad == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())