extends SceneTree

const State = preload("res://scripts/m2/GameState.gd")
const Builder = preload("res://scripts/m4/LevelBuilder.gd")
const Rules = preload("res://scripts/battle/CombatRules.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FIDELITY_FAIL " + label)
func read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var m2 := read_json("res://data/m2.json")
	var m4 := read_json("res://data/m4.json")
	var state = State.new()
	state.new_game(m2)
	state.setup_m4(m4)
	check(state.money == 500 and state.party.is_empty(), "original new game")
	check(state.protagonist["level"] == 1 and state.protagonist["xp"] == 0, "hero growth base")
	check(state.protagonist["item_slots"] == [2,3,100,0,0,0,0,0], "hero raw inventory")
	check(Rules.hit_experience(10,10) == 8 and Rules.kill_experience(10,10) == 12, "xp thresholds")
	state.add_item(81, 1)
	check(state.give_item(state.protagonist,81).ok and state.item_count(81) == 0, "unique item ownership")
	check(not state.give_item(state.person(1),81).ok, "no duplicate equipment")
	var font: Font = load("res://assets/font/hzk16.fnt")
	for idx in range(47):
		# Structural coverage, not a claim that a bot has legitimately won each battle.
		var people: Array = []
		for slot in range(40):
			people.append(state.person(slot))
		var lv := Builder.build(m4,m2,idx,people)
		state.apply_difficulty(lv)
		var battle = load("res://scripts/Battle.gd").new()
		root.add_child(battle)
		battle.fast_sim = true
		battle.setup(m4,lv,font,state.battle_context())
		check(battle.scenario.trigger_authoritative, "authoritative triggers L%02d" % idx)
		var slots := {}
		for u in battle.units:
			check(not slots.has(u.slot), "unique active slot L%02d/%d" % [idx,u.slot])
			slots[u.slot] = true
			check(u.x >= 0 and u.x < battle.map_w and u.y >= 0 and u.y < battle.map_h, "unit bounds L%02d/%d" % [idx,u.slot])
			check(u.max_hp > 0 and u.hp <= u.max_hp, "HP L%02d/%d" % [idx,u.slot])
		if idx == 0:
			var hero = battle.unit_by_slot(0)
			check(hero != null, "hero slot0")
			if hero != null:
				await battle._gain_xp(hero,108)
				check(hero.data.level == 2 and hero.data.xp == 8, "instant xp levelup")
				state.apply_battle_progress([hero])
				check(state.protagonist.level == 2 and state.protagonist.xp == 8, "persist battle growth")
		if idx == 2:
			var target = battle.unit_by_slot(42)
			check(target == null or not target.alive, "tutorial mine kills default slot42")
			check(int(battle.stats.kills_by_mine) == 1, "tutorial real mine stat")
			for slot in [2,3]:
				var carrier = battle.unit_by_slot(slot)
				check(carrier != null and int(carrier.mine_slots[0]) == 1, "tutorial mine retained")
		battle.queue_free()
		await process_frame
	print("ORIGINAL_FIDELITY failures=", failures)
	quit(1 if failures else 0)
