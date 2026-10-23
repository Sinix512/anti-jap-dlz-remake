"""M4 战役数据：把 FIGHT/MAP/PEOPLE 的 47 关全部数据化。

只读 data/ 与 out/，写 godot/data/m4.json + godot/assets/map/*.png。
产物不入库。

设计原则：
- 关卡数据只描述“原版里有什么”，运行时逻辑在 GDScript；
- 敌我按 FIGHT.People.unknown_18 判定（0 友方 / 1 敌方），不再按槽位 <40；
- 未出场但在图内的 Fighter 记录作为增援池（reserve）；
- 36 个主线关 + 8 个隐藏关（模拟/虚构）+ 3 个彩蛋关；
- 目标、保护名单、城镇映射是“可玩性复刻”，在 meta 里标明。

用法：
    python3 tools/prepare_m4.py
"""
from __future__ import annotations

import json
import shutil
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from trigger_data import TRIGGERS as LEVEL_TRIGGERS


def _trigger_spawn_slots(trig: dict) -> set:
    """所有 spawn / spawn_range 槽位；这些记录必须保留给运行时生成。"""
    out = set()

    def walk(node) -> None:
        if isinstance(node, dict):
            if "spawn" in node:
                out.add(int(node["spawn"]))
            if "spawn_range" in node:
                r = node["spawn_range"]
                out.update(range(int(r["from"]), int(r["to"])))
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(trig.get("rules", []))
    return out


TRIGGER_SPAWN_SLOTS = {i: _trigger_spawn_slots(t)
                       for i, t in LEVEL_TRIGGERS.items()}

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = ROOT / "out"
GODOT = ROOT / "godot"
ASSETS = GODOT / "assets"
GODOT_DATA = GODOT / "data"
TILE = 48

MAIN_LEVELS = list(range(0, 36))
HIDDEN_SIM = list(range(36, 40))
HIDDEN_FICTION = list(range(40, 44))
EASTER = list(range(44, 47))

# 可玩性补足：原版过场/触发器里的友军增援与个别 Easter 单位的实际 HP
# 不在 FIGHT.DAT 的静态槽里，这里显式建模，避免“目标存在但不可完成”。
ALLY_WAVES = {
    32: {"turn": 1, "side": "player", "pids": [33, 30, 31, 32, 26, 27, 28, 29]},
    33: {"turn": 1, "side": "player", "pids": [33, 30, 31, 32, 26, 27, 28, 29]},
    34: {"turn": 1, "side": "player", "pids": [33, 30, 31, 32, 26, 27, 28, 29]},
    35: {"turn": 1, "side": "player",
         "pids": [33, 30, 31, 32, 26, 27, 28, 29, 24, 25, 22, 23]},
    40: {"turn": 1, "side": "player", "pids": [33, 30, 31, 32, 26, 27]},
    46: {"turn": 1, "side": "player",
         "pids": [33, 4, 8, 9, 5, 7, 6, 10, 11, 12]},
}
# 后期/彩蛋关的敌军数量与静态 Fighter 槽不一致（原版靠脚本分批投入）；
# 这里给可玩性上限，超出部分不进入首发，避免 5-10 人面对 30-58 个同时行动。
ENEMY_CAP = {20: 20, 25: 20, 27: 20, 31: 18, 32: 20, 33: 20, 34: 20,
             35: 12, 36: 10, 37: 10, 38: 10, 39: 10, 40: 10,
             41: 10, 42: 10, 43: 10, 46: 12}
ENEMY_LEVEL_CAP = {20: 20, 25: 20, 27: 20, 31: 20, 32: 20, 33: 20, 34: 20,
                   35: 20, 36: 20, 37: 20, 38: 20, 39: 20, 40: 20,
                   41: 20, 42: 20, 43: 20}
ENEMY_HP_CAP = {20: 600, 25: 600, 27: 600, 31: 600, 32: 600, 33: 600, 34: 600,
                35: 600, 36: 600, 37: 600, 38: 600, 39: 600, 40: 600,
                41: 600, 42: 600, 43: 600}
ENEMY_WAVE_DISABLE = set(range(36, 44))
HP_OVERRIDES = {
    45: {"柳忻": 1376},   # 与 L44 的柳忻一致，避免赛跑关被高等级敌军一击秒杀
    46: {"张嘎": 662},
}

TOWN_OF_LEVEL = {
    0: 0, 1: 0, 2: 1, 3: 2, 4: 1, 5: 3, 6: 6, 7: 4, 8: 5, 9: 5,
    10: 6, 11: 6, 12: 7, 13: 7, 14: 7, 15: 8, 16: 8, 17: 8,
    18: 9, 19: 10, 20: 11, 21: 12, 22: 13, 23: 18, 24: 14,
    25: 15, 26: 15, 27: 15, 28: 16, 29: 16, 30: 16,
    31: 17, 32: 17, 33: 17, 34: 17, 35: 17,
}
for _i in HIDDEN_SIM + HIDDEN_FICTION + EASTER:
    TOWN_OF_LEVEL[_i] = 0

