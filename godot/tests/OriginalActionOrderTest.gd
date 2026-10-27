extends SceneTree
const Codec=preload("res://scripts/battle/StateCodec.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
class Observer extends RefCounted:
	var status_text:=""
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
class SettlementProbe extends "res://scripts/m4/Campaign.gd":
	var settled := false
	func _settle_battle(_result:String,_message:String) -> void:settled=true
var checks:=0
var failures:=0
var m2:Dictionary
var m4:Dictionary
var b
var events:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("ORDER_FAIL "+label)
func fixture() -> void:
	if b!=null:b.free()
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4.duplicate(true),m4.levels[0].duplicate(true),load("res://assets/font/hzk16.fnt"),{})
	b.set_process(false);b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false;b.scenario=Observer.new();b.phase="qa"
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.mines.clear();b.level.index=2;b.level.difficulty_setting=1
	events.clear()
	b.presentation_step.connect(func(kind:String,payload:Dictionary):events.append({"kind":kind,"payload":payload.duplicate(true),"time":Time.get_ticks_msec()}))
func unit(slot:int,side:int,tile:Vector2i,hp:=500,level:=1):
	var d:Dictionary=m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"name":"fixture%d"%slot,"side":"player" if side==0 else "enemy","faction":side,"x":tile.x,"y":tile.y,"hp":hp,"max_hp":hp,"morale":100,"level":level,"xp":0,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0],"control":true,"bingzhong":1,"zhili":100,"wuli":100},true)
	return b._spawn_unit(d)
func count_event(kind:String) -> int:return events.filter(func(e):return e.kind==kind).size()
func event_index(kind:String,slot:=-1) -> int:
	for i in range(events.size()):
		if events[i].kind==kind and (slot<0 or int(events[i].payload.get("slot",-1))==slot):return i
	return -1
