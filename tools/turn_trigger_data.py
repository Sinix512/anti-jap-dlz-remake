"""Exact transcription of DLZ.exe's 47-entry per-round table at 0x446750.

Static rule facts decoded from the per-turn table at 0x446750.
NOT the 0x4465D0 intro table. Called by 0x40497D after turn increments,
then terrain recovery (0x42A395), mine timers (0x41F2E2), then 0x446510.
Rules must run ONCE PER ROUND, in listed source order; not on each UI tick.
All ranges are half-open. Empty entries 19/44/45 really are no-ops.

Additional generic DSL needed by the consumer:
* turn_eq_flag {addr, add}: turn == flag[addr]+add (uint32 addition).
* flag_sum_lt {addrs, value}: uint32(sum(flag[a])) < value.
* if {when, then, else}: conditional action, evaluated at execution time.
* adjust_field_range {from,to,field,add?,mul?,div?,min?,source_semantics?}:
  update every slot, even an inactive reserve. Operations mul/div/add then min.
  source_semantics='u32_sub15_lt2': result=1 if uint32(old-15)<2 else old-15.
* restore_hp_range {from,to}: max HP from original 0x429E31, including reserves.
* random_choice {options:[action-list,...]}: uniform rand()%len(options).
* scripted_attack {attacker_slot,target_slot}: 0x412030 then 0x41307F;
  attack centered on target's current tile, bypass range/action validation.

set_field 'morale'=Fighter+08, 'integrity'=+0C, 'defense_integrity'=+10,
'pad3e'=+3E (AI/player control permission), 'moveable'=+3F.
"""
from __future__ import annotations

try:
    from .trigger_data import (all_, any_, stage, area, flag, turn_gt, turn_eq,
        turn_le, message, set_flag, spawn, remove, remove_range, field, many,
        target, win, lose, spawn_range)
except ImportError:
    from trigger_data import (all_, any_, stage, area, flag, turn_gt, turn_eq,
        turn_le, message, set_flag, spawn, remove, remove_range, field, many,
        target, win, lose, spawn_range)

ENTRIES = [
    0x40F24D,0x40F364,0x40F429,0x40F441,0x40F459,0x40F4DC,0x40F554,
    0x40F56C,0x40F584,0x40F59C,0x40F5B4,0x40F66B,0x40F687,0x40F788,
    0x40F7DA,0x40F7F2,0x40F84B,0x40F94E,0x40F966,0x40F9D7,0x40F9DC,
    0x40FA0D,0x40FA3C,0x40FA54,0x40FA6C,0x40FA84,0x40FAC7,0x40FADF,
    0x40FB2A,0x40FBE8,0x40FC04,0x40FC1C,0x40FC7E,0x40FC96,0x40FCC5,
    0x40FCF4,0x40FD23,0x40FEE6,0x40FFFF,0x41018E,0x4104AC,0x4109D5,
    0x4110A6,0x4115BA,0x41175D,0x41186E,0x41199C,
]

def r(rid, when, actions):
    return {"id": "t750_" + rid, "on": "turn", "when": when,
            "then": actions}  # no once: L00 artillery repeats on eligible rounds

def msgs(*pointers):
    return [message("0x%06X" % p) for p in pointers]

def eqflag(addr, add=0):
    return {"turn_eq_flag": {"addr": addr, "add": add}}

def iff(when, then, else_=None):
    return {"if": {"when": when, "then": then, "else": else_ or []}}

def adjust(lo, hi, name, **kwargs):
    return {"adjust_field_range": {"from": lo, "to": hi, "field": name, **kwargs}}

def hp(lo, hi):
    return {"restore_hp_range": {"from": lo, "to": hi}}

def dests(lo, hi, x, y, behavior):
    return [many(lo, hi, "behavior", behavior), many(lo, hi, "target_x", x),
            many(lo, hi, "target_y", y)]

TURN_TRIGGERS = {i: {"entry": "0x%06X" % e, "table": "0x446750",
                       "rules": []}
                 for i, e in enumerate(ENTRIES)}

# Source order is important: e.g. L16/L18/L20 skip all events on timeout.
# The simple timeout-only entries, or entries with timeout as their last branch.
LIMITS = {0:40, 1:50, 2:30, 3:20, 4:30, 5:30, 6:20, 7:40, 8:30, 9:30,
          10:30, 12:30, 13:30, 14:30, 15:30, 16:30, 17:30, 18:30, 20:30,
          21:20, 22:30, 23:30, 24:30, 25:40, 26:20, 27:40, 28:30, 30:40,
          31:30, 32:50, 33:50, 34:60, 35:80, 39:50, 40:45, 41:40, 43:50}