# 目标表：手动把原版胜利文本落成可执行目标。
# type: annihilate / kill / reach / reach_unit / collect / survive / race /
#       capture_or_annihilate
OBJECTIVES = {
    0: {"type": "reach", "targets": [[17, 1]], "any": True},
    1: {"type": "reach_unit", "units": ["朱老忠"], "radius": 1},
    2: {"type": "annihilate"},
    3: {"type": "reach", "targets": [[12, 1], [13, 1]], "units": ["李向阳"],
        "count": 1},
    4: {"type": "kill", "names": ["高敬天"]},
    5: {"type": "annihilate"},
    6: {"type": "annihilate"},
    7: {"type": "annihilate"},
    8: {"type": "annihilate"},
    9: {"type": "annihilate"},
    10: {"type": "reach", "targets": [[4, 35], [18, 34], [25, 29]], "count": 3},
    11: {"type": "reach", "targets": [[21, 4]], "units": ["林嫂"]},
    12: {"type": "capture_or_annihilate", "targets": [[13, 28], [20, 29], [17, 31]]},
    13: {"type": "annihilate"},
    14: {"type": "annihilate"},
    15: {"type": "annihilate"},
    16: {"type": "reach", "targets": [[34, 34]], "units": ["李正"]},
    17: {"type": "collect", "targets": [[3, 5], [5, 5], [7, 5], [9, 5], [11, 5]],
         "count": 5, "label": "机枪"},
    18: {"type": "reach_unit", "units": ["郑之光"], "radius": 1},
    19: {"type": "kill", "names": ["金花婆"]},
    20: {"type": "annihilate"},
    21: {"type": "kill", "names": ["高得远"]},
    22: {"type": "annihilate"},
    23: {"type": "reach", "targets": [[24, 3]], "any": True},
    24: {"type": "annihilate"},
    25: {"type": "annihilate"},
    26: {"type": "reach", "targets": [[8, 2]], "any": True},
    27: {"type": "annihilate"},
    28: {"type": "kill", "names": ["山田"]},
    29: {"type": "kill", "names": ["川岛芳子"]},
    30: {"type": "reach", "targets": [[20, 1]], "units": ["李正"]},
    31: {"type": "annihilate"},
    32: {"type": "annihilate"},
    33: {"type": "annihilate"},
    34: {"type": "annihilate"},
    35: {"type": "annihilate"},
    36: {"type": "survive", "turns": 40},
    37: {"type": "annihilate"},
    38: {"type": "annihilate"},
    39: {"type": "annihilate"},
    40: {"type": "annihilate"},
    41: {"type": "annihilate"},
    42: {"type": "annihilate"},
    43: {"type": "annihilate"},
    44: {"type": "kill", "names": ["冈村宁次"]},
    45: {"type": "race", "targets": [[18, 4]], "units": ["柳忻"], "rival": "龟田"},
    46: {"type": "annihilate"},
}

PROTECT = {
    3: ["李向阳"], 6: ["柳忻"], 8: ["李霜泗"], 11: ["林嫂"],
    15: ["老百姓"], 16: ["李正"], 17: ["吴海"], 18: ["郑之光"],
    20: ["方仲雄"], 25: ["柳忻"], 27: ["村民"], 29: ["傅正明"],
    30: ["李正"], 31: ["唐联西"],
    36: ["宋学义", "葛振林", "马宝玉", "胡德林", "胡福才"],
    37: ["林彪"], 38: ["李宗仁"], 39: ["杜聿明"],
    40: ["宋学义", "葛振林", "马宝玉", "胡德林", "胡福才"],
    41: ["林彪"], 42: ["李宗仁"], 43: ["杜聿明"],
    44: ["李正"], 45: ["柳忻"], 46: ["张嘎", "村民"],
}

