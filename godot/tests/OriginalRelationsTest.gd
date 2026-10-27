extends SceneTree
## Read-only original-rule matrices: real movement/skill tables and production resolvers.
const AI = preload("res://scripts/battle/OriginalAI.gd")
const State = preload("res://scripts/m2/GameState.gd")
const Codec = preload("res://scripts/battle/StateCodec.gd")
const D4 = "0x7d06d4"
const D8 = "0x7d06d8"
var checks := 0
var failures := 0
var m4: Dictionary
var m2: Dictionary
var font_ref: Font
var b
var camp
var turn_observations: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RELATION_FAIL " + label)
func close_fixture() -> void:
	if is_instance_valid(b):
		b.scenario.battle = null
		b.free()
	b = null
func fixture(w := 7, h := 1, bz := 1, terrain_id := 0) -> void:
	close_fixture()
	var lv: Dictionary = m4.levels[0].duplicate(true)
	lv.index = -1
	for key in ["waves","start_actions","chests","protect","units","reserves","spawn_pool","slot_pool"]: lv[key] = []
	lv.triggers = {"authoritative":true,"rules":[],"texts":{}}
	lv.objective = {"type":"annihilate","label":"relation fixture"}
	lv.map.width = w; lv.map.height = h
	lv.map.terrain = []
	for i in range(w*h): lv.map.terrain.append(terrain_id)
	var initial: Dictionary = m4.levels[0].units[0].duplicate(true)
	initial.merge({"slot":0,"faction":0,"side":"player","x":0,"y":0,"bingzhong":bz},true)
	lv.units = [initial]
	b = load("res://scripts/Battle.gd").new(); root.add_child(b)
	b.setup(m4,lv,font_ref,{"script_globals":{D4:10,D8:20}})
	b.fast_sim = true; b.animations_enabled = false; b.sfx_enabled = false; b.set_process(false)
	for u in b.units: u.free()
	b.units.clear(); b.player_units.clear(); b.enemy_units.clear()
	b.selected = null; b.finished_flag = false; b.busy = false; b.phase = "player"
	b.scenario.protagonist = null
	b.level.units.clear(); b.level.slot_pool.clear()
	turn_observations.clear()
	b.story_event.connect(observe_story)
func observe_story(kind: String, rec: Dictionary) -> void:
	if kind == "turn": turn_observations.append([int(rec.turn),rel(D4),rel(D8)])
func unit(slot: int, faction: int, pos: Vector2i, move_budget := 5, bz := 1):
	var d: Dictionary = m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"name":"relation%d"%slot,"faction":faction,"side":"player" if faction==0 else "enemy","x":pos.x,"y":pos.y,"bingzhong":bz,"level":10,"xp":0,"zhili":100,"wuli":80,"hp":1000,"max_hp":1000,"morale":100,"control":false,"auto":true,"behavior":13,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0],"attack_count":0,"skills":{},"skill_counts":{}},true)
	var u = b._spawn_unit(d)
	u.move = move_budget; u.acted = true
	return u
func rel(addr: String) -> int: return b.scenario._global_value(addr)
func corridor(expected: Dictionary) -> Dictionary:
	var out := {}
	for x in expected: out[Vector2i(int(x),0)] = int(expected[x])
	return out
func reachable(u, expected: Dictionary, label: String) -> void:
	var actual: Dictionary = b.compute_reachable(u)
	check(actual == expected,label+" exact costs/set actual="+str(actual))
func cast(caster, target, sid: int) -> void:
	caster.acted = false
	b.selected = caster; b.active_skill_id = sid; b.active_skill = b.data.skills[sid]
	b._execute_skill_at(Vector2i(target.x,target.y))
func pair(actor_slot: int, target_slot: int, sid: int, hp := 900, morale := 99, faction := 0) -> Array:
	fixture(7,7)
	var actor = unit(actor_slot,0,Vector2i(3,4))
	var target = actor if actor_slot == target_slot else unit(target_slot,faction,Vector2i(3,3))
	if actor_slot == target_slot:
		# Real class3 at level76 has exactly 1000 maxHP; self gains XP and
		# production _gain_xp recomputes maxHP even without leveling.
		actor.bingzhong = 3; actor.data.bingzhong = 3; actor.data.level = 76
	target.hp = hp; target.morale = morale
	actor.skill_counts[b.SKILL_KEYS[sid]] = 1
	return [actor,target]
