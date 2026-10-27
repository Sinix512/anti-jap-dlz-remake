extends SceneTree
# Synthetic action-continuity fixtures, NOT campaign progression evidence.
class Observer extends RefCounted:
	var status_text:=""
	var start_phase_pending:=false
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
var completed:=false
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("MINE_CONTINUITY_FAIL "+label)
func fixture() -> void:
	if b!=null:b.free()
	var lv:Dictionary=m4.levels[7].duplicate(true)
	lv.start_actions=[];lv.triggers.rules=[]
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4.duplicate(true),lv,load("res://assets/font/hzk16.fnt"),{})
	b.set_process(false);b.scenario=Observer.new();b.busy=false;b.sfx_enabled=false
	b.fast_sim=false;b.presentation_in_headless=true;b.animation_speed=0;b.ai_delay=0
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.mines.clear();b.chests.clear()
	for i in range(b.terrain.size()):b.terrain[i]=0
func unit(slot:int,tile:Vector2i,hp:=121):
	var d:Dictionary=m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"name":"赵　虎" if slot==2 else "fixture%d"%slot,
		"side":"enemy" if slot==40 else "player","faction":1 if slot==40 else 0,
		"x":tile.x,"y":tile.y,"hp":hp,"max_hp":hp,"morale":100,"level":3,
		"xp":0,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0],
		"control":slot!=40,"bingzhong":6,"behavior":13},true)
	return b._spawn_unit(d)
func mine(tile:Vector2i,code:=0) -> void:
	b.mines.append({"tile":tile,"mine":b.data.mines[code%10],"mine_id":code%10,"code":code,"low":1,"owner_side":"player"})
func unlocked(label:String) -> void:
	print("UNLOCK ",label," ",str({"busy":b.busy,"finished":b.finished_flag,"movement":b._movement_active,"depth":b.action_resolution_depth,"fx":b.progress_fx_active,"phase":b.phase}))
	check(not b.busy and not b._movement_active and b.action_resolution_depth==0 and not b.progress_fx_active,label+" releases action locks")
func click_unit(u) -> void:
	# Real viewport dispatch, not _select_unit (which bypasses click routing).
	var logical:Vector2=b.get_global_transform_with_canvas()*u.position
	var physical:Vector2=root.get_final_transform()*logical
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=physical
		Input.parse_input_event(event)
		await process_frame
func watchdog() -> void:
	await create_timer(35).timeout
	if completed:return
	push_error("MINE_CONTINUITY_TIMEOUT "+str({"phase":b.phase,"busy":b.busy,"depth":b.action_resolution_depth,"movement":b._movement_active,"log":b.log_history}))
	quit(2)
func run() -> void:
	watchdog()
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	fixture();var mover=unit(0,Vector2i(5,5),300);unit(2,Vector2i(5,7));unit(40,Vector2i(20,20),300)
	b._select_unit(mover)
	await b._player_move(Vector2i(6,5))
	check(not mover.acted and mover.moved and b.selected==mover and b.native_range_phase=="menu" and is_instance_valid(b.context_menu),"ordinary movement still opens reversible action menu")
	b._cancel()
	check(mover.x==5 and mover.y==5 and not mover.moved and b.selected==null,"ordinary move cancellation still restores original tile")
	for hp in [121,120]:
		fixture();unit(0,Vector2i(5,7),300);unit(40,Vector2i(20,20),300)
		var actor=unit(2,Vector2i(5,5),hp)
		mine(Vector2i(6,5));b._select_unit(actor)
		await b._player_move(Vector2i(7,5))
		check(actor.x==6 and actor.y==5 and actor.hp==maxi(0,hp-120) and actor.acted and actor.moved,"manual mine stops movement/spends action HP%d"%hp)
		check(actor.alive==(hp>120) and b.mines.is_empty(),"manual mine survival/death HP%d"%hp)
		unlocked("manual HP%d"%hp)
		check(b.selected==null and b.native_range_phase=="idle" and b._selection_origin.is_empty(),"manual HP%d clears completed selection/menu mode"%hp)
		# Reproduce the player's actual next click, including native menu routing.
		await click_unit(b.unit_by_slot(0))
		check(b.selected==b.unit_by_slot(0) and b.mode=="move","manual HP%d viewport click selects next unit"%hp)
	fixture();unit(0,Vector2i(1,1),300);unit(40,Vector2i(20,20),300)
	var actor=unit(2,Vector2i(5,5))
	actor.behavior=8;actor.target_x=8;actor.target_y=5;mine(Vector2i(6,5))
	b.phase="ally"
	await b._ai_act(actor,"enemy")
	check(actor.x==6 and actor.hp==1 and actor.acted and actor.moved,"automatic ally mine interrupts path alive")
	unlocked("automatic ally")
	fixture();var hero=unit(0,Vector2i(1,1),300);hero.acted=true
	unit(40,Vector2i(20,20),300)
	actor=unit(2,Vector2i(5,5),120);actor.behavior=8;actor.target_x=8;actor.target_y=5
	mine(Vector2i(6,5))
	await b._on_end_turn(true)
	check(not actor.alive and b.turn==2 and b.phase=="player","automatic mine death finishes entire round")
	unlocked("round after automatic death")
	fixture();unit(0,Vector2i(1,1),300);unit(40,Vector2i(20,20),300)
	actor=unit(2,Vector2i(5,5),300);mine(Vector2i(6,5),1);mine(Vector2i(7,5),1)
	b.selected=actor;b.compute_reachable(actor)
	await b._player_move(Vector2i(8,5))
	check(b.mines.is_empty() and actor.acted and actor.x==6,"manual mixed blast chain completes once")
	unlocked("chain")
	b.queue_free();await process_frame
	root.get_node("Music").release_playback();completed=true
	print("MINE_ACTION_CONTINUITY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