func run() -> void:
	m2=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json")))
	m4=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	fixture();var h=unit(0,0,Vector2i(8,15),90)
	h.data.xp=95;b.fast_sim=false;b.animations_enabled=true;b.animation_speed=0
	var old_camera:Vector2=b.camera.position
	b._gain_xp(h,10)
	check(h.data.level==1 and h.data.xp==105 and b.progress_fx_active,"XP full value/old level until upgrade presentation completes")
	check(not b.camera_follow,"upgrade temporarily suspends follow-camera")
	await b._wait_for_progress_fx()
	check(h.data.level==2 and h.data.xp==5 and b.camera.position==old_camera,"upgrade commits and restores previous camera")
	check(events[-1].kind=="xp_commit" and count_event("xp_start")==1,"upgrade commits once after presentation")
	h.data.level=99;h.data.xp=95;events.clear()
	b._gain_xp(h,10)
	check(b.progress_fx_active and h.data.xp==105,"level99 still plays original upgrade effect")
	await b._wait_for_progress_fx()
	check(h.data.level==99 and h.data.xp==5,"level99 caps only after effect and keeps modulo")
	# Native per-item death XP: first kill levels up, next uses the NEW level.
	fixture();h=unit(0,0,Vector2i(5,7),90);h.data.xp=99;h.item_slots[0]=45
	var a=unit(40,1,Vector2i(5,5),10,2);var c=unit(41,1,Vector2i(6,5),10,2)
	b.fast_sim=false;b.animations_enabled=true;b.animation_speed=0;b.presentation_in_headless=true
	b.data.items["44"].anm_index=-1 # Isolate the digital/death/XP transaction, not ANM timing.
	b.selected=h;b.active_item_id=44
	var started:=Time.get_ticks_msec()
	b._execute_item_at(Vector2i(5,5))
	check(b.busy and a.hp==0 and a.alive and h.item_slots[0]==45,"numeric damage precedes numbers, but stage/item stay uncommitted")
	await create_timer(0.1).timeout
	check(a.alive and c.alive and h.data.level==1 and h.item_slots[0]==45,"no death/XP/consumption during32-frame number stage")
	while b.busy and Time.get_ticks_msec()-started<7000:await process_frame
	var awards:Array=events.filter(func(e):return e.kind=="xp_start").map(func(e):return e.payload.amount)
	check(awards==[8,6] and h.data.level==2 and h.data.xp==13,"item kill XP waits across level transition and recalculates next kill")
	check(not a.alive and not c.alive and not a.visible and not c.visible and h.item_slots[0]==0 and b.action_resolution_depth==0,"all deaths finish before item consumption/unlock")
	check(event_index("numbers_end")<event_index("inactive",40) and event_index("inactive",40)<event_index("xp_start",0),"numbers -> inactive -> per-death XP")
	check(event_index("xp_commit",0)<event_index("death_end",40) and event_index("death_end",40)<event_index("inactive",41),"previous XP/death completes before next death")
	var number_events:Array=events.filter(func(e):return e.kind in ["numbers_start","numbers_end"])
	check(number_events[1].time-number_events[0].time>=1024,"digital stage keeps32x32ms even at FLM speed0")
	check(a.sprite.scale==Vector2.ONE,"death never invents sprite shrinking")
	# Skill and mine use two numeric penalties, but ONE final FLM31.
	for kind in ["skill","mine","attack"]:
		fixture();h=unit(0,0,Vector2i(1,1),90,5)
		a=unit(1,0,Vector2i(5,5),1);c=unit(2,0,Vector2i(6,5),1)
		var enemy=unit(40,1,Vector2i(5,7),500,5)
		if kind=="skill":
			enemy.skill_counts.kongxi=45;b.selected=enemy;b.active_skill_id=15;b.active_skill=b.data.skills[15];await b._execute_skill_at(Vector2i(5,5))
		elif kind=="mine":
			b.mines.append({"tile":Vector2i(5,5),"mine":b.data.mines[1],"mine_id":1,"code":1,"low":1});await b._detonate_mines(Vector2i(5,5))
		else:
			# Only this fixture replaces the gun's mask so both deaths are certain.
			b.data.unit_types[enemy.bingzhong].apply=1;enemy.attack_count=45
			await b._perform_attack(enemy,a)
		check(not a.alive and not c.alive,kind+" actually kills both fixture allies")
		check(h.data.level==3 and count_event("penalty_commit")==2 and count_event("penalty_fx")==1,kind+" applies two level penalties, one final FLM31")
		check(event_index("death_end",2)<event_index("penalty_fx"),kind+" finishes all deaths before final penalty effect")
		if kind!="mine":check(event_index("penalty_fx")<event_index("xp_start",40),kind+" penalty precedes unified XP")
	# Throwing item tests penalty count BEFORE each casualty increment (third included).
	fixture();h=unit(0,0,Vector2i(1,1),90,5)
	a=unit(1,0,Vector2i(5,5),1);c=unit(2,0,Vector2i(6,5),1);unit(3,0,Vector2i(5,6),1)
	var enemy=unit(40,1,Vector2i(5,7),500,5);enemy.item_slots[0]=45
	b.selected=enemy;b.active_item_id=44;await b._execute_item_at(Vector2i(5,5))
	check(b.stats.losses==3 and h.data.level==2 and count_event("penalty_fx")==3,"item third casualty still penalizes unlike attack/skill/mine")
	# Shared mine XP has max(1,raw/count), and recipients are slot-ordered.
	fixture()
	for slot in [4,2,0,3,1,41]:unit(slot,0,Vector2i(1,slot%5+1),500)
	unit(60,1,Vector2i(5,5),10)
	b.mines.append({"tile":Vector2i(5,5),"mine":b.data.mines[0],"mine_id":0,"code":0,"low":1});await b._detonate_mines(Vector2i(5,5))
	var xp_events:Array=events.filter(func(e):return e.kind=="xp_start")
	check(xp_events.map(func(e):return e.payload.slot)==[0,1,2,3,4,41],"shared mine XP runs in native slot order, including slots40..59")
	check(xp_events.all(func(e):return e.payload.amount==9),"raw4/count5 still awards9, not8")
	var camp=SettlementProbe.new();root.add_child(camp);camp.battle=b
	camp.pending_battle_result={"result":"victory","message":"fixture"};b.action_resolution_depth=1
	camp._process(0)
	check(not camp.settled and not camp.pending_battle_result.is_empty(),"Campaign cannot settle during originating action transaction")
	b.action_resolution_depth=0;camp._process(0)
	check(camp.settled and camp.pending_battle_result.is_empty(),"Campaign settles once transaction inventory/XP writes complete")
	camp.battle=null;camp.queue_free();await process_frame
	# Independent L02 entry must not execute following actions or T750 early.
	b.free();b=load("res://scripts/Battle.gd").new();root.add_child(b);b.presentation_in_headless=true;b.sfx_enabled=false;b.animation_speed=0
	var gs=load("res://scripts/m2/GameState.gd").new();gs.new_game(m2);gs.setup_m4(m4)
	var level:Dictionary=Builder.build(m4,m2,2,[gs.protagonist_member()])
	level.start_actions=[{"if":{"when":{"all":[]},"then":[{"random_choice":{"options":[level.start_actions+[{"flag_set":{"addr":"0x583f48","value":73}}]]}}]}}]
	started=Time.get_ticks_msec()
	b.setup(m4,level,load("res://assets/font/hzk16.fnt"),gs.battle_context());b.set_process(false)
	check(b.scenario.start_phase_pending and b.busy and b.scenario._last_turn_hook==-1,"standalone L02 blocks first turn while demo mine plays")
	check(b.unit_by_slot(42)!=null and b.scenario._global_value("0x583f48")!=73,"recursive script tail cannot run before demo damage")
	while b.scenario.start_phase_pending and Time.get_ticks_msec()-started<8000:await process_frame
	check(not b.scenario.start_phase_pending and not b.busy and b.unit_by_slot(42)==null,"standalone L02 waits actual damage/death and unlocks once")
	check(b.scenario._global_value("0x583f48")==73 and b.scenario._last_turn_hook==1 and b.stats.kills_by_mine==1,"recursive tail then first turn; tutorial mine resolves once")
	b.queue_free();await process_frame;await create_timer(0.5).timeout
	root.get_node("Music").release_playback()
	print("ORIGINAL_ACTION_ORDER checks=",checks," failures=",failures)
	quit(1 if failures else 0)
