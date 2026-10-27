extends SceneTree
# Byte-verified 41E97A/41EB2D/4048D5 contract; isolated fixtures, not campaign play.
class CaptureBattle extends "res://scripts/Battle.gd":
	var dumps:=0
	func _dump_playtest_state() -> void:dumps+=1
class Observer extends RefCounted:
	var status_text:=""
	var start_phase_pending:=false
	var _trigger_active:=false
	var _round_active:=false
	var _apply_depth:=0
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func on_turn_start(_turn) -> void:pass
	func ai_prepare(_u) -> bool:return false
	func check_end() -> bool:return false
var b
var m4:Dictionary
var checks:=0
var failures:=0
var events:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("AUTO_CAMERA_FAIL "+label)
func fixture() -> void:
	if b!=null:b.free()
	var lv:Dictionary=m4.levels[7].duplicate(true);lv.start_actions=[];lv.triggers.rules=[]
	b=CaptureBattle.new();root.add_child(b)
	b.setup(m4.duplicate(true),lv,load("res://assets/font/hzk16.fnt"),{})
	b.set_process(false);b.scenario=Observer.new();b.busy=false;b.sfx_enabled=false;b.animations_enabled=false
	b.fast_sim=false;b.animation_speed=0;b.ai_delay=0
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.mines.clear();b.chests.clear()
	for i in range(b.terrain.size()):b.terrain[i]=0
	events.clear()
	b.presentation_step.connect(func(kind,payload):events.append({"kind":kind,"payload":payload.duplicate(true)}))
	origin(Vector2i.ZERO)
func origin(tile:Vector2i) -> void:
	b.camera.position=Vector2(tile*48)-b.map_rect().position+Vector2(320,240);b._clamp_camera()
func unit(slot:int,tile:Vector2i,hp:=500):
	var d:Dictionary=m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"name":"fixture%d"%slot,"side":"enemy" if slot==40 else "player","faction":1 if slot==40 else 0,
		"x":tile.x,"y":tile.y,"hp":hp,"max_hp":hp,"morale":100,"level":3,"xp":0,
		"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0],"control":slot!=40,"bingzhong":6,"behavior":13},true)
	return b._spawn_unit(d)
func focus_events(reason:String) -> Array:
	return events.filter(func(e):return e.kind=="camera_focus" and e.payload.reason==reason)