func end_round() -> void:
	for u in b.units: u.acted = true
	await b._on_end_turn()
func zoc_matrix() -> void:
	fixture(); var u=unit(0,0,Vector2i(0,0)); reachable(u,corridor({1:1,2:2,3:3,4:4,5:5}),"Z01")
	fixture(); u=unit(0,0,Vector2i(0,0)); unit(1,0,Vector2i(2,0)); reachable(u,corridor({1:1,3:3,4:4,5:5}),"Z02")
	check(b._path_to(Vector2i(5,0),Vector2i(0,0)).has(Vector2i(2,0)),"Z02 path crosses ally")
	fixture(); u=unit(0,0,Vector2i(0,0)); var enemy=unit(40,1,Vector2i(4,0)); reachable(u,corridor({1:1,2:2,3:3}),"Z03")
	enemy.acted=true; enemy.control=false; enemy.behavior=13; reachable(u,corridor({1:1,2:2,3:3}),"Z04 inactive enemy ZOC")
	enemy.alive=false; reachable(u,corridor({1:1,2:2,3:3,4:4,5:5}),"Z05 stage0")
	fixture(); u=unit(0,0,Vector2i(3,0),3); unit(40,1,Vector2i(2,0)); reachable(u,corridor({4:1,5:2,6:3}),"Z06 start exemption")
	fixture(); u=unit(40,1,Vector2i(0,0)); enemy=unit(41,2,Vector2i(4,0)); reachable(u,corridor({1:1,2:2,3:3}),"Z07 faction1 vs2")
	u.behavior=8; u.target_x=6; u.target_y=0; u.home_x=0; u.home_y=0
	var plan: Dictionary=AI.plan(b,u)
	check(plan.kind=="move" and plan.station==Vector2i(3,0),"AI Z07 consumes ZOC range")
	check(Vector2i(u.x,u.y)==Vector2i(0,0) and Vector2i(enemy.x,enemy.y)==Vector2i(4,0),"AI planning position immutability")
	enemy.data.faction=1; reachable(u,corridor({1:1,2:2,3:3,5:5}),"Z08 faction1 ally")
	plan=AI.plan(b,u); check(plan.station==Vector2i(5,0),"AI Z08 passes exact ally")
	fixture(); u=unit(40,1,Vector2i(0,0)); unit(41,1,Vector2i(2,0)); unit(42,2,Vector2i(3,0)); reachable(u,corridor({1:1}),"Z09 ally in enemy ZOC")
	fixture(3,3); u=unit(0,0,Vector2i(0,0),4); unit(40,1,Vector2i(1,1)); reachable(u,{Vector2i(1,0):1,Vector2i(0,1):1},"Z10 diagonal exits")
	fixture(2,2); u=unit(0,0,Vector2i(0,0),1); unit(40,1,Vector2i(1,1)); reachable(u,{Vector2i(1,0):1,Vector2i(0,1):1},"Z11 exact exhausted budget")
	fixture(); u=unit(0,0,Vector2i(0,0),0); reachable(u,{},"Z12 zero budget")
	# Real class11 has terrain1 cost1 and terrain9 cost4. No table mutation.
	fixture(4,2,11,1); u=unit(0,0,Vector2i(0,0),4,11); b.terrain[1]=9
	reachable(u,{Vector2i(1,0):4,Vector2i(2,0):4,Vector2i(0,1):1,Vector2i(1,1):2,Vector2i(2,1):3,Vector2i(3,1):4},"Z13 real weighted terrain")
	fixture(5,3); u=unit(0,0,Vector2i(2,1),1); u.behavior=8;u.target_x=4;u.target_y=0
	plan=AI.plan(b,u);check(plan.station==Vector2i(2,0),"AI row-major equal Manhattan tie")
