#!/usr/bin/env python3
"""Declarative transcription of DLZ.exe 0x446510 per-level trigger functions.

Every rule points at the instruction address that proves it.  The data is
consumed by tools/prepare_m4.py and executed by godot/scripts/m4/Scenario.gd;
never hard-code per-level ifs in GDScript.

Conventions
-----------
* `flag` values are the original .data dwords (e.g. 0x583F18), per battle.
* `unit_*` slots are FIGHT.DAT Fighter slots 0..127.
* `dest` uses the current battle tile of that slot (original Fighter.dest).
* `message` is a slot in the original TXT.DAT table at 0x472588 (0x43DD47
  displays it as a dialogue popup; it is not a WAV pointer).
* `inferred` notes mark semantics that need runtime evidence.
"""

from __future__ import annotations

# ---------------------------------------------------------------- helpers

def _rule(rid, when, then, *, on="tick", once=False, note="", requires_result_zero=True):
    r = {"id": rid, "when": when, "then": then}
    r["requires_result_zero"] = requires_result_zero
    if on != "tick":
        r["on"] = on
    if once:
        r["once"] = True
    if note:
        r["note"] = note
    return r


def all_(*conds):
    return {"all": list(conds)}


def any_(*conds):
    return {"any": list(conds)}


def stage(slot, eq=0):
    return {"unit_stage": {"slot": slot, "eq": eq}}


def dest(slot, x, y):
    return {"unit_dest": {"slot": slot, "x": x, "y": y}}


def area(slot, x, y, w, h):
    return {"unit_dest_area": {"slot": slot, "x": x, "y": y, "w": w, "h": h}}


def adjacent(a, b):
    return {"adjacent": {"a": a, "b": b}}


def flag(addr, eq=None, neq=None, gte=None):
    f = {"addr": addr}
    if eq is not None:
        f["eq"] = eq
    if neq is not None:
        f["neq"] = neq
    if gte is not None:
        f["gte"] = gte
    return {"flag": f}


def bit(addr, mask, set_=False):
    return {"flag_bit": {"addr": addr, "mask": mask, "set": set_}}


def all_dead():
    return {"all_units_dead": True}


def cell(x, y, eq=1):
    return {"map_cell_occupied": {"x": x, "y": y, "eq": eq}}


def turn_gt(n):
    return {"turn": {"gt": n}}


def slots_count(slots, eq=None, lt=None):
    c = {"slots": list(slots)}
    if eq is not None:
        c["eq"] = eq
    if lt is not None:
        c["lt"] = lt
    return {"unit_count": c}


def turn_le(n):
    return {"turn": {"le": n}}


def turn_gt_flag(addr, add=0):
    return {"turn_gt_flag": {"addr": addr, "add": add}}


def region_gt(x, y, w, h, count=1):
    return {"cell_region_gt": {"x": x, "y": y, "w": w, "h": h, "count": count}}


def message_table(addr, index):
    return message("%s[%d]" % (addr, index))


def slot_cell(slot, eq=1):
    return {"slot_pos_cell_occupied": {"slot": slot, "eq": eq}}


def global_cond(addr, eq=None, neq=None):
    g = {"addr": addr}
    if eq is not None:
        g["eq"] = eq
    if neq is not None:
        g["neq"] = neq
    return {"global": g}


def flag_turn(addr, add=0):
    return {"flag_set_from_turn": {"addr": addr, "add": add}}


def flag_set_from_turn(addr, add=0):
    return {"flag_set_from_turn": {"addr": addr, "add": add}}


def map_cell_slot(slot, value=1):
    return {"set_map_cell_at_slot": {"slot": slot, "value": value}}


def range_count(lo, hi, eq=None, lt=None, faction=None):
    c = {"from": lo, "to": hi}
    if eq is not None:
        c["eq"] = eq
    if lt is not None:
        c["lt"] = lt
    if faction is not None:
        c["faction"] = faction
    return {"unit_count": c}


def any_player_death():
    return {"all_players_dead": True}


def message(ptr):
    return {"message": ptr}



def turn_eq(n):
    return {"turn": {"eq": n}}


def random_slot_dest(slot, options, direction=1):
    return {"random_slot_dest": {"slot": slot, "options": [list(o) for o in options],
                                 "direction": direction}}


def party_morale(add):
    return {"party_levels": {"from": 0, "to": 24, "add": add}}


def recruit(slots):
    return {"recruit": list(slots)}


def choice(prompt, options, default=0):
    return {"choice": {"prompt": prompt, "options": list(options),
                       "default": default}}


def option(label, actions):
    return {"label": label, "then": list(actions)}

def set_flag(addr, value=1):
    return {"flag_set": {"addr": addr, "value": value}}


def set_bit(addr, mask):
    return {"flag_or": {"addr": addr, "mask": mask}}


def spawn(slot):
    return {"spawn": slot}


def remove(slot):
    return {"remove": slot}


def remove_range(lo, hi, alive_only=False):
    a = {"from": lo, "to": hi}
    if alive_only:
        a["alive_only"] = True
    return {"remove_range": a}


def scripted_clear_range(lo, hi):
    # 409E16..409E55: live slots only, remove -> 42AFD2 loot -> gun count.
    return {"scripted_clear_range": {"from": lo, "to": hi}}


def behavior(slot, value):
    return {"set_field": {"slot": slot, "field": "behavior", "value": value}}


def field(slot, name, value):
    return {"set_field": {"slot": slot, "field": name, "value": value}}


def many(lo, hi, name, value):
    return {"set_field_range": {"from": lo, "to": hi, "field": name, "value": value}}


def target(slot, x, y):
    return {"set_field": {"slot": slot, "field": "target_x", "value": x}}, \
           {"set_field": {"slot": slot, "field": "target_y", "value": y}}


def win():
    return {"result": "victory"}


def lose():
    return {"result": "defeat"}


def score(n):
    return {"money": n}


def global_set(addr, value):
    return {"global_set": {"addr": addr, "value": value}}


def success_text(text):
    return {"success_text": text}