MAX_DEPLOY = {0: 1, 26: 1, 45: 1}
# 5 个代表关的关卡初始化函数（DLZ.exe 0x4465D0 表）：
# 这些函数只做开场音效/旗标，不包含逐回合触发器。用于 TRIGGERS.md 的证据。
TRIGGER_FUNCTIONS = {
    0: "0x40BE07",
    3: "0x40C15B",
    12: "0x40C646",
    18: "0x40C8DA",
    36: "0x40D020",
}
PARTY_DEPLOY = {**{i: True for i in MAIN_LEVELS}}
PARTY_DEPLOY[46] = True  # 鬼子进村：张嘎 + 村民 + 队伍 + 八路军增援
PROTECT_ALL = {36, 40}  # 狼牙山：五壮士全部阵亡才失败
# 剧情加入：按原作情节在胜利后加入队伍（pid 对应 PEOPLE.DAT）。
# 这不是反汇编确认的加入触发器，是可玩性/剧情补足。
JOIN_AFTER = {
    6: [8],    # 接应肖飞
    11: [13],  # 解救林嫂
    18: [21],  # 智擒郑之光
    19: [22],  # 义收金花婆
    23: [34],  # 营救彼德
    30: [33],  # 红岩反击战：李正
}
TURN_LIMIT_OVERRIDE = {i: 60 for i in range(36)}  # 主线至少 60 回合；原版 20-40 回合对低等级队伍过紧

# 每关推荐剧情 TXT n（M5 再细化；这里只放关键的开场/收尾）
STORY_IDS = {
    0: [521, 0, 1, 2, 3], 1: [522, 4, 5, 6, 7, 8],
    2: [524, 9, 10, 11, 12, 13, 14, 15],
    3: [526, 17, 18, 19, 20, 21, 22],
    4: [528, 23, 24, 25, 26, 27],
    5: [530, 28, 29, 30, 31, 32], 6: [532, 33, 34, 35, 36],
    7: [534, 37, 38, 39, 40, 41], 8: [534, 42, 43, 44, 45, 46],
    9: [536, 47, 48, 49], 10: [538, 50, 51, 52, 53, 54],
    11: [540, 55, 56, 57, 58, 59], 12: [542, 60, 61, 62, 63],
    13: [544, 64, 65, 66, 67], 14: [546, 68, 69, 70, 71, 72, 73, 74],
    15: [550, 75, 76, 77, 78, 79, 80], 16: [552, 81, 82, 83, 84, 85, 86, 87, 88, 89],
    17: [554, 90, 91, 92, 93], 18: [556, 94, 95, 96, 97, 98, 99],
    19: [558, 100, 101, 102, 103, 104, 105], 20: [560, 106, 107, 108, 109, 110],
    21: [562, 111, 112, 113, 114, 115], 22: [564, 116, 117, 118, 119, 120],
    23: [564, 121, 122, 123, 124], 24: [570, 125, 126, 127, 128, 129],
    25: [570, 130, 131, 132, 133], 26: [574, 134, 135, 136, 137, 138, 139, 140],
    27: [576, 141, 142, 143, 144, 145], 28: [578, 146, 147, 148, 149, 150, 151],
    29: [580, 152, 153, 154, 155, 156, 157, 158],
    30: [584, 159, 160, 161, 162, 163], 31: [590, 164, 165, 166, 167, 168, 169],
    32: [584, 170, 171, 172, 173, 174, 175], 33: [584, 176, 177, 178, 179, 180],
    34: [590, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190],
    35: [590, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
         204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215],
    36: [421, 422, 423, 424, 425], 37: [443, 444, 445, 446, 447, 448, 449, 450,
                                          451, 452, 453, 454, 455, 462, 463],
    38: [468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481,
         482, 483, 484, 485, 498],
    39: [501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 515],
    40: [421, 422, 423, 424, 425], 41: [443, 444, 445, 446, 447, 448, 449, 450],
    42: [468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481],
    43: [501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 515],
    44: [445, 446, 447, 448, 449], 45: [565, 566, 567, 568],
    46: [333, 334, 335, 336, 337, 338, 339],
}

