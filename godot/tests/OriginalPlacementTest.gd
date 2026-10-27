extends SceneTree
const Placement = preload("res://scripts/battle/OriginalPlacement.gd")
var checks := 0
var failures := 0
var b
class Observer extends RefCounted:
	var status_text:=""
	func ai_prepare(_u) -> bool:return false
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:failures += 1;push_error("PLACEMENT_FAIL "+label)
func clear_units() -> void:
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear()
func run() -> void:
	var size := Vector2i(20,24)
	var origin := Vector2i(7,7)
	var occupied := {}
	for offset in Placement.OFFSETS:
		check(Placement.find_cell(origin,size,occupied)==origin+offset,"447390 offset "+str(offset))
		occupied[origin+offset] = true
	check(Placement.find_cell(origin,size,occupied)==Vector2i(-1,-1),"only25 cells, no outer/global fallback")
	check(Placement.find_cell(Vector2i(-1,0),size,{})==Vector2i(0,0),"bounds skip in exact native order")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	b=load("res://scripts/Battle.gd").new();root.add_child(b);b.fast_sim=true
	b.setup(data,data.levels[4],load("res://assets/font/hzk16.fnt"),{})
	b.set_process(false);clear_units()
	var expected := [Vector2i(6,22),Vector2i(5,23),Vector2i(7,23),Vector2i(6,21),Vector2i(5,22),Vector2i(7,22)]
	for n in range(6):
		var u=b.spawn_slot(51+n)
		check(u!=null and Vector2i(u.x,u.y)==expected[n],"L04 T13 reinforcement slot%d"%(51+n))
	check(b.units.size()==6 and b.spawn_slot(51)==null,"active slot cannot spawn twice")
	clear_units()
	b.terrain.fill(15) # native placement has no terrain test, even here.
	var first=b.spawn_slot(51)
	check(first!=null and Vector2i(first.x,first.y)==Vector2i(6,22),"spawn does not test move_cost(3)")
	clear_units()
	origin=Vector2i(6,22)
	for offset in Placement.OFFSETS:
		var tile:Vector2i=origin+offset
		if tile.x<0 or tile.y<0 or tile.x>=20 or tile.y>=24:continue
		var rec:Dictionary=data.levels[4].units[0].duplicate(true)
		rec.merge({"slot":100+b.units.size(),"x":tile.x,"y":tile.y},true)
		b._spawn_unit(rec)
	check(b.spawn_slot(51)==null,"exhaustion reports placement failure")
	var unplaced=b.unit_by_slot(51)
	check(unplaced!=null and unplaced.alive and not unplaced.placed and not unplaced.visible,"429CC8 failed search retains stage1 without a map occupant")
	check(b._unit_at(origin)!=unplaced and not b._is_occupied(Vector2i(6,19)),"unplaced does not occupy original or global fallback cell")
	var snap:Dictionary=unplaced.state_record()
	check(snap.placed==false,"unplaced status persists in battle saves")
	# Follow-up contract: live stage participates in the AI queue while absent
	# from map target lookup. Waiting/same-position commands do not insert it.
	b.scenario=Observer.new();b.finished_flag=false;b.phase="enemy"
	unplaced.behavior=11;unplaced.acted=false
	await b._ai_act(unplaced,"player")
	check(unplaced.acted and not unplaced.placed and not unplaced.visible,"unplaced live slot can take an AI wait without entering map")
	check(b.unit_by_slot(51)==unplaced and b._alive_count(b.enemy_units)>0,"stage1 ghost stays active for slot lookup and remaining-enemy count")
	check(b.spawn_slot(51)==null,"active unplaced slot does not retry spawn")
	# Clear one actual adjacent cell, then permit an actual ordinary AI move.
	for blocker in b.units:
		if blocker!=unplaced and blocker.x==6 and blocker.y==21:blocker.alive=false
	b.terrain.fill(0);unplaced.behavior=8;unplaced.target_x=6;unplaced.target_y=21
	unplaced.skill_counts.clear();unplaced.move=4;unplaced.acted=false;unplaced.moved=false
	await b._ai_act(unplaced,"player")
	check(unplaced.placed and unplaced.visible and Vector2i(unplaced.x,unplaced.y)==Vector2i(6,21),"first nonzero AI movement inserts formerly unplaced slot")
	check(b._unit_at(Vector2i(6,21))==unplaced,"moved ghost becomes a normal map target")
	check(b._unit_at(origin)!=null and b._unit_at(origin)!=unplaced,"safe runtime does not erase unrelated old-origin occupant")
	# Ordinary mine interrupts the real AI path, but the entrant is already a
	# map occupant at the mine cell before the ordinary damage resolver scans it.
	unplaced.placed=false;unplaced.visible=false;unplaced.x=origin.x;unplaced.y=origin.y
	unplaced.position=unplaced._tile_center(unplaced.x,unplaced.y)
	unplaced.hp=500;unplaced.max_hp=500;unplaced.morale=100;unplaced.acted=false;unplaced.moved=false
	b.mines.append({"tile":Vector2i(6,21),"mine":b.data.mines[0],"mine_id":0,"code":0,"low":1,"owner_side":"player"})
	await b._ai_act(unplaced,"player")
	check(unplaced.placed and unplaced.alive and Vector2i(unplaced.x,unplaced.y)==Vector2i(6,21),"ordinary mine truncates ghost path after inserting at actual mine cell")
	check(unplaced.hp==380 and unplaced.acted and b.mines.is_empty(),"newly inserted ghost receives ordinary mine damage and spends action")
	unplaced.set_tile(6,19)
	check(unplaced.placed and unplaced.visible and b._unit_at(Vector2i(6,19))==unplaced,"subsequent placement makes slot occupy its tile")
	b.queue_free();await process_frame
	print("ORIGINAL_PLACEMENT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
