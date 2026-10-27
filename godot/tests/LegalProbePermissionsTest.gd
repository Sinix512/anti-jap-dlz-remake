extends SceneTree
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const Forecast=preload("res://tests/helpers/TacticalForecast.gd")
const Planner=preload("res://tests/helpers/TacticalPlanner.gd")
const Ambush=preload("res://tests/helpers/AmbushPlanner.gd")
class Observer extends RefCounted:
	var status_text:=""
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
	func ai_prepare(_u) -> bool:return false
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("PERMISSION_FAIL "+label)
func run() -> void:
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var state=State.new();state.new_game(m2);state.setup_m4(m4)
	var b=load("res://tests/helpers/LegalProbeBattle.gd").new();root.add_child(b)
	b.setup(m4,Builder.build(m4,m2,0,[state.protagonist_member()]),load("res://assets/font/hzk16.fnt"),state.battle_context())
	b.fast_sim=true;b.set_process(false);b.animations_enabled=false;b.sfx_enabled=false;b.scenario=Observer.new();b.report_violations=false
	var hero=b.unit_by_slot(0);var enemy=b.unit_by_slot(40)
	for u in b.units:
		if u!=hero and u!=enemy:u.alive=false
	b.terrain.fill(0)
	hero.set_tile(5,5);enemy.set_tile(5,4)
	hero.hp=1000;hero.max_hp=1000;hero.acted=false;hero.moved=false
	enemy.hp=1000;enemy.max_hp=1000;enemy.skill_counts={};enemy.behavior=7;enemy.move=0;enemy.acted=false
	var before:Array=[]
	for u in b.units:before.append(u.state_record())
	var random_before:int=b.rng_state
	var mask_before:PackedByteArray=b.native_dark_mask.duplicate()
	var prediction:Dictionary=Forecast.evaluate(b,hero.slot,{"kind":"wait","station":Vector2i(hero.x,hero.y)})
	var after:Array=[]
	for u in b.units:after.append(u.state_record())
	check(before==after,"forecast never mutates live units or learned counters")
	check(b.rng_state==random_before and b.native_dark_mask==mask_before,"forecast does not inspect/advance future RNG or visible mask")
	var phase_plan:Array=Planner.plan(b,[hero.slot])
	var planned_state:Array=[]
	for u in b.units:planned_state.append(u.state_record())
	check(planned_state==before and b.rng_state==random_before and b.native_dark_mask==mask_before,"whole-phase planner does not mutate live board, practice, RNG or range")
	var station_valid:bool=phase_plan.size()==1 and int(phase_plan[0].slot)==hero.slot
	if station_valid:
		var point:Vector2i=phase_plan[0].action.station
		station_valid=point==Vector2i(hero.x,hero.y) or b.compute_reachable(hero).has(point)
	check(station_valid,"whole-phase plan has one actor and a legal single-move endpoint")
	var shadow=Forecast.copy_board(b)
	var clone=shadow.unit_by_slot(hero.slot)
	var forbidden:=Vector2i(hero.x+1,hero.y)
	shadow.mines.append({"tile":forbidden,"kind":0,"fuse":0,"active":true})
	var candidate_set:Array=Planner.candidates(shadow,clone)
	check(candidate_set.all(func(a):return a.station!=forbidden),"phase candidates do not move onto a visible mine")
	check(shadow.turn==b.turn and b.mines.is_empty(),"planning board preserves turn and independently owns mine records")
	shadow.free()
	b.phase="enemy";await b._ai_act(enemy,"player")
	check(prediction.units[hero.slot].hp==hero.hp and prediction.units[hero.slot].morale==hero.morale,"single enemy attack forecast matches unchanged actual resolver")
	b.phase="player";hero.acted=false;hero.moved=false
	await b._perform_attack(hero,enemy)
	check(b.legal_action_log.size()==1 and hero.acted,"one legal attack commits")
	var hp_before:int=enemy.hp
	await b._perform_attack(hero,enemy)
	check(enemy.hp==hp_before and b.legal_action_log.size()==1 and b.legal_errors.size()==1,"second action refused before damage")
	hero.acted=false;hero.moved=false
	var start:=Vector2i(hero.x,hero.y)
	var reachable:Dictionary=b.compute_reachable(hero)
	var goal:Vector2i=reachable.keys()[0]
	await b._bot_move_to(hero,goal)
	check(Vector2i(hero.x,hero.y)!=start and hero.moved and b.legal_move_log.size()==1,"one legal move commits")
	var moved_to:=Vector2i(hero.x,hero.y)
	await b._bot_move_to(hero,start)
	check(Vector2i(hero.x,hero.y)==moved_to and b.legal_move_log.size()==1 and b.legal_errors.size()==2,"second movement refused")
	hero.acted=false;b.selected=hero;b.active_skill_id=15;b.active_skill=b.data.skills[15];hero.skill_counts.kongxi=0
	await b._execute_skill_at(Vector2i(enemy.x,enemy.y))
	check(b.legal_errors.size()==3 and not hero.acted,"unlearned skill refused")
	hero.item_slots.fill(0);b.selected=hero;b.active_item_id=41
	await b._execute_item_at(Vector2i(enemy.x,enemy.y))
	check(b.legal_errors.size()==4 and not hero.acted,"uncarried item refused")
	# Artificial unit fixture only: duty renews a teammate's already-used turn.
	enemy.side="player";enemy.data.faction=0;enemy.control=true;enemy.acted=true;enemy.moved=true;enemy.data.zhili=0
	enemy.set_tile(hero.x,hero.y-1);b.player_units.append(enemy)
	hero.skill_counts.duzhan=1;hero.data.zhili=100
	b._probe_actions.clear();b.selected=hero;b.active_skill_id=12;b.active_skill=b.data.skills[12]
	await b._execute_skill_at(Vector2i(enemy.x,enemy.y))
	check(not enemy.acted and not enemy.moved and int(b._probe_epochs.get(enemy.slot,0))==1,"earned duty renewal opens a new permission epoch")
	check(b.legal_errors.size()==4,"legal duty does not add a spurious permission failure")
	hero.acted=false;hero.moved=false;hero.mine_slots.fill(0);b.selected=hero;b.mine_kind=0
	var mine_tile:Vector2i=b._mine_place_tiles(hero,0).keys()[0]
	await b._place_mine(mine_tile)
	check(b.mines.is_empty() and b.legal_errors.size()==5,"uncarried mine cannot be committed")
	b.turn+=1;hero.mine_slots[0]=1;b.selected=hero
	await b._place_mine(mine_tile)
	check(b.mines.size()==1 and hero.acted and not hero.mine_slots.has(1) and b.legal_action_log.back().kind=="mine:0","legal mine consumes carried stock and records action")
	var second:Vector2i=b._mine_place_tiles(hero,0).keys()[0]
	hero.mine_slots[0]=1;b.selected=hero
	await b._place_mine(second)
	check(b.mines.size()==1 and hero.mine_slots.has(1) and b.legal_errors.size()==6,"second mine action is refused without consuming stock")
	hero.acted=false;b.busy=true
	var hp_busy:int=enemy.hp
	await b._perform_attack_at(hero,Vector2i(enemy.x,enemy.y))
	check(enemy.hp==hp_busy and b.legal_errors.size()==7 and not hero.acted,"busy presentation rejects a player action")
	b.busy=false
	b.queue_free();await process_frame;await process_frame
	check(Ambush.no_new_casualties({0:{"alive":true},1:{"alive":false},2:{"alive":true}},{0:{"alive":true},1:{"alive":false},2:{"alive":true}}),"unrelated baseline casualty does not veto a mine improvement")
	check(not Ambush.no_new_casualties({0:{"alive":true},1:{"alive":true}},{0:{"alive":true},1:{"alive":false}}),"mine planner refuses a newly predicted teammate casualty")
	check(not Ambush.no_new_casualties({0:{"alive":false}},{0:{"alive":false}}),"mine planner refuses commander death even when baseline is doomed")
	check(Ambush.no_new_casualties({0:{"alive":true},1:{"alive":false}},{0:{"alive":true},1:{"alive":true}}),"mine planner permits saving a baseline casualty")
	await mine_checks(m4,m2,state)
	await inventory_checks(m4,m2,state)
	await protected_forecast_checks(m4,m2,state)
	print("LEGAL_PROBE_PERMISSIONS checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func mine_checks(m4:Dictionary,m2:Dictionary,state) -> void:
	# Large HP is an isolated mechanics fixture, never campaign provenance.
	var world=load("res://scripts/Battle.gd").new();root.add_child(world)
	world.setup(m4,Builder.build(m4,m2,0,[state.protagonist_member()]),load("res://assets/font/hzk16.fnt"),{})
	world.fast_sim=true;world.sfx_enabled=false;world.set_process(false);world.scenario=Observer.new()
	var hero=world.unit_by_slot(0);var enemy=world.unit_by_slot(40)
	for unit in world.units:
		if unit!=hero and unit!=enemy:unit.alive=false
	world.terrain.fill(0);hero.set_tile(5,5);enemy.set_tile(5,4)
	hero.hp=1000;hero.max_hp=1000;enemy.hp=1000;enemy.max_hp=1000;enemy.move=4
	world.mines=[{"tile":Vector2i(5,3),"mine":world.data.mines[0],"mine_id":0,"code":0,"low":1}]
	var board=Forecast.copy_board(world);var clone=board.unit_by_slot(enemy.slot)
	Forecast.apply_action(board,clone,{"kind":"attack","station":Vector2i(5,2),"tile":Vector2i(hero.x,hero.y)},true)
	check(Vector2i(clone.x,clone.y)==Vector2i(5,3) and clone.hp==880 and clone.acted and board.mines.is_empty() and board.unit_by_slot(0).hp==1000,"shadow mine interrupts intermediate step and cancels planned attack")
	world.phase="enemy";await world._bot_move_to(enemy,Vector2i(5,2))
	check(Vector2i(enemy.x,enemy.y)==Vector2i(clone.x,clone.y) and enemy.hp==clone.hp and enemy.acted and world.mines.is_empty(),"intermediate mine forecast matches actual unchanged movement resolver")
	board.free()
	enemy.set_tile(5,4);enemy.hp=1000;enemy.acted=false;enemy.moved=false;hero.set_tile(5,2);hero.hp=1000
	world.mines=[{"tile":Vector2i(5,3),"mine":world.data.mines[1],"mine_id":1,"code":1,"low":1},{"tile":Vector2i(5,2),"mine":world.data.mines[0],"mine_id":0,"code":0,"low":1}]
	board=Forecast.copy_board(world);clone=board.unit_by_slot(enemy.slot)
	Forecast.apply_action(board,clone,{"kind":"move","station":Vector2i(5,3)},true)
	await world._bot_move_to(enemy,Vector2i(5,3))
	check(board.mine_events.size()==2 and board.mines.is_empty() and world.mines.is_empty() and clone.hp==enemy.hp and board.unit_by_slot(0).hp==hero.hp and Vector2i(clone.x,clone.y)==Vector2i(enemy.x,enemy.y),"mine chain/percentages/friendly fire and stop agree with actual resolver")
	board.free()
	hero.set_tile(5,5);hero.acted=false;hero.moved=false;hero.mine_slots=[1,0,0,0,0,0,0,0]
	enemy.set_tile(5,0);enemy.hp=1000;enemy.move=8;enemy.acted=false;enemy.moved=false;enemy.select=1;enemy.skill_counts={};enemy.behavior=7
	world.phase="player"
	board=Forecast.copy_board(world)
	Forecast.apply_action(board,board.unit_by_slot(0),{"kind":"mine","mine":0,"station":Vector2i(5,5),"tile":Vector2i(5,4)})
	check(board.mines.size()==1 and board.unit_by_slot(0).mine_slots[0]==0 and world.mines.is_empty() and hero.mine_slots[0]==1,"mine placement consumes clone-only stock and preserves actual mine inventory")
	board.free()
	var before:Array=[]
	for unit in world.units:before.append(unit.state_record())
	var rng:int=world.rng_state;var mask:PackedByteArray=world.native_dark_mask.duplicate()
	var intention:Dictionary=Ambush.plan(world,hero)
	var after:Array=[]
	for unit in world.units:after.append(unit.state_record())
	check(not intention.is_empty() and intention.mine==0 and not intention.prediction.mine_events.is_empty() and before==after and world.rng_state==rng and world.native_dark_mask==mask and world.mines.is_empty(),"ambush plans a natural visible enemy path without mutating source or future RNG")
	# An unmoving gun line cannot be ambushed from the baseline path alone.
	# The optional player-only search may move its planter to invite pursuit.
	hero.set_tile(12,5);hero.hp=1000;hero.max_hp=1000;hero.move=8;hero.acted=false;hero.moved=false;hero.mine_slots=[1,0,0,0,0,0,0,0]
	enemy.set_tile(3,5);enemy.hp=100;enemy.max_hp=100;enemy.move=8;enemy.acted=false;enemy.moved=false;enemy.behavior=7
	world.mines.clear()
	var idle:Dictionary=Forecast.evaluate(world,0,{"kind":"wait","station":Vector2i(12,5)})
	check(idle.plans.all(func(p):return p.path.is_empty()),"distant visible guard has no pursuit path when planter stays put")
	before=[]
	for unit in world.units:before.append(unit.state_record())
	var lure:Dictionary=Ambush.plan(world,hero,true)
	after=[]
	for unit in world.units:after.append(unit.state_record())
	check(not lure.is_empty() and lure.station!=Vector2i(12,5) and before==after and world.rng_state==rng and world.native_dark_mask==mask and world.mines.is_empty(),"active lure derives a legal mine from relocation without mutating source, RNG or mask")
	if not lure.is_empty():
		await world._bot_move_to(hero,lure.station)
		world.selected=hero;world.mine_kind=int(lure.mine)
		await world._place_mine(lure.tile)
		world.phase="enemy";await world._ai_act(enemy,"player")
		check(not enemy.alive and hero.alive and world.mines.is_empty() and not hero.mine_slots.has(1),"unmodified enemy AI naturally triggers carried lure mine after one player move and action")
	else:check(false,"unmodified enemy AI naturally triggers carried lure mine after one player move and action")
	world.queue_free();await process_frame;await process_frame

func inventory_checks(m4:Dictionary,m2:Dictionary,state) -> void:
	var world=load("res://tests/helpers/LegalProbeBattle.gd").new();root.add_child(world)
	world.setup(m4,Builder.build(m4,m2,0,[state.protagonist_member()]),load("res://assets/font/hzk16.fnt"),{})
	world.fast_sim=true;world.sfx_enabled=false;world.set_process(false);world.scenario=Observer.new();world.report_violations=false
	var hero=world.unit_by_slot(0);var enemy=world.unit_by_slot(40)
	hero.set_tile(5,5);enemy.set_tile(5,4);hero.item_slots=[2,7,2,0,0,0,0,0];world.selected=hero
	await world._discard_item(1);await world._discard_item(1)
	check(hero.acted and hero.item_slots==[7,2,0,0,0,0,0,0] and world.legal_action_log.size()==1 and world.legal_errors.size()==1,"discard is audited once and second discard is refused")
	world.turn+=1;hero.acted=false;world.selected=hero;hero.item_slots=[2,7,2,0,0,0,0,0];enemy.item_slots=[1,1,1,1,1,1,1,1]
	world._item_option(1,1)
	await world._execute_item_transfer(Vector2i(5,4));world.selected=hero;world.active_item_id=1
	await world._execute_item_transfer(Vector2i(5,4))
	check(hero.acted and hero.item_slots==[7,2,0,0,0,0,0,0] and world.legal_action_log.size()==2 and world.legal_errors.size()==2,"full-target item give is audited once, repeated turn action refused")
	world.turn+=1;hero.acted=false;hero.bingzhong=4;hero.data.bingzhong=4;world.selected=hero;hero.item_slots=[62,0,0,0,0,0,0,0]
	await world._use_manual_item(61);world.selected=hero;await world._use_manual_item(61)
	check(hero.acted and hero.item_slots[0]==62 and world.legal_action_log.size()==3 and world.legal_errors.size()==3,"even unsuccessful manual use is one audited action and cannot repeat")
	world.turn+=1;hero.acted=false;world.selected=hero;hero.item_slots=[82,0,0,0,0,0,0,0];world.active_item_id=81
	await world._execute_item_at(Vector2i(5,5))
	check(not hero.acted and hero.item_slots[0]==82 and world.legal_action_log.size()==3 and world.legal_errors.size()==4,"probe cannot bypass native equipment-use restriction via target resolver")
	world.selected=hero;await world._on_wait()
	check(hero.acted and world.legal_action_log.size()==4 and world.legal_action_log.back().kind=="wait" and world.legal_errors.size()==4,"explicit wait commits the native action tail and is permission audited")
	world.selected=hero;await world._on_wait()
	check(world.legal_action_log.size()==4 and world.legal_errors.size()==5,"second explicit wait is refused without a second tail")
	world.queue_free();await process_frame;await process_frame

func protected_forecast_checks(m4:Dictionary,m2:Dictionary,state) -> void:
	var world=load("res://tests/helpers/LegalProbeBattle.gd").new();root.add_child(world)
	world.setup(m4,Builder.build(m4,m2,0,[state.protagonist_member()]),load("res://assets/font/hzk16.fnt"),state.battle_context())
	world.set_process(false);world.fast_sim=true;world.animations_enabled=false;world.scenario=Observer.new()
	var hero=world.unit_by_slot(0);var enemy=world.unit_by_slot(40)
	for u in world.units:
		if u!=hero and u!=enemy:u.alive=false
	world.terrain.fill(0);hero.set_tile(5,5);enemy.set_tile(5,4)
	hero.slot=9;hero.unit_name="李　霜泗";hero.key="unrelated_key";hero.hp=1;hero.max_hp=200;hero.skill_counts={};hero.protected=false
	enemy.hp=999;enemy.max_hp=999;enemy.skill_counts={};enemy.behavior=7;enemy.move=0;enemy.select=1
	world.level.protect=[]
	var ordinary:Dictionary=Forecast.evaluate(world,hero.slot,{"kind":"wait","station":Vector2i(5,5)})
	world.level.protect=["李霜泗"]
	var guarded:Dictionary=Forecast.evaluate(world,hero.slot,{"kind":"wait","station":Vector2i(5,5)})
	check(not ordinary.units[9].alive and not guarded.units[9].alive and guarded.cost>ordinary.cost+90000,"forecast recognizes normalized protected name even when live key differs")
	world.level.protect=[];hero.protected=true
	var flagged:Dictionary=Forecast.evaluate(world,hero.slot,{"kind":"wait","station":Vector2i(5,5)})
	check(flagged.cost==guarded.cost and hero.hp==1 and enemy.hp==999,"forecast protected flag equivalence without changing live HP")
	world.queue_free();await process_frame;await process_frame