CN_DIGITS = {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
             "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def norm(text: str) -> str:
    return str(text).replace("\u3000", "").replace(" ", "")


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
    for key in ("超过", "坚持"):
        pos = failure.find(key)
        if pos < 0:
            continue
        tail = failure[pos + len(key):]
        end = tail.find("个回合")
        if end < 0:
            continue
        n = cn_number(tail[:end])
        if n:
            return n
    return 0


def copy_asset(src: Path, rel: str) -> str:
    dst = ASSETS / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    return "res://assets/" + rel


def walkable(move_row: list[int], terrain: int) -> bool:
    if terrain < 0 or terrain >= len(move_row):
        return False
    c = int(move_row[terrain])
    return 1 <= c < 99


def bfs(move_row: list[int], terrain: list[int], w: int, h: int,
        starts: list[tuple[int, int]]) -> set[tuple[int, int]]:
    q = deque()
    seen: set[tuple[int, int]] = set()
    for x, y in starts:
        if 0 <= x < w and 0 <= y < h and walkable(move_row, terrain[y * w + x]):
            if (x, y) not in seen:
                seen.add((x, y))
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen \
                    and walkable(move_row, terrain[ny * w + nx]):
                seen.add((nx, ny))
                q.append((nx, ny))
    return seen


def snap_targets(targets, reachable, w, h, blocked):
    out = []
    for tx, ty in targets:
        tx = max(0, min(w - 1, int(tx)))
        ty = max(0, min(h - 1, int(ty)))
        best = None
        bestd = 10 ** 9
        for x, y in reachable:
            if (x, y) in blocked:
                continue
            d = abs(x - tx) + abs(y - ty)
            if d < bestd:
                bestd, best = d, (x, y)
        if best is None:
            best = (tx, ty)
        out.append([best[0], best[1]])
    return out


def deploy_positions(specials, terrain, w, h, move_row, occupied, count):
    cand = []
    for s in specials:
        if s["direction"] == 0 and not s["empty"]:
            cand.append((s["x"], s["y"]))
    if not cand:
        # 从下往上找可走格，靠近地图中部
        for y in range(h - 2, 0, -1):
            for x in range(w // 2 - 1, -1, -1):
                if walkable(move_row, terrain[y * w + x]) and (x, y) not in occupied:
                    cand.append((x, y))
                    break
            for x in range(w // 2, w):
                if walkable(move_row, terrain[y * w + x]) and (x, y) not in occupied:
                    cand.append((x, y))
                    break
    # 去掉不可走/占用，补齐周围格
    out = []
    for x, y in cand:
        if 0 <= x < w and 0 <= y < h and walkable(move_row, terrain[y * w + x]) \
                and (x, y) not in occupied and (x, y) not in out:
            out.append((x, y))
    i = 0
    while len(out) < count and i < len(cand) * 8:
        bx, by = cand[i % len(cand)]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)):
            nx, ny = bx + dx, by + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in out \
                    and (nx, ny) not in occupied \
                    and walkable(move_row, terrain[ny * w + nx]):
                out.append((nx, ny))
                break
        i += 1
    return out[:count]


def unit_hp(f: dict, p: dict, u: dict) -> tuple[int, str]:
    raw = int(f["tili"])
    if raw == 4500:
        return max(1, int(u["tili"]) + (int(p["level"]) - 1) * int(u["tili_plus"])), "formula"
    return max(1, raw), "explicit"


def make_ally(pid: int, people: list, units: dict, x: int, y: int) -> dict:
    p = people[pid]
    u = units[int(p["bingzhong"])]
    hp = max(1, int(u["tili"]) + (int(p["level"]) - 1) * int(u["tili_plus"]))
    return {
        "slot": 100 + pid,
        "side": "player",
        "name": str(p["name"]),
        "key": norm(str(p["name"])),
        "unit_name": str(u["name"]),
        "bingzhong": int(p["bingzhong"]),
        "level": int(p["level"]),
        "wuli": int(p["wuli"]),
        "zhili": int(p["zhili"]),
        "hp": hp,
        "raw_hp": hp,
        "hp_source": "ally",
        "x": int(x),
        "y": int(y),
        "direction": 1,
        "behavior": 1,
        "target_slot": 0,
        "target_x": 0,
        "target_y": 0,
        "face": int(p["face"]),
        "face_png": f"res://assets/face/face_{int(p['face']):03d}.png",
        "army_png": f"res://assets/army/army_{int(u['img_index']):03d}.png",
        "select": int(u["select"]),
        "apply": int(u["apply"]),
        "move": int(u["yidong"]),
        "gongji": int(u["gongji"]),
        "fangyu": int(u["fangyu"]),
        "tili": int(u["tili"]),
        "tili_plus": int(u["tili_plus"]),
        "jingyan": int(p.get("jingyan", 0)),
        "skills": u.get("skills", {}),
        "skill_counts": p.get("skills", {}),
        "attack_count": int(p.get("gongji", 0)),
        "items": p.get("wupin", []),
        "mines": p.get("dilei", []),
        "is_boss": False,
        "protected": False,
        "control": False,
        "auto": True,
    }


def snap_unit_to_reach(x: int, y: int, reach: set, occupied: set,
                       w: int, h: int) -> tuple[int, int]:
    if (x, y) in reach and (x, y) not in occupied:
        return x, y
    best = None
    bestd = 10 ** 9
    for r in range(1, 10):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if abs(dx) != r and abs(dy) != r:
                    continue
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h):
                    continue
                if (nx, ny) not in reach or (nx, ny) in occupied:
                    continue
                d = abs(dx) + abs(dy)
                if d < bestd:
                    bestd = d
                    best = (nx, ny)
        if best is not None:
            return best
    return x, y


def level_kind(idx: int) -> tuple[str, str, int]:
    if idx in MAIN_LEVELS:
        return "main", "", idx
    if idx in HIDDEN_SIM:
        return "hidden", "simulation", idx - 36
    if idx in HIDDEN_FICTION:
        return "hidden", "fiction", idx - 40
    return "easter", "", idx - 44