func run() -> void:
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	fixture()
	for full in [false,true]:
		b.fullscreen_map=full
		var w:int=b.map_w;var h:int=b.map_h
		var vectors:Array=[[[0,0],[0,0]],[[4,4],[0,0]],[[5,5],[1,1]],[[w-6,h-6],[w-10,h-10]],[[w-5,h-5],[w-9,h-9]],[[w-1,h-1],[w-9,h-9]]]
		if full:vectors=[[[0,0],[0,0]],[[6,4],[0,0]],[[7,5],[1,1]],[[w-8,h-7],[w-14,h-11]],[[w-7,h-6],[w-13,h-10]],[[w-1,h-1],[w-13,h-10]]]
		for row in vectors:
			b._native_camera_focus(Vector2i(row[0][0],row[0][1]),"fixture")
			check(b._camera_origin_tile()==Vector2i(row[1][0],row[1][1]),"native origin full=%s tile=%s"%[full,row[0]])
		origin(Vector2i.ZERO);events.clear()
		var size:=Vector2i(13,10) if full else Vector2i(9,9)
		b._native_camera_actor(size-Vector2i.ONE)
		check(events.is_empty(),"inside half-open actor bounds full=%s"%full)
		b._native_camera_actor(Vector2i(size.x,4))
		check(focus_events("actor").size()==1,"outside half-open actor bounds full=%s"%full)
	b.fullscreen_map=false;origin(Vector2i.ZERO);events.clear()
	b._native_camera_move_step(Vector2i(7,4));check(events.is_empty(),"movement interior does not recenter")
	b._native_camera_move_step(Vector2i(8,4));check(b._camera_origin_tile()==Vector2i(4,0) and focus_events("move_edge").size()==1,"movement current edge recenters before next tile")
	fixture();var hero=unit(0,Vector2i(1,1));var actor=unit(40,Vector2i(20,20))
	b.camera_follow=true;b.camera_follow_target=hero;b.phase="enemy"
	await b._ai_act(actor,"player")
	check(events.filter(func(e):return e.kind=="camera_focus").is_empty() and b._camera_origin_tile()==Vector2i.ZERO,"pure wait never steals camera")
	actor.acted=false;actor.behavior=8;actor.target_x=28;actor.target_y=20;actor.move=8
	b.animations_enabled=true;b.animation_speed=1;b.set_process(true)
	await b._ai_act(actor,"player")
	b.set_process(false)
	check(actor.x==28 and actor.y==20 and b._camera_origin_tile()==Vector2i(20,16),"real movement follows by edge not stale selected hero")
	check(focus_events("move_start").size()==1 and focus_events("move_edge").size()==1,"real movement has one start and one edge pan")
	check(not b.camera_follow and b.camera_follow_target==null,"automatic camera is not overwritten by manual follow")
	fixture();hero=unit(0,Vector2i(20,18));actor=unit(40,Vector2i(20,20));actor.behavior=1;b.phase="enemy"
	await b._ai_act(actor,"player")
	check(focus_events("attack_target").size()==1 and b._camera_origin_tile()==Vector2i(16,14),"AI attack focuses target")
	fixture();hero=unit(0,Vector2i(1,1));actor=unit(40,Vector2i(20,20));actor.hp=1;actor.behavior=1;actor.skill_counts.buji=1;b.phase="enemy"
	await b._ai_act(actor,"player")
	check(focus_events("skill_target").size()==1 and b._camera_origin_tile()==Vector2i(16,16),"AI skill focuses target")
	fixture();hero=unit(0,Vector2i(1,1));hero.acted=true;actor=unit(40,Vector2i(20,20));actor.behavior=8;actor.target_x=24;actor.target_y=20
	origin(Vector2i(2,3));var previous:Vector2=b.camera.position
	await b._on_end_turn()
	check(b.turn==2 and b.phase=="player" and b.camera.position==previous,"whole round restores previous origin after maintenance")
	check(events[-1].kind=="camera_restore","restoration is after all action/round presentation")
	b._process(0.0);check(b.camera.position==previous,"restored camera remains stable next frame")
	fixture();hero=unit(0,Vector2i(1,1));actor=unit(2,Vector2i(20,20))
	for t in [Vector2i(20,20),Vector2i(21,20)]:b.mines.append({"tile":t,"mine":b.data.mines[1],"mine_id":1,"code":1,"low":1})
	await b._detonate_mines(Vector2i(20,20))
	check(focus_events("mine").map(func(e):return e.payload.tile)==[Vector2i(20,20),Vector2i(21,20)],"each queued chain mine gets its own focus")
	events.clear();origin(Vector2i.ZERO)
	await b.scripted_mine(Vector2i(20,20),0,2)
	check(focus_events("mine").is_empty() and focus_events("scripted_mine").size()==1 and b._camera_origin_tile()==Vector2i(16,16),"scripted demonstration focuses once before its direct explosion")
	b.playtest_mode=true;b.progress_fx_active=true
	var key:=InputEventKey.new();key.keycode=KEY_F8;key.pressed=true
	b._unhandled_input(key)
	check(b.dumps==1,"F8 diagnostics work during progress input lock")
	var runtime:Dictionary=b._playtest_runtime()
	check(runtime.progress_fx and runtime.action_depth==0 and runtime.automatic_slot==-1 and runtime.has("last_stage"),"snapshot includes live locks and last resolution boundary")
	b.playtest_mode=false;b.progress_fx_active=false
	b.queue_free();await process_frame;root.get_node("Music").release_playback()
	print("AUTOMATIC_CAMERA checks=",checks," failures=",failures)
	quit(1 if failures else 0)