func skill_matrix() -> void:
	for row in [[0,7,12,20],[7,0,11,20],[8,7,10,22],[7,8,10,21],[0,8,10,20],[7,7,10,20]]:
		for sid in [0,1,2]:
			var p:=pair(row[0],row[1],sid); var a=p[0];var t=p[1]
			cast(a,t,sid)
			var tag:="S%d %d->%d"%[sid,row[0],row[1]]
			check(t.hp==(900 if sid==1 else 1000) and t.morale==(99 if sid==0 else 100),tag+" HP/morale")
			check(rel(D4)==row[2] and rel(D8)==row[3],tag+" exact relations")
			check(int(a.skill_counts[b.SKILL_KEYS[sid]])==2 and a.acted and int(a.data.xp)==[10,4,8][sid],tag+" practice/action/XP")
	for row in [[0,1000,99,1000,99,1,0,10],[1,900,100,900,100,1,0,10],[2,1000,100,1000,100,1,0,10],[2,1000,99,1000,100,2,8,12],[2,999,100,1000,100,2,8,12],[2,999,99,1000,100,2,8,12]]:
		var sid:int=row[0];var p:=pair(0,7,sid,row[1],row[2]);var a=p[0];var t=p[1];cast(a,t,sid)
		check(t.hp==row[3] and t.morale==row[4],"effective sid%d hp%d morale%d result"%[sid,row[1],row[2]])
		check(int(a.skill_counts[b.SKILL_KEYS[sid]])==row[5] and int(a.data.xp)==row[6] and a.acted,"effective practice/XP/action "+str(row))
		check(rel(D4)==row[7] and rel(D8)==20,"effective relations "+str(row))
	for sid in [0,1,2]:
		var p:=pair(0,7,sid,900,99,1);var a=p[0];var t=p[1]
		check(b._skill_targets(a,b.data.skills[sid]).has(Vector2i(t.x,t.y)) and not b._skill_targets(a,b.data.skills[sid],true).has(Vector2i(t.x,t.y)),"player enemy center legal / AI filtered sid%d"%sid)
		cast(a,t,sid)
		check(t.hp==900 and t.morale==99 and int(a.skill_counts[b.SKILL_KEYS[sid]])==1 and int(a.data.xp)==0 and a.acted and rel(D4)==10 and rel(D8)==20,"hostile support sid%d"%sid)
	for hostile in [false,true]:
		fixture(7,7);var a=unit(7,0,Vector2i(3,4));var t=unit(0,0,Vector2i(3,3));var v=unit(8,1 if hostile else 0,Vector2i(4,3))
		a.skill_counts.yiliao=45;t.hp=900;t.morale=99;v.hp=900;v.morale=99
		cast(a,t,2)
		check(t.hp==1000 and t.morale==100 and v.hp==(900 if hostile else 1000) and v.morale==(99 if hostile else 100),"AoE channels hostile="+str(hostile))
		check(rel(D4)==11 and rel(D8)==(20 if hostile else 21),"AoE relations hostile="+str(hostile))
		check(int(a.skill_counts.yiliao)==(46 if hostile else 47) and int(a.data.xp)==(8 if hostile else 16) and a.acted,"AoE counts XP hostile="+str(hostile))
func faction_matrix() -> void:
	for sides in [[0,0],[0,1],[0,2],[1,1],[1,2],[2,1],[2,2]]:
		fixture(7,7);var a=unit(40,sides[0],Vector2i(3,4));var t=unit(41,sides[1],Vector2i(3,3))
		t.hp=500;a.acted=false;a.select=4
		var equal:bool=sides[0]==sides[1]
		check(b.same_faction(a,t)==equal and b.attack_targets(a).has(Vector2i(3,3))==not equal,"faction attack selection "+str(sides))
		# Class1 Lv10 W80 has ATK138; DEF93*110% terrain0 =>102.
		# Center apply0=100%; max(HP/20=25,138-102)=36.
		check(b._effective_attack(a)==138 and b._effective_defense(t)==102,"faction real-table attack/defense "+str(sides))
		await b._perform_attack(a,t)
		check(t.hp==(500 if equal else 464),"faction resolved HP "+str(sides))
		fixture(7,7);a=unit(40,sides[0],Vector2i(3,4));t=unit(41,sides[1],Vector2i(3,3))
		t.hp=500;a.skill_counts.buji=1
		cast(a,t,0)
		check(t.hp==(620 if equal else 500) and rel(D4)==10 and rel(D8)==20,"faction actual supply "+str(sides))
	# A non-healing support action must not accidentally use relationship helper.
	var p:=pair(0,7,12);p[1].data.zhili=0;p[1].integrity=60;p[1].defense_integrity=60
	cast(p[0],p[1],12)
	check(p[1].integrity==80 and p[1].defense_integrity==80 and rel(D4)==10 and rel(D8)==20,"real supervise repairs without relation growth")
