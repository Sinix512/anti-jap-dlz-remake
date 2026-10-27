extends SceneTree
# Static contracts: People.side controls statistics, XP and406C30 all128 scan.
# Synthetic resolver fixtures, NOT legal campaign play/completion evidence.
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const Codec=preload("res://scripts/battle/StateCodec.gd")
var checks:=0
var failures:=0
var m2:Dictionary
var m4:Dictionary
var npc_record:Dictionary
var b
var penalties:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("FACTION_FAIL "+label)
func fixture(idx:=18) -> void:
	if b!=null:b.free()
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.fast_sim=true
	b.setup(m4.duplicate(true),m4.levels[idx].duplicate(true),load("res://assets/font/hzk16.fnt"),{"campaign_story":true})
	b.animations_enabled=false;b.sfx_enabled=false;b.set_process(false)
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.mines.clear()
	for i in range(b.terrain.size()):b.terrain[i]=0
	b.scenario.trigger_flags.clear();b.scenario.start_phase_pending=false
	b.level.difficulty_setting=2
	b.stats={"losses":0,"kills":0,"kills_by_mine":0,"kills_by_gun":0,"loot_count":0}
	b.busy=false
	penalties.clear()
	b.presentation_step.connect(func(kind,payload):
		if kind=="penalty_commit":penalties.append(payload))
func unit(slot:int,faction:int,tile:Vector2i,hp:=100,lv:=1):
	var d:Dictionary=npc_record.duplicate(true) if slot==21 else m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"hero":slot==0,"name":"fixture%d"%slot,"faction":faction,"side":"player" if faction==0 else "enemy","x":tile.x,"y":tile.y,"hp":hp,"max_hp":hp,"level":lv,"xp":0,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0]},true)
	return b._spawn_unit(d)
func base(idx:=18):
	fixture(idx)
	var hero=unit(0,0,Vector2i(1,1),100,5)
	b.scenario.protagonist=hero
	return hero
func mine(tile:Vector2i) -> void:
	b.mines.append({"tile":tile,"mine":b.data.mines[0],"mine_id":0,"code":0,"low":1,"owner_side":"player"})
