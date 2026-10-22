"""M5 剧情数据：478 条 TXT、说话人/头像、关卡剧情、结局与过场索引。

只读 data/、out/、godot/data/m4.json，写 godot/data/m5.json + 结局图。
产物不入库。

用法：
    python3 tools/prepare_m5.py
"""
from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = ROOT / "out"
GODOT = ROOT / "godot"
ASSETS = GODOT / "assets"
UI = ASSETS / "ui"
GODOT_DATA = GODOT / "data"

# TXT 行首的两位说话人码：00 = 主角 GG，01..39 = PEOPLE.DAT 对应角色，
# 40+ = 敌军/旁白。这个映射由 00-39 与 40 人表的对话内容逐条对照得到。
ENEMY_NAMES = {
    40: ("日军军官", 70), 41: ("日军", 69), 42: ("伪军", 78),
    43: ("特务", 96), 44: ("日军", 69), 45: ("伪军", 78),
    46: ("日军", 69), 47: ("汉奸", 99), 48: ("国军", 21),
    49: ("日军军官", 70), 50: ("日军军官", 70), 51: ("日军", 69),
    52: ("日军", 69), 53: ("日军军官", 70), 54: ("伪军", 78),
    55: ("汉奸", 99), 56: ("日军高官", 143), 57: ("刘麻子", 99),
    58: ("日军高官", 143), 59: ("将军", 143), 60: ("日军", 69),
    61: ("日军", 69), 62: ("日军", 69), 63: ("日军", 69),
    64: ("日军", 69), 65: ("日军", 69), 66: ("日军", 69),
    67: ("坂垣", 143), 68: ("坂垣", 143), 69: ("日军", 69),
    70: ("日军高官", 70), 71: ("松井", 143), 72: ("日军", 69),
    73: ("日军", 69), 74: ("日军高官", 70), 75: ("日军", 69),
    76: ("日军", 69), 77: ("日军", 69), 78: ("日军", 69),
    79: ("日军", 69), 80: ("日军高官", 143), 81: ("日军", 69),
    82: ("日军", 69), 83: ("日军", 69), 84: ("日军高官", 143),
    85: ("日军高官", 143), 86: ("日军高官", 143), 87: ("军区首长", 143),
    88: ("军区首长", 143),
}


def load(name: str):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def norm(s: str) -> str:
    return str(s).replace("\u3000", "").replace(" ", "")


def speaker_for(code: int, people: list[dict]) -> tuple[str, int]:
    if code == 0:
        return "GG", -1
    if 1 <= code <= 39:
        p = people[code]
        return norm(p["name"]), int(p["face"])
    if code in ENEMY_NAMES:
        return ENEMY_NAMES[code]
    if code >= 90:
        return "旁白", -1
    return "敌军", 69


def parse_record(rec: dict, people: list[dict]) -> dict:
    lines = []
    for raw in rec["text"].splitlines():
        m = re.match(r"^(\d{2})(.*)$", raw)
        if m:
            code = int(m.group(1))
            text = m.group(2)
            name, face = speaker_for(code, people)
            lines.append({"code": code, "speaker": name, "face": face,
                          "text": text})
        elif raw.strip():
            lines.append({"code": -1, "speaker": "旁白", "face": -1,
                          "text": raw})
    return {"n": int(rec["n"]), "lines": lines, "raw": rec["text"]}


