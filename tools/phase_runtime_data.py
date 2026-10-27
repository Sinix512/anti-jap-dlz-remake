"""Ordered entry scripts compiled from retained 4465D0 Evidence.
Pure cosmetic waits/camera pans are omitted, not the ordering of state/dialogue.
"""
from phase_trigger_data import START_PHASES

def compile_start(index):
    p = START_PHASES[index]
    def msg(*ids): return [{"message_record": n} for n in ids]
    def spawn(*slots): return [{"spawn": n} for n in slots]
    def move(slot,x,y): return {"phase_move":{"slot":slot,"x":x,"y":y}}
    writes=[]
    for w in p.get("literal_writes",[]):
        if w["table"]=="global" and 0x583F18 <= int(w["address"],16) <= 0x583F57:
            if int(w["address"],16)==0x583F54: continue
            writes.append({"flag_set":{"addr":f'0x{int(w["address"],16):X}',"value":w["value"]}})
        elif w["table"]=="people":
            if w["offset"]==24: writes.append({"set_faction":{"slot":w["slot"],"value":w["value"]}})
            elif w["offset"]==124:
                writes.append({"mine_bytes":{"slot":w["slot"],"values":[(w["value"]>>(j*8))&255 for j in range(4)]}})
        elif w["table"]=="fighter":
            field={4:"hp",60:"stage",61:"behavior",63:"moveable"}.get(w["offset"])
            if field: writes.append({"set_field":{"slot":w["slot"],"field":field,"value":w["value"]}})
    for w in p.get("people_byte_writes",[]): writes.append({"mine_bytes":{"slot":w["slot"],"values":w["bytes"]}})
    actions = writes + spawn(*p.get("spawn_slots",[])) + msg(*p.get("messages",[]))
    if index==2:
        actions=writes+msg(333,335,334)+[move(2,12,7),move(3,13,6),move(2,14,7),move(3,15,6),move(42,11,7),{"phase_mine":{"tile":[11,7],"type":0,"slot":42}}]+msg(336,337,338,16)
    elif index==5: actions=msg(33,34)+writes+spawn(40,41,42,43,44,45)+msg(35,36)
    elif index==6: actions=msg(45)+writes+spawn(40,41,42,43,44,45,46)+msg(46,43,47,48,49)
    elif index==9: actions=writes+msg(60)+spawn(11)+msg(61,62,64)
    elif index==13: actions=writes+msg(91)+[move(56,13,37),{"remove":56}]
    elif index==15: actions=msg(101)+writes+spawn(17,18)+msg(102)+[{"phase_movie":"train"}]+msg(103)+spawn(33,55,56)+msg(104)
    elif index==25:
        # 40CB49: the three explosions are ordered between TXT187 and188.
        explosions=[{"phase_flm":{"index":0,"tile":[x,y],"camera":focus,"wait_ms":1000}}
                    for x,y,focus in [(10,9,True),(12,9,False),(24,10,True)]]
        actions=writes+spawn(12,15,16)+msg(187)+explosions+msg(188,189)+[move(7,18,29)]+msg(191,198,190,196)+[{"remove":7}]
    elif index in (37,41):
        ids=p["messages"]
        actions=writes+msg(ids[0])+spawn(40)+msg(ids[1])+spawn(*[v for v in p["spawn_slots"] if v!=40])+msg(*ids[2:])
    if "random_dest" in p:
        q=p["random_dest"]
        actions.append({"random_slot_dest":{"slot":q["slot"],"options":[v[:2] for v in q["choices"]],"direction":q["choices"][0][2]}})
    if "random_behavior" in p: actions.append({"random_behavior":p["random_behavior"]})
    if "clear_skills_slots" in p: actions.append({"clear_skills":p["clear_skills_slots"]})
    actions.append({"flag_set":{"addr":"0x583F54","value":1}})
    return actions