func round_matrix() -> void:
	for index in range(8):
		fixture(7,7);var girl=unit(7,0,Vector2i(2,2));var a=unit(0,0,Vector2i(1,2));var c=unit(8,0,Vector2i(3,2))
		var expected:=[11,21]
		match index:
			1:a.set_tile(1,1);c.set_tile(4,2);expected=[10,20]
			2:a.set_tile(2,2);expected=[10,21]
			3:a.alive=false;expected=[10,21]
			4:girl.alive=false;b.level.slot_pool=[{"slot":7,"x":2,"y":2}];expected=[10,20]
			5:b.set_slot_faction(7,2);b.set_slot_faction(8,1)
			6:b.finished_flag=true;expected=[10,20]
			7:b.scenario.finished=true;expected=[10,20]
		await end_round()
		check(rel(D4)==expected[0] and rel(D8)==expected[1],"round matrix %d relations"%index)
		check(b.turn==(1 if index in [6,7] else 2),"round matrix %d turn"%index)
		if index not in [6,7]:check(turn_observations==[[2,expected[0],expected[1]]],"T750 sees accumulated relations %d"%index)
		if index==0:
			await end_round();check(rel(D4)==12 and rel(D8)==22 and b.turn==3,"second independent round +1 each")
	fixture(7,7);var a=unit(0,0,Vector2i(1,2));var girl=unit(7,0,Vector2i(2,2));var cond:={"adjacent":{"a":0,"b":7}}
	check(b.scenario._cond(cond),"Scenario adjacency live Manhattan1")
	a.alive=false;check(not b.scenario._cond(cond),"Scenario adjacency actor stage0");a.alive=true
	girl.alive=false;b.level.slot_pool=[{"slot":7,"x":2,"y":2}];check(not b.scenario._cond(cond),"Scenario adjacency target pool stage0");girl.alive=true
	a.set_tile(2,2);check(not b.scenario._cond(cond),"Scenario adjacency distance0")
	a.set_tile(0,2);check(not b.scenario._cond(cond),"Scenario adjacency distance2")
func persistence_matrix() -> void:
	var p:=pair(0,7,0);var a=p[0];var t=p[1]
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp)
	camp.state=State.new();camp.state.new_game(m2);camp.state.setup_m4(m4)
	camp.current_battle_index=0;camp.current_battle_standalone=false
	camp.state.script_globals={D4:10,D8:20};camp.state.save_checkpoint(false)
	b.story_event.connect(camp._on_battle_story_event)
	cast(a,t,0)
	check(int(camp.state.script_globals[D4])==12,"Campaign production global signal writes growth")
	var loaded=State.new();loaded.new_game(m2);loaded.setup_m4(m4)
	loaded.from_dict(JSON.parse_string(JSON.stringify(camp.state.to_dict())))
	check(int(loaded.script_globals[D4])==12,"GameState JSON retains relation growth")
	var encoded:Dictionary=JSON.parse_string(JSON.stringify(b.snapshot()))
	var snap:Dictionary=Codec.unpack(encoded)
	close_fixture();b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4,snap.level,font_ref,snap.context,encoded)
	b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false;b.set_process(false)
	b.story_event.connect(camp._on_battle_story_event)
	check(rel(D4)==12 and b.turn==1,"Battle JSON resume no growth or turn replay")
	await end_round()
	check(rel(D4)==13 and int(camp.state.script_globals[D4])==13 and b.turn==2,"resumed real endturn grows exactly once")
	camp.state.load_checkpoint()
	check(int(camp.state.script_globals[D4])==13,"production retry checkpoint preserves earned relation")
	camp.free();camp=null
func overflow_matrix() -> void:
	for addr in [D4,D8]:
		fixture(7,7);unit(7,0,Vector2i(2,2));unit(0 if addr==D4 else 8,0,Vector2i(1,2))
		b.scenario._set_global(addr,4294967295)
		await end_round()
		check(rel(addr)==0,"UINT32 round wrap "+addr+" actual="+str(rel(addr)))
		var p:=pair(0 if addr==D4 else 8,7,0)
		b.scenario._set_global(addr,4294967294);cast(p[0],p[1],0)
		check(rel(addr)==0,"UINT32 skill +2 wrap "+addr+" actual="+str(rel(addr)))
func run() -> void:
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"));m2=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	font_ref=load("res://assets/font/hzk16.fnt")
	zoc_matrix();skill_matrix();await faction_matrix();await round_matrix();await persistence_matrix();await overflow_matrix()
	close_fixture();await process_frame;await create_timer(0.3).timeout
	print("ORIGINAL_RELATIONS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