def main() -> None:
    people = load("people.json")["records"]
    txt = load("txt.json")["records"]
    m4 = json.loads((GODOT_DATA / "m4.json").read_text(encoding="utf-8")) \
        if (GODOT_DATA / "m4.json").exists() else {"levels": []}
    UI.mkdir(parents=True, exist_ok=True)
    GODOT_DATA.mkdir(parents=True, exist_ok=True)

    records = [parse_record(r, people) for r in txt]
    by_n = {r["n"]: r for r in records}

    # 结局图：END00 640×480；END01-05 320×200，放大到 640×400 居中
    for i in range(6):
        src = OUT / "img" / f"END{i:02d}.png"
        if not src.exists():
            continue
        im = Image.open(src).convert("RGB")
        if im.size != (640, 480):
            im = im.resize((640, 400), Image.NEAREST)
            canvas = Image.new("RGB", (640, 480), (0, 0, 0))
            canvas.paste(im, (0, 40))
            im = canvas
        im.save(UI / f"end_{i:02d}.png")
    for src, dst in (("JZ-1", "jz1.png"), ("JZ-2", "jz2.png"),
                     ("ZYB", "credits.png")):
        p = OUT / "img" / f"{src}.png"
        if p.exists():
            shutil.copyfile(p, UI / dst)

    # 关卡剧情：前 2 条作开场，后 2 条作收尾；完整列表仍保留供回顾
    scenes = {}
    for lv in m4.get("levels", []):
        ids = [int(n) for n in lv.get("story_ids", []) if int(n) in by_n]
        # 去重但保留顺序
        seen = set()
        ids = [n for n in ids if not (n in seen or seen.add(n))]
        intro = ids[:2]
        outro = ids[-2:] if len(ids) > 2 else []
        # 战斗内事件：从中间的 TXT 记录里按关键词归到回合/死亡/宝箱/到达。
        # 不能确定的记录保留在 all/archive，不假装有触发器。
        mid = ids[2:-2] if len(ids) >= 6 else []
        unit_names = []
        for u in lv.get("units", []):
            if u.get("side") == "enemy" and u.get("key"):
                unit_names.append(str(u["key"]))
        events = []
        used = set()
        # 第一遍：优先保留宝箱/增援/死亡/到达等明确关键词事件。
        for n in mid:
            if len(events) >= 4:
                break
            rec = by_n.get(n)
            if rec is None:
                continue
            text = str(rec.get("raw", ""))
            ev = None
            if ("宝箱" in text or "武器" in text or "弹药" in text) and \
                    not any(e["trigger"] == "chest" for e in events):
                ev = {"trigger": "chest", "ids": [n]}
            elif ("增援" in text or "援兵" in text or "援军" in text):
                for tt in (2, 3, 4, 5):
                    if not any(e["trigger"] == "turn" and int(e.get("turn", 0)) == tt
                            for e in events):
                        ev = {"trigger": "turn", "turn": tt, "ids": [n]}
                        break
            else:
                for name in unit_names:
                    if name and name in text:
                        ev = {"trigger": "unit_died", "key": name, "ids": [n]}
                        break
            if ev is None and ("到达" in text or "山神庙" in text) and \
                    not any(e["trigger"] == "reach" for e in events):
                ev = {"trigger": "reach", "ids": [n]}
            if ev is not None and n not in used:
                used.add(n)
                events.append(ev)
        # 第二遍：剩余 mid 记录填入未占用的回合事件，最多 4 个事件/关。
        for n in mid:
            if len(events) >= 4:
                break
            if n in used or n not in by_n:
                continue
            for tt in (3, 4, 5, 2):
                if not any(e["trigger"] == "turn" and int(e.get("turn", 0)) == tt
                        for e in events):
                    events.append({"trigger": "turn", "turn": tt, "ids": [n]})
                    used.add(n)
                    break
        scenes[str(lv["index"])] = {
            "intro": intro,
            "outro": outro,
            "all": ids,
            "events": events,
        }
        for n in ids:
            rec = by_n.get(n)
            if rec is None:
                continue
            if n in intro:
                rec["trigger"] = "start"
            elif n in outro:
                rec["trigger"] = "victory"
            else:
                rec["trigger"] = "archive"
        for ev in events:
            for n in ev["ids"]:
                if n in by_n:
                    by_n[n]["trigger"] = ev["trigger"]

    # 全量 478 条加上 trigger / level 元数据：未能挂事件的明确标为 archive，
    # 不假装已接入战斗；level=-1 表示不属于任何关卡场景。
    for r in records:
        r.setdefault("trigger", "archive")
        r.setdefault("level", -1)
    for k in scenes:
        for n in scenes[k].get("all", []):
            if int(n) in by_n:
                by_n[int(n)]["level"] = int(k)

    # 剧情档案：按 n 顺序每 20 条一组
    archive = []
    for i in range(0, len(records), 20):
        chunk = records[i:i + 20]
        archive.append({
            "start": chunk[0]["n"],
            "end": chunk[-1]["n"],
            "ids": [r["n"] for r in chunk],
        })

    media_path = GODOT_DATA / "m5_media.json"
    media = json.loads(media_path.read_text(encoding="utf-8")) \
        if media_path.exists() else {"clips": [], "flc": [], "anm": []}
    clips = media.get("clips", [])
    media["mpeg"] = [c for c in clips if c.get("kind") == "mpeg"]
    media["flc"] = [c for c in clips if c.get("kind") == "flc"]
    anm_path = GODOT_DATA / "m5_anm.json"
    media["anm"] = json.loads(anm_path.read_text(encoding="utf-8")) \
        if anm_path.exists() else {"files": []}
    for f in media["anm"].get("files", []):
        dec = f.get("decode", {})
        webm = str(dec.get("webm_path", ""))
        if webm.startswith("res://"):
            ogv = webm[:-5] + ".ogv" if webm.endswith(".webm") else ""
            if ogv and (GODOT / ogv.replace("res://", "")).exists():
                dec["ogv_path"] = ogv

    endings = [
        {"id": 0, "score": 0, "image": "res://assets/ui/end_00.png",
         "title": "未竟之路",
         "text": "平阳的硝烟未散，游击队的名字却已传遍冀中。\n"
                 "你们还会回来。"},
        {"id": 1, "score": 2800, "image": "res://assets/ui/end_01.png",
         "title": "初出茅庐",
         "text": "平阳根据地站稳了脚跟。\n"
                 "地雷战、地道战，从这片土地上传向整个华北。"},
        {"id": 2, "score": 3000, "image": "res://assets/ui/end_02.png",
         "title": "继往开来",
         "text": "敌人被赶出了平阳。\n"
                 "新的任务在等着这支从群众中走出来的队伍。"},
        {"id": 3, "score": 3300, "image": "res://assets/ui/end_03.png",
         "title": "战斗英雄",
         "text": "平阳的铁路回到了人民手中。\n"
                 "那些埋在土地里的雷，见证了人民战争的力量。"},
        {"id": 4, "score": 3600, "image": "res://assets/ui/end_05.png",
         "title": "支前模范",
         "text": "从平阳到华北，从游击到反攻。\n"
                 "每一座村庄、每一条地道，都是胜利的根基。"},
        {"id": 5, "score": 2800, "image": "res://assets/ui/end_04.png",
         "title": "部队休整",
         "text": "隐藏关的硝烟散去。\n"
                 "历史与虚构在此交汇，而人民仍在书写自己的故事。"},
    ]

    payload = {
        "meta": {
            "title": "抗日：地雷战 / M5 剧情",
            "version": 1,
            "font": "res://assets/font/hzk16.fnt",
            "player_default": "李勇",
            "placeholder_note": "GG=主角名；AA/BB/CC/DD/TT=原版强调/地名/物品/时间占位符，运行时去标记。",
            "record_count": len(records),
            "hidden_unlock_score": 2800,
            "ending_thresholds": [2800, 3000, 3300, 3600],
        },
        "records": records,
        "scenes": scenes,
        "archive": archive,
        "endings": endings,
        "media": media,
        "credits_image": "res://assets/ui/credits.png",
    }
    (GODOT_DATA / "m5.json").write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8")
    print("records", len(records), "scenes", len(scenes),
          "archive", len(archive), "endings", len(endings))
    print("media clips", len(media.get("clips", [])),
          "flc", len(media.get("flc", [])), "anm", len(media.get("anm", [])))
    print("m5.json", (GODOT_DATA / "m5.json").stat().st_size, "bytes")


if __name__ == "__main__":
    main()