def timeout(level):
    return r("timeout", turn_gt(LIMITS[level]), [lose()])

T = {i: [] for i in range(47)}
T[0] = [
    r("turn6_40_41", all_(turn_eq(6), flag("0x583F18", 0), stage(40,1), stage(41,1)),
      msgs(0x4725A0) + [remove(41), *target(40,0,3)] + msgs(0x4725E8) +
      [remove(40), field(40,"dest_x",1), field(40,"dest_y",3), set_flag("0x583F18",2)]),
    r("artillery", all_(turn_gt(6),
      {"flag_sum_lt": {"addrs":["0x583F2C","0x583F30"],"value":2}}, area(0,4,15,8,8)),
      [{"random_choice": {"options": [
          [iff(area(0,6,y,4,1), [{"scripted_attack": {"attacker_slot":45,"target_slot":0}}])]
          for y in (18,19,20)]}}]),
    timeout(0),
]
T[1] = [r("turn4",turn_eq(4),msgs(0x472AB8)+
          [adjust(40,48,"morale",add=-15,source_semantics="u32_sub15_lt2")]),
        r("rescue_timeout",all_(flag("0x583F18",0),turn_gt(40)),
          [lose()]+msgs(0x4725B4,0x4725B8)), timeout(1)]
T[4] = [r("turn9",turn_eq(9),msgs(0x4725FC)),
        r("turn13",turn_eq(13),[spawn_range(51,57)]+msgs(0x472600)), timeout(4)]
T[5] = [timeout(5), r("turn7",turn_eq(7),[spawn(5),spawn(6)]+msgs(0x47261C)),
        r("turn8",turn_eq(8),msgs(0x472620,0x472624)+[field(5,"pad3e",1),field(6,"pad3e",1)])]
T[10] = [timeout(10),r("turn21",turn_eq(21),[spawn_range(53,63),
           iff(stage(40,1),msgs(0x4729A8))]),r("turn22",turn_eq(22),msgs(0x4729AC))]
T[11] = [r("turn2",turn_eq(2),msgs(0x4729BC))]
T[12] = [r("turn2",turn_eq(2),msgs(0x4729E8)),
         r("turn11",turn_eq(11),[{"presentation_sequence":
           [{"phase_flm":{"index":0,"tile":[9,5],"camera":True,"wait_ms":1000}}]+
           msgs(0x4726B8,0x4726BC,0x4726C0)}]+
           [adjust(40,128,"morale",div=2,min=1)]),timeout(12)]
T[13] = [r("turn9",turn_eq(9),[spawn(15),spawn(16)]+msgs(0x4726FC,0x472700)),timeout(13)]
T[15] = [r("turn9",turn_eq(9),[spawn_range(40,55)]+msgs(0x472A1C)),timeout(15)]
T[16] = [
    r("turn3",turn_eq(3),msgs(0x47273C,0x472740)+[many(40,55,"integrity",95)]),
    r("train_reinforcement",all_(turn_le(30),flag("0x583F18",neq=0),eqflag("0x583F50",3)),
      [spawn_range(61,69),iff(flag("0x583F1C",0),msgs(0x472A30),
        msgs(0x472758)+[remove_range(61,69)])]),timeout(16)]
T[18] = [r("turn3",turn_eq(3),msgs(0x472A58)),
         r("turn8",turn_eq(8),[spawn_range(65,77)]+msgs(0x472774)),timeout(18)]
T[20] = [r("turn5",turn_eq(5),msgs(0x4727A8)),timeout(20)]
T[21] = [r("turn3",turn_eq(3),msgs(0x472A04)),timeout(21)]
T[25] = [timeout(25),r("turn9",turn_eq(9),[spawn(28),spawn(29)]+msgs(0x47288C))]
T[27] = [timeout(27),r("turn2",turn_eq(2),[many(72,87,"behavior",6)])]
T[28] = [timeout(28),r("turn2",turn_eq(2),msgs(0x472B0C)),
         r("turn5",turn_eq(5),[spawn(30),spawn(58),spawn(59)]+msgs(0x4728C8)),
         r("turn6",turn_eq(6),msgs(0x4728CC)),
         r("turn9",turn_eq(9),[spawn_range(53,57)]+msgs(0x4728D0))]
T[29] = [r("turn2",turn_eq(2),msgs(0x472934))]
T[31] = [r("turn2",turn_eq(2),msgs(0x472B1C)),
         r("turn4",turn_eq(4),[many(51,71,"behavior",4)]),timeout(31)]
T[33] = [timeout(33),r("turn2",turn_eq(2),msgs(0x472B44))]
T[34] = [timeout(34),r("turn2",turn_eq(2),msgs(0x472B58))]
T[35] = [timeout(35),r("turn2",turn_eq(2),msgs(0x472BBC))]