func run() -> void:
	m2=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var inconsistencies:Array=[]
	for lv in m4.levels:
		for pool in ["units","slot_pool","spawn_pool"]:
			for d in lv.get(pool,[]):
				if str(d.side)!=("player" if int(d.faction)==0 else "enemy"):inconsistencies.append([lv.index,pool,d.slot])
	check(inconsistencies.is_empty(),"all47 generated pools derive side from exact People faction")
	for d in m4.levels[18].units:
		if int(d.slot)==21:npc_record=d.duplicate(true)
	check(npc_record.get("side")=="enemy" and int(npc_record.get("faction",0))==1 and not npc_record.control,"authentic unrecruited21 template retains faction1/control0")
	var old:Dictionary=m4.duplicate(true)
	for d in old.levels[18].units:
		if int(d.slot)==21:d.side="player"
	var built:Dictionary=Builder.build(old,m2,18,[])
	check(built.units.filter(func(d):return int(d.slot)==21)[0].side=="enemy","Builder fixes stale pre-overlay side cache")
	var joined:Dictionary=Builder.build(old,m2,18,[{"pid":21,"faction":0,"bingzhong":1,"level":7}])
	var joined21:Dictionary=joined.units.filter(func(d):return int(d.slot)==21)[0]
	check(joined21.side=="player" and int(joined21.faction)==0 and int(joined21.level)==7 and not joined21.control,"persistent party overlay precedes side sync; control independent")
	var hero=base()
	var stale:Dictionary=npc_record.duplicate(true);stale.side="player";stale._runtime_state=true;stale.x=10;stale.y=10
	var npc=b._spawn_unit(stale)
	check(npc.side=="enemy" and npc.data.side=="enemy" and npc in b.enemy_units and npc not in b.player_units,"late/runtime hydration fixes cache before grouping")
	check(not npc.control and not b.scenario._cond({"all_units_dead":true}),"alive unrecruited21 blocks annihilation with no40+ enemies")
	check(b.scenario._cell_code(10,10)==2 and b.same_faction(npc,unit(40,1,Vector2i(12,12))),"unrecruited occupancy2 and faction1 equality")
	var third=unit(41,2,Vector2i(13,12))
	check(third.side=="enemy" and int(third.data.faction)==2 and not b.same_faction(third,npc),"nonzero group does not collapse exact third faction")
	check(b.scenario._cell_code(13,12)==3,"third faction retains original occupancy byte3")
	third.placed=false
	check(b.scenario._cell_code(13,12)==0 and b.alive_enemies()==3,"unplaced active fighter blocks annihilation but has no occupied cell")
	third.placed=true
	var snap:Dictionary=Codec.unpack(b.snapshot())
	for d in snap.level.units:
		if int(d.slot)==21:d.side="player"
	var restored=load("res://scripts/Battle.gd").new();root.add_child(restored);restored.fast_sim=true
	restored.setup(m4.duplicate(true),snap.level,load("res://assets/font/hzk16.fnt"),snap.context,Codec.pack(snap));restored.set_process(false)
	check(restored.unit_by_slot(21).side=="enemy" and restored.unit_by_slot(21) in restored.enemy_units and restored.alive_enemies()==3,"JSON resume cannot resurrect contradictory side cache")
	restored.free()
	b.set_slot_faction(21,0)
	check(npc.side=="player" and npc.data.faction==0 and npc in b.player_units and npc not in b.enemy_units and not npc.control,"recruit side write updates caches but not independent control")
	for kind in ["attack","skill"]:
		hero=base();npc=unit(21,1,Vector2i(1,2),1,30);unit(40,1,Vector2i(12,12))
		if kind=="attack":await b._perform_attack(hero,npc)
		else:
			hero.data.zhili=100;npc.data.zhili=0
			hero.skill_counts.huogong=1;b.selected=hero;b.active_skill_id=3;b.active_skill=b.data.skills[3]
			await b._execute_skill_at(Vector2i(npc.x,npc.y))
		check(not npc.alive and b.stats.kills==1 and b.stats.kills_by_gun==1 and b.stats.losses==0,"%s kill21 counted once as nonmine enemy, no scripted-remove kills"%kind)
		check(penalties.is_empty(),"%s kill21 does not penalize hero"%kind)
		check(b.last_result=="victory" and b.last_result_trigger.id=="unrecruited_21_lost_win" and b.unit_by_slot(40)==null,"%s kill21 reaches original311/312 victory"%kind)
	hero=base();npc=unit(21,1,Vector2i(10,10),1,30);var target=unit(40,1,Vector2i(8,8),1,1)
	var scenario=b.scenario;b.scenario=null
	mine(Vector2i(8,8));await b._detonate_mines(Vector2i(8,8))
	check(not target.alive and hero.gained_xp==12 and npc.gained_xp==0,"unrecruited21 neither denominator nor recipient of shared mine XP")
	mine(Vector2i(10,10));await b._detonate_mines(Vector2i(10,10))
	check(not npc.alive and hero.gained_xp==24 and int(hero.data.level)==5 and b.stats.kills_by_mine==2 and b.stats.losses==0,"unrecruited21 mine death grants12 XP, no friendly loss/penalty")
	b.scenario=scenario;await scenario.on_tick()
	check(b.last_result=="victory" and b.last_result_trigger.id=="unrecruited_21_lost_win","mine death21 publishes original alternate victory after accounting")
	hero=base();npc=unit(21,1,Vector2i(2,1),1,30);unit(40,1,Vector2i(12,12))
	await b.scenario.on_tick()
	check(npc.side=="player" and int(npc.data.faction)==0 and npc.control and npc in b.player_units,"real meet21 trigger writes faction then control")
	mine(Vector2i(2,1));await b._detonate_mines(Vector2i(2,1))
	check(not npc.alive and hero.gained_xp==0 and b.stats.losses==1 and b.stats.kills==0 and int(hero.data.level)==4,"recruited21 mine death applies friendly penalty and no enemy XP")
	await b.scenario.on_tick()
	check(not b.finished_flag and b.unit_by_slot(40)!=null,"recruited21 death cannot take unrecruited victory")
	for active in [false,true]:
		hero=base(17);var fourteen=unit(14,0,Vector2i(12,12));var twenty=unit(20,0,Vector2i(15,15))
		var side_events:Array=[]
		b.story_event.connect(func(kind,payload):
			if kind=="person_side":side_events.append(payload))
		if not active:b.remove_slot(14);b.remove_slot(20)
		hero.set_tile(25,6);await b.scenario.on_tick()
		check(int(fourteen.data.faction)==(1 if active else 0),"L17 crate14 faction write requires live stage %s"%active)
		for tile in [Vector2i(32,6),Vector2i(39,6),Vector2i(44,7),Vector2i(43,5)]:
			hero.set_tile(tile.x,tile.y);await b.scenario.on_tick()
		check(int(twenty.data.faction)==(1 if active else 0) and b.last_result=="victory","L17 final20 faction write requires live stage %s"%active)
		check(active or side_events.is_empty(),"L17 departed14/20 are not persistently ejected by spurious side events %s"%active)
	hero=base(22);var twenty_four=unit(24,1,Vector2i(10,10),17,8);var twenty_five=unit(25,1,Vector2i(11,10),29,9)
	twenty_four.control=false;twenty_five.control=false
	twenty_four.data.xp=27;twenty_five.data.xp=33;twenty_five.behavior=7
	b.remove_slot(24);b.fast_sim=false;await b.scenario.on_tick();await b.scenario.resolve_choice(2)
	check(not twenty_four.alive and twenty_four.hp==0 and Vector2i(twenty_four.x,twenty_four.y)==Vector2i(10,10),"L22 side write does not resurrect/heal/relocate defeated24")
	check(twenty_five.alive and twenty_five.hp==29 and Vector2i(twenty_five.x,twenty_five.y)==Vector2i(11,10),"L22 side write preserves live25 stage/HP/position")
	check(not twenty_four.control and not twenty_five.control and twenty_five.behavior==7 and int(twenty_four.data.xp)==27 and int(twenty_five.data.xp)==33,"L22 no extra control/behavior/XP changes")
	check(twenty_four.side=="player" and twenty_four.data.faction==0 and twenty_five.side=="player" and twenty_five.data.faction==0 and b.stats.get("recruited",[]).is_empty(),"L22 two People.side writes are sufficient; no second settlement recruitment")
	hero=base(23);var occupant=unit(40,2,Vector2i(7,31))
	for pool in ["slot_pool","spawn_pool"]:
		for d in b.level[pool]:
			if int(d.slot)==34:d.x=7;d.y=31
	b.scenario._set_global("0x583F20",1)
	b.scenario._set_global("0x583F54",1) # entry already completed; do not randomize34 again
	check(b.scenario._cond({"slot_pos_cell_occupied":{"slot":34,"eq":0}})==false,"L23 target may be occupied by nonplayer")
	await b.scenario.on_tick()
	check(occupant.alive and b.last_result=="victory" and b.last_result_trigger.id=="spawn_34_win","L23 original nonempty-cell test accepts faction2 occupant")
	b.queue_free();await process_frame;await create_timer(0.15).timeout
	print("ORIGINAL_FACTION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