def main() -> None:
    maps = load("map.json")["maps"]
    levels = load("fight.json")["levels"]
    fighters = load("fighter.json")["levels"]
    people = load("people.json")["records"]
    game = load("game.json")
    items = {str(it["index"]): it for it in game["items"]}
    units = game["units"]
    move_rows = {str(i): v for i, v in enumerate(game["unit_move"])}
    ASSETS.mkdir(parents=True, exist_ok=True)
    GODOT_DATA.mkdir(parents=True, exist_ok=True)
    (ASSETS / "map").mkdir(parents=True, exist_ok=True)

    # 地图 & 单位图
    for i in range(47):
        copy_asset(OUT / "map" / f"map_{i:02d}.png", f"map/map_{i:02d}.png")
    for i in range(170):
        p = OUT / "face" / f"face_{i:03d}.png"
        if p.exists():
            copy_asset(p, f"face/face_{i:03d}.png")
    for i in range(91):
        p = OUT / "army" / f"army_{i:03d}.png"
        if p.exists():
            copy_asset(p, f"army/army_{i:03d}.png")

    out_levels = []
    for idx in range(47):
        m = maps[idx]
        lv = levels[idx]
        fl = fighters[idx]
        w, h = int(m["width"]), int(m["height"])
        terrain = [((int(v) >> 12) & 0xF) for v in m["tiles"]]
        move3 = move_rows["3"]
        kind, mode, sub = level_kind(idx)
        specials_all = lv["intro"]["special_positions"]
        specials = [{**s, "empty": bool(s["empty"])} for s in specials_all]
        chests_raw = [c for c in lv["intro"]["chests"] if not c["empty"]]

        active = []
        reserves = []
        spawn_needed = TRIGGER_SPAWN_SLOTS.get(idx, set())
        all_recs = {}
        for f in fl["fighters"]:
            p = people[f["slot"]] if f["slot"] < 40 else lv["people"][f["slot"] - 40]
            u = units[int(p["bingzhong"])]
            # 槽位 0..39 是 PEOPLE.DAT 的我方名册；40..127 的 People
            # 用 unknown_18 区分友军(0)/敌军(1)。这是 M0 复核后的规则。
            if f["slot"] < 40:
                side = "player"
            else:
                side = "player" if int(p["unknown_18"]) == 0 else "enemy"
            hp, hp_source = unit_hp(f, p, u)
            rec = {
                "slot": int(f["slot"]),
                "side": side,
                "name": str(f["unit"]),
                "key": norm(f["unit"]),
                "unit_name": str(u["name"]),
                "bingzhong": int(p["bingzhong"]),
                "level": int(p["level"]),
                "wuli": int(p["wuli"]),
                "zhili": int(p["zhili"]),
                "hp": hp,
                "raw_hp": int(f["tili"]),
                "hp_source": hp_source,
                "x": int(f["pos_x"]),
                "y": int(f["pos_y"]),
                "direction": int(f["direction"]),
                "behavior": int(f["behavior"]),
                "target_slot": int(f["target_slot"]),
                "target_x": int(f["target_x"]),
                "target_y": int(f["target_y"]),
                "face": int(p["face"]),
                "face_png": f"res://assets/face/face_{int(p['face']):03d}.png",
                "army_png": f"res://assets/army/army_{int(u['img_index']):03d}.png",
                "select": int(u["select"]),
                "apply": int(u["apply"]),
                "move": int(u["yidong"]),
                "gongji": int(u["gongji"]),
                "fangyu": int(u["fangyu"]),
                "tili": int(u["tili"]),
                "tili_plus": int(u["tili_plus"]),
                "jingyan": int(p.get("jingyan", 0)),
                "skills": u.get("skills", {}),
                "skill_counts": p.get("skills", {}),
                "attack_count": int(p.get("gongji", 0)),
                "items": p.get("wupin", []),
                "mines": p.get("dilei", []),
                "is_boss": hp >= 1000,
                "protected": False,
                "control": True,
                "auto": side == "player" and str(f["unit"]).replace("\u3000", "") in
                        ("国军", "八路军", "村民", "老百姓", "游击队员", "自卫队"),
            }
            if idx in ENEMY_LEVEL_CAP and rec["side"] == "enemy":
                rec["level"] = min(int(rec["level"]), int(ENEMY_LEVEL_CAP[idx]))
            if idx in ENEMY_HP_CAP and rec["side"] == "enemy":
                rec["hp"] = min(int(rec["hp"]), int(ENEMY_HP_CAP[idx]))
                rec["raw_hp"] = rec["hp"]
                rec["hp_source"] = "balance_cap"
            if idx in HP_OVERRIDES and rec["key"] in {
                    norm(k) for k in HP_OVERRIDES[idx]}:
                rec["hp"] = int(HP_OVERRIDES[idx][rec["key"]])
                rec["raw_hp"] = rec["hp"]
                rec["hp_source"] = "override"
            if idx == 19 and f["slot"] == 22:
                rec["side"] = "enemy"
                rec["auto"] = False
                rec["control"] = False
            # 黑风寨的向天虎/向天豹是寨主，FIGHT.People.unknown_18 误标成友军；
            # 0x40A4AF 在 24 号阵亡时直接给胜利，可反证其敌军身份。
            if idx == 22 and f["slot"] in (24, 25):
                rec["side"] = "enemy"
                rec["auto"] = False
                rec["control"] = False
            # 第 15 关的老百姓在 People 表里被标成 enemy(1)，但原版是
            # 需要保护的村民；按剧情语义改为友军 AI。
            if idx == 15 and str(f["unit"]) == "老百姓":
                rec["side"] = "player"
                rec["auto"] = True
                rec["control"] = False
                rec["protected"] = True
            all_recs[int(f["slot"])] = rec
            if f["active"]:
                active.append(rec)
            elif int(f["slot"]) in spawn_needed:
                # 触发器生成的槽位不能提前进入 active/波次，否则会双重生成；
                # 但记录必须保留在 spawn_pool 里供 0x429CC8 数据化版本使用。
                pass
            elif str(f["unit"]) != "孙悟空" and 0 <= rec["x"] < w and 0 <= rec["y"] < h:
                reserves.append(rec)

        spawn_pool = [all_recs[s] for s in sorted(spawn_needed) if s in all_recs]
        if idx in ENEMY_CAP:
            cap = int(ENEMY_CAP[idx])
            kept = [r for r in active if r["side"] == "enemy"][:cap]
            active = [r for r in active if r["side"] != "enemy"] + kept
        # 保护名单
        protect_names = PROTECT.get(idx, [])
        for r in active + reserves + spawn_pool:
            if r["side"] == "player" and r["key"] in {norm(n) for n in protect_names}:
                r["protected"] = True
        # 没有任何可控友军时，把有名友军设为可控
        if not any(r["side"] == "player" and not r["auto"] for r in active):
            for r in active:
                if r["side"] == "player":
                    r["auto"] = False

        occupied = {(r["x"], r["y"]) for r in active}
        occupied |= {(c["x"], c["y"]) for c in chests_raw}
        max_deploy = MAX_DEPLOY.get(idx, 10)
        deploy = []
        if PARTY_DEPLOY.get(idx, False):
            deploy = deploy_positions(specials, terrain, w, h, move3, occupied,
                                      min(10, max_deploy))
        # 目标：优先用显式坐标，再按 type2 特殊位置
        obj_raw = dict(OBJECTIVES[idx])
        if "units" in obj_raw:
            obj_raw["unit_keys"] = [norm(n) for n in obj_raw["units"]]
        if "names" in obj_raw:
            obj_raw["name_keys"] = [norm(n) for n in obj_raw["names"]]
        if "rival" in obj_raw:
            obj_raw["rival_key"] = norm(obj_raw["rival"])
        if obj_raw["type"] in ("reach", "capture_or_annihilate", "race") \
                and "targets" not in obj_raw:
            obj_raw["targets"] = [[s["x"], s["y"]] for s in specials
                                  if not s["empty"] and s["direction"] == 2]
        if obj_raw["type"] == "reach_unit":
            obj_raw["unit_positions"] = []
            for r in active + reserves + spawn_pool:
                if r["side"] == "player" and r["key"] in obj_raw.get("unit_keys", []):
                    obj_raw["unit_positions"].append([r["x"], r["y"]])
        # 目标可达性：以部署点/固定友军为起点做一次 BFS
        starts = deploy + [(r["x"], r["y"]) for r in active if r["side"] == "player"]
        reach = bfs(move3, terrain, w, h, starts)
        if not reach:
            reach = {(x, y) for y in range(h) for x in range(w)
                     if walkable(move3, terrain[y * w + x])}
        # 敌军必须在玩家可达域内，否则“全歼”永远无法完成。
        occupied = {(r["x"], r["y"]) for r in active}
        for r in active + reserves:
            if r["side"] != "enemy":
                continue
            nx, ny = snap_unit_to_reach(int(r["x"]), int(r["y"]), reach,
                                        occupied, w, h)
            if (nx, ny) != (int(r["x"]), int(r["y"])):
                occupied.discard((int(r["x"]), int(r["y"])))
                r["x"], r["y"] = nx, ny
                occupied.add((nx, ny))
        # 目标必须由指定单位/任意我方走到；按单位单独算可达域再吸附
        target_reach = reach
        if obj_raw.get("unit_keys"):
            us = [r for r in active + reserves
                  if r["side"] == "player" and r["key"] in obj_raw["unit_keys"]]
            if us:
                target_reach = bfs(move3, terrain, w, h,
                                   [(r["x"], r["y"]) for r in us])
        if obj_raw["type"] == "race":
            ru = [r for r in active + reserves
                  if r["side"] == "player" and r["key"] in obj_raw.get("unit_keys", [])]
            rv = [r for r in active + reserves
                  if r["side"] == "enemy" and r["key"] == obj_raw.get("rival_key")]
            if ru and rv:
                ra = bfs(move3, terrain, w, h, [(ru[0]["x"], ru[0]["y"])])
                rb = bfs(move3, terrain, w, h, [(rv[0]["x"], rv[0]["y"])])
                inter = ra & rb
                if inter:
                    target_reach = inter
        if "targets" in obj_raw:
            obj_raw["targets"] = snap_targets(obj_raw["targets"], target_reach,
                                               w, h, occupied)
        if "unit_positions" in obj_raw:
            obj_raw["unit_positions"] = snap_targets(obj_raw["unit_positions"],
                                                     reach, w, h, occupied)

        # 增援：按回合分批；没有友军时友方增援直接入场
        friendly_reserves = [r for r in reserves if r["side"] == "player"]
        enemy_reserves = [r for r in reserves if r["side"] == "enemy"]
        waves = []
        if friendly_reserves and not any(r["side"] == "player" for r in active):
            active.extend(friendly_reserves)
            friendly_reserves = []
        if friendly_reserves:
            waves.append({"turn": 3, "side": "player", "units": friendly_reserves})
        if enemy_reserves:
            if not any(r["side"] == "enemy" for r in active):
                active.extend(enemy_reserves)
                enemy_reserves = []
            else:
                first = enemy_reserves[:max(1, len(enemy_reserves) // 2)]
                rest = enemy_reserves[max(1, len(enemy_reserves) // 2):]
                waves.append({"turn": 2, "side": "enemy", "units": first})
                if rest:
                    waves.append({"turn": 5, "side": "enemy", "units": rest})
        if idx in ENEMY_WAVE_DISABLE:
            waves = [w for w in waves if str(w.get("side", "")) != "enemy"]
        if idx in ALLY_WAVES:
            aw = ALLY_WAVES[idx]
            ally_units = []
            for j, pid in enumerate(aw["pids"]):
                ax = 2 + (j % 5) * 3
                ay = max(1, h - 2)
                ally_units.append(make_ally(int(pid), people, units, ax, ay))
            waves.append({"turn": int(aw["turn"]), "side": "player",
                          "units": ally_units})
        reserve_out = []
        for wave in waves:
            reserve_out.extend(wave["units"])

        # 目标 turn 数
        if obj_raw["type"] == "survive":
            obj_raw.setdefault("turns", turn_limit(lv["failure"]) or 40)
        if obj_raw["type"] == "race":
            obj_raw.setdefault("rival", "龟田")
        # 宝箱
        chests = []
        for c in chests_raw:
            it = items.get(str(c["wupin"]), {})
            chests.append({
                **c,
                "item_name": it.get("name", "物资"),
                "item_icon": f"res://assets/goods/goods_{int(it.get('goods', 0)):03d}.png"
                             if it else "",
            })
        # 目标标签
        obj_raw["label"] = {
            "annihilate": "全歼敌人",
            "kill": "击毙 " + "、".join(obj_raw.get("names", [])),
            "reach": "到达目标",
            "reach_unit": "接近 " + "、".join(obj_raw.get("units", [])),
            "collect": "搜集 %d 箱%s" % (int(obj_raw.get("count", 1)),
                                          obj_raw.get("label", "物资")),
            "survive": "坚持 %d 回合" % int(obj_raw.get("turns", 40)),
            "race": "抢先到达山神庙",
            "capture_or_annihilate": "占领仓库或全歼敌人",
        }.get(obj_raw["type"], "完成任务")
        # 0x11C：按 PEOPLE.DAT 索引解码的每关队伍候选（推断）。
        cand_pids = sorted({int(v) for v in lv["intro"]["unknown_11c"]
                            if int(v) != 255})
        cand_names = [norm(people[pid]["name"]) for pid in cand_pids]
        # 胜负文本
        score = 60
        stars = (3 if idx <= 12 else 4 if idx <= 28 else 5)
        out_levels.append({
            "index": idx,
            "name": lv["name"],
            "name_gbk_hex": lv["name"].encode("gb18030", errors="replace").hex(),
            "success_gbk_hex": lv["success"].strip().strip("\u3000").encode("gb18030", errors="replace").hex(),
            "failure_gbk_hex": lv["failure"].strip().strip("\u3000").encode("gb18030", errors="replace").hex(),
            "kind": kind,
            "hidden_mode": mode,
            "sub_index": sub,
            "town": TOWN_OF_LEVEL[idx],
            "success": lv["success"].strip().strip("\u3000"),
            "failure": lv["failure"].strip().strip("\u3000"),
            "turn_limit": TURN_LIMIT_OVERRIDE.get(idx, turn_limit(lv["failure"])),
            "original_turn_limit": (
                int(obj_raw.get("turns", 0)) if obj_raw["type"] == "survive"
                else turn_limit(lv["failure"])),
            "trigger_evidence": ({
                "init_function": TRIGGER_FUNCTIONS[idx],
                "source": "DLZ.exe 0x4465D0 per-level init table",
                "special_count_raw": int(lv["intro"]["special_count_raw"]),
                "special_count": sum(1 for s in specials if not s["empty"]),
                # 0x11C 的 32 字节：非 FF 值对应 PEOPLE.DAT 索引。
                # 这些名字与剧情加入/关卡队伍高度吻合，暂作为“队伍候选”证据，
                # 不直接限制部署（避免改变现有 47 关平衡）。
                "player_indices": sorted({int(v) for v in
                                          lv["intro"]["unknown_11c"]
                                          if int(v) != 255}),
                "player_names": [norm(people[int(v)]["name"]) for v in
                                 sorted({int(v) for v in
                                         lv["intro"]["unknown_11c"]
                                         if int(v) != 255})],
                "dynamic_spawns": [],
            } if idx in TRIGGER_FUNCTIONS else {}),
            "difficulty": int(lv["intro"]["difficulty_raw"]),
            "stars": stars,
            "score_base": score,
            "score_max": 100,
            "map": {
                "index": idx,
                "width": w,
                "height": h,
                "tile": TILE,
                "png": f"res://assets/map/map_{idx:02d}.png",
                "blk": m["blk"],
                "terrain": terrain,
            },
            "units": active,
            "players": sum(1 for u in active if u["side"] == "player"),
            "enemies": sum(1 for u in active if u["side"] == "enemy"),
            "reserves": reserve_out,
            "spawn_pool": spawn_pool,
            "waves": waves,
            "deploy": [[x, y] for x, y in deploy],
            "party_deploy": bool(PARTY_DEPLOY.get(idx, False)),
            "max_deploy": max_deploy,
            "objective": obj_raw,
            "protect": protect_names,
            "protect_all": idx in PROTECT_ALL,
            "party_candidates": [
                {"pid": pid, "name": name}
                for pid, name in zip(cand_pids, cand_names)
            ],
            "joins": JOIN_AFTER.get(idx, []),
            "chests": chests,
            "specials": [s for s in specials if not s["empty"]],
            "story_ids": STORY_IDS.get(idx, []),
            "media": "d%02d" % (idx + 1) if idx < 36 else "",
            "triggers": LEVEL_TRIGGERS.get(idx, {}),
        })

    # 战斗表
    payload = {
        "meta": {
            "title": "抗日：地雷战 / M4 战役",
            "version": 1,
            "tile": TILE,
            "font": "res://assets/font/hzk16.fnt",
            "font_size": 16,
            "mine_type": 0,
            "mines": 3,
            "mine_png": "res://assets/mine/mine_000.png",
            "main_levels": len(MAIN_LEVELS),
            "hidden_levels": len(HIDDEN_SIM) + len(HIDDEN_FICTION),
            "easter_levels": len(EASTER),
            "hidden_unlock_score": 2800,
            "ending_thresholds": [2800, 3000, 3300, 3600],
            "save_prefix": "dlz_m4_save_",
            "note": "目标/保护名单/城镇映射为可玩性复刻；原版触发器仍待反汇编完全确认。",
        },
        "levels": out_levels,
        "unit_types": units,
        "unit_move": move_rows,
        "select_ranges": {str(i): game["select_ranges"][i] for i in range(16)},
        "apply_ranges": {str(i): game["apply_ranges"][i] for i in range(48)},
        "skills": game["skills"],
        "item_valid": game["item_valid"],
        "terrain_modifiers": game["terrain_modifiers"],
        "mines": game["mines"],
        "mine_terrain": game["mine_terrain"],
        "items": items,
    }
    (GODOT_DATA / "m4.json").write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8")
    print("levels", len(out_levels))
    print("main", len(MAIN_LEVELS), "hidden", len(HIDDEN_SIM) + len(HIDDEN_FICTION),
          "easter", len(EASTER))
    print("units active", sum(len(l["units"]) for l in out_levels),
          "reserves", sum(len(l["reserves"]) for l in out_levels),
          "waves", sum(len(l["waves"]) for l in out_levels))
    print("m4.json", (GODOT_DATA / "m4.json").stat().st_size, "bytes")


if __name__ == "__main__":
    main()
