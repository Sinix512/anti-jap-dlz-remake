extends SceneTree
# Intentional L17 gameplay exception, not an original-fidelity claim or campaign play.
const Codec=preload("res://scripts/battle/StateCodec.gd")
const State=preload("res://scripts/m2/GameState.gd")
const CRATES=[Vector2i(25,6),Vector2i(32,6),Vector2i(39,6),Vector2i(44,7),Vector2i(43,5)]
var checks:=0
var failures:=0
var m4:Dictionary
var m2:Dictionary
var font:Font
var b
var state
var side14_events:Array=[]

func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("YULAI_FAIL "+label)
func unit(slot:int,faction:int,tile:Vector2i):
	var d:Dictionary=m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"hero":slot==0,"name":"fixture%d"%slot,
		"faction":faction,"side":"player" if faction==0 else "enemy","x":tile.x,"y":tile.y,
		"hp":126,"max_hp":337,"level":20,"xp":56,"morale":88,"control":true,
		"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0]},true)
	return b._spawn_unit(d)
func on_story(kind:String,payload:Dictionary) -> void:
	if kind=="person_side":
		state.set_person_side(int(payload.slot),int(payload.faction))
		if int(payload.slot)==14:side14_events.append(payload)
func make_battle(level:Dictionary,context:Dictionary,encoded:Dictionary={}) -> void:
	if b!=null:b.free()
	b=load("res://scripts/Battle.gd").new();root.add_child(b);b.fast_sim=true
	b.setup(m4.duplicate(true),level,font,context,encoded)
	b.animations_enabled=false;b.sfx_enabled=false;b.set_process(false)
	b.story_event.connect(on_story)
func fixture(faction:int):
	state=State.new();state.setup_m4(m4);state.new_game(m2);state.set_person_side(14,faction)
	side14_events.clear()
	make_battle(m4.levels[17].duplicate(true),{"campaign_story":true})
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.mines.clear()
	b.terrain.fill(0);b.scenario.trigger_flags.clear();b.trigger_messages.clear()
	b.scenario.started=true;b.scenario.start_phase_pending=false;b.busy=false
	var hero=unit(0,0,Vector2i(1,1));b.scenario.protagonist=hero
	unit(14,faction,Vector2i(12,12));unit(40,1,Vector2i(10,10))
	return hero
func run() -> void:
	m4=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	m2=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json")))
	font=load("res://assets/font/hzk16.fnt")
	for faction in [0,2]:
		var hero=fixture(faction)
		var rain=b.unit_by_slot(14)
		for i in range(CRATES.size()):
			hero.set_tile(CRATES[i].x,CRATES[i].y);await b.scenario.on_tick()
			check(b.unit_faction(rain)==faction and side14_events.is_empty(),"crate %d preserves current faction %d, no persistent side event"%[i,faction])
			check(rain.hp==126 and rain.morale==88 and int(rain.data.xp)==56 and not rain.acted,"crate %d does not heal, damage, grant XP or consume Yulai's action"%i)
			check(int(b.scenario.trigger_flags["0x%x"%(0x583f18+i*4)])==1,"crate %d collected"%i)
			check(b.finished_flag==(i==4),"five crates required, step %d"%i)
			if i==0:
				var count:int=b.trigger_messages.size();await b.scenario.on_tick()
				check(b.trigger_messages.size()==count,"same crate cannot report twice")
			if i==1:
				var snap:Dictionary=Codec.unpack(b.snapshot())
				make_battle(snap.level,snap.context,Codec.pack(snap))
				hero=b.unit_by_slot(0);rain=b.unit_by_slot(14)
				check(b.unit_faction(rain)==faction and (rain in b.player_units)==(faction==0),"mid-battle JSON resume groups Yulai correctly")
		check(b.last_result=="victory" and b.last_result_trigger.id=="all_five_win","original five-crate victory preserved")
		check(state.has_member(14)==(faction==0),"persistent party membership preserved")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--repair-save="):await verify_repaired_copy(arg.trim_prefix("--repair-save="))
	b.free();await process_frame
	print("YULAI_CRATE_FACTION ","PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func verify_repaired_copy(path:String) -> void:
	# Explicit staged copy only. This test never calls save_slot or touches user saves.
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	state=State.new();state.setup_m4(m4)
	check(state.from_dict(saved),"repaired copy loads through GameState")
	check(state.has_member(14) and int(state.person(14).faction)==0,"repaired copy restores strategic roster")
	var encoded:Dictionary=state.battle_resume.snapshot
	var snap:Dictionary=Codec.unpack(encoded)
	side14_events.clear();make_battle(snap.level,snap.context,encoded)
	var rain=b.unit_by_slot(14)
	var expected:Dictionary=snap.level.units.filter(func(u):return int(u.slot)==14)[0]
	check(rain.side=="player" and rain in b.player_units and rain not in b.enemy_units,"repaired copy restores live faction and grouping")
	check(b.turn==int(snap.turn) and b.phase==snap.phase and rain.hp==int(expected.hp) and rain.morale==int(expected.morale),"repaired copy preserves turn, phase, HP and morale")
	check(not rain.acted and rain.control,"repaired Yulai remains selectable and can act")
	var hero=b.unit_by_slot(0)
	for tile in CRATES:
		hero.set_tile(tile.x,tile.y);await b.scenario.on_tick()
		check(rain.side=="player" and side14_events.is_empty() and state.has_member(14),"subsequent saved crate cannot re-eject Yulai at %s"%tile)
	check(b.last_result=="victory" and b.last_result_trigger.id=="all_five_win","repaired copy can complete five-crate objective")
