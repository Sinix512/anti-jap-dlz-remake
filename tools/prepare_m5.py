"""M5 剧情数据：稀疏 TXT 槽、说话人/头像、章节分支、结局与过场索引。

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

# DLZ.exe 4294BE: entry uses gate4476D8 and TXT[521+2*level];
# victory has already incremented level, uses gate447798 and TXT[520+2*new].
# These are NOT difficulty-dependent A/base variants.
CHAPTER_ENTRY_ENABLED = {0, 6, 9, 13, 27}
CHAPTER_VICTORY_ENABLED = set(range(22)) | {24} | set(range(27, 37))


def chapter_transitions(by_n: dict, levels: list[dict], media: dict) -> dict:
    """Exact 47-level chapter MPEG/TXT branch facts; no guessed fallback."""
    clips = {str(c.get("id", "")): c for c in media.get("mpeg", [])}
    by_level = {int(lv["index"]): lv for lv in levels}
    result = {}
    for level in range(47):
        entries = {}
        for kind, loaded_level, text_id, enabled, movie in (
            ("entry", level, 521 + 2 * level,
             level in CHAPTER_ENTRY_ENABLED, f"d{level + 1:02d}a"),
            ("victory", level + 1, 522 + 2 * level,
             level + 1 in CHAPTER_VICTORY_ENABLED, f"d{level + 1:02d}"),
        ):
            clip = clips.get(movie, {})
            text = by_n.get(text_id)
            entries[kind] = {
                "enabled": enabled,
                "loaded_level_index": loaded_level,
                "speaker_level": loaded_level,
                "mpeg_id": movie,
                "mpeg_path": clip.get("ogv_path", clip.get("path", "")),
                "mpeg_available": bool(clip),
                "text_id": text_id,
                "text_table_address": f"0x{0x472588 + text_id * 4:x}",
                "text_present": text is not None,
                "text_empty": text is None or not bool(text.get("lines")),
            }
        entries["entry"]["initial_entry_only"] = True
        entries["entry"]["guard"] = "global583F54==0"
        entries["victory"]["phase_calls"] = bool(by_level.get(level, {}).get(
            "victory_phase", {}).get("plays_base_transition", False))
        result[str(level)] = entries
    return result

# 原版历史照片轮播：文件名表 0x447DB0，切换循环 0x42DC9E。
# ticks 是照片开始显示的计时器阈值；55ms/tick，npic25在tick0显示。
HISTORY_PHOTOS = [
    ("npic25", "npic_25.png", 0),
    ("918-2", "history_918_2.png", 0x113),
    ("918-3", "history_918_3.png", 0x226),
    ("77-1", "history_77_1.png", 0x352),
    ("77-2", "history_77_2.png", 0x5AA),
    ("npic18", "npic_18.png", 0x753),
    ("npic19", "npic_19.png", 0x7D0),
    ("npic20", "npic_20.png", 0x84D),
    ("npic21", "npic_21.png", 0x8CA),
    ("npic22", "npic_22.png", 0x947),
    ("npic29", "npic_29.png", 0x9C4),
    ("npic08", "npic_08.png", 0xB22),
    ("npic07", "npic_07.png", 0xBD1),
    ("npic06", "npic_06.png", 0xC80),
    ("npic05", "npic_05.png", 0xD2F),
    ("npic04", "npic_04.png", 0xDDE),
    ("npic03", "npic_03.png", 0xE8D),
    ("npic02", "npic_02.png", 0xF3C),
    ("npic01", "npic_01.png", 0xFEB),
]

# TXT 行首的两位说话人码：00 = 主角 GG，01..39 = PEOPLE.DAT 对应角色，
# 40+ = 敌军/旁白。这个映射由 00-39 与 40 人表的对话内容逐条对照得到。
ENEMY_NAMES = {
    40: ("日军军官", 70), 41: ("日军", 69), 42: ("伪军", 78),
    43: ("特务", 96), 44: ("日军", 69), 45: ("伪军", 78),
    46: ("日军", 69), 47: ("汉奸", 99), 48: ("日军高官", 143),
    49: ("日军军官", 70), 50: ("日军军官", 70), 51: ("日军", 69),
    52: ("日军", 69), 53: ("日军军官", 70), 54: ("日军", 69),
    55: ("汉奸", 99), 56: ("汉奸", 99), 57: ("刘麻子", 99),
    58: ("日军高官", 143), 59: ("将军", 143), 60: ("日军", 69),
    61: ("日军", 69), 62: ("日军", 69), 63: ("日军", 69),
    64: ("日军", 69), 65: ("日军", 69), 66: ("日军", 69),
    67: ("坂垣", 143), 68: ("矶谷", 143), 69: ("日军", 69),
    70: ("汉奸", 70), 71: ("松井", 143), 72: ("日军", 69),
    73: ("日军", 69), 74: ("日军高官", 70), 75: ("日军", 69),
    76: ("俘虏", 69), 77: ("日军", 69), 78: ("日军", 69),
    79: ("日军", 69), 80: ("日军高官", 143), 81: ("日军", 69),
    82: ("日军", 69), 83: ("日军", 69), 84: ("日军高官", 143),
    85: ("日军高官", 143), 86: ("日军高官", 143), 87: ("军区首长", 143),
    88: ("军区首长", 143),
    # TXT 521 三行以 98/99 开头，内容是军区司令部下达任务，不是旁白。
    98: ("军区首长", 143), 99: ("军区首长", 143),
}

# 40+ 是“场景内角色码”，同一个码在不同关卡可以是不同人。这里只对
# 台词能直接确定说话者的记录做覆盖，避免把全局表当成绝对映射。
SPEAKER_OVERRIDES = {
    30: {49: ("国军", 21)},       # “高镇长，我们支援您来了！”
    65: {50: ("汉奸", 99)},       # “八路一来，第一个做掉你！”
    119: {50: ("日军军官", 70)},  # “火车怎么停下来了？”
    264: {48: ("汉奸", 99)},      # “你的亲爹来了。”
}


def load(name: str):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def norm(s: str) -> str:
    return str(s).replace("\u3000", "").replace(" ", "")


def speaker_for(code: int, people: list[dict], n: int = -1) -> tuple[str, int]:
    ov = SPEAKER_OVERRIDES.get(n, {})
    if code in ov:
        return ov[code]
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


def native_segments(stream: str) -> list[tuple[int, str]]:
    """43CC96: physical lines are already removed by43C9EC, not boundaries."""
    raw = stream.encode("gb18030"); cursor = 0; result = []
    while cursor + 1 < len(raw) and raw[cursor] != 0:
        head = raw[cursor:cursor+2]; cursor += 2
        code = int(head) if len(head) == 2 and all(48 <= b <= 57 for b in head) else -1
        start = cursor
        while cursor < len(raw) and raw[cursor] != 0:
            value = raw[cursor]
            if value >= 128 or value in b"ABCD": cursor += 1
            elif value in b"GT": cursor += 2 # original does not validate second byte
            else: break
        result.append((code, raw[start:cursor].decode("gb18030")))
    return result


def parse_record(rec: dict, people: list[dict]) -> dict:
    if "native_stream" not in rec:
        raise ValueError("Missing native_stream: rerun extract_all.prepare_txt(); physical lines are not native records")
    lines = []
    for code, text in native_segments(rec["native_stream"]):
        name, face = speaker_for(code, people, int(rec["n"])) if code >= 0 else ("旁白", -1)
        lines.append({"code": code, "speaker": name, "face": face, "text": text})
    return {"n": int(rec["n"]), "lines": lines, "raw": rec["text"],
            "native_stream": rec["native_stream"]}


def main() -> None:
    people = load("people.json")["records"]
    txt = load("txt.json")["records"]
    m4 = json.loads((GODOT_DATA / "m4.json").read_text(encoding="utf-8")) \
        if (GODOT_DATA / "m4.json").exists() else {"levels": []}
    UI.mkdir(parents=True, exist_ok=True)
    GODOT_DATA.mkdir(parents=True, exist_ok=True)

    records = [parse_record(r, people) for r in txt]
    by_n = {r["n"]: r for r in records}

    # 40E709 uses426059 pixel-only loads: END keeps live KUANG04, not the
    # embedded END palette. END01..05 remain320x200 on black at(160,80).
    original = ROOT.parent / "dlz" / "ANTI-JAP"
    end_palette = bytes(v * 4 for v in (original / "KUANG04.IMG").read_bytes()[-768:])
    for i in range(6):
        src = original / f"END{i:02d}.IMG"
        if not src.exists():
            continue
        size = (640, 480) if i == 0 else (320, 200)
        im = Image.frombytes("P", size, src.read_bytes()[16:16 + size[0] * size[1]])
        im.putpalette(end_palette)
        im = im.convert("RGB")
        if im.size != (640, 480):
            canvas = Image.new("RGB", (640, 480), (0, 0, 0))
            canvas.paste(im, (160, 80))
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
    # 4294BE: A版是初次战斗入口，base是上一关胜利后的章节过渡。
    # 动画flag只在MPEG与对应TXT间选择，不在A/base间选择。
    present_bases = set()
    for c in media["mpeg"]:
        cid = str(c.get("id", ""))
        if cid.startswith("d") and cid[1:].isdigit():
            c["entry"] = "victory_transition"
            c["entry_level"] = int(cid[1:]) - 1
            c["loaded_level_index"] = int(cid[1:])
            present_bases.add(int(cid[1:]))
        elif cid.startswith("d") and cid.endswith("a") and cid[1:-1].isdigit():
            c["entry"] = "battle_entry"
            c["entry_level"] = int(cid[1:-1]) - 1
            c["loaded_level_index"] = int(cid[1:-1]) - 1
        else:
            c["entry"] = "archive"
    media["mpeg_missing_bases"] = [n for n in range(1, 37)
                                   if n not in present_bases]
    media["mpeg_entry_note"] = (
        "base dNN在L(NN-1)胜利并加载下一关后播放；A版是初次战斗入口。"
        "7D06BC=0播放MPEG，=1显示章节TXT；缺失影片静默跳过，不自动文字fallback。")
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

    endings = [{"id":i, "image":f"res://assets/ui/end_{i:02d}.png",
                "records":records, "title":f"原版后记 {i+1}"}
               for i,records in enumerate([[401],[403],[402],[404],[405,406],[407]])]


    history = []
    for i, (src, dst, ticks) in enumerate(HISTORY_PHOTOS):
        # 42E0F1/42DC9E center unscaled native IMG dimensions and fill with
        # the nearest palette black. Every one of these 19 shipped palettes
        # has an exact RGB(0,0,0), so its first match is the weighted minimum
        # independent of the positive channel weights used by 421D10.
        original = (ROOT.parent / "dlz" / "ANTI-JAP" / (src.upper() + ".IMG")).read_bytes()
        raw_palette = original[-768:]
        scale = 1 if max(raw_palette) > 63 else 4
        colors = [list(raw_palette[p:p+3]) for p in range(0,768,3)]
        colors = [[min(255, c*scale) for c in rgb] for rgb in colors]
        black = colors.index([0,0,0])
        with Image.open(UI / dst) as image:
            width, height = image.size
        history.append({
            "index": i, "id": src, "path": "res://assets/ui/" + dst,
            "ticks": ticks, "width": width, "height": height,
            "background_rgb": colors[black], "background_index": black,
        })

    payload = {
        "meta": {
            "title": "抗日：地雷战 / M5 剧情",
            "version": 1,
            "font": "res://assets/font/hzk16.fnt",
            "player_default": "李勇",
            "placeholder_note": "GG=主角名，TT=当前关卡名；AA/BB/CC/DD强调下一个字。",
            "record_count": len(records),
            "text_table_base": "0x472588",
            "text_table_slot_count": 640,
            "record_index_note": "records只含非空槽；n是原TXT槽号，不是此数组下标，无偏移。",
            "hidden_unlock_score": 2800,
            "ending_thresholds": [2800, 3000, 3300, 3600],
        },
        "records": records,
        "scenes": scenes,
        "archive": archive,
        "endings": endings,
        "media": media,
        "chapter_transitions": chapter_transitions(by_n, m4.get("levels", []), media),
        "chapter_branch": {
            "function": "0x4294be",
            "animation_flag": "0x7d06bc",
            "flag0": "MPEG",
            "flag1": "TXT",
            "missing_mpeg": "skip; never automatically substitute TXT",
            "entry_text_formula": "521+2*level",
            "victory_text_formula": "522+2*old_level",
        },
        "history": history,
        "credits_image": "res://assets/ui/credits.png",
    }
    (GODOT_DATA / "m5.json").write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8")
    (GODOT_DATA / "m5_history.json").write_text(
        json.dumps({"meta": {
            "source": "DLZ.exe filename table 0x447DB0 / loop 0x42DC9E",
            "count": len(history),
        }, "photos": history}, ensure_ascii=False, indent=1) + "\n",
        encoding="utf-8")
    print("records", len(records), "scenes", len(scenes),
          "archive", len(archive), "endings", len(endings))
    print("media clips", len(media.get("clips", [])),
          "flc", len(media.get("flc", [])), "anm", len(media.get("anm", [])))
    print("m5.json", (GODOT_DATA / "m5.json").stat().st_size, "bytes")


if __name__ == "__main__":
    main()