def failure_text(text):
    return {"failure_text": text}


def spawn_range(lo, hi):
    return {"spawn_range": {"from": lo, "to": hi}}


def at(slot, x, y):
    return (field(slot, "target_x", x), field(slot, "target_y", y))


# ---------------------------------------------------------------- levels

TRIGGERS = {
    0: {
        "entry": "0x408D28",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()],
                  note="0x408D2D：主角 stage=0 即失败"),
            _rule("reach_north_house_clear",
                  all_(dest(0, 17, 0), {"all_units_dead": False}),
                  [message("0x4725A8"), message("0x4725AC"),
                   remove(42), remove(43), remove(44), win()],
                  note="0x408D78：到达 (17,0) 且仍有敌军时撤走 42–44 后胜利"),
            _rule("reach_north_house_win", all_(dest(0, 17, 0), all_dead()),
                  [message("0x4725A8"), win()],
                  note="0x408DBC：到达 (17,0) 且已全歼时直接胜利"),
            _rule("behaviour_40_41", all_(area(0, 6, 18, 5, 4),
                                          flag("0x583F18", 0), stage(40, 1)),
                  [set_flag("0x583F18", 1),
                   behavior(40, 2), field(40, "target_slot", 0),
                   behavior(41, 2), field(41, "target_slot", 0),
                   message("0x472974")],
                  note="0x408DC6：进入 (6..10,18..21) 后 40/41 转为 behavior 2"),
            _rule("spawn_40_41", all_(area(0, 0, 5, 3, 4),
                                      flag("0x583F1C", 0),
                                      flag("0x583F18", 2)),
                  [set_flag("0x583F1C", 1), spawn(40), spawn(41),
                   behavior(40, 2), field(40, "target_slot", 0),
                   behavior(41, 2), field(41, "target_slot", 0),
                   message("0x472974"), message("0x4725D8")],
                  note="0x408E37：需要 0x583F18==2（T750 0x40F305 写入）"),
            _rule("spawn_42_44", all_(area(0, 12, 8, 5, 3),
                                      flag("0x583F20", 0)),
                  [set_flag("0x583F20", 1), spawn(42), spawn(43), spawn(44),
                   message("0x4725A4")],
                  note="0x408ECC：进入 (12..16,8..10) 生成 42–44"),
            _rule("flag_5_17", dest(0, 5, 17), [set_flag("0x583F2C", 1)],
                  note="0x408F2D"),
            _rule("flag_8_16", dest(0, 8, 16), [set_flag("0x583F30", 1)],
                  note="0x408F49"),
            # T750 entry0 0x40F24D：第 6 回合把 40/41 撤下并改到 (1,3)，
            # 之后 L00 的 spawn_40_41 才会在西北院重新放出两人。
            _rule("turn6_move_40_41",
                  all_(turn_eq(6), flag("0x583F18", 0), stage(40, 1), stage(41, 1)),
                  [message("0x4725A0"), remove(41),
                   field(40, "target_x", 0), field(40, "target_y", 3),
                   message("0x4725E8"), remove(40),
                   field(40, "x", 1), field(40, "y", 3),
                   set_flag("0x583F18", 2)],
                  note="0x40F24D T750 entry0：第 6 回合重排 40/41 到 (1,3)"),
            _rule("turn_limit_defeat", turn_gt(40), [lose()],
                  note="0x40F358 T750 entry0：第 40 回合后失败"),
        ],
        "notes": ["0x583F18==2 由 T750 entry0 0x40F305 写入；turn6_move_40_41 复刻该段。"],
    },
    1: {
        "entry": "0x408F67",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()],
                  note="0x408F6D"),
            _rule("escort_lost", stage(1), [lose()], note="0x408F9D：1 号槽阵亡即失败"),
            _rule("join_1", all_(adjacent(0, 1), flag("0x583F18", 0)),
                  [message("0x4725B0"), field(1, "pad3e", 1),
                   many(41, 47, "behavior", 6),
                   success_text("全歼敌人"), failure_text("超过五十回合"),
                   set_flag("0x583F18", 1)],
                  note="0x408FC1：与 1 号相邻后 41–46 转为 behavior 6"),
            _rule("win", all_(all_dead(), flag("0x583F18", neq=0)),
                  [message("0x472990"), win()], note="0x409044"),
        ],
    },
    2: {
        "entry": "0x40907B",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409080"),
            _rule("unit_49_lost", all_(stage(49), flag("0x583F18", 0)),
                  [message("0x472AD4"), set_flag("0x583F18", 1)], note="0x4090AD"),
            _rule("win", all_dead(), [message("0x4725D0"), win()], note="0x4090DA"),
        ],
    },
    3: {
        "entry": "0x409107",
        "rules": [
            _rule("li_lost", stage(4), [message("0x4725F0"), lose()], note="0x40910A"),
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40913C"),
            _rule("win", any_(all_dead(), dest(4, 20, 2)),
                  [message("0x4725E4"), win()],
                  note="0x40916B：全歼或李向阳到达 (20,2)"),
            _rule("meet_li", all_(adjacent(0, 4), flag("0x583F18", 0)),
                  [message("0x4725EC"), field(4, "pad3e", 1),
                   set_flag("0x583F18", 1)],
                  note="0x40919F"),
        ],
    },
    4: {
        "entry": "0x4091DA",
        "rules": [
            _rule("target_escaped", stage(40), [message("0x472628"), win()],
                  note="0x4091DD：40 号槽消失即胜利"),
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409203"),
        ],
    },
    5: {
        "entry": "0x409232",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409235"),
            _rule("win", all_dead(), [win()], note="0x409264/40926D: unguarded result write",
                  requires_result_zero=False),
        ],
    },
    6: {
        "entry": "0x409279",
        "rules": [
            _rule("protect_lost", stage(7), [lose()], note="0x40927C：7 号槽阵亡"),
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40929C"),
            _rule("win", all_dead(), [message("0x472650"), message("0x472654"), win()],
                  note="0x4092CC"),
        ],
    },
    7: {
        "entry": "0x409307",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40930B"),
            _rule("ambush", all_(area(7, 5, 8, 5, 5), flag("0x583F18", 0)),
                  [set_flag("0x583F18", 1),
                   message("0x47294C"), message("0x472950"), message("0x472954"),
                   many(40, 47, "behavior", 6),
                   many(40, 47, "target_slot", 7)],
                  note="0x40933D：7 号槽进入 (5..9,8..12)，40–46 围攻 7"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F1C", 0)),
                  [set_flag("0x583F1C", 1), message("0x472958"), message("0x47295C")],
                  note="0x4093DC"),
            _rule("win", all_dead(), [message("0x472960"), win()], note="0x409416"),
        ],
    },
    8: {
        "entry": "0x409445",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409448"),
            _rule("escort_lost", stage(9), [message("0x472984"), lose()], note="0x40947A：9 号槽阵亡"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x472970"), set_flag("0x583F18", 1)], note="0x4094AE"),
            _rule("win", all_dead(),
                  [message("0x47266C"), message("0x472670"), message("0x472674"),
                   score(2000), win()],
                  note="0x4094DA：+0x7D0 分"),
        ],
    },
    9: {
        "entry": "0x409533",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409536"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x472684"), set_flag("0x583F18", 1)], note="0x409565"),
            _rule("win", all_dead(), [message("0x472698"), win()], note="0x409592"),
        ],
    },
    10: {
        "entry": "0x4095BF",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409604"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x4729B0"), set_flag("0x583F18", 1)], note="0x409636"),
            _rule("boss_win", all_dead(),
                  [spawn(12), message("0x4729B8"), win()],
                  note="0x409663：全歼后 12 号出场并胜利"),
            _rule("spawn_65", all_(slot_cell(65), flag("0x583F1C", 0)),
                  [spawn(65), set_flag("0x583F1C", 1)],
                  note="0x40969D：65 号目标格被占后出场"),
            _rule("spawn_63", all_(slot_cell(63), flag("0x583F20", 0)),
                  [spawn(63), set_flag("0x583F20", 1)],
                  note="0x4096DD：63 号目标格被占后出场"),
            _rule("spawn_64", all_(slot_cell(64), flag("0x583F24", 0)),
                  [spawn(64), set_flag("0x583F24", 1)],
                  note="0x40971D：64 号目标格被占后出场"),
            _rule("rescued_65_lost", all_(stage(65), flag("0x583F1C", neq=0)),
                  [lose()], note="0x40975D：已救出的 65 阵亡即失败"),
            _rule("rescued_63_lost", all_(stage(63), flag("0x583F20", neq=0)),
                  [lose()], note="0x409781"),
            _rule("rescued_64_lost", all_(stage(64), flag("0x583F24", neq=0)),
                  [lose()], note="0x4097A4"),
            _rule("spawn_12", all_(slot_cell(12), stage(12)),
                  [spawn(12), message("0x472690"), message("0x472694")],
                  note="0x4097C8：12 号目标格被占且未出场时增援"),
            _rule("all_rescued_win",
                  all_(flag("0x583F1C", neq=0), flag("0x583F20", neq=0),
                       flag("0x583F24", neq=0)),
                  [spawn(12), message("0x4729B4"), win()],
                  note="0x40981E：三名村民都救出后胜利"),
        ],
        "notes": ["0x40969D 起用目标格占位判定；复刻用存活单位占位等价。"],
    },
    11: {
        "entry": "0x409860",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409865"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x4729C0"), set_flag("0x583F18", 1)], note="0x409895"),
            _rule("unit_13_lost", stage(13),
                  [message("0x4729C4"), message("0x4729C8"), lose()],
                  note="0x4098C2：13 号阵亡即失败"),
            _rule("target_x_19", dest(13, 8, 4), [field(13, "target_x", 19)],
                  note="0x409900：13 号到达 (8,4) 后转向 x=19"),
            _rule("win", dest(13, 19, 4), [message("0x4729CC"), win()],
                  note="0x409925：13 号到达 (19,4) 胜利"),
        ],
    },
    12: {
        "entry": "0x40995B",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40995E"),
            _rule("annihilate_win", all_dead(),
                  [message("0x4729F0"), message("0x4726C4"), message("0x4726C8"), win()],
                  note="0x409990：全歼胜利"),
            _rule("warehouse_win", all_(cell(8, 3, 1), cell(10, 3, 1)),
                  [message("0x4729EC"), message("0x4726C4"), message("0x4726C8"), win()],
                  note="0x4099D8：仓库两格 (8,3)/(10,3) 各占 1 人"),
        ],
    },
    13: {
        "entry": "0x409A49",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409A4C"),
            _rule("win", all_dead(), [message("0x472708"), message("0x47270C"), win()],
                  note="0x409A7B"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x472704"), set_flag("0x583F18", 1)], note="0x409AB6"),
        ],
    },
    14: {
        "entry": "0x409AE6",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409AE9"),
            _rule("unit_41_lost", all_(stage(41), flag("0x583F18", 0)),
                  [message("0x472A8C"), set_flag("0x583F18", 1)], note="0x409B1B"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F1C", 0)),
                  [message("0x472A88"), set_flag("0x583F1C", 1)], note="0x409B48"),
            _rule("win", all_dead(), [message("0x472714"), win()], note="0x409B76"),
        ],
    },
    15: {
        "entry": "0x409BA2",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409BA5"),
            _rule("unit_33_lost", stage(33), [lose()], note="0x409BD7"),
            _rule("unit_55_lost", stage(55), [lose()], note="0x409BFB"),
            _rule("unit_56_lost", stage(56), [lose()], note="0x409C1B"),
            _rule("win_after_turn_9", all_(all_dead(), turn_gt(9)),
                  [message("0x47272C"), message("0x472730"), message("0x472734"),
                   global_set("0x95EB1C", 1), win()],
                  note="0x409C3C：全歼且回合>9"),
        ],
    },
    16: {
        "entry": "0x409C99",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409C9D"),
            _rule("unit_33_lost", all_(stage(33), flag("0x583F18", neq=0)),
                  [lose()], note="0x409CCF：33 号阵亡且事件已发生"),
            _rule("unit_35_lost", all_(stage(35), flag("0x583F18", neq=0)),
                  [message("0x472A34"), message("0x472A38"), lose()],
                  note="0x409CFC"),
            _rule("escape_win", dest(35, 22, 34),
                  [message("0x47275C"), message("0x472760"),
                   global_set("0x95EB00", 1), win()],
                  note="0x409D46：35 号到达 (22,34) 胜利"),
            _rule("railway_event", all_(adjacent(0, 19), flag("0x583F18", 0)),
                  [message("0x472748"), message("0x47274C"),
                   global_set("0x7D18DC", 0),
                   map_cell_slot(19, 1), field(19, "behavior", 0),
                   scripted_clear_range(40, 61),
                   message("0x472750"), spawn(33), spawn(35),
                   flag_turn("0x583F50"), set_flag("0x583F18", 1),
                   set_flag("0x583F1C", 1)],
                  note="0x409D97：与 19 号相邻后清场 40–60，33/35 登场"),
            _rule("all_dead_event", all_(all_dead(), flag("0x583F18", 0)),
                  [message("0x472744"), spawn(33), spawn(35),
                   flag_turn("0x583F50"), set_flag("0x583F18", 1)],
                  note="0x409E99：全歼时补 33/35"),
        ],
    },
    17: {
        "entry": "0x409EE6",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x409F4A"),
            _rule("meet_20", all_(adjacent(0, 20), flag("0x583F50", 0)),
                  [message("0x472768"), remove(20), set_flag("0x583F50", 1)],
                  note="0x409F7C"),
        ] + [
            _rule("occupy_%d_%d" % (x, y),
                  all_(cell(x, y, 1), flag("0x583F18", 0) if i == 0 else
                       flag("0x%06X" % (0x583F18 + i * 4), 0)),
                  # Intentional gameplay exception, user-approved 2026-10-29:
                  # native 40A023 changes live Yulai to enemy after ANY crate.
                  # TXT303 only reports a machine gun; keep his current faction.
                  [message("0x472A44"),
                   set_flag("0x%06X" % (0x583F18 + i * 4), 1)],
                  note="0x409FCA：5 个占位点之一；可玩性修正：不再执行原40A023将雨来改为敌方的写入")
            for i, (x, y) in enumerate([(25, 6), (32, 6), (39, 6), (44, 7), (43, 5)])
        ] + [
            _rule("refresh_remaining_crates_text", {}, [{"text_digit_from_flags": {
                "field": "success", "gbk_byte_offset": 12,
                "flags": ["0x583F18", "0x583F1C", "0x583F20", "0x583F24", "0x583F28"],
                "subtract_from": 5, "modulus": 6, "unsigned_bits": 32,
                "digits": "012345"}}], requires_result_zero=False,
                  note="0x40A03D..40A073: success[12] = '0' + uint32(5-sum(flags))%6"),
            _rule("all_five_win",
                  {"flag_sum_eq": {"addrs": ["0x583F18", "0x583F1C", "0x583F20", "0x583F24", "0x583F28"], "value": 5}},
                  [message("0x47276C"), {"if": {"when": {"not": stage(20)},
                    "then": [global_set("0x7D1960", 1)]}}, win()],
                  note="0x40A03D：五个点都占完"),
        ],
    },
    18: {
        "entry": "0x40A0BA",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40A0BE"),
            _rule("meet_21", all_(adjacent(0, 21), flag("0x583F50", 0)),
                  [message("0x472778"), message("0x47277C"),
                   global_set("0x7D19E4", 0), map_cell_slot(21, 1),
                   field(21, "pad3e", 1), message("0x472A5C"),
                   set_flag("0x583F50", 1)],
                  note="0x40A0F0：与郑之光相邻，等待对话结果"),
            _rule("unrecruited_21_lost_win", all_(stage(21), flag("0x7D19E4", neq=0)),
                  [message("0x472A64"), remove_range(40, 77), message("0x472A68"), win()],
                  note="0x40A16D..40A1D9: People21.side!=0; new-game initialized to1"),
            _rule("annihilate_win", all_dead(),
                  [message("0x472A60"), win()], note="0x40A1DB"),
        ],
        "notes": ["0x7D19E4 is People21.side, initialized by the bulk PEOPLE.DAT load, not an independent zero global. Killing unrecruited21 wins; meeting changes side0 first."],
    },
    19: {
        "entry": "0x40A209",
        "rules": [
            _rule("any_player_death", any_player_death(), [lose()],
                  note="0x40A20D：0x406C8C 扫描全128槽，无存活side0即失败（tick）"),
            _rule("group_1_win", slots_count([40, 41, 42], eq=0),
                  [message("0x472788"), message("0x47278C"), message("0x472790"),
                   score(1000), win()],
                  note="0x40A22E：40–42 全部离场，+1000"),
            _rule("group_2_win", slots_count([43, 44, 45], eq=0),
                  [message("0x472794"), message("0x472798"), message("0x47279C"),
                   global_set("0x7D1A68", 1), score(2000), win()],
                  note="0x40A2A2：43–45 全部离场，+2000"),
        ],
        "notes": ["0x406C8C：全场没有stage非0且People.side0的单位时失败；不是任一阵亡。"],
    },
    20: {
        "entry": "0x40A325",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40A328"),
            _rule("unit_23_lost", all_(stage(23), flag("0x583F18", 0)),
                  [message("0x4727AC"), set_flag("0x583F18", 1)], note="0x40A35A"),
            _rule("unit_48_lost", all_(stage(48), flag("0x583F1C", 0)),
                  [message("0x4727B0"), set_flag("0x583F1C", 1)], note="0x40A387"),
            _rule("win", all_dead(), [message("0x472A90"),
                   {"if": {"when": {"people_compare": {"a": 0, "b": 23, "field": "level", "op": "gt"}},
                           "then": [message("0x4727C8"), message("0x4727CC"), {"set_faction": {"slot": 23, "value": 0}}],
                           "else": [message("0x4727D0")]}}, win()], note="0x40A3B5/40A3D5"),
        ],
        "notes": ["0x40A3D5 的 People0.level>People23.level决定招募。"],
    },
    21: {
        "entry": "0x40A427",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40A42A"),
            _rule("target_lost", stage(40),
                  [message("0x4727D4"), {"if": {"when": {"not": all_dead()},
                    "then": [message("0x472ADC")]}}, message("0x472AE0"), win()],
                  note="0x40A459：40 号离场即胜利"),
        ],
    },
    22: {
        "entry": "0x40A4AF",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40A4B5"),
            _rule("unit_24_lost", stage(24),
                  [message("0x472804"), message("0x472808"),
                   choice("", [
                       option("枪  毙", [message("0x47280C"), party_morale(2),
                                       message("0x47281C"), win()]),
                       option("放  逐", [message("0x472810"), score(5000),
                                       message("0x47281C"), win()]),
                       option("收  编", [message("0x472814"), message("0x472818"),
                                       {"set_faction": {"slot": 24, "value": 0}},
                                       {"set_faction": {"slot": 25, "value": 0}},
                                       message("0x47281C"), win()]),
                   ], 0)],
                  note="0x40A4E7：0x426E7D 三选一；0=枪毙(People0..23等级+2)/1=放走(+5000)/2=收编"),
            _rule("unit_25_lost", all_(stage(25), flag("0x583F18", 0)),
                  [message("0x4727E0"), set_flag("0x583F18", 1)], note="0x40A648"),
        ],
        "notes": ["0x426E7D 是 3 选 1 对话，返回 0/1/2；三个分支均由 choice 动作执行。"],
    },
    23: {
        "entry": "0x40A679",
        "rules": [
            # T750 entry23 0x40CA3F：第 1 回合从三个预设点随机选 34 号出生。
            _rule("init_slot34",
                  all_(turn_eq(1), flag("0x583F54", 0)),
                  [message("0x472834"), message("0x472838"),
                   random_slot_dest(34, [(0, 31), (7, 31), (21, 21)], 1),
                   field(34, "direction", 1), set_flag("0x583F54", 1)],
                  note="0x40CA3F T750 entry23：34 号随机出生点 (0,31)/(7,31)/(21,21)"),
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40A67C"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [set_flag("0x583F18", 1), message("0x472828")], note="0x40A6AE"),
            _rule("unit_41_lost", all_(stage(41), flag("0x583F1C", 0)),
                  [set_flag("0x583F1C", 1), message("0x47282C")], note="0x40A6DB"),
            _rule("all_clear", all_(all_dead(), flag("0x583F20", 0)),
                  [set_flag("0x583F20", 1), message("0x47283C")], note="0x40A709"),
            _rule("spawn_34_win", all_({"not": slot_cell(34, 0)}, flag("0x583F20", neq=0)),
                  [spawn(34), message("0x472840"), message("0x472844"), win()],
                  note="0x40A733：全歼后 34 号目标格被占，34 出场并胜利"),
        ],
    },
    24: {
        "entry": "0x40A79C",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40A79F"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x472AE4"), set_flag("0x583F18", 1)], note="0x40A7D1"),
            _rule("unit_27_lost", all_(stage(27), flag("0x583F1C", 0)),
                  [message("0x472860"), global_set("0x7D1CFC", 0),
                   message("0x472864"), global_set("0x7D1C78", 0),
                   {"if": {"when": {"not": stage(26)}, "then": [map_cell_slot(26, 1)]}},
                   message("0x472868"),
                   set_flag("0x583F1C", 1)],
                  note="0x40A7FE：27 号离场，26 号目标格标记"),
            _rule("win", all_dead(), [message("0x472AE8"), win()], note="0x40A886"),
        ],
    },
    25: {
        "entry": "0x40A8B3",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40A8B6"),
            _rule("unit_57_lost", all_(stage(57), flag("0x583F18", 0)),
                  [message("0x472888"), set_flag("0x583F18", 1)], note="0x40A8E5"),
            _rule("win", all_dead(),
                  [message("0x472890"), message("0x472894"), message("0x47289C"), win()],
                  note="0x40A912"),
        ],
    },
    26: {
        "entry": "0x40A95C",
        "rules": [
            _rule("any_player_death", any_player_death(), [lose()],
                  note="0x40A95F：0x406C8C 扫描全128槽，无存活side0即失败（tick）"),
            _rule("reach_cell", cell(2, 39, 1), [message("0x472AEC"), win()],
                  note="0x40A97D：地图格 (2,39) 被我方占住"),
        ],
        "notes": ["0x406C8C：全场无存活side0时失败；不检查last_dead。"],
    },
    27: {
        "entry": "0x40A9B9",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40A9BF"),
            _rule("unit_76_lost", all_(stage(76), flag("0x583F18", 0)),
                  [message("0x472AF8"), set_flag("0x583F18", 1)], note="0x40A9F8"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F1C", 0)),
                  [message("0x472AFC"), set_flag("0x583F1C", 1)], note="0x40AA25"),
            _rule("six_must_live", slots_count([41, 42, 43, 44, 45, 46], lt=6),
                  [lose()], note="0x40AA53：41–46 必须全部存活"),
            _rule("win", all_dead(), [message("0x472B00"), win()], note="0x40AA93"),
        ],
    },
    28: {
        "entry": "0x40AAC2",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40AAC5"),
            _rule("meet_30", all_(adjacent(0, 30), flag("0x583F18", 0)),
                  [message("0x4728D8"), set_flag("0x583F18", 1),
                   {"if": {"when": {"people_compare": {"a": 0, "b": 30, "field": "zhili", "op": "gte", "add": 10}},
                           "then": [message("0x4728DC"), message("0x4728E0"), set_flag("0x583F1C", 1)]}}],
                  note="0x40AAf7：与 30 号相邻；People0智力>=People30智力+10"),
            _rule("turn_target", area(40, 8, 0, 3, 1),
                  [field(40, "target_x", 0)], note="0x40AB61：把 40 号目标改到左侧"),
            _rule("escape_defeat", area(40, 0, 0, 1, 1),
                  [lose()], note="0x40AB8C：40 号到达 (0,0) 失败"),
            _rule("target_lost", stage(40),
                  [message("0x4728E4"), win(), {"if": {"when": flag("0x583F1C", 0),
                    "then": [message("0x4728D4"), global_set("0x7D1E88", 1)]}}],
                  note="0x40ABB7：40 号离场即胜利"),
        ],
        "notes": ["0x40AB29 的 People0/30智力比较决定台词与People30阵营。"],
    },
    29: {
        "entry": "0x40AC08",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40AC0C"),
            _rule("unit_32_lost", stage(32), [lose()], note="0x40AC3E"),
            _rule("unit_41_lost", all_(stage(41), flag("0x583F18", 0)),
                  [message("0x472944"), set_flag("0x583F18", 1)], note="0x40AC62"),
            _rule("flee_target", area(40, 27, 14, 3, 3),
                  [many(40, 50, "target_x", 47), many(40, 50, "target_y", 0)],
                  note="0x40AC8F：40 号进入 (27..29,14..16)，40–49 目标改到 (47,0)"),
            _rule("escape_defeat", area(40, 46, 0, 3, 1),
                  [lose()], note="0x40ACEA：40 号到达顶部出口失败"),
            _rule("target_lost", stage(40),
                  [message("0x4728EC"), message("0x4728F0"),
                   remove_range(40, 56, True), message("0x4728F4"), win()],
                  note="0x40AD16：40 号被消灭后清场并胜利"),
        ],
    },
    30: {
        "entry": "0x40AD9D",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40ADA1"),
            _rule("unit_33_lost", stage(33), [message("0x472938"), lose()], note="0x40ADD3"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x47293C"), set_flag("0x583F18", 1)], note="0x40AE05"),
            _rule("win", all_dead(), [message("0x472940"), win()], note="0x40AE33"),
            _rule("escape_win", dest(33, 31, 0),
                  [message("0x47290C"), remove_range(40, 84, True), win()],
                  note="0x40AE5F：33 号到达 (31,0)，清场后胜利"),
        ],
    },
    31: {
        "entry": "0x40AECF",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40AED2"),
            _rule("meet_31", all_(adjacent(6, 31), flag("0x583F18", 0)),
                  [message("0x472914"), message("0x472918"),
                   field(31, "pad3e", 1), set_flag("0x583F18", 1)],
                  note="0x40AF04：6 号与 31 号相邻"),
            _rule("win_before_meet", all_(all_dead(), flag("0x583F18", 0)),
                  [message("0x47291C"), global_set("0x7D1F0C", 1), win()],
                  note="0x40AF4B：未见 31 号即全歼"),
            _rule("win_after_meet", all_(all_dead(), flag("0x583F18", neq=0)),
                  [win()], note="0x40AF4B"),
        ],
    },
    32: {
        "entry": "0x40AF8B",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40AF8E"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x472B38"), set_flag("0x583F18", 1)], note="0x40AFBD"),
            _rule("win", all_dead(), [message("0x472B3C"), win()], note="0x40AFEA"),
        ],
    },
    33: {
        "entry": "0x40B017",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40B01A"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x472B48"), set_flag("0x583F18", 1)], note="0x40B049"),
            _rule("win", all_dead(), [message("0x472B4C"), win()], note="0x40B076"),
        ],
    },
    34: {
        "entry": "0x40B0A3",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40B0A6"),
            _rule("unit_40_lost", all_(stage(40), flag("0x583F18", 0)),
                  [message("0x472B5C"), set_flag("0x583F18", 1)], note="0x40B0D8"),
            _rule("unit_70_lost", all_(stage(70), flag("0x583F1C", 0)),
                  [message("0x472B60"), set_flag("0x583F1C", 1)], note="0x40B105"),
            _rule("unit_71_lost", all_(stage(71), flag("0x583F20", 0)),
                  [message("0x472B64"), set_flag("0x583F20", 1)], note="0x40B133"),
            _rule("win", all_dead(), [message("0x472B68"), win()], note="0x40B160"),
        ],
    },
    35: {
        "entry": "0x40B18D",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472598"), lose()], note="0x40B203"),
        ] + [
            _rule("loss_cue_%d" % (40 + i),
                  all_(stage(40 + i), bit("0x583F18", 1 << i, False)),
                  [message_table("0x472B78", i), set_bit("0x583F18", 1 << i)],
                  note="0x40B247：40–55 逐个阵亡音效（位掩码）")
            for i in range(16)
        ] + [
            _rule("win", all_dead(), [message("0x472BC0"), win()], note="0x40B2A0"),
        ],
    },
    36: {
        "entry": "0x40B2CF",
        "rules": [
            _rule("hero_down_%d" % (40 + i),
                  all_(stage(40 + i), flag("0x%06X" % (0x583F18 + i * 4), 0),
                       turn_le(40)),
                  [message("0x%06X" % (0x472C44 + i * 4)),
                   set_flag("0x%06X" % (0x583F18 + i * 4), 1)],
                  note="0x40B2CF：五壮士逐个阵亡音效")
            for i in range(5)
        ] + [_rule("all_players_lost", {"all_players_dead": True},
                   [message("0x472C5C"), lose()], note="0x40B3E1/0x40B3F3")],
        "notes": ["0x406C8C 扫描全场128槽：无存活side0时失败，不是任一阵亡。"],
    },
    37: {
        "entry": "0x40B46C",
        "rules": [
            _rule("cue_41", all_(stage(41), flag("0x583F1C", 0)),
                  [message("0x472CA8"), set_flag("0x583F1C", 1)], note="0x40B470"),
            _rule("cue_42", all_(stage(42), flag("0x583F20", 0)),
                  [message("0x472CAC"), set_flag("0x583F20", 1)], note="0x40B49D"),
            _rule("cue_43", all_(stage(43), flag("0x583F24", 0)),
                  [message("0x472CB0"), set_flag("0x583F24", 1)], note="0x40B4CA"),
            _rule("cue_44", all_(stage(44), flag("0x583F28", 0), turn_gt(20)),
                  [message("0x472CB4"), set_flag("0x583F28", 1)], note="0x40B4F8"),
            _rule("cue_45", all_(stage(45), flag("0x583F2C", 0)),
                  [message("0x472CB8"), set_flag("0x583F2C", 1)], note="0x40B52E"),
            _rule("cue_58", all_(stage(58), flag("0x583F30", 0)),
                  [message("0x472CC0"), set_flag("0x583F30", 1)], note="0x40B55B"),
            _rule("reinforce", all_(range_count(40, 128, lt=2, faction={"neq": 0}), flag("0x583F34", 0)),
                  [set_flag("0x583F34", 1), spawn_range(95, 105),
                   message("0x472C90"), spawn(44), spawn(48), spawn(49),
                   message("0x472C94"), many(95, 105, "morale", 80)],
                  note="0x40B589：40..127存活且People.side非0的单位<2 时大举增援"),
            _rule("unit_40_lost", stage(40),
                  [message("0x472CBC"), lose()], note="0x40B639"),
            _rule("win", all_dead(), [message("0x472CC4"), win()], note="0x40B666"),
        ],
    },
    38: {
        "entry": "0x40B695",
        "rules": [
            _rule("unit_40_lost", stage(40),
                  [message("0x472D1C"), lose()], note="0x40B6A2"),
            _rule("reinforce",
                  all_(stage(44), stage(59), stage(60), flag("0x583F18", 0)),
                  [flag_set_from_turn("0x583F4C"), set_flag("0x583F18", 1),
                   message("0x472CFC"), spawn(68), spawn(69), spawn(71),
                   spawn_range(98, 126),
                   field(67, "behavior", 5),
                   field(67, "target_x", 18), field(67, "target_y", 15),
                   many(80, 90, "behavior", 5),
                   many(80, 90, "target_x", 18), many(80, 90, "target_y", 15),
                   field(70, "behavior", 4),
                   field(70, "target_x", 5), field(70, "target_y", 3),
                   many(90, 98, "behavior", 4),
                   many(90, 98, "target_x", 5), many(90, 98, "target_y", 3)],
                  note="0x40B6D4：44/59/60 都不在场时三路增援"),
            _rule("crowd_defeat", region_gt(16, 38, 6, 5, 1),
                  [message("0x472D54"), lose()], note="0x40B83C：出口区格子重叠即失败"),
        ] + [
            _rule("cue_%d" % slot,
                  all_(*([stage(slot), bit("0x583F1C", mask, False)] +
                         ([turn_gt_flag("0x583F4C", add)] if add is not None else []))),
                  [message(ptr), set_bit("0x583F1C", mask)],
                  note="0x40B8BB：阵亡/失守音效")
            for slot, mask, ptr, add in [
                (41, 0x1, "0x472D20", None), (42, 0x2, "0x472D24", None),
                (43, 0x4, "0x472D28", None), (44, 0x8, "0x472CF8", None),
                (45, 0x10, "0x472D2C", None), (46, 0x20, "0x472D18", None),
                (61, 0x40, "0x472D30", 4), (62, 0x80, "0x472D34", 4),
                (67, 0x100, "0x472D38", None), (68, 0x200, "0x472D3C", 0),
                (69, 0x400, "0x472D40", 0), (70, 0x800, "0x472D44", None),
                (71, 0x1000, "0x472D48", 0), (72, 0x2000, "0x472D4C", None),
            ]
        ] + [
            _rule("win", all_dead(), [message("0x472D50"), win()], note="0x40BC01"),
        ],
    },
    39: {
        "entry": "0x40BC2F",
        "rules": [
            _rule("unit_40_lost", stage(40),
                  [message("0x472D70"), lose()], note="0x40BC33"),
            _rule("cue_41", all_(stage(41), flag("0x583F1C", 0)),
                  [message("0x472D74"), set_flag("0x583F1C", 1)], note="0x40BC65"),
            _rule("cue_42", all_(stage(42), flag("0x583F20", 0)),
                  [message("0x472D78"), set_flag("0x583F20", 1)], note="0x40BC92"),
            _rule("cue_43", all_(stage(43), flag("0x583F24", 0)),
                  [message("0x472D7C"), set_flag("0x583F24", 1)], note="0x40BCC0"),
            _rule("cue_61", all_(stage(61), flag("0x583F28", 0)),
                  [message("0x472D80"), set_flag("0x583F28", 1)], note="0x40BCED"),
            _rule("cue_62", all_(stage(62), flag("0x583F2C", 0)),
                  [message("0x472D84"), set_flag("0x583F2C", 1)], note="0x40BD1A"),
            _rule("cue_63", all_(stage(63), flag("0x583F30", 0)),
                  [message("0x472D88"), set_flag("0x583F30", 1)], note="0x40BD48"),
            _rule("unit_64_down", all_(stage(64), flag("0x583F34", 0)),
                  [message("0x472D8C"), set_flag("0x583F34", 1),
                   flag_set_from_turn("0x583F4C", 1),
                   many(62, 96, "behavior", 4)],
                  note="0x40BD75：64 号阵亡后 62–95 转为 behavior 4"),
            _rule("win", all_dead(), [message("0x472D94"), win()], note="0x40BDD8"),
        ],
    },
    40: {
        "entry": "0x410243",
        "rules": [
            _rule("hero_lost", stage(0), [message("0x472C04"), lose()], note="0x410246"),
        ] + [
            _rule("cue_%d" % (40 + i),
                  all_(stage(40 + i), flag("0x%06X" % (0x583F18 + i * 4), 0)),
                  [message("0x%06X" % (0x472C30 + i * 4)),
                   set_flag("0x%06X" % (0x583F18 + i * 4), 1)],
                  note="0x410278：40–44 逐个阵亡音效")
            for i in range(5)
        ] + [
            _rule("all_five_lost", slots_count([40, 41, 42, 43, 44], eq=0),
                  [message("0x472C58"), lose()], note="0x41035B：五人全部阵亡"),
            _rule("win", all_dead(), [message("0x472C68"), win()], note="0x4103B9"),
        ],
    },
    41: {
        "entry": "0x41061F",
        "rules": [
            _rule("cue_41", all_(stage(41), flag("0x583F1C", 0)),
                  [message("0x472CA8"), set_flag("0x583F1C", 1)], note="0x410622"),
            _rule("cue_42", all_(stage(42), flag("0x583F20", 0)),
                  [message("0x472CAC"), set_flag("0x583F20", 1)], note="0x41064F"),
            _rule("cue_43", all_(stage(43), flag("0x583F24", 0)),
                  [message("0x472CB0"), set_flag("0x583F24", 1)], note="0x41067C"),
            _rule("cue_44", all_(stage(44), flag("0x583F28", 0), turn_gt(20)),
                  [message("0x472CB4"), set_flag("0x583F28", 1)], note="0x4106AA"),
            _rule("cue_45", all_(stage(45), flag("0x583F2C", 0)),
                  [message("0x472CB8"), set_flag("0x583F2C", 1)], note="0x4106E0"),
            _rule("cue_58", all_(stage(58), flag("0x583F30", 0)),
                  [message("0x472CC0"), set_flag("0x583F30", 1)], note="0x41070D"),
            _rule("unit_40_lost", stage(40),
                  [message("0x472CBC"), lose()], note="0x41073B"),
            _rule("hero_lost_2", stage(0),
                  [message("0x472C04"), lose()], note="0x41076A"),
            _rule("win", all_dead(), [message("0x472CC4"), win()], note="0x410799"),
        ],
    },
    42: {
        "entry": "0x410B99",
        "rules": [
            _rule("unit_40_lost", stage(40),
                  [message("0x472D1C"), lose()], note="0x410B9F"),
            _rule("hero_lost", stage(0),
                  [message("0x472C04"), lose()], note="0x410BD8"),
            _rule("crowd_defeat", region_gt(16, 38, 6, 5, 1),
                  [message("0x472D54"), lose()], note="0x410C0A"),
        ] + [
            _rule("cue_%d" % slot,
                  all_(*([stage(slot), bit("0x583F1C", mask, False)] +
                         ([turn_gt(add)] if add is not None else []))),
                  [message(ptr), set_bit("0x583F1C", mask)],
                  note="0x410C88：阵亡/失守音效")
            for slot, mask, ptr, add in [
                (41, 0x1, "0x472D20", None), (42, 0x2, "0x472D24", None),
                (43, 0x4, "0x472D28", None), (44, 0x8, "0x472CE0", None),
                (45, 0x10, "0x472D2C", None), (46, 0x20, "0x472D18", None),
                (61, 0x40, "0x472D30", 12), (62, 0x80, "0x472D34", 12),
                (67, 0x100, "0x472D38", None), (68, 0x200, "0x472D3C", 8),
                (69, 0x400, "0x472D40", 8), (70, 0x800, "0x472D44", None),
                (71, 0x1000, "0x472D48", 8), (72, 0x2000, "0x472D4C", None),
            ]
        ] + [
            _rule("win", all_dead(), [message("0x472D50"), win()], note="0x410FB1"),
        ],
    },
    43: {
        "entry": "0x41134F",
        "rules": [
            _rule("unit_40_lost", stage(40),
                  [message("0x472D70"), lose()], note="0x411353"),
            _rule("hero_lost", stage(0),
                  [message("0x472C04"), lose()], note="0x411385"),
            _rule("cue_41", all_(stage(41), flag("0x583F1C", 0)),
                  [message("0x472D74"), set_flag("0x583F1C", 1)], note="0x4113B7"),
            _rule("cue_42", all_(stage(42), flag("0x583F20", 0)),
                  [message("0x472D78"), set_flag("0x583F20", 1)], note="0x4113E5"),
            _rule("cue_43", all_(stage(43), flag("0x583F24", 0)),
                  [message("0x472D7C"), set_flag("0x583F24", 1)], note="0x411412"),
            _rule("cue_61", all_(stage(61), flag("0x583F28", 0)),
                  [message("0x472D80"), set_flag("0x583F28", 1)], note="0x41143F"),
            _rule("cue_62", all_(stage(62), flag("0x583F2C", 0)),
                  [message("0x472D84"), set_flag("0x583F2C", 1)], note="0x41146D"),
            _rule("cue_63", all_(stage(63), flag("0x583F30", 0)),
                  [message("0x472D88"), set_flag("0x583F30", 1)], note="0x41149A"),
            _rule("unit_64_down", all_(stage(64), flag("0x583F34", 0)),
                  [message("0x472D8C"), set_flag("0x583F34", 1),
                   flag_set_from_turn("0x583F4C", 1),
                   many(62, 96, "behavior", 4)],
                  note="0x4114C7：64 号阵亡后 62–95 转为 behavior 4"),
            _rule("win", all_dead(), [message("0x472D94"), win()], note="0x411529"),
        ],
    },
    44: {
        "entry": "0x411672",
        "rules": [
            _rule("unit_40_lost", stage(40), [lose()], note="0x411675"),
            _rule("win", stage(56), [win()], note="0x411695：56 号离场即胜利"),
        ],
    },
    45: {
        "entry": "0x411762",
        "rules": [
            _rule("unit_40_lost", stage(40), [lose()], note="0x411765"),
            _rule("win_reach", dest(40, 0, 0), [win()],
                  note="0x41177C：40 号到达 (0,0) 胜利"),
            _rule("rival_reach", dest(41, 0, 0), [lose()],
                  note="0x411798：41 号先到 (0,0) 失败"),
        ],
    },
    46: {
        "entry": "0x411873",
        "rules": [
            _rule("too_few", range_count(70, 81, lt=11), [lose()],
                  note="0x411880：70–80 存活少于 11 失败"),
            _rule("win", all_dead(), [win()], note="0x4118C2"),
        ],
    },
}