def langya_waves():
    # Source order: turn26 BEFORE turn24; this is not a typo.
    return [r("turn%d" % t,turn_eq(t),[spawn_range(lo,hi)])
            for t,lo,hi in [(11,70,76),(16,76,82),(21,82,88),(26,88,94)]] + [
        r("turn24",turn_eq(24),[spawn_range(94,100),many(60,70,"behavior",4)]),
        r("turn36",turn_eq(36),[spawn_range(100,106)])]
T[36] = [r("turn2",turn_eq(2),msgs(0x472C2C)),
         r("survived",turn_gt(40),msgs(0x472C60,0x472C64)+[remove_range(40,45),win()]),
         *langya_waves()]
T[37] = [r("turn3",turn_eq(3),msgs(0x472CA0)),
         r("turn5",turn_eq(5),msgs(0x472C8C)+[field(58,"behavior",1),many(59,94,"behavior",6)]),
         r("turn7",turn_eq(7),msgs(0x472CA4)),
         r("turn8",turn_eq(8),msgs(0x472C88)+[hp(40,58),many(40,58,"morale",100)]),
         r("turn12",turn_eq(12),msgs(0x472C9C)+[many(40,58,"morale",100)])]


def taierzhuang_delayed():
    return [spawn_range(61,67)]+msgs(0x472D08,0x472D0C)+dests(67,68,19,40,4)+dests(80,90,19,40,4)

def taierzhuang_cues():
    return [r("turn%d"%t,turn_eq(t),msgs(p)) for t,p in [(2,0x472CE8),(3,0x472CEC),(4,0x472CF0)]] + [
        r("turn5",all_(turn_eq(5),stage(44,1)),msgs(0x472CF4))]
T[38] = [*taierzhuang_cues(),
         r("relative2",eqflag("0x583F4C",2),msgs(0x472D04)),
         r("relative4",eqflag("0x583F4C",4),taierzhuang_delayed()),
         r("relative5",eqflag("0x583F4C",5),msgs(0x472D10,0x472D14))]


def kunlun(relative_add):
    return [r("turn2",turn_eq(2),msgs(0x472D60)),r("turn10",turn_eq(10),msgs(0x472D64)),
            r("relative",eqflag("0x583F4C",relative_add),msgs(0x472D6C)),
            r("turn35",turn_eq(35),[spawn_range(118,128)]+msgs(0x472C10)),
            r("timeout",turn_gt(50),msgs(0x472D90)+[lose()])]
T[39] = kunlun(0)
T[40] = [r("turn2",turn_eq(2),msgs(0x472C2C)),timeout(40),*langya_waves()]
T[41] = [timeout(41),r("turn3",turn_eq(3),msgs(0x472CA0)),
         r("turn5",turn_eq(5),msgs(0x472C8C)+[field(58,"behavior",1),many(59,94,"behavior",6)]),
         r("turn9",turn_eq(9),msgs(0x472CA4)),
         r("turn11",turn_eq(11),msgs(0x472C88)+[hp(40,58),many(40,58,"morale",100)]),
         r("turn16",turn_eq(16),msgs(0x472C9C)+[many(40,58,"morale",100)]),
         r("turn21",turn_eq(21),[spawn_range(95,105)]+msgs(0x472C90)+
           [spawn(44),spawn(48),spawn(49)]+msgs(0x472C94)+[many(95,105,"morale",90)])]
T[42] = [*taierzhuang_cues(),
         r("turn8",turn_eq(8),[set_flag("0x583F18",1)]+msgs(0x472D00)+
           [spawn(68),spawn(69),spawn(71),spawn_range(98,128)]+
           dests(67,68,18,15,5)+dests(80,90,18,15,5)+
           dests(70,71,5,3,4)+dests(90,98,5,3,4)),
         r("turn10",turn_eq(10),msgs(0x472D04)),
         r("turn12",turn_eq(12),taierzhuang_delayed()),
         r("turn13",turn_eq(13),msgs(0x472D10,0x472D14))]
T[43] = kunlun(1)
T[46] = [r("turn2",turn_eq(2),[field(80,"pad3e",1)])]

for i in range(47):
    if not T[i] and i in LIMITS:
        T[i] = [timeout(i)]
    TURN_TRIGGERS[i]["rules"] = T[i]

# Alternative spelling used by source tooling; no implicit integration occurs.
TRIGGERS = TURN_TRIGGERS

if __name__ == "__main__":
    import json
    print(json.dumps(TURN_TRIGGERS, ensure_ascii=False, indent=2))
