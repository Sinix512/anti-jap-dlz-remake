extends SceneTree
const Candidates=preload("res://tests/helpers/ForecastCandidateSet.gd")
const Legacy=preload("res://tests/helpers/LegacyForecastCandidates251.gd")
const Public=preload("res://tests/helpers/PublicRoundForecast.gd")
const Codec=preload("res://scripts/battle/StateCodec.gd")
const Unit=preload("res://scripts/BattleUnit.gd")
var checks:=0
var failures:=0
var data:Dictionary
var boards:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("CANDIDATE_SET_FAIL "+label)
func unit(b,slot:int,faction:int,tile:Vector2i):
	var u=Unit.new();u.slot=slot;u.pid=slot;u.x=tile.x;u.y=tile.y
	u.side="player" if faction==0 else "enemy";u.data={"faction":faction,"level":4,"xp":0,"wuli":70,"zhili":30}
	u.hp=70;u.max_hp=100;u.morale=70;u.bingzhong=1;u.select=1;u.move=4;u.control=true;u.behavior=11
	u.item_slots=[2,42,33,0,0,0,0,0];u.mine_slots=[0,0,0,0,0,0,0,0]
	for key in b.SKILL_KEYS:u.skill_counts[key]=1
	b.add_child(u);b.units.append(u)
	if faction==0:b.player_units.append(u)
	else:b.enemy_units.append(u)
	return u
func fixture(index:int):
	var b=load("res://scripts/Battle.gd").new();boards.append(b)
	b.data=data.duplicate(true);b.map_w=40;b.map_h=40;b.terrain.resize(1600);b.terrain.fill(0)
	b.level={"index":index,"difficulty_setting":1};b.turn=1;b.rng_state=789123
	var offset:=Vector2i(24,24) if index==7 else Vector2i.ZERO
	unit(b,0,0,offset+Vector2i(5,5));unit(b,7,0,offset+Vector2i(5,4));unit(b,40,1,offset+Vector2i(6,5));unit(b,48,1,offset+Vector2i(7,6))
	return b
func state(b) -> Array:
	return b.units.map(func(u):return u.state_record())
func run() -> void:
	data=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	var current=Candidates.new();var frozen=Legacy.new()
	for index in [0,4,5,6,7,8]:
		for variant in ["normal","moved","no_enemies","visible_mine","full_hp"]:
			var b=fixture(index);var u=b.unit_by_slot(0)
			match variant:
				"moved":u.moved=true
				"no_enemies":
					for e in b.enemy_units:e.alive=false
				"visible_mine":b.mines=[{"tile":Vector2i(u.x-1,u.y),"code":0,"low":1,"owner_side":"player","mine":b.data.mines[0]}]
				"full_hp":
					for ally in b.player_units:ally.hp=ally.max_hp;ally.morale=100
			var before:=state(b)
			var reference:Dictionary=frozen.generate(b,u)
			var generated:Dictionary=current.generate(b,u)
			check(reference==generated,"live choices/order/utility unchanged L%d %s"%[index,variant])
			check(before==state(b) and b.rng_state==789123,"live units and RNG unchanged L%d %s"%[index,variant])
			var shadow=Public.clone_public_board(b);boards.append(shadow)
			var shadow_before:=Public.snapshot(shadow)
			var public_choices:Dictionary=current.generate(shadow,shadow.unit_by_slot(0))
			check(public_choices==reference,"cached public occupancy reproduces linear live candidate collection L%d %s"%[index,variant])
			check(Public.snapshot(shadow)==shadow_before,"public collection restores unit/occupancy logical state L%d %s"%[index,variant])
			if variant=="visible_mine":check(public_choices.candidates.all(func(a):return a.station!=shadow.mines[0].tile),"same visible mine endpoint exclusion")
	# Frozen reference deliberately lacks shadow-cache refresh. Confirm this
	# fixture really exposes that stale-caster-occupancy bug, not vacuous parity.
	var b=fixture(8);var shadow=Public.clone_public_board(b);boards.append(shadow)
	var wrong:Dictionary=frozen.generate(shadow,shadow.unit_by_slot(0))
	var right:Dictionary=current.generate(shadow,shadow.unit_by_slot(0))
	check(wrong!=right,"differential fixture detects stale public caster occupancy")
	for board in boards:board.free()
	boards.clear();await process_frame
	print("FORECAST_CANDIDATE_SET checks=",checks," failures=",failures)
	quit(1 if failures else 0)
