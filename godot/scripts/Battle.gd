extends Node2D
const InventorySlots=preload("res://scripts/battle/InventorySlots.gd")
const TouchBridge=preload("res://scripts/ui/TouchInput.gd")

## M1 战斗核心：地图、单位、Dijkstra 移动、普通攻击、地雷、回合与简单 AI。

signal finished(result: String, message: String)
signal toolbar_requested(action: String)
signal looted(item_id: int)
signal story_event(kind: String, data: Dictionary)
signal presentation_step(kind: String, payload: Dictionary)

var action_resolution_depth := 0
var _active_ai_slot := -1
var _resolution_trace: Dictionary = {}
var _pending_numbers: Array = []
var display_timer_elapsed := 0.0
var display_timer_count := 0

const CombatRules = preload("res://scripts/battle/CombatRules.gd")
const StateCodec = preload("res://scripts/battle/StateCodec.gd")
const RangeMask = preload("res://scripts/battle/OriginalRangeMask.gd")
const SKILL_KEYS := ["buji", "jili", "yiliao", "huogong", "gunmu", "leishi", "weishe", "saorao", "pohuai", "lueduo", "fanjian", "yibing", "duzhan", "ansha", "shidu", "kongxi"]
const TILE := 48
const SIDEBAR_SHIFT := 100.0
const TOP_SHIFT := 40.0
const NORMAL_MAP_RECT := Rect2(14,32,432,432)
const FULL_MAP_RECT := Rect2(0,0,624,480)
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const PLAYER_COLOR := Color("#4da3ff")
const ENEMY_COLOR := Color("#ff5a5a")

var data: Dictionary = {}
var level: Dictionary = {}
var font: Font

var map_w := 0
var map_h := 0
var terrain: Array = []
var units: Array = []
var player_units: Array = []
var enemy_units: Array = []

var native_dark_mask := PackedByteArray()
var native_range_phase := "idle"
var native_range_layer: Node2D
var _selection_origin: Dictionary = {}
var _context_is_action := false
var map_sprite: Sprite2D
var units_root: Node2D
var fx_root: Node2D
var overlay: Node2D
var camera: Camera2D
# Manual selection follow; automatic actions use the native tile-window rules.
var camera_follow := true
var camera_follow_target: Node2D = null

var hud_layer: CanvasLayer
var hud_root: Control
var level_label: Label
var turn_label: Label
var phase_label: Label
var objective_label: Label
var objective_guide_bg: ColorRect
var objective_guide: Label
var enemy_label: Label
var mine_label: Label
var message_label: Label
var unit_label: Label
var portrait: TextureRect
var btn_attack: Button
var btn_mine: Button
var btn_skill: Button
var btn_item: Button
var btn_wait: Button
var btn_cancel: Button
var btn_end: Button
var action_panel: Control
var context_menu: Control
var hud_frame: TextureRect
var minimap: Control
var hud_stats: Dictionary = {}
var fullscreen_map := false
var _right_down := Vector2.ZERO
var _right_dragged := false
var _right_held := false
var _ignore_right_release := false
var _normal_hud_visible: Array = []
# Mobile-only aim state. It is never included in snapshots or combat rules.
var touch_layer: CanvasLayer
var touch_confirm: Button
var touch_cancel_button: Button
var desktop_cancel_header: ColorRect
var _cancel_view_rect := Rect2()
var touch_hint: Label
var touch_full_header: ColorRect
var _touch_pan_allowed := false
var _touch_aim := Vector2i(-1,-1)
var _touch_aim_signature := ""
var _touch_camera_start := Vector2.ZERO
var animations_enabled := true
var sfx_enabled := true

var turn := 1
var phase := "player"
var selected: Node2D = null
var mode := "idle"
var busy := false
var finished_flag := false
var move_tiles: Dictionary = {}
var attack_tiles: Dictionary = {}
var move_prev: Dictionary = {}
var hover_tile := Vector2i(-1, -1)
var focus_cycle := 0

var mines: Array = []
var mine_nodes: Dictionary = {}
var mines_left := 3
var mine_kind := 0
var rng_state := 1
var battle_context: Dictionary = {}
var consumed_mines: Dictionary = {}
var consumed_items: Dictionary = {}
var active_skill: Dictionary = {}
var active_skill_id := -1
var active_item_id := -1
var mine_texture: Texture2D
var chest_nodes: Dictionary = {}
var _opening_chest := -1
var chests: Array = []
var scenario
var stats := {"kills": 0, "losses": 0, "chests": 0, "deployed": 0,
		"kills_by_gun": 0, "kills_by_mine": 0}
var ai_delay := 0.02
var animation_speed := 1
var _finishing := false
var fast_sim := false
var progress_fx_active := false
var progress_fx_queue: Array = []
var last_result := ""
var last_message := ""
var last_result_condition := "" # Intro condition, never a cause-of-defeat dialog.
# Diagnostic provenance only; independent from the fixed result notice.
var last_result_trigger: Dictionary = {}
# 手动试玩模式：--playtest 时记录 AI 切换，F9 导出当前局面，
# 每场结束追加 JSONL 战报，方便试玩后定位软锁/异常行为。
var playtest_mode := false
var log_history: Array = []
var input_history: Array = []
var pending_story: Array = []
var trigger_messages: Array = []
var _choice_layer: CanvasLayer
var _choice_prev_busy := false
var sfx_nodes: Array = []
var _trigger_accum := 0.0
var _auto_end_pending := false
var _movement_active := false
var initial_state: Dictionary = {}
var presentation_in_headless := false


func setup(d: Dictionary, lv: Dictionary, f: Font, ctx: Dictionary = {}, resume: Dictionary = {}) -> void:
	data = StateCodec.integers(d)
	level = StateCodec.integers(lv)
	font = f
	map_w = int(level["map"]["width"])
	map_h = int(level["map"]["height"])
	terrain = level["map"]["terrain"]
	native_dark_mask = RangeMask.cleared(map_w,map_h)
	mine_kind = int(data["meta"].get("mine_type", 0))
	battle_context = ctx.duplicate(true) if not ctx.is_empty() else {}
	if battle_context.is_empty():
		var default_mines := int(data["meta"].get("mines", 3))
		battle_context = {"mines": {str(mine_kind): default_mines}, "items": {},
				"consumed_mines": {}, "consumed_items": {}}
	consumed_mines = (battle_context.get("consumed_mines", {}) as Dictionary).duplicate(true)
	consumed_items = (battle_context.get("consumed_items", {}) as Dictionary).duplicate(true)
	battle_context["consumed_mines"] = consumed_mines
	battle_context["consumed_items"] = consumed_items
	_refresh_mine_left()
	mine_texture = load(str(data.get("mine_png", ""))) if ResourceLoader.exists(str(data.get("mine_png", ""))) else null
	scenario = load("res://scripts/m4/Scenario.gd").new()
	playtest_mode = OS.get_cmdline_user_args().has("--playtest")
	if playtest_mode:
		scenario.ai_trace = true
		print("PLAYTEST_MODE log=", ProjectSettings.globalize_path(
				"user://dlz_playtest.jsonl"))
	chests.clear()
	for c in level.get("chests", []):
		var cc: Dictionary = (c as Dictionary).duplicate(true)
		cc["opened"] = bool(c.get("opened",false)) if not resume.is_empty() else false
		chests.append(cc)
	_build_world()
	# 目标单位必须在单位生成后缓存；否则 reach_unit 会永远找不到目标。
	scenario.setup(self, level)
	if not resume.is_empty():
		_restore_state(resume)
		_spawn_level_markers()
		_build_hud()
		if fullscreen_map:
			fullscreen_map = false
			_toggle_map_mode()
		_clamp_camera()
		update_hud()
		return
	stats["deployed"] = player_units.size()
	stats["enemies_total"] = enemy_units.size()
	initial_state = snapshot()
	_spawn_level_markers()
	_build_hud()
	if scenario != null:
		scenario.on_start()
	turn = 1
	phase = "player"
	stats["deployed"] = player_units.size()
	stats["enemies_total"] = enemy_units.size()
	_begin_player_phase("第 1 回合，我方行动")
	# 41B53C starts fully bright, with no selected slot or movement mask.


func can_save() -> bool:
	return not busy and not finished_flag and phase == "player" and mode == "idle" \
		and not is_instance_valid(action_panel) and not is_instance_valid(_choice_layer)


func snapshot() -> Dictionary:
	var lv := level.duplicate(true)
	lv["units"] = []
	for unit in units: lv["units"].append(unit.state_record())
	lv["chests"] = chests.duplicate(true)
	var scenario_state := {}
	for field in ["wave_done","reached","searched","killed","collected","chests_opened",
		"race_winner","start_phase_pending","started","finished","status_text",
		"trigger_flags","trigger_done","_last_dead_side","_last_dead_slot","_last_turn_hook",
		"native_result","result_writes","_native_status_text"]:
		scenario_state[field] = scenario.get(field)
	return StateCodec.pack({"version":1,"level":lv,"context":battle_context,
		"turn":turn,"phase":phase,"stats":stats,"mines":mines,"rng_state":rng_state,
		"mine_kind":mine_kind,"scenario":scenario_state,"camera":camera.position,
		"fullscreen_map":fullscreen_map,"animation_speed":animation_speed,
		"display_timer_elapsed":display_timer_elapsed,"display_timer_count":display_timer_count,
		"sfx_enabled":sfx_enabled,"log_history":log_history})


func _restore_state(encoded: Dictionary) -> void:
	var snap: Dictionary = StateCodec.unpack(encoded)
	turn = int(snap.get("turn",1))
	phase = str(snap.get("phase","player"))
	stats = snap.get("stats",{}).duplicate(true)
	mines = snap.get("mines",[]).duplicate(true)
	rng_state = int(snap.get("rng_state",1))
	mine_kind = int(snap.get("mine_kind",0))
	log_history = snap.get("log_history",[]).duplicate()
	animation_speed = int(snap.get("animation_speed",1))
	ai_delay = animation_speed * 0.1
	sfx_enabled = bool(snap.get("sfx_enabled",true))
	fullscreen_map = bool(snap.get("fullscreen_map",false))
	display_timer_elapsed=float(snap.get("display_timer_elapsed",0.0))
	display_timer_count=int(snap.get("display_timer_count",0))
	for field in snap.get("scenario",{}): scenario.set(field,snap.scenario[field])
	camera_follow = false
	camera.position = snap.get("camera",camera.position)
	for mine in mines: _draw_mine(mine)
	# Original battle loading clears selection/interactive mode, not action availability.
	selected = null
	mode = "idle"
	busy = false


func _build_world() -> void:
	# 地图边角允许镜头露出边界；用深色底而不是引擎默认灰底。
	RenderingServer.set_default_clear_color(Color("#15170f"))
	map_sprite = Sprite2D.new()
	map_sprite.centered = false
	map_sprite.position = Vector2.ZERO
	map_sprite.z_index = -100
	var mp := str(level["map"]["png"])
	if ResourceLoader.exists(mp):
		map_sprite.texture = load(mp)
	add_child(map_sprite)
	native_range_layer=preload("res://scripts/battle/MapRangeLayer.gd").new()
	native_range_layer.battle=self
	native_range_layer.z_index=-99
	var dark_path:=mp.replace(".png","_dark.png")
	if ResourceLoader.exists(dark_path):native_range_layer.texture=load(dark_path)
	add_child(native_range_layer)

	units_root = Node2D.new()
	add_child(units_root)

	overlay = preload("res://scripts/Overlay.gd").new()
	overlay.battle = self
	overlay.z_index = 4000
	add_child(overlay)

	fx_root = Node2D.new()
	fx_root.z_index = 4090
	add_child(fx_root)

	for ud in level["units"]:
		_spawn_unit(ud)

	camera = Camera2D.new()
	camera.enabled = true
	# 原版战斗视口约 440×450，48px 一格；固定 1:1 才能看清单位和格子。
	# 旧版把整张大图缩到 0.35，人物只剩 16px，且在底边会被战报条盖住。
	camera.zoom = Vector2.ONE
	camera.position = _initial_camera()
	add_child(camera)
	camera.make_current()
	_clamp_camera()


func _spawn_unit(ud: Dictionary) -> Node2D:
	var u = preload("res://scripts/BattleUnit.gd").new()
	units_root.add_child(u)
	u.setup(ud, self)
	_refresh_equipment(u)
	units.append(u)
	if u.is_player():
		player_units.append(u)
	else:
		enemy_units.append(u)
	return u


func set_slot_faction(slot: int, faction: int) -> void:
	for key in ["slot_pool", "spawn_pool", "units"]:
		for rec in level.get(key, []):
			if int(rec.get("slot", -1)) == slot:
				rec["faction"] = faction
				rec["side"] = "player" if faction == 0 else "enemy"
				rec["auto"] = faction == 0 and not bool(rec.get("control",true))
	# People is independent of Fighter.stage. L22 writes side0 for the already
	# dead slot24; updating only the pool would let settlement overwrite it from
	# the stale dead node's data.faction and silently undo recruitment.
	var u = null
	for candidate in units:
		if int(candidate.slot)==slot:
			u=candidate
			break
	if u != null:
		player_units.erase(u)
		enemy_units.erase(u)
		u.side = "player" if faction == 0 else "enemy"
		u.data["faction"] = faction
		u.data["side"] = u.side
		u.auto = faction == 0 and not u.control
		u.data["auto"] = u.auto
		if faction == 0:
			player_units.append(u)
		else:
			enemy_units.append(u)
	emit_story_event("person_side", {"slot": slot, "faction": faction})


func set_slot_inventory(slot: int, key: String, values: Array) -> void:
	var slots: Array = values.duplicate()
	slots.resize(8)
	for i in range(8):
		if slots[i] == null:
			slots[i] = 0
	for pool in ["slot_pool", "spawn_pool", "units"]:
		for rec in level.get(pool, []):
			if int(rec.get("slot", -1)) == slot:
				rec[key] = slots.duplicate()
	var u = unit_by_slot(slot)
	if u != null:
		u.set(key, slots.duplicate())


func clear_slot_skills(slot: int) -> void:
	var zero := {}
	for key in SKILL_KEYS:
		zero[key] = 0
	for pool in ["slot_pool", "spawn_pool", "units"]:
		for rec in level.get(pool, []):
			if int(rec.get("slot", -1)) == slot:
				rec["skill_counts"] = zero.duplicate()
				rec["skills"] = zero.duplicate()
	var u = unit_by_slot(slot)
	if u != null:
		u.skill_counts = zero.duplicate()
		u.skills = zero.duplicate()


func scripted_mine(tile: Vector2i, mine_id: int, victim_slot: int) -> void:
	var definitions: Array = data.get("mines", [])
	if mine_id < 0 or mine_id >= definitions.size():
		return
	var u = unit_by_slot(victim_slot)
	_native_camera_focus(tile,"scripted_mine")
	mines.append({"tile": tile, "mine": definitions[mine_id], "mine_id": mine_id,
		"owner_side": "player", "apply_fw": int(definitions[mine_id].get("apply_fw", 0))})
	# 40C0CD focuses once above, rather than using the normal queue consumer.
	await _trigger_mine(tile, u, false)


func spawn_reserve(rec: Dictionary) -> Node2D:
	var d: Dictionary = rec.duplicate(true)
	var t := _free_tile_near(int(d.get("x", 0)), int(d.get("y", 0)))
	if t.x < 0:
		return null
	d["x"] = t.x
	d["y"] = t.y
	var u := _spawn_unit(d)
	if u.side == "enemy":
		stats["enemies_total"] = int(stats.get("enemies_total", 0)) + 1
	else:
		stats["deployed"] = int(stats.get("deployed", 0)) + 1
	u.moved = false
	u.acted = false
	u.refresh()
	return u


func spawn_slot(slot: int) -> Node2D:
	"""按 FIGHT 槽位生成/激活一个单位（0x429CC8 的数据化版本）。"""
	if unit_by_slot(slot) != null:
		return null
	var rec: Dictionary = {}
	for key in ["slot_pool", "spawn_pool", "reserves", "units"]:
		for r in level.get(key, []):
			if int(r.get("slot", -1)) == slot:
				rec = (r as Dictionary).duplicate(true)
				break
		if not rec.is_empty():
			break
	if rec.is_empty():
		_log("触发器生成槽 %d 缺少 FIGHT 记录" % slot)
		return null
	var t := Vector2i(int(rec.get("x", 0)), int(rec.get("y", 0)))
	var occupied := {}
	for unit in units:
		if unit.alive and unit.placed:occupied[Vector2i(unit.x,unit.y)] = true
	var destination := preload("res://scripts/battle/OriginalPlacement.gd").find_cell(t,Vector2i(map_w,map_h),occupied)
	if destination.x >= 0:
		rec["x"] = destination.x
		rec["y"] = destination.y
	var u := _spawn_unit(rec)
	u.placed = destination.x >= 0
	u.visible = u.placed
	u.moved = false
	u.acted = false
	u.refresh()
	if u.side == "enemy":
		stats["enemies_total"] = int(stats.get("enemies_total", 0)) + 1
	else:
		stats["deployed"] = int(stats.get("deployed", 0)) + 1
	if not u.placed:
		presentation_step.emit("spawn_unplaced", {"slot":slot})
		return null
	_log("战场变化：%s 出现" % u.unit_name)
	update_hud()
	return u


func remove_slot(slot: int) -> void:
	"""0x429BED：撤走槽位，不触发阵亡结算。"""
	var u = unit_by_slot(slot)
	if u == null:
		return
	u.alive = false
	u.visible = false
	u.hp = 0
	u.status_stun = 999
	if u == selected:
		selected = null
	update_hud()


func scripted_clear_slot(slot: int) -> void:
	# 409E16..409E55: active Fighter only; 429BED -> 42AFD2 -> 8331F0++.
	# Keep the actual People/node reference: unit_by_slot excludes it after remove.
	# This is NOT death (no XP, penalty, death callbacks, or item erasure).
	var u = unit_by_slot(slot)
	if u == null:return
	remove_slot(slot)
	_collect_native_casualty_loot(u)
	stats["kills_by_gun"]=(int(stats.get("kills_by_gun",0))+1)&0xffffffff
	stats["kills"]=(int(stats.get("kills",0))+1)&0xffffffff


func set_slot_field(slot: int, field_name: String, value: int) -> void:
	var u = scenario._slot_unit(slot) if scenario != null else unit_by_slot(slot)
	if field_name == "dest_x":
		field_name = "x"
	elif field_name == "dest_y":
		field_name = "y"
	if u != null and u.alive:
		match field_name:
			"level":
				u.data["level"] = clampi(value,1,99)
				u.max_hp = maxi(1,int(unit_class(u).get("tili",50))+(int(u.data["level"])-1)*int(unit_class(u).get("tili_plus",0)))
				u.hp = mini(u.hp,u.max_hp)
			"behavior": u.behavior = value
			"target_slot": u.target_slot = value
			"target_x": u.target_x = value
			"target_y": u.target_y = value
			"x", "pos_x":
				u.x = value
				u.position = Vector2(u.x * TILE + TILE / 2.0,
						u.y * TILE + TILE / 2.0)
			"y", "pos_y":
				u.y = value
				u.position = Vector2(u.x * TILE + TILE / 2.0,
						u.y * TILE + TILE / 2.0)
			"direction": u.direction = value
			"hp": u.hp = clampi(value, 0, u.max_hp)
			"max_hp": u.max_hp = maxi(1, value)
			"morale": u.morale = clampi(value, 0, 100)
			"integrity": u.integrity = clampi(value, 0, 100)
			"defense_integrity": u.defense_integrity = clampi(value, 0, 100)
			"pad3e":
				u.control = value != 0
				u.auto = u.is_player() and not u.control
			"moveable":
				u.moved = value == 0
				u.acted = value == 0
			_: u.data[field_name] = value
		u.refresh()
		return
	for key_name in ["spawn_pool", "reserves", "slot_pool"]:
		for r in level.get(key_name, []):
			if int(r.get("slot", -1)) == slot:
				var key := "x" if field_name == "pos_x" else ("y" if field_name == "pos_y" else field_name)
				r[key] = value


func get_slot_field(slot: int, field_name: String) -> int:
	var u = scenario._slot_unit(slot) if scenario != null else unit_by_slot(slot)
	if u != null:
		match field_name:
			"hp": return int(u.hp)
			"max_hp": return int(u.max_hp)
			"morale": return int(u.morale)
			"integrity": return int(u.integrity)
			"defense_integrity": return int(u.defense_integrity)
		return int(u.data.get(field_name, 0))
	for key in ["spawn_pool", "reserves", "slot_pool"]:
		for rec in level.get(key, []):
			if int(rec.get("slot", -1)) == slot:
				if field_name == "max_hp":
					return maxi(1, int(rec.get("tili", 50)) +
							(int(rec.get("level", 1)) - 1) * int(rec.get("tili_plus", 0)))
				return int(rec.get(field_name, 100 if field_name in ["morale", "integrity"] else 0))
	return 0


func scripted_attack(attacker_slot: int, target_slot: int) -> void:
	# 40F14B: same attack resolver, fixed north-facing mask, even if gunner45
	# has stage0. A temporary renderer is not inserted into the active slot queue.
	var target = unit_by_slot(target_slot)
	if target == null: return
	var attacker = unit_by_slot(attacker_slot)
	var temporary := attacker == null
	if temporary:
		var rec: Dictionary = {}
		for record in level.get("slot_pool",[]):
			if int(record.get("slot",-1)) == attacker_slot: rec = record; break
		if rec.is_empty(): return
		attacker = preload("res://scripts/BattleUnit.gd").new()
		units_root.add_child(attacker)
		attacker.setup(rec.duplicate(true),self)
		attacker.visible = false
	var previous_busy := busy
	busy = true
	action_resolution_depth += 1
	attacker.direction = 0
	_play_sfx(int(unit_class(attacker).get("audio_gongji",-1)))
	await _resolve_attack(attacker,target,0)
	if temporary:
		for field in ["level","xp"]: set_slot_field(attacker_slot,field,int(attacker.data.get(field,0)))
		set_slot_field(attacker_slot,"attack_count",int(attacker.attack_count))
		attacker.queue_free()
	action_resolution_depth -= 1
	busy = previous_busy or finished_flag


func trigger_message(record: int, addr: String) -> void:
	trigger_messages.append({"record": record, "addr": addr})
	emit_story_event("trigger_message", {"record": record, "addr": addr})
	if record >= 0:
		_log("剧情：TXT %d" % record)


func add_party_morale(add: int) -> void:
	for u in player_units:
		if is_instance_valid(u) and u.alive:
			u.morale = clampi(int(u.morale) + add, 0, 100)


func recruit_slots(slots: Array) -> void:
	# 40A619/40A623: L22 recruitment is only two People.side writes.
	# Inactive fighters must remain inactive; no healing/relocation/control edit.
	for slot in slots:
		set_slot_faction(int(slot),0)
	update_hud()


func show_trigger_choice(sc, _prompt: String, labels: Array) -> void:
	if fast_sim or finished_flag or labels.is_empty():
		if sc != null:
			sc.resolve_choice(0)
		return
	if is_instance_valid(_choice_layer):
		_choice_layer.queue_free()
	_choice_prev_busy = busy
	busy = true
	_choice_layer = CanvasLayer.new()
	_choice_layer.layer = 125
	add_child(_choice_layer)
	# L22 calls426E7D, not the cancellable426A05 menu. Prior TXT
	# records already carry the prompt; only the native88x88 menu is painted.
	var picker=preload("res://scripts/ui/OriginalChoice.gd").new()
	_choice_layer.add_child(picker)
	picker.chosen.connect(func(index:int):_on_trigger_choice(sc,index))
	picker.setup(font,labels,Vector2(276,196),false,[],false)


func _on_trigger_choice(sc, index: int) -> void:
	if is_instance_valid(_choice_layer):
		_choice_layer.queue_free()
	_choice_layer = null
	busy = _choice_prev_busy
	if sc != null:
		sc.resolve_choice(index)


func _any_free_tile() -> Vector2i:
	for y in range(map_h):
		for x in range(map_w):
			var t := Vector2i(x, y)
			if not _is_occupied(t) and move_cost(3, _terrain_at(t)) < 99:
				return t
	return Vector2i(-1, -1)


func _free_tile_near(tx: int, ty: int) -> Vector2i:
	if _in_bounds(Vector2i(tx, ty)) and not _is_occupied(Vector2i(tx, ty)) 			and move_cost(3, _terrain_at(Vector2i(tx, ty))) < 99:
		return Vector2i(tx, ty)
	for r in range(1, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var t := Vector2i(tx + dx, ty + dy)
				if _in_bounds(t) and not _is_occupied(t) 						and move_cost(3, _terrain_at(t)) < 99:
					return t
	return Vector2i(-1, -1)


func alive_enemies() -> int:
	return _alive_count(enemy_units)


func alive_players() -> int:
	return _alive_count(player_units)


func unit_by_slot(slot: int):
	for u in units:
		if u.alive and u.slot == slot:
			return u
	return null


func _spawn_level_markers() -> void:
	for old in chest_nodes.values():
		if is_instance_valid(old):old.queue_free()
	chest_nodes.clear()
	var seen:Dictionary={}
	for i in range(chests.size()):
		var c: Dictionary = chests[i]
		var tile:=Vector2i(int(c.x),int(c.y))
		if seen.has(tile):continue # 4170AA: first matching box wins.
		seen[tile]=true
		var s := Sprite2D.new()
		s.texture = _chest_texture(c)
		s.centered = true
		s.position = Vector2(int(c["x"]) * TILE + TILE / 2.0,
				int(c["y"]) * TILE + TILE / 2.0)
		s.z_index = -2
		units_root.add_child(s)
		chest_nodes[i] = s


func _chest_texture(c:Dictionary) -> Texture2D:
	var at:=AtlasTexture.new()
	at.atlas=load("res://assets/palette/box_map.png")
	var frame:=int(c.get("appearance",0))*2+(1 if bool(c.get("opened",false)) or int(c.get("wupin",-1))<0 else 0)
	at.region=Rect2(0,frame*48,48,48)
	return at


func _chest_at(t: Vector2i) -> int:
	for i in range(chests.size()):
		var c: Dictionary = chests[i]
		if int(c["x"]) == t.x and int(c["y"]) == t.y:
			# 429A4A stops at the first coordinate match, including an empty
			# box. Never fall through to a second overlapping box.
			return -1 if bool(c.get("opened",false)) or int(c.get("wupin",-1))<0 else i
	return -1


func _open_chest(u, i: int) -> void:
	if u==null or not u.alive or i<0 or i>=chests.size() or _opening_chest>=0:return
	var c: Dictionary = chests[i]
	if bool(c.get("opened",false)) or int(c.get("wupin",-1))<0:return
	var iid:=int(c.wupin)
	var item:Dictionary=data.get("items",{}).get(str(iid),{})
	var previous_busy:=busy
	_opening_chest=i;busy=true;action_resolution_depth+=1
	# The reward reads the old item ID; only afterwards does 429BA8 empty
	# the source field. Keep both the runtime UI flag and native field coherent.
	if scenario != null:
		scenario.on_chest(u, c)
	# 429B41 uses Item+40 audio_get, then 43D56B waits for acknowledgement.
	# The native source ID is still present throughout that blocking notice.
	_play_sfx(int(item.get("audio_get",-1)))
	if not fast_sim:
		await _manual_notice("       得到  "+str(item.get("name",c.get("item_name","")))+"  ！")
	c["opened"] = true
	c["wupin"] = -1
	stats["chests"] = int(stats.get("chests", 0)) + 1
	if chest_nodes.has(i):
		var node = chest_nodes[i]
		if is_instance_valid(node):
			node.texture = _chest_texture(c)
	action_resolution_depth-=1;_opening_chest=-1
	busy=previous_busy or finished_flag
	update_hud()


func _after_unit_step(u) -> void:
	if u == null or not u.alive or finished_flag:
		return
	var t := Vector2i(u.x, u.y)
	# Native pickup has no side/control filter (429A4A).
	var ci := _chest_at(t)
	if ci >= 0:
		await _open_chest(u, ci)
	if scenario != null:
		await scenario.on_unit_moved(u)
	if not _check_end():
		update_hud()


func _camera_focus_unit():
	# 优先选主角/部署队长，而不是所有我方的平均点。后者在多单位关卡
	# 会把镜头拉到空地中间，玩家开局看不到自己的人。
	for u in player_units:
		if u.alive and bool(u.data.get("hero", false)):
			return u
	for u in player_units:
		if u.alive and int(u.slot) < 0:
			return u
	for u in player_units:
		if u.alive:
			return u
	return null


func map_rect() -> Rect2:
	# Reserve the same top/bottom touch chrome in full-map mode; do not put
	# cancel/confirm over actionable cells. Desktop only reserves the top strip
	# while a visible target-cancel button needs it in fullscreen.
	if fullscreen_map and _touch_mode():return Rect2(0,32,624,432)
	if fullscreen_map and _target_action_mode():return Rect2(0,32,624,448)
	return FULL_MAP_RECT if fullscreen_map else NORMAL_MAP_RECT


func _focus_screen() -> Vector2:
	return map_rect().get_center()


func _focus_position(world: Vector2) -> Vector2:
	return world + Vector2(320,240) - _focus_screen()


func _camera_origin_tile() -> Vector2i:
	return _tile_of(camera.position + map_rect().position - Vector2(320,240)) if camera != null else Vector2i.ZERO


func _native_camera_focus(tile: Vector2i, reason: String) -> void:
	if camera == null or fast_sim:return
	# 41E97A: integer window origins, including the asymmetric full-map Y.
	var size := Vector2i(13,10) if fullscreen_map else Vector2i(9,9)
	var left := 7 if fullscreen_map else 5
	var right := 7 if fullscreen_map else 5
	var bottom := 6 if fullscreen_map else 5
	var x := 0 if tile.x<left else (tile.x-(left-1) if tile.x<map_w-right else map_w-size.x)
	var y := 0 if tile.y<5 else (tile.y-4 if tile.y<map_h-bottom else map_h-size.y)
	var origin := Vector2i(clampi(x,0,maxi(0,map_w-size.x)),clampi(y,0,maxi(0,map_h-size.y)))
	camera_follow=false;camera_follow_target=null
	camera.position=Vector2(origin*TILE)-map_rect().position+Vector2(320,240)
	_clamp_camera()
	presentation_step.emit("camera_focus",{"tile":tile,"origin":origin,"reason":reason})


func _native_camera_actor(tile: Vector2i) -> void:
	if camera == null or fast_sim:return
	var size := Vector2i(13,10) if fullscreen_map else Vector2i(9,9)
	if not Rect2i(_camera_origin_tile(),size).has_point(tile):
		_native_camera_focus(tile,"actor")


func _native_camera_move_step(current: Vector2i) -> void:
	if camera == null or fast_sim:return
	var offset := current-_camera_origin_tile()
	var size := Vector2i(13,10) if fullscreen_map else Vector2i(9,9)
	# 41EB2D tests the CURRENT cell before 41E5F1's four 12px substeps.
	if offset.x<=0 or offset.y<=0 or offset.x>=size.x-1 or offset.y>=size.y-1:
		_native_camera_focus(current,"move_edge")


func _restore_round_camera(previous: Vector2) -> void:
	if camera == null or fast_sim:return
	camera_follow=false;camera_follow_target=null
	camera.position=previous
	_clamp_camera()
	presentation_step.emit("camera_restore",{"origin":_camera_origin_tile()})


func _initial_camera() -> Vector2:
	var focus = _camera_focus_unit()
	if focus != null:
		return _focus_position(Vector2(focus.x * TILE + TILE/2, focus.y * TILE + TILE/2))
	var p: Array = level["map"].get("player_focus",[0,0])
	return _focus_position(Vector2(float(p[0])*TILE+24,float(p[1])*TILE+24))


func _clamp_camera() -> void:
	if camera == null: return
	var rect := map_rect()
	# Normal mode is exactly nine original 48px tiles, no fractional camera/zoom.
	camera.zoom = Vector2.ONE
	var origin := camera.position + rect.position - Vector2(320,240)
	origin.x = clampf(roundf(origin.x/TILE)*TILE,0,maxi(0,map_w*TILE-int(rect.size.x)))
	origin.y = clampf(roundf(origin.y/TILE)*TILE,0,maxi(0,map_h*TILE-int(rect.size.y)))
	camera.position = origin - rect.position + Vector2(320,240)
	camera.force_update_scroll()
	if minimap != null: minimap.queue_redraw()


func screen_to_tile(point: Vector2) -> Vector2i:
	if not map_rect().has_point(point) or camera == null: return Vector2i(-1,-1)
	var world := camera.position + point - Vector2(320,240)
	return _tile_of(world)


# ---------------- Touchscreen-only presentation adapter ----------------

func _touch_mode() -> bool:
	var touch = get_node_or_null("/root/TouchInput") if is_inside_tree() else null
	return touch != null and touch.is_touch_mode()

func _fit_topbar_button(button: Button) -> void:
	# OriginalUI.button initially sizes against fallback font/theme metrics,
	# which may leave a 31px control crossing y=32. Apply compact local
	# padding after entering the tree, then settle the actual 28px size.
	# Keep a local, compact style override; never shrink the shared theme.
	for state in ["normal","hover","pressed","disabled"]:
		var style:StyleBox = button.get_theme_stylebox(state).duplicate()
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		button.add_theme_stylebox_override(state,style)
	button.custom_minimum_size.y = 28
	button.size.y = 28

func _touch_mode_changed(enabled: bool) -> void:
	if enabled and touch_layer == null and hud_root != null:
		touch_layer = CanvasLayer.new()
		touch_layer.layer = 31
		add_child(touch_layer)
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		touch_layer.add_child(root)
		touch_full_header = ColorRect.new()
		touch_full_header.size = Vector2(640,32)
		touch_full_header.color = Color(0.04,0.04,0.04,1)
		touch_full_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(touch_full_header)
		for spec in [["取消",8,_touch_back],["确认",380,_touch_commit],["菜单",440,_touch_menu]]:
			var button := OriginalUI.button(str(spec[0]),font,Vector2(80 if int(spec[1])==8 else 56,28),spec[2],16)
			button.position = Vector2(int(spec[1]),2)
			root.add_child(button)
			_fit_topbar_button(button)
			if int(spec[1]) == 380:touch_confirm = button
			elif int(spec[1]) == 8:touch_cancel_button = button
		var bg := ColorRect.new()
		bg.position = Vector2(0,464);bg.size = Vector2(640,16)
		bg.color = Color(0.04,0.04,0.04,0.95);bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
		touch_hint = OriginalUI.label("",font,16,OriginalUI.GOLD_LIGHT)
		touch_hint.position = Vector2(8,464);touch_hint.size = Vector2(624,16)
		touch_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(touch_hint)
	if touch_layer != null:touch_layer.visible = enabled
	_update_touch_chrome()

func _touch_signature() -> String:
	return "%s/%s/%s/%s/%s/%s" % [selected.get_instance_id() if is_instance_valid(selected) else -1,
		mode,native_range_phase,active_skill_id,active_item_id,mine_kind]

func _touch_candidate_valid() -> bool:
	return (_touch_target_requires_confirmation() and _touch_aim.x >= 0 and _touch_aim_signature == _touch_signature() and _touch_map_ready()
		and RangeMask.allows(native_dark_mask,map_w,map_h,_touch_aim))

func _touch_map_ready() -> bool:
	return (not busy and not finished_flag and phase == "player" and not progress_fx_active
		and not is_instance_valid(action_panel) and not is_instance_valid(context_menu))

func _target_action_mode() -> bool:
	return selected != null and (mode in ["attack","skill","item","item_give"] or mode.begins_with("mine_"))

func _touch_target_requires_confirmation() -> bool:
	# Moving only stages a reversible location. Timer landings only open the
	# duration picker; choosing its duration is the final action confirmation.
	return _target_action_mode() and mode != "mine_timer" and not (mode == "mine_place" and mine_kind / 10 == 2)

func _target_cancel_text() -> String:
	match mode:
		"attack":return "取消攻击"
		"skill":return "取消策略"
		"item","item_give":return "取消物品"
	return "取消地雷" if mode.begins_with("mine_") else "取消"

func _update_target_cancel() -> void:
	if btn_cancel == null:return
	# This is one ordinary mouse HUD button, not touchscreen chrome. The old
	# placeholder used to stay hidden, leaving only an undiscoverable right click.
	var show_cancel := not _touch_mode() and _target_action_mode() and _touch_map_ready()
	btn_cancel.visible = show_cancel
	btn_cancel.disabled = not show_cancel
	btn_cancel.text = _target_cancel_text()
	if desktop_cancel_header != null:desktop_cancel_header.visible = show_cancel and fullscreen_map
	var rect := map_rect()
	if rect != _cancel_view_rect:
		_cancel_view_rect = rect
		# Target mode is set after the native mask is built. Synchronize the
		# fullscreen top reservation at HUD update, not only next frame's pan.
		_clamp_camera()
		if is_instance_valid(native_range_layer):native_range_layer.queue_redraw()
		if is_instance_valid(overlay):overlay.queue_redraw()

func _update_touch_chrome() -> void:
	if touch_layer == null:return
	touch_full_header.visible = fullscreen_map
	touch_confirm.disabled = not _touch_candidate_valid()
	touch_cancel_button.text = _target_cancel_text()
	if _touch_candidate_valid():
		touch_hint.text = "再点同格或点确认结束行动；" + _target_cancel_text() + "返回"
	elif mode == "move":
		touch_hint.text = "点可达格即移动；取消可撤回；拖动地图；长按情报"
	elif _target_action_mode() and not _touch_target_requires_confirmation():
		touch_hint.text = "点目标选择回合；选择回合即确认结束行动"
	elif _target_action_mode():
		touch_hint.text = "点格预览，再确认结束行动；可点" + _target_cancel_text()
	else:
		touch_hint.text = "点人物选择；拖动地图；长按情报"

func _touch_button_at(point: Vector2) -> int:
	if Rect2(8,2,80,28).has_point(point):return 0
	if Rect2(380,2,56,28).has_point(point):return 1
	if Rect2(440,2,56,28).has_point(point):return 2
	return -1

func touch_accepts(point: Vector2) -> bool:
	if not _touch_mode() or camera == null:return false
	# The cancel affordance remains reachable above native modal input layers.
	if _touch_button_at(point) >= 0:return true
	return _touch_map_ready() and map_rect().has_point(point)

func touch_begin(point: Vector2) -> void:
	_touch_camera_start = camera.position
	_touch_pan_allowed = map_rect().has_point(point)

func touch_pan(total: Vector2) -> void:
	if not _touch_pan_allowed or not _touch_map_ready():return
	touch_cancel()
	camera_follow = false
	camera_follow_target = null
	camera.position = _touch_camera_start - total
	_clamp_camera()

func touch_tap(point: Vector2, held: bool) -> void:
	match _touch_button_at(point):
		0:_touch_back();return
		1:_touch_commit();return
		2:_touch_menu();return
	if not _touch_map_ready() or not map_rect().has_point(point):return
	var tile := screen_to_tile(point)
	if not _in_bounds(tile):return
	if held:
		touch_cancel()
		var unit := _unit_at(tile)
		if unit != null and unit.alive:
			# Inspect without changing the actor or committing/reverting a
			# reversible move. Returning to aim still needs a fresh preview.
			_open_unit_info(unit)
		return
	hover_tile = tile
	if is_instance_valid(overlay):overlay.queue_redraw()
	if _touch_target_requires_confirmation():
		if not RangeMask.allows(native_dark_mask,map_w,map_h,tile):
			touch_cancel()
			return
		if _touch_aim == tile and _touch_aim_signature == _touch_signature():
			_touch_commit()
		else:
			_touch_aim = tile
			_touch_aim_signature = _touch_signature()
			update_hud()
			_update_touch_chrome()
		return
	touch_cancel()
	hover_tile = tile
	_on_map_click(tile)
	_update_touch_chrome()

func _touch_commit() -> void:
	if not _touch_candidate_valid():return
	var tile := _touch_aim
	_touch_aim = Vector2i(-1,-1)
	_touch_aim_signature = ""
	_on_map_click(tile)
	_update_touch_chrome()

func _touch_back() -> void:
	var touch = get_node_or_null("/root/TouchInput")
	if touch != null:touch.request_back()
	else:_cancel()

func _touch_menu() -> void:
	if not _touch_map_ready():return
	touch_cancel()
	_open_system_menu(Vector2(400,32))

func touch_cancel() -> void:
	_touch_aim = Vector2i(-1,-1)
	_touch_aim_signature = ""
	if _touch_mode():hover_tile = Vector2i(-1,-1)
	if is_instance_valid(overlay):overlay.queue_redraw()
	_update_touch_chrome()

func _draw_touch_aim(ci: CanvasItem) -> void:
	if not _touch_mode() or not _touch_candidate_valid():return
	var rect := Rect2(Vector2(_touch_aim*TILE)+Vector2(3,3),Vector2(TILE-6,TILE-6))
	var clip := Rect2(camera.position+map_rect().position-Vector2(320,240),map_rect().size)
	var visible := rect.intersection(clip)
	if visible.has_area():ci.draw_rect(visible,Color(1,0.95,0.35),false,3)


# ---------------- HUD ----------------

func _hud_label(text: String, pos: Vector2, size: Vector2,
		fs: int = 16, color: Color = Color("#e8edf4")) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(fs, OriginalUI.MIN_TEXT_SIZE))
	l.add_theme_color_override("font_color", color)
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(l)
	return l


func _hud_button(text: String, pos: Vector2, size: Vector2, cb: Callable) -> Button:
	var b := OriginalUI.button(text, font, size, cb, 16)
	b.position = pos
	b.size = size
	hud_root.add_child(b)
	return b


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 30
	add_child(hud_layer)
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := OriginalUI.make_theme(font)
	hud_root.theme = t
	hud_layer.add_child(hud_root)

	hud_frame = TextureRect.new()
	hud_frame.texture = load("res://assets/ui/hud_battle.png")
	hud_frame.position = Vector2.ZERO
	hud_frame.size = Vector2(640,480)
	hud_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(hud_frame)
	# Nonvisual compatibility labels retain full task/log text; the original map is unobstructed.
	for key in ["level","objective","phase","enemy","mine","message","guide","unit"]:
		var lab := _hud_label("",Vector2.ZERO,Vector2.ZERO)
		lab.visible = false
		hud_stats[key] = lab
	level_label = hud_stats.level
	objective_label = hud_stats.objective
	phase_label = hud_stats.phase
	enemy_label = hud_stats.enemy
	mine_label = hud_stats.mine
	message_label = hud_stats.message
	objective_guide = hud_stats.guide
	unit_label = hud_stats.unit
	objective_guide_bg = ColorRect.new()
	objective_guide_bg.visible = false
	hud_root.add_child(objective_guide_bg)
	portrait = TextureRect.new()
	portrait.position = Vector2(464,38)
	portrait.size = Vector2(80,100)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(portrait)
	for row in [["name",548,38,78,20],["wuli",548,58,78,20],["zhili",548,78,78,20],
		["class",548,98,78,20],["levelnum",548,118,78,20],["xp",548,138,78,20],
		["attack",464,160,84,20],["defense",548,160,78,20],["hp",464,180,160,20],
		["morale",464,200,160,20],["round",548,220,78,20],["side",464,220,80,20]]:
		hud_stats[row[0]] = _hud_label("",Vector2(row[1],row[2]),Vector2(row[3],row[4]),16,Color("#a4fcfc"))
	turn_label = hud_stats.round
	minimap = load("res://scripts/ui/BattleMinimap.gd").new()
	minimap.battle = self
	minimap.position = Vector2(459,252)
	minimap.size = Vector2(168,212)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(minimap)
	var names := ["退 出","重 来","存 档","取 档","音 乐","音 效","我 方","敌 方","速 度","动 画","结 束","任 务","分 屏"]
	for i in range(13):
		var button := TextureButton.new()
		button.position = Vector2(88+i*28 if i<10 else 500+(i-10)*28,4)
		button.size = Vector2(28,24)
		for state in [0,1]:
			var texture := AtlasTexture.new()
			texture.atlas = load("res://assets/ui/button%02d_original.png" % state)
			texture.region = Rect2(0,i*24,28,24)
			if state == 0: button.texture_normal = texture
			else: button.texture_pressed = texture; button.texture_hover = texture
		button.tooltip_text = names[i]
		button.button_down.connect(_toolbar.bind(i))
		hud_root.add_child(button)
	# Action buttons now belong to the six-row contextual menu, not the minimap.
	for key in ["attack","skill","mine","item","wait","cancel","end"]:
		var button := Button.new()
		button.visible = false
		hud_root.add_child(button)
		hud_stats["button_"+key] = button
	btn_attack = hud_stats.button_attack
	btn_skill = hud_stats.button_skill
	btn_mine = hud_stats.button_mine
	btn_item = hud_stats.button_item
	btn_wait = hud_stats.button_wait
	btn_cancel = hud_stats.button_cancel
	btn_end = hud_stats.button_end
	btn_cancel.text = "取消攻击"
	btn_cancel.position = Vector2(8,2)
	btn_cancel.size = Vector2(80,28)
	btn_cancel.custom_minimum_size = Vector2(80,28)
	btn_cancel.add_theme_font_override("font",font)
	btn_cancel.add_theme_font_size_override("font_size",16)
	btn_cancel.focus_mode = Control.FOCUS_NONE
	btn_cancel.pressed.connect(_on_cancel)
	_fit_topbar_button(btn_cancel)
	desktop_cancel_header = ColorRect.new()
	desktop_cancel_header.size = Vector2(640,32)
	desktop_cancel_header.color = Color(0.04,0.04,0.04,1)
	desktop_cancel_header.visible = false
	desktop_cancel_header.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(desktop_cancel_header)
	hud_root.move_child(desktop_cancel_header,0)
	add_to_group("touch_battle")
	var touch = get_node_or_null("/root/TouchInput")
	if touch != null and not touch.touch_mode_changed.is_connected(_touch_mode_changed):
		touch.touch_mode_changed.connect(_touch_mode_changed)
	_touch_mode_changed(_touch_mode())


func _toolbar(index: int, system_menu:=false) -> void:
	match index:
		0: toolbar_requested.emit("exit")
		1: toolbar_requested.emit("restart")
		2: toolbar_requested.emit("save")
		3: toolbar_requested.emit("load")
		4:
			var music = get_node_or_null("/root/Music")
			if music != null: music.toggle()
		5: sfx_enabled = not sfx_enabled; _log("音效开启" if sfx_enabled else "音效关闭")
		6: _show_roster("player")
		7: _show_roster("enemy")
		8: _show_speed(system_menu)
		9: toolbar_requested.emit("movie_toggle")
		10: _ask_end_turn(system_menu)
		11: _show_task()
		12: _toggle_map_mode()


func _set_animation_speed(value: int) -> void:
	animation_speed = clampi(value,0,4)
	ai_delay = animation_speed * 0.1
	_close_action_panel()


func _toggle_map_mode() -> void:
	fullscreen_map = not fullscreen_map
	if fullscreen_map:
		_normal_hud_visible.clear()
		for child in hud_root.get_children():
			if child != action_panel and child != context_menu and child.visible:
				_normal_hud_visible.append(child)
				child.visible = false
	else:
		for child in _normal_hud_visible:
			if is_instance_valid(child): child.visible = true
		_normal_hud_visible.clear()
	_close_context_menu()
	_clamp_camera()
	_update_touch_chrome()
	_update_target_cancel()


func _show_task() -> void:
	var entries:Array=[]
	if int(level.index)<45:
		entries.append({"text":"第","at":Vector2(100,80)})
		entries.append({"text":str(int(level.index)+1),"at":Vector2(116,80)})
		entries.append({"text":"关：","at":Vector2(132,80)})
	else:entries.append({"text":"休闲关","at":Vector2(100,80)})
	entries.append({"text":str(level.get("name","")),"at":Vector2(200,80)})
	entries.append({"text":"胜利条件：","at":Vector2(100,120)})
	entries.append({"text":str(level.get("success","")),"at":Vector2(200,120)})
	entries.append({"text":"失败条件：","at":Vector2(100,160)})
	entries.append({"text":str(level.get("failure","")),"at":Vector2(200,160)})
	entries.append({"text":"当前得分：","at":Vector2(420,400)})
	entries.append({"text":str(int(battle_context.get("score_total",0))),"at":Vector2(500,400)})
	_open_readout([entries])


func _open_readout(pages:Array) -> void:
	_close_context_menu();_close_action_panel()
	if pages.is_empty():return
	var readout=preload("res://scripts/ui/OriginalReadout.gd").new()
	hud_root.add_child(readout);action_panel=readout
	readout.closed.connect(_close_action_panel)
	var background:Image=null
	if DisplayServer.get_name()!="headless":
		# Restore the closed menu before taking the native screen backup. Keep
		# the modal claimed while waiting; never capture its own text/darkening.
		readout.visible=false
		await get_tree().process_frame
		if not is_instance_valid(readout) or action_panel!=readout:return
		RenderingServer.force_sync();RenderingServer.force_draw()
		background=get_viewport().get_texture().get_image().get_region(Rect2i(80,60,480,360))
	readout.setup(font,data.meta.battle_palette,pages,background,data.meta.map_dark_lut)
	readout.visible=true


func _open_toolbar_choice(lines:Array,origin:Vector2,callback:Callable) -> void:
	_close_context_menu();_close_action_panel()
	var picker=preload("res://scripts/ui/OriginalChoice.gd").new()
	hud_root.add_child(picker);action_panel=picker
	picker.chosen.connect(func(index:int):
		_close_action_panel();callback.call(index))
	picker.cancelled.connect(func():_ignore_right_release=true;_close_action_panel())
	picker.setup(font,lines,origin)


func _show_speed(system_menu:=false) -> void:
	var lines:Array=["最 快","较 快","普 通","较 慢","最 慢"]
	lines[animation_speed]+=" *"
	_open_toolbar_choice(lines,Vector2(320,200) if system_menu else Vector2(282,32),_set_animation_speed)


func _close_context_menu() -> void:
	_context_is_action=false
	if is_instance_valid(context_menu):
		context_menu.visible = false
		context_menu.queue_free()
	context_menu = null


func _open_context_menu() -> void:
	_close_context_menu()
	if selected == null or not selected.alive or selected.acted or busy or phase != "player": return
	if not selected.is_player() or not selected.control: return
	var entries := [["休  息",_request_wait],["攻  击%2d"%CombatRules.skill_level(selected.attack_count),_on_attack],
		["策  略",_on_skill],["地  雷",_on_mine],["物  品",_on_item],["情  报",_open_unit_info]]
	_clear_native_range("menu")
	mode="idle"
	move_tiles.clear();attack_tiles.clear()
	_native_menu(entries,Vector2(320,240))
	_context_is_action=true


func _open_system_menu(point: Vector2) -> void:
	if busy or finished_flag: return
	var names := ["退 出","重 来","存 档","取 档","音 乐","音 效","我 方","敌 方","速 度","动 画","结 束","任 务","分 屏"]
	var entries: Array = []
	for index in range(names.size()): entries.append([names[index],_toolbar.bind(index,true),false])
	_native_menu(entries,Vector2(minf(point.x,551),minf(point.y,151)))


func _native_menu(entries: Array, point: Vector2) -> void:
	_close_context_menu()
	var picker=preload("res://scripts/ui/OriginalChoice.gd").new()
	context_menu=picker
	hud_root.add_child(picker)
	picker.chosen.connect(func(index:int):
		var callback:Callable=entries[index][1]
		_close_context_menu()
		if callback.is_valid():callback.call())
	picker.cancelled.connect(func():_ignore_right_release=true;_cancel())
	picker.setup(font,entries.map(func(entry):return str(entry[0])),point)


func update_hud() -> void:
	if hud_root == null:
		return
	level_label.text = "L%02d  %s" % [int(level["index"]), level["name"]]
	var tlim := int(level.get("turn_limit", 0))
	turn_label.text = ("第 %d/%d 回合" % [turn, tlim]) if tlim > 0 else ("第 %d 回合" % turn)
	turn_label.add_theme_color_override("font_color",
			Color("#ff8a6a") if tlim > 0 and turn >= tlim - 5 else OriginalUI.GOLD_LIGHT)
	if phase == "player":
		phase_label.text = "我方回合"
		phase_label.add_theme_color_override("font_color", PLAYER_COLOR)
	elif phase == "enemy":
		phase_label.text = "敌方行动"
		phase_label.add_theme_color_override("font_color", ENEMY_COLOR)
	elif phase == "ally":
		phase_label.text = "友军行动"
		phase_label.add_theme_color_override("font_color", Color("#8fd18f"))
	else:
		phase_label.text = "战斗结束"
		phase_label.add_theme_color_override("font_color", Color("#f2c14e"))
	var obj_text := str(level.get("success", "全歼敌人"))
	if scenario != null and str(scenario.status_text) != "":
		obj_text = str(scenario.status_text)
	objective_label.text = "目标：%s" % obj_text
	objective_guide.visible = false
	objective_guide_bg.visible = false
	enemy_label.text = "敌军 %d / 我军 %d" % [_alive_count(enemy_units), _alive_count(player_units)]
	var cur_mine := "?"
	var mine_defs: Array = data.get("mines", [])
	if mine_kind >= 0 and not mine_defs.is_empty():
		cur_mine = str(mine_defs[mine_kind % 10].get("name", "?"))
	mine_label.text = "%s×%d  宝箱%d" % [cur_mine,
			_inventory_count("mines", mine_kind), int(stats.get("chests", 0))]
	message_label.text = str(level.get("message", ""))
	if selected != null and is_instance_valid(selected):
		var u = selected
		var atk := _effective_attack(u)
		var df := _effective_defense(u)
		var tag := "我方" if u.is_player() else "敌方"
		if u.is_player() and u.auto:
			tag = "友军"
		var state := "已行动" if u.acted else ("已移动" if u.moved else "待命")
		var equip_txt := "无" if int(u.equip) < 0 else str(u.equip_name)
		unit_label.text = "%s [%s] Lv%d\nHP %d/%d\n士气%d  攻%d 防%d\n移%d 射程%d EXP%d/100\n装备:%s\n%s" % [
			u.unit_name, tag, int(u.data.get("level", 1)), u.hp, u.max_hp, u.morale,
			atk, df, u.move, attack_radius(u), int(u.data.get("xp", 0)), equip_txt, state
		]
		if u.data.get("face_png", "") != "" and ResourceLoader.exists(u.data["face_png"]):
			portrait.texture = load(u.data["face_png"])
			portrait.visible = true
		else:
			portrait.visible = false
	else:
		unit_label.text = "点击我方单位开始行动\n亮格为当前可选范围\n左键确认 / 右键取消"
		portrait.visible = false

	var display_unit = selected if selected != null and is_instance_valid(selected) else _unit_at(hover_tile)
	for key in ["name","wuli","zhili","class","levelnum","xp","attack","defense","hp","morale","side"]:
		hud_stats[key].text = ""
	if display_unit != null:
		var u = display_unit
		hud_stats.name.text = u.unit_name
		hud_stats.wuli.text = "武力 %d" % int(u.data.get("wuli",0))
		hud_stats.zhili.text = "智力 %d" % int(u.data.get("zhili",0))
		hud_stats["class"].text = str(unit_class(u).get("name",""))
		hud_stats.levelnum.text = "等级 %d" % int(u.data.get("level",1))
		hud_stats.xp.text = "经验 %d" % int(u.data.get("xp",0))
		hud_stats.attack.text = "攻击 %d" % _effective_attack(u)
		hud_stats.defense.text = "防御 %d" % _effective_defense(u)
		hud_stats.hp.text = "体力 %d/%d" % [u.hp,u.max_hp]
		hud_stats.morale.text = "士气 %d/100" % u.morale
		hud_stats.side.text = "已行动" if u.acted else ("我方" if u.is_player() else "敌方")
		var fp := str(u.data.get("face_png",""))
		portrait.texture = load(fp) if ResourceLoader.exists(fp) else null
		portrait.visible = not fullscreen_map
	turn_label.text = "回合 %d" % turn
	if minimap != null: minimap.queue_redraw()
	var can_act: bool = phase == "player" and not busy and not finished_flag
	var controllable: bool = selected != null and selected.is_player() and selected.control
	btn_attack.disabled = not (can_act and controllable and not selected.acted)
	btn_mine.disabled = not can_act or not controllable or not can_mine(selected)
	btn_skill.disabled = not (can_act and controllable and not selected.acted
			and not available_skills(selected).is_empty())
	btn_item.disabled = not (can_act and controllable and not selected.acted)
	btn_wait.disabled = not (can_act and controllable and not selected.acted)
	btn_cancel.disabled = mode == "idle" and selected == null and action_panel == null
	btn_end.disabled = not can_act
	_update_target_cancel()
	if phase == "player":
		btn_end.text = "结束回合"
	elif phase == "enemy":
		btn_end.text = "敌方行动中…"
	else:
		btn_end.text = "战斗结束"
	if overlay != null:
		overlay.queue_redraw()


func _play_flm(flm_index: int, world: Vector2, scale_factor: float = 1.0, frame_ms := 20) -> float:
	if flm_index < 0 or fast_sim or not animations_enabled:
		return 0.0
	# Original speed0 is immediate, not a 1ms/frame substitute.
	if animation_speed==0:return 0.0
	var path := "res://assets/flm/flm_%03d.png" % flm_index
	if not ResourceLoader.exists(path):
		return 0.0
	var tex: Texture2D = load(path)
	if tex == null:
		return 0.0
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("default")
	frames.set_animation_speed("default", 1000.0 / maxf(1,animation_speed*float(frame_ms)))
	frames.set_animation_loop("default", false)
	for i in range(16):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * TILE, 0, TILE, TILE)
		frames.add_frame("default", at)
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = frames
	anim.material = _effect_clip_material()
	anim.position = world
	anim.scale = Vector2(scale_factor, scale_factor)
	anim.z_index = 0
	anim.animation_finished.connect(anim.queue_free)
	fx_root.add_child(anim)
	anim.play("default")
	return 16.0*animation_speed*frame_ms/1000.0


func _play_single_cell_flm(index: int, world: Vector2, wave := -1) -> float:
	# 429810: only level-up/penalty/script explosions use 40ms per frame.
	var duration:=_play_flm(index,world,1.0,40)
	if wave>=0:_play_sfx(wave)
	return duration


func _queue_progress_flm(index:int,world:Vector2,wave:int,post_ms:=0) -> void:
	if fast_sim or not animations_enabled:return
	progress_fx_queue.append({"index":index,"world":world,"wave":wave,"post_ms":post_ms})
	if not progress_fx_active:_run_progress_flm()


func _run_progress_flm() -> void:
	progress_fx_active=true
	while not progress_fx_queue.is_empty():
		var effect:Dictionary=progress_fx_queue.pop_front()
		var duration:=_play_single_cell_flm(effect.index,effect.world,effect.wave)
		var delay:=duration+float(effect.post_ms)/1000.0
		if delay>0:await _wait_presentation_time(delay)
	progress_fx_active=false


func _wait_presentation_time(seconds:float) -> void:
	# GetTickCount-based original waits begin at this call, not at the beginning
	# of an expensive render frame (a new SceneTreeTimer may inherit that delta).
	var until:=Time.get_ticks_msec()+int(ceil(seconds*1000.0))
	while Time.get_ticks_msec()<until:
		await get_tree().process_frame


func _wait_for_progress_fx() -> void:
	while progress_fx_active:
		await get_tree().process_frame


func _play_sfx(wave_id: int, volume_db: float = -6.0) -> void:
	if wave_id < 0 or not sfx_enabled or fast_sim:
		return
	var path := "res://assets/audio/wave_%04d.wav" % wave_id
	if not ResourceLoader.exists(path):
		return
	while sfx_nodes.size() >= 8:
		var old = sfx_nodes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	var c := ConfigFile.new()
	var sv := 0.8
	if c.load("user://dlz_config.cfg") == OK:
		sv = float(c.get_value("audio", "sfx_volume", 0.8))
	p.volume_db = volume_db + linear_to_db(clampf(sv, 0.0, 1.0))
	add_child(p)
	sfx_nodes.append(p)
	p.finished.connect(p.queue_free)
	p.play()


func emit_story_event(kind: String, data: Dictionary = {}) -> void:
	pending_story.append({"kind": kind, "data": data})
	story_event.emit(kind, data)


func _log(text: String) -> void:
	level["message"] = text
	log_history.append("T%d %s" % [turn, text])
	if log_history.size() > 80:
		log_history.pop_front()
	if message_label != null:
		message_label.text = text


# ---------------- 选择 / 输入 ----------------

func _advance_display_timer(delta:float) -> void:
	# Deterministic replay of55ms WM_TIMER / every sixth callback, not a claim
	# of dynamic Windows message-coalescing parity. Blocking actions pause idle.
	if fast_sim or busy or finished_flag or _movement_active or progress_fx_active or action_resolution_depth>0 or is_instance_valid(action_panel) or is_instance_valid(context_menu):return
	display_timer_elapsed+=delta
	while display_timer_elapsed>=0.055:
		display_timer_elapsed-=0.055
		display_timer_count=(display_timer_count+1)&0xffffffff
		if display_timer_count%6==0:
			for unit in units:
				if unit.display_state==1:unit.advance_display()


func _process(delta: float) -> void:
	_update_target_cancel()
	var modal_open:=is_instance_valid(action_panel) or is_instance_valid(context_menu)
	# A modal can open without moving the mouse. Hide/reveal the aim aid even
	# when the usual hover-update branch below is intentionally suspended.
	if mode in ["attack","skill"] and is_instance_valid(overlay):overlay.queue_redraw()
	_advance_display_timer(delta)
	# 触发器必须在无头 bot（camera 为空）下也继续跑。
	if scenario != null and not finished_flag and not busy and not modal_open and not progress_fx_active and action_resolution_depth==0 and not _movement_active:
		_trigger_accum += delta
		if _trigger_accum >= 0.1:
			_trigger_accum = 0.0
			await scenario.on_tick()
			if not busy and phase == "player" and not fast_sim: _auto_end_if_ready()
	if camera == null or modal_open:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO and not busy:
		camera_follow = false
		camera.position += dir * TILE
		_clamp_camera()
	elif camera_follow and camera_follow_target != null \
			and is_instance_valid(camera_follow_target) and camera_follow_target.alive:
		var want := _focus_position(camera_follow_target.position)
		camera.position = want
		_clamp_camera()
	if _touch_mode():
		_update_touch_chrome()
		return # Keep the last tapped aim; a touchscreen has no hover cursor.
	var t := screen_to_tile(get_viewport().get_mouse_position())
	if t != hover_tile:
		hover_tile = t
		update_hud()
		if overlay != null:
			overlay.queue_redraw()
func _unhandled_input(event: InputEvent) -> void:
	# Diagnostics must still work while an effect owns the normal input lock.
	if event is InputEventKey and event.pressed and not event.echo and playtest_mode \
			and event.keycode in [KEY_F8,KEY_F9]:
		_dump_playtest_state()
		get_viewport().set_input_as_handled()
		return
	if progress_fx_active or is_instance_valid(action_panel) or is_instance_valid(context_menu):return
	if _touch_mode() and event is InputEventMouse and event.device == TouchBridge.SYNTHETIC_DEVICE:
		# UI gestures are never map commands. A modal may disappear between
		# finger-down and finger-up; do not let its synthesized release/tap
		# bypass the map's preview/confirm route. Minimap panning is harmless.
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and not fullscreen_map and minimap.actual_rect().has_point(event.position-minimap.position):
			var tile:Vector2i=minimap.tile_at(event.position-minimap.position)
			camera_follow=false
			camera.position=_focus_position(Vector2(tile.x*TILE+24,tile.y*TILE+24))
			_clamp_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _right_held:
		var diff: Vector2 = event.position - _right_down
		if diff.length() >= 20:
			camera_follow = false
			camera.position -= Vector2(signf(diff.x)*TILE,0) if absf(diff.x)>absf(diff.y) else Vector2(0,signf(diff.y)*TILE)
			_clamp_camera()
			_right_down = event.position
			_right_dragged = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if fullscreen_map and event.double_click and event.pressed:
				_right_held = false
				_ignore_right_release = true
				_open_system_menu(event.position)
				get_viewport().set_input_as_handled()
				return
			if event.pressed:
				_right_down = event.position
				_right_dragged = false
				_right_held = true
			else:
				_right_held = false
				if not _right_dragged and not _ignore_right_release: _cancel()
				_ignore_right_release = false
			get_viewport().set_input_as_handled()
			return
		if not event.pressed: return
		if event.button_index == MOUSE_BUTTON_LEFT and not fullscreen_map and minimap.actual_rect().has_point(event.position-minimap.position):
			var tile: Vector2i = minimap.tile_at(event.position-minimap.position)
			camera_follow = false
			camera.position = _focus_position(Vector2(tile.x*TILE+24,tile.y*TILE+24))
			_clamp_camera()
			get_viewport().set_input_as_handled()
			return
		if not map_rect().has_point(event.position): return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_trace_input("pointer", {"screen":[event.position.x,event.position.y],"busy":busy,"phase":phase})
			if finished_flag or busy or phase != "player": return
			_close_context_menu()
			_on_map_click(screen_to_tile(event.position))
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_toggle_map_mode()
		elif event.keycode == KEY_ESCAPE:
			_cancel()
		elif event.keycode == KEY_TAB:
			_focus_next_side()
		elif event.keycode == KEY_1:
			_on_attack()
		elif event.keycode == KEY_2:
			_on_skill()
		elif event.keycode == KEY_3:
			_on_mine()
		elif event.keycode == KEY_4:
			_on_item()
		elif event.keycode == KEY_5:
			_request_wait()
		elif event.keycode == KEY_6:
			_ask_end_turn()


func _playtest_units() -> Array:
	var out: Array = []
	for u in units:
		if not is_instance_valid(u):
			continue
		out.append({
			"slot": int(u.slot), "pid": int(u.pid), "name": str(u.unit_name),
			"side": str(u.side), "alive": bool(u.alive),
			"x": int(u.x), "y": int(u.y), "hp": int(u.hp),
			"behavior": int(u.behavior), "target_slot": int(u.target_slot),
			"target": [int(u.target_x), int(u.target_y)],
			"home": [int(u.home_x), int(u.home_y)],
			"acted": bool(u.acted), "auto": bool(u.auto),
		})
	return out


func _playtest_snapshot() -> Dictionary:
	var trig := {}
	if scenario != null:
		trig = {
			"flags": (scenario.trigger_flags as Dictionary).duplicate(true),
			"done": (scenario.trigger_done as Dictionary).duplicate(true),
			"pending_choice": (scenario.pending_choice as Dictionary).duplicate(true),
			"ai_log": (scenario.ai_log as Array).duplicate(),
		}
	return {
		"level_index": int(level.get("index", -1)),
		"level_name": str(level.get("name", "")),
		"turn": turn, "phase": phase, "finished": finished_flag,
		"result": last_result, "message": last_message,
		"condition": last_result_condition, "result_trigger": last_result_trigger.duplicate(true),
		"stats": stats.duplicate(true),
		"units": _playtest_units(),
		"triggers": trig,
		"log": log_history.duplicate(),
		"input": input_history.duplicate(true),
		"runtime": _playtest_runtime(),
	}


func _playtest_runtime() -> Dictionary:
	var out := {"busy":busy,"mode":mode,"movement":_movement_active,
		"native_range_phase":native_range_phase,"selected_slot":int(selected.slot) if is_instance_valid(selected) else -1,
		"action_depth":action_resolution_depth,"progress_fx":progress_fx_active,
		"progress_queued":progress_fx_queue.size(),"numbers_pending":_pending_numbers.size(),
		"automatic_slot":_active_ai_slot,"auto_end_pending":_auto_end_pending,
		"last_stage":_resolution_trace.duplicate(true),
		"action_panel":str(action_panel.get_script().resource_path) if is_instance_valid(action_panel) and action_panel.get_script()!=null else "",
		"camera_follow":camera_follow,
		"camera_target":int(camera_follow_target.slot) if is_instance_valid(camera_follow_target) else -1}
	if camera!=null:out["camera_origin"]=[_camera_origin_tile().x,_camera_origin_tile().y]
	if scenario!=null:
		for field in ["_trigger_active","_round_active","_apply_depth","start_phase_pending"]:
			out[field]=scenario.get(field)
	return out


func _trace_resolution(stage: String, slot := -1, tile := Vector2i(-1,-1)) -> void:
	_resolution_trace={"stage":stage,"slot":slot,"tile":[tile.x,tile.y],"ticks_ms":Time.get_ticks_msec()}
	if not playtest_mode:return
	# Flush each boundary: a hung action need not reach the battle-end report.
	var path := "user://dlz_playtest_runtime.jsonl"
	var f := FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f==null:return
	f.seek_end()
	f.store_line(JSON.stringify({"level_index":level.get("index",-1),"turn":turn,"phase":phase,
		"runtime":_playtest_runtime(),"units":_playtest_units(),"log":log_history.slice(-8)}))
	f.close()


func _dump_playtest_state() -> void:
	var path := ProjectSettings.globalize_path("user://dlz_playtest_state.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_log("试玩状态导出失败：%s" % path)
		return
	f.store_string(JSON.stringify(_playtest_snapshot(), "\t"))
	f.close()
	_log("试玩状态已导出：%s" % path)
	print("PLAYTEST_STATE ", path)


func _append_playtest_report(result: String, message: String) -> void:
	var path := ProjectSettings.globalize_path("user://dlz_playtest.jsonl")
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var f := FileAccess.open(path, mode)
	if f == null:
		return
	f.seek_end()
	var rec := _playtest_snapshot()
	rec["result"] = result
	rec["message"] = message
	f.store_line(JSON.stringify(rec))
	f.close()


func _zoom_at(factor: float) -> void:
	if camera == null:
		return
	var z := clampf(camera.zoom.x * factor, 0.30, 2.0)
	camera.zoom = Vector2(z, z)
	_clamp_camera()


func _tile_of(world: Vector2) -> Vector2i:
	return Vector2i(int(floor(world.x / TILE)), int(floor(world.y / TILE)))


func _in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_w and t.y < map_h


func _terrain_at(t: Vector2i) -> int:
	if not _in_bounds(t):
		return 15
	return int(terrain[t.y * map_w + t.x])


func _unit_at(t: Vector2i) -> Node2D:
	for u in units:
		if u.alive and u.placed and u.x == t.x and u.y == t.y:
			return u
	return null


func _is_occupied(t: Vector2i, ignore: Node2D = null,
		pass_allies := false, mover: Node2D = null) -> bool:
	for u in units:
		if u == ignore or not u.alive or not u.placed:
			continue
		if pass_allies and mover != null and same_faction(u,mover):
			continue
		if u.x == t.x and u.y == t.y:
			return true
	return false


func _on_map_click(t: Vector2i) -> void:
	_trace_input("tile", {"tile":[t.x,t.y],"mode":mode,
		"blue":move_tiles.has(t),"red":attack_tiles.has(t)})
	if not _in_bounds(t):return
	if mode.begins_with("mine_"):
		_mine_click(t);return
	if mode=="item_give":
		_execute_item_transfer(t);return
	if mode in ["skill","item","attack"]:
		# Native target clicks test833418, not occupancy or an enemy-only set.
		# Invalid clicks leave the range untouched; only right cancel leaves it.
		if not RangeMask.allows(native_dark_mask,map_w,map_h,t):return
		match mode:
			"skill":_execute_skill_at(t)
			"item":_execute_item_at(t)
			"attack":_perform_attack_at(selected,t)
		return
	if native_range_phase=="move" and selected!=null:
		if RangeMask.allows(native_dark_mask,map_w,map_h,t):_player_move(t)
		return
	if native_range_phase=="menu" and selected!=null:
		_open_context_menu();return
	var u:=_unit_at(t)
	if u!=null and u.alive:
		_select_unit(u)
		if not u.is_player() or not u.control or u.acted:_open_unit_info()
	else:_clear_selection()


func _trace_input(kind: String, details: Dictionary) -> void:
	var rec := details.duplicate(true)
	rec["kind"] = kind
	rec["turn"] = turn
	if camera != null:
		rec["camera"] = [camera.position.x, camera.position.y]
		rec["zoom"] = camera.zoom.x
	input_history.append(rec)
	if input_history.size() > 120:
		input_history.pop_front()


func _focus_player() -> void:
	var u = _camera_focus_unit()
	if u != null:
		_select_unit(u)
		camera.position = _focus_position(u.position)
		_clamp_camera()


func _set_native_range(mask:PackedByteArray,range_phase:String) -> void:
	touch_cancel()
	native_dark_mask=mask
	native_range_phase=range_phase
	if is_instance_valid(native_range_layer):
		# Clearing the native mask is synchronous before MENU saves its rect.
		# queue_redraw alone leaves the old dark canvas until the next frame,
		# so force_draw during menu entry could capture stale range pixels.
		native_range_layer.visible=mask.count(1)>0
		native_range_layer.queue_redraw()
	if is_instance_valid(overlay):overlay.queue_redraw()
	presentation_step.emit("range_mask",{"phase":range_phase,"dark_count":mask.count(1)})


func _clear_native_range(range_phase:="idle") -> void:
	_set_native_range(RangeMask.cleared(map_w,map_h),range_phase)


func _target_native_range(u,range_id:int,force_self:bool,range_phase:String) -> void:
	var matrix:Array=data.get("select_ranges",{}).get(str(range_id),[])
	_set_native_range(RangeMask.selection(map_w,map_h,Vector2i(u.x,u.y),matrix,force_self),range_phase)


func _select_unit(u: Node2D) -> void:
	if selected!=null and is_instance_valid(selected):selected.set_selected(false)
	selected=u
	camera_follow=true;camera_follow_target=u
	u.set_selected(true)
	mode="idle"
	move_tiles.clear();attack_tiles.clear()
	_selection_origin={"slot":u.slot,"x":u.x,"y":u.y,"direction":u.direction,"moved":u.moved}
	# 41F424 builds a movement mask even for inspected/noncontrolled units.
	var reachable:=compute_reachable(u)
	_set_native_range(RangeMask.movement(map_w,map_h,Vector2i(u.x,u.y),reachable),"move")
	if u.is_player() and not u.acted and u.control:
		if not u.moved:move_tiles=reachable;mode="move"
		else:_clear_native_range("menu")
	_log("%s：HP %d/%d"%[u.unit_name,u.hp,u.max_hp])
	update_hud()


func _clear_selection() -> void:
	_close_context_menu()
	if selected!=null and is_instance_valid(selected):selected.set_selected(false)
	selected=null
	_selection_origin.clear()
	camera_follow=true;camera_follow_target=null
	mode="idle"
	move_tiles.clear();attack_tiles.clear()
	_clear_native_range()
	update_hud()


func _cancel_action_menu() -> void:
	# 41FC6E cancellation restores pre-move coordinates/direction/occupancy.
	if selected!=null and is_instance_valid(selected) and not selected.acted and int(_selection_origin.get("slot",-1))==int(selected.slot):
		selected.set_tile(int(_selection_origin.x),int(_selection_origin.y))
		selected.direction=int(_selection_origin.direction)
		selected.moved=bool(_selection_origin.moved)
		selected.refresh()
	_clear_selection()


func _cancel() -> void:
	if busy or phase!="player":return
	if is_instance_valid(context_menu):
		var was_action:=_context_is_action
		_close_context_menu()
		if was_action:_cancel_action_menu()
		return
	if action_panel!=null:
		_close_action_panel()
		if native_range_phase=="menu":_open_context_menu()
		update_hud();return
	if mode in ["attack","skill","item","item_give"] or mode.begins_with("mine_"):
		mode="idle";active_skill={};active_skill_id=-1;active_item_id=-1
		move_tiles.clear();attack_tiles.clear()
		_clear_native_range("menu")
		_open_context_menu();update_hud()
	elif native_range_phase=="menu":_cancel_action_menu()
	else:_clear_selection()


func _focus_next_side() -> void:
	if camera == null:
		return
	# 轮流跳到最近的敌人 / 我方单位
	var candidates: Array = []
	if phase == "player":
		candidates = enemy_units
	else:
		candidates = player_units
	var alive: Array = []
	for u in candidates:
		if u.alive:
			alive.append(u)
	if alive.is_empty():
		return
	focus_cycle = (focus_cycle + 1) % alive.size()
	var u = alive[focus_cycle]
	camera_follow = true
	camera_follow_target = u
	camera.position = _focus_position(u.position)
	_clamp_camera()
	_log("镜头：%s" % u.unit_name)


# ---------------- 范围 / 移动 ----------------

func move_cost(bz: int, terr: int) -> int:
	var rows: Dictionary = data.get("unit_move", {})
	var row = rows.get(str(bz), [])
	if terr < 0 or terr >= row.size():
		return 1
	var c := int(row[terr])
	if c <= 0 or c >= 99:
		return 99
	return c


func compute_reachable(u: Node2D) -> Dictionary:
	var start := Vector2i(u.x, u.y)
	var dist := {start: 0}
	var prev := {}
	var open: Array = [start]
	while not open.is_empty():
		var best_i := 0
		for i in range(1, open.size()):
			if int(dist[open[i]]) < int(dist[open[best_i]]):
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		# 418E29：起点可离开ZOC，其他进入敌军四邻格便停止扩散。
		var zoc := false
		if cur != start:
			for d in DIRS:
				var neighbor = _unit_at(cur + d)
				if neighbor != null and not same_faction(neighbor,u):
					zoc = true
		if zoc:
			continue
		for d in DIRS:
			var n: Vector2i = cur + d
			if not _in_bounds(n):
				continue
			var occupant = _unit_at(n)
			if occupant != null and occupant != u and not same_faction(occupant,u):
				continue
			var cost := move_cost(u.bingzhong, _terrain_at(n))
			var nd := int(dist[cur]) + cost
			if cost >= 99 or nd > u.move:
				continue
			if not dist.has(n) or nd < int(dist[n]):
				dist[n] = nd
				prev[n] = cur
				if not open.has(n):
					open.append(n)
	for t in dist.keys():
		if t == start or _unit_at(t) != null:
			dist.erase(t)
	move_prev = prev
	return dist


func _path_to(t: Vector2i, start: Vector2i) -> Array:
	var path: Array = []
	var cur := t
	while cur != start:
		path.append(cur)
		if not move_prev.has(cur):
			return []
		cur = move_prev[cur]
	path.reverse()
	return path


func _update_objective_guide() -> void:
	if objective_guide == null or objective_guide_bg == null:
		return
	if scenario == null or finished_flag:
		objective_guide.visible = false
		objective_guide_bg.visible = false
		return
	var target: Vector2i = scenario.primary_target_tile()
	if target.x < 0:
		objective_guide.visible = false
		objective_guide_bg.visible = false
		return
	var anchor = scenario.protagonist
	if anchor == null or not is_instance_valid(anchor) or not anchor.alive:
		for p in player_units:
			if p.alive:
				anchor = p
				break
	if anchor == null:
		objective_guide.visible = false
		objective_guide_bg.visible = false
		return
	var dx := target.x - int(anchor.x)
	var dy := target.y - int(anchor.y)
	var dir := ""
	if dx > 0:
		dir += "东"
	elif dx < 0:
		dir += "西"
	if dy < 0:
		dir += "北"
	elif dy > 0:
		dir += "南"
	if dir == "":
		dir = "目标"
	var dist := maxi(absi(dx), absi(dy))
	objective_guide_bg.visible = true
	objective_guide.visible = true
	objective_guide.text = "目标：%s %d格    亮格=当前可选范围" % [dir, dist]


func attack_radius(u: Node2D) -> int:
	var ranges: Dictionary = data.get("select_ranges",{})
	var matrix: Array = ranges.get(str(u.select),[])
	var radius := 0
	if matrix.size() < 9: return 0
	for y in range(-4,5):
		for x in range(-4,5):
			if int(matrix[y+4][x+4]) > 0: radius = maxi(radius,maxi(absi(x),absi(y)))
	return radius


func attack_targets(u: Node2D) -> Dictionary:
	var out := {}
	var ranges: Dictionary = data.get("select_ranges",{})
	var matrix: Array = ranges.get(str(u.select),[])
	if matrix.size() < 9: return out
	for y in range(-4,5):
		for x in range(-4,5):
			if int(matrix[y+4][x+4]) != 1: continue
			var tile := Vector2i(u.x+x,u.y+y)
			var target = _unit_at(tile)
			if target != null and not same_faction(target,u): out[tile] = target
	return out


func _player_move(t: Vector2i) -> void:
	if selected == null or busy:
		return
	var u = selected
	if not u.alive or not u.is_player() or not u.control or u.acted or u.moved:return
	var start := Vector2i(u.x, u.y)
	var path := _path_to(t, start)
	_trace_input("move", {"from": [start.x, start.y], "to": [t.x, t.y],
			"path_length": path.size(), "moved": u.moved, "acted": u.acted})
	if path.is_empty() and t!=start:
		_log("该格当前不可达，请重新选择单位刷新范围")
		return
	busy = true
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	update_hud()
	_play_sfx(int(unit_class(u).get("audio_yidong", -1)), -10.0)
	for step in path:
		await u.move_visual(step.x, step.y, 0.075)
		if await _trigger_mine(step, u):
			u.acted = true
			break
	_clear_native_range("menu")
	u.moved = true
	u.refresh()
	attack_tiles.clear()
	await _wait_for_progress_fx()
	_log("%s 移动到 (%d,%d)" % [u.unit_name, u.x, u.y])
	# Ordinary movement is still reversible in 41FC6E. Commit pickup/T510
	# only after an action; a mine interruption has already spent that action.
	if u.acted:
		await _after_completed_action(u)
		# A mine commits the action instead of opening the reversible move menu.
		# Leaving selected+"menu" here swallows every later map click, because
		# _open_context_menu correctly refuses an acted/dead actor.
		if selected==u:_clear_selection()
	busy = finished_flag
	_trace_resolution("player_move_done",int(u.slot),Vector2i(u.x,u.y))
	update_hud()
	if u.alive and not u.acted and not finished_flag: _open_context_menu()


# ---------------- 攻击 ----------------

func compute_damage(attacker: Node2D, defender: Node2D) -> int:
	return clampi(maxi(defender.hp / 20, CombatRules.damage(_effective_attack(attacker),
			_effective_defense(defender))), 1, defender.hp)


func _attack_anim(attacker: Node2D, defender: Node2D) -> void:
	if attacker.has_method("play_attack"):
		await attacker.play_attack(not fast_sim and animations_enabled and (DisplayServer.get_name()!="headless" or presentation_in_headless))


func _perform_attack(attacker: Node2D, defender: Node2D, _counter: bool = false) -> void:
	if attacker == null or defender == null or not attacker.alive or not defender.alive or same_faction(attacker,defender):
		return
	await _perform_attack_at(attacker,Vector2i(defender.x,defender.y))


func _perform_attack_at(attacker:Node2D,tile:Vector2i) -> void:
	if attacker==null or not attacker.alive or not _in_bounds(tile):return
	busy=true
	action_resolution_depth+=1
	mode="idle"
	move_tiles.clear();attack_tiles.clear()
	_clear_native_range("action")
	update_hud()
	_play_sfx(int(unit_class(attacker).get("audio_gongji",-1)))
	var facing:=_face_target(attacker,tile)
	# Freeze the same area for animation and resolution before per-victim
	# practice/XP can change the attacker. This also matches the aim preview.
	var cells:=normal_attack_cells(attacker,tile,facing)
	attacker.display_action_lock=true
	await _attack_anim(attacker, _unit_at(tile))
	# 4212A7 vs4043EA: player becomes s0 before FLM/damage; AI after.
	if phase=="player":attacker.display_state=0;attacker.refresh()
	await _play_action_effect("",int(unit_class(attacker).get("flm_gongji",-1)),Vector2(tile*TILE+Vector2i(24,24)),cells,-1)
	await _resolve_attack_at(attacker,tile,facing,cells)
	attacker.display_action_lock=false
	attacker.display_state=0;attacker.refresh()
	await _wait_for_progress_fx()
	action_resolution_depth -= 1
	busy = finished_flag
	update_hud()
	if not _check_end() and selected != null and is_instance_valid(selected) and selected.acted:
		_clear_selection()
	await _after_completed_action(attacker)


func _resolve_attack(attacker, defender, facing: int) -> void:
	await _resolve_attack_at(attacker,Vector2i(defender.x,defender.y),facing)


func normal_attack_cells(attacker,center:Vector2i,facing:int) -> Array:
	var apply:=CombatRules.attack_apply(int(unit_class(attacker).get("apply",0)),int(attacker.attack_count))
	return _apply_tiles(center,apply,facing)


func attack_preview_cells() -> Array:
	if mode!="attack" or busy or phase!="player" or finished_flag or progress_fx_active:return []
	if is_instance_valid(action_panel) or is_instance_valid(context_menu):return []
	if selected==null or not is_instance_valid(selected) or not selected.alive or selected.acted:return []
	if not attack_tiles.has(hover_tile):return []
	return normal_attack_cells(selected,hover_tile,_facing(Vector2i(selected.x,selected.y),hover_tile))


func _resolve_attack_at(attacker,center:Vector2i,facing:int,cells=null) -> void:
	var base_xp := 0
	var kill_xp := 0
	var attack_power := _effective_attack(attacker)
	if cells==null:cells=normal_attack_cells(attacker,center,facing)
	var deaths: Array = []
	# 41307F：使用兵种原始作用模板，先累计命中经验cap48，再加击杀经验；无反击。
	for cell in cells:
		var target = _unit_at(cell["tile"])
		if target == null or same_faction(target,attacker):
			continue
		var dmg := mini(int(target.hp), maxi(1, maxi(int(target.hp) / 20,
				CombatRules.damage(attack_power, _effective_defense(target), int(cell["pct"])))))
		base_xp += CombatRules.hit_experience(int(attacker.data.get("level", 1)), int(target.data.get("level", 1))) >> (0 if attacker.side == "player" else 2)
		attacker.attack_count += 1
		target.data["last_attacker_slot"] = int(attacker.slot)
		var died := _apply_hp_damage(target, dmg, "gun")
		_log("%s 攻击 %s，造成 %d 伤害（士气 %d）" % [attacker.unit_name, target.unit_name, dmg, target.morale])
		if died:
			deaths.append(target)
	attacker.acted = true
	attacker.refresh()
	await _wait_damage_numbers("attack")
	var penalty := false
	for target in deaths:
		_retire_unit(target)
		kill_xp += CombatRules.kill_experience(int(attacker.data.get("level", 1)), int(target.data.get("level", 1)))
		_collect_native_casualty_loot(target)
		penalty = _record_unit_loss(target) or penalty
		await _complete_unit_death(target)
	if penalty: await _play_loss_penalty()
	await _gain_xp(attacker, mini(48, base_xp) + kill_xp)

func _player_attack(target: Node2D) -> void:
	if selected == null or busy:
		return
	var attacker = selected
	await _perform_attack(attacker, target)


func _retire_unit(u: Node2D) -> void:
	# Original death loops mark stage inactive before this death's XP/stat work.
	u.alive = false
	presentation_step.emit("inactive", {"slot":u.slot})


func _collect_native_casualty_loot(u:Node2D) -> void:
	# 42AFD2: side!=0, eight carried item WORDs -> temporary WORD counts.
	# Called by gun/skill/item deaths and scripted clear, NOT mine deaths.
	# Source slots remain intact; this is not pickup, practice, or a notice.
	if unit_faction(u)==0:return
	var loot:Dictionary=battle_context.get("temporary_loot",{})
	for raw in u.item_slots:
		if int(raw)==0:continue
		var key:=str(int(raw)-1)
		loot[key]=(int(loot.get(key,0))+1)&0xffff
	battle_context["temporary_loot"]=loot


func _loss_penalty(u: Node2D, item_order := false) -> bool:
	if u.side != "player" or u.slot >= 32 or (u.slot == 0 and not item_order):return false
	var difficulty := int(level.get("difficulty_setting", 1))
	if difficulty != 2 and not (difficulty == 1 and int(stats.get("losses",0)) < 3):return false
	for hero in units:
		if hero.slot != 0:continue
		hero.data["level"] = maxi(1, int(hero.data.get("level", 1)) - 1)
		hero.max_hp = maxi(1, int(unit_class(hero).get("tili", 50)) + (int(hero.data["level"]) - 1) * int(unit_class(hero).get("tili_plus", 0)))
		hero.hp = mini(int(hero.hp), int(hero.max_hp))
		hero.refresh()
		presentation_step.emit("penalty_commit", {"slot":hero.slot,"level":hero.data.level})
		return true
	return false


func _record_unit_loss(u: Node2D, item_order := false) -> bool:
	# 415C35 tests loss-count BEFORE increment; attack/skill/mine test AFTER.
	var penalty := _loss_penalty(u,true) if item_order else false
	stats["kills" if u.side == "enemy" else "losses"] = int(stats.get("kills" if u.side == "enemy" else "losses", 0)) + 1
	if u.side == "enemy":
		var key := "kills_by_mine" if str(u.last_damage_kind) == "mine" else "kills_by_gun"
		stats[key] = int(stats.get(key,0)) + 1
	if not item_order:penalty = _loss_penalty(u)
	return penalty


func _play_loss_penalty() -> void:
	var hero = unit_by_slot(0)
	if hero == null:return
	presentation_step.emit("penalty_fx", {"slot":0})
	var old_camera := camera.position if camera != null else Vector2.ZERO
	var old_follow := camera_follow
	if camera != null and not fast_sim and animations_enabled:
		camera_follow = false
		camera.position = _focus_position(hero.position)
		_clamp_camera()
		camera.force_update_scroll()
	_queue_progress_flm(31,hero.position,18)
	await _wait_for_progress_fx()
	if camera != null:
		camera.position = old_camera
		camera_follow = old_follow
		camera.force_update_scroll()


func _complete_unit_death(u: Node2D) -> void:
	_play_death_mix(u)
	u.disappear()
	presentation_step.emit("death_end", {"slot":u.slot})
	_log("%s 阵亡" % u.unit_name)
	if scenario != null:
		await scenario.on_unit_died(u)
		if finished_flag:return
	for name in level.get("fail_units", []):
		if u.unit_name == str(name):
			_finish("defeat", "%s 阵亡" % u.unit_name)
			return
	_check_end()


func _play_death_mix(u: Node2D) -> void:
	if fast_sim or not animations_enabled or (DisplayServer.get_name()=="headless" and not presentation_in_headless):return
	var index_path:=str(level.map.png).replace(".png","_index.png")
	if not ResourceLoader.exists(index_path) or not data.meta.has("battle_palette"):return
	var tile:=Vector2i(u.x,u.y)
	if not _in_bounds(tile):return
	var clip:=map_rect()
	var screen:Vector2=get_global_transform_with_canvas()*Vector2(tile*TILE)
	if not clip.intersects(Rect2(screen,Vector2(48,48))):return
	var Mix=preload("res://scripts/battle/OriginalDeathMix.gd")
	var source:Dictionary=Mix.sources(index_path)
	var frame:int=u.native_frame()
	# Same world mask as4170AA, independent of modern target dictionaries.
	var layers:Dictionary={"chests":chests,"box":source.box,"mine":source.mine,
		"mine_present":mines.any(func(m):return m.tile==tile),"behavior":u.behavior,
		"luan_glyph":PackedByteArray(data.meta.get("luan_glyph",[])),
		"dark":native_dark_mask[tile.y*map_w+tile.x]!=0,
		"dark_lut":PackedByteArray(data.meta.map_dark_lut)}
	var buffers:Dictionary=Mix.tile_buffers(source.map,map_w,tile,source.army,int(unit_class(u).img_index),frame,layers)
	u.disappear()
	var texture:=ImageTexture.create_from_image(Mix.rgba(buffers.old,data.meta.battle_palette))
	# A Sprite2D queue_redraw is deferred until the next SceneTree frame. Native
	# blits must be visible *within* this synchronous transaction, so submit a
	# direct canvas command instead of yielding33 frames to flush that queue.
	var material:=_effect_clip_material()
	var canvas_item:=RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(canvas_item,fx_root.get_canvas_item())
	RenderingServer.canvas_item_set_transform(canvas_item,Transform2D(0.0,Vector2(tile*TILE)))
	RenderingServer.canvas_item_set_material(canvas_item,material.get_rid())
	RenderingServer.canvas_item_add_texture_rect(canvas_item,Rect2(0,0,48,48),texture.get_rid())
	presentation_step.emit("death_mix_start",{"slot":u.slot})
	var indices:=PackedByteArray()
	# 4240B9 performs synchronous blits, with no Sleep, timer, shrink or fixed
	# vsync count. force_draw submits each blit without yielding input/actions.
	for i in range(33):
		indices=Mix.frame_indices(buffers.old,buffers.new,i,source.lut)
		texture.update(Mix.rgba(indices,data.meta.battle_palette))
		if DisplayServer.get_name()!="headless":
			RenderingServer.force_sync()
			RenderingServer.force_draw()
		presentation_step.emit("death_mix_frame",{"slot":u.slot,"weight":i*8})
	indices=Mix.final_indices(indices,buffers.new)
	texture.update(Mix.rgba(indices,data.meta.battle_palette))
	if DisplayServer.get_name()!="headless":
		RenderingServer.force_sync()
		RenderingServer.force_draw()
	presentation_step.emit("death_mix_end",{"slot":u.slot})
	RenderingServer.free_rid(canvas_item)


func _on_unit_died(u: Node2D) -> void:
	# Compatibility entry for isolated fixtures. Action resolvers explicitly
	# arrange inactive / XP / penalty / disappearance according to action kind.
	if u == null or not u.alive:return
	_retire_unit(u)
	if _record_unit_loss(u):_play_loss_penalty()
	await _complete_unit_death(u)


func _queue_damage_number(value:int,world:Vector2,channel:String,recovery:=false) -> void:
	if value==0:return
	_pending_numbers.append({"value":value,"world":world,"channel":channel,"recovery":recovery})


func _wait_damage_numbers(kind: String) -> void:
	presentation_step.emit("numbers_start", {"kind":kind})
	var numbers := _pending_numbers
	_pending_numbers = []
	if not fast_sim and animations_enabled and (DisplayServer.get_name()!="headless" or presentation_in_headless):
		var labels: Array = []
		for number in numbers:
			var label := Label.new()
			label.text = str(number.value)
			label.add_theme_font_override("font",font)
			label.add_theme_font_size_override("font_size",16)
			label.add_theme_color_override("font_color",Color("#6bff8a") if number.recovery else (Color("#ff6b6b") if number.channel=="hp" else Color("#d18cff")))
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.material = _effect_clip_material()
			fx_root.add_child(label)
			labels.append(label)
		# Original loops run even for empty/missed effects: 32 x 4259CC(32),
		# independent of FLM speed. Do not fade numeric text before this ends.
		for frame in range(32):
			for i in range(labels.size()):
				var number:Dictionary=numbers[i]
				var y:int=8-2*frame
				if kind in ["skill","item"]:
					y=(-24+frame if number.recovery else -8-frame)+(16 if number.channel=="morale" else 0)
				labels[i].position=number.world+Vector2(-8,y)
			await _wait_presentation_time(0.032)
		for label in labels:label.queue_free()
	for unit in units:unit.restore_damage_display()
	presentation_step.emit("numbers_end", {"kind":kind})


func _check_end() -> bool:
	if finished_flag:
		return true
	if scenario != null:
		return scenario.check_end()
	# 没有 objective 的 M1 回退
	if _alive_count(enemy_units) == 0:
		_finish("victory", str(level.get("success", "全歼敌人")))
		return true
	if _alive_count(player_units) == 0:
		_finish("defeat", "我军全灭")
		return true
	return false


func _alive_count(arr: Array) -> int:
	var n := 0
	for u in arr:
		if u.alive:
			n += 1
	return n


# ---------------- 数值 / 库存 ----------------

func unit_class(u: Node2D) -> Dictionary:
	var ut = data.get("unit_types", {})
	if ut is Array:
		var arr: Array = ut
		if u.bingzhong >= 0 and u.bingzhong < arr.size():
			return arr[u.bingzhong]
		return {}
	if ut is Dictionary:
		return (ut as Dictionary).get(str(u.bingzhong), {})
	return {}


func unit_faction(u) -> int:
	return int(u.data.get("faction",0 if u.side=="player" else 1))


func same_faction(a,b) -> bool:
	# 418C7C/40251A compare exact People.side, not just friendly vs enemy.
	return unit_faction(a)==unit_faction(b)


func terrain_bonus(t: Vector2i) -> int:
	var mods: Array = data.get("terrain_modifiers", [])
	var idx := _terrain_at(t)
	if idx < 0 or idx >= mods.size():
		return 0
	var m = mods[idx]
	if m is Array and m.size() >= 3:
		return int(m[2])
	return 0


func _inventory_count(kind: String, id: int) -> int:
	return int(_carried_stock(selected, kind).get(str(id), 0))


func _carried_stock(u, kind: String) -> Dictionary:
	var out := {}
	if u == null or not is_instance_valid(u):
		return out
	var slots: Array = u.mine_slots if kind == "mines" else u.item_slots
	for raw in slots:
		if int(raw) > 0:
			var key := str(int(raw) - 1)
			out[key] = int(out.get(key, 0)) + 1
	return out


func _consume_inventory(kind: String, id: int) -> bool:
	if selected == null:
		return false
	var slots: Array = selected.mine_slots if kind == "mines" else selected.item_slots
	var index := slots.find(id + 1)
	if index < 0:
		return false
	InventorySlots.remove_id(slots,id+1)
	_refresh_equipment(selected)
	_refresh_mine_left()
	return true


func _compact_mine_slots(u) -> void:
	InventorySlots.compact(u.mine_slots)


func _add_carried_mine(u,code:int) -> bool:
	var index:int=u.mine_slots.find(0)
	if index<0:return false
	u.mine_slots[index]=code+1
	_compact_mine_slots(u)
	return true


func _refresh_mine_left() -> void:
	mines_left = 0
	for u in player_units:
		for raw in u.mine_slots:
			if int(raw) > 0:
				mines_left += 1


func _gain_xp(u: Node2D, amount: int) -> void:
	if u == null or amount <= 0:return
	u.gained_xp += amount
	if u.side == "player":stats["xp"] = int(stats.get("xp", 0)) + amount
	var xp := int(u.data.get("xp", 0)) + amount
	var lv := int(u.data.get("level", 1))
	u.data["xp"] = xp
	presentation_step.emit("xp_start", {"slot":u.slot,"amount":amount,"level":lv,"xp":xp})
	if xp / 100 > 0:
		var old_camera := camera.position if camera != null else Vector2.ZERO
		var old_follow := camera_follow
		if camera != null and not fast_sim and animations_enabled:
			camera_follow = false
			camera.position = _focus_position(u.position)
			_clamp_camera()
			camera.force_update_scroll()
		_queue_progress_flm(30,u.position,15,100)
		await _wait_for_progress_fx()
		if camera != null:
			camera.position = old_camera
			camera_follow = old_follow
			camera.force_update_scroll()
	u.data["xp"] = xp % 100
	u.data["level"] = mini(99,lv+xp/100)
	u.max_hp = maxi(1, int(unit_class(u).get("tili", 50)) + (int(u.data.level) - 1) * int(unit_class(u).get("tili_plus", 0)))
	u.hp = mini(int(u.hp), int(u.max_hp))
	u.refresh()
	presentation_step.emit("xp_commit", {"slot":u.slot,"level":u.data.level,"xp":u.data.xp})


func _attack_level(u: Node2D) -> int:
	return CombatRules.skill_level(int(u.attack_count))


func _terrain_defense(u: Node2D) -> int:
	return terrain_bonus(Vector2i(u.x, u.y))


func _effective_defense(u: Node2D) -> int:
	return CombatRules.defense_power(u.data, unit_class(u), u.morale,
			_terrain_defense(u), u.defense_bonus, u.defense_integrity)


func _effective_attack(u: Node2D) -> int:
	return CombatRules.attack_power(u.data, unit_class(u), u.morale, u.integrity,
			int(u.attack_count), u.attack_bonus)


func _morale_loss(damage: int, max_hp: int) -> int:
	return max(1, 20 * damage / max(1, max_hp))


func _apply_hp_damage(target: Node2D, damage: int, kind: String = "") -> bool:
	target.last_damage_kind = kind
	var actual := mini(int(target.hp), maxi(0, damage))
	target.take_damage(actual)
	# 仅普攻伤害隐式降低士气，技能/投掷/地雷各自处理第二渠道。
	if kind == "gun" and actual > 0:
		target.morale = maxi(0, int(target.morale) - _morale_loss(actual, target.max_hp))
	if kind!="skill":_queue_damage_number(actual,target.position,"hp")
	return target.hp <= 0 or target.morale <= 0


func _mine_at(t: Vector2i) -> int:
	for i in range(mines.size()):
		if mines[i]["tile"] == t:
			return i
	return -1


func can_mine(u: Node2D) -> bool:
	if u == null or phase != "player" or busy or finished_flag or not u.is_player() or not u.control or u.acted:
		return false
	# 41FF39 opens all five operations even with no carried/map mines.
	return true


func _mine_place_tiles(u, code: int) -> Dictionary:
	var out := {}
	if int(level.get("index", -1)) in [14, 17]:
		return out
	var rows: Array = data.get("mine_terrain", [])
	var row := code / 4
	if row < 0 or row >= rows.size():
		return out
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var t := Vector2i(u.x + dx, u.y + dy)
			if not _in_bounds(t) or _unit_at(t) != null or _mine_at(t) >= 0:
				continue
			var terr := _terrain_at(t)
			if terr >= 0 and terr < rows[row].size() and int(rows[row][terr]) != 0:
				out[t] = 1
	return out


func _place_mine(tile := Vector2i(-1, -1), rounds := 1) -> void:
	if selected == null or _inventory_count("mines", mine_kind) <= 0:
		return
	var allowed := _mine_place_tiles(selected, mine_kind)
	if not allowed.has(tile):
		mode = "mine_place"
		move_tiles.clear()
		attack_tiles = allowed
		_set_native_range(RangeMask.from_cells(map_w,map_h,allowed.keys()),"mine-target")
		_log("选择周围空格埋设地雷" if not allowed.is_empty() else "本关或周围地形不允许埋设")
		update_hud()
		return
	var m:Dictionary=data["mines"][mine_kind%10]
	# 4208C4 commits low, clears mask, then commits high/inventory/state.
	var placed_record:Dictionary={"tile":tile,"mine":m,"mine_id":mine_kind%10,"code":0,
		"low":rounds+1 if mine_kind/10==2 else 1,"owner_side":selected.side,
		"apply_fw":int(m.get("apply_fw",0))}
	mines.append(placed_record)
	_clear_native_range("action")
	placed_record.code=mine_kind
	_consume_inventory("mines",mine_kind)
	_draw_mine(placed_record)
	_log("%s 埋设%s%s" % [selected.unit_name, ["普通", "引爆", "定时", "遥控"][mine_kind / 10], m.get("name", "地雷")])
	_finish_mine_action()


func _draw_mine(record: Dictionary) -> void:
	var tile: Vector2i = record["tile"]
	var texture:Texture2D=load("res://assets/palette/mine_map.png")
	if texture != null:
		if mine_nodes.has(tile) and is_instance_valid(mine_nodes[tile]):mine_nodes[tile].queue_free()
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position = Vector2(tile.x * TILE + 24, tile.y * TILE + 24)
		sprite.z_index = -1
		units_root.add_child(sprite)
		mine_nodes[tile] = sprite


func _finish_mine_action() -> void:
	_clear_native_range()
	_selection_origin.clear()
	var caster = selected
	if selected != null:
		selected.acted = true
		selected.refresh()
	mode = "idle"
	attack_tiles.clear()
	move_tiles.clear()
	update_hud()
	if caster != null: _after_completed_action(caster)


func _mine_command(command: String) -> void:
	_close_action_panel()
	if selected == null:
		return
	if command == "place":
		_open_mine_menu()
		return
	if command == "give":
		_open_carried_mine_picker(true)
		return
	mode = "mine_" + command
	_set_native_range(RangeMask.mine_geometry(map_w,map_h,Vector2i(selected.x,selected.y),command=="remote"),"mine-target")
	move_tiles.clear()
	attack_tiles.clear()
	for rec in mines:
		var t: Vector2i = rec["tile"]
		var d := absi(t.x - int(selected.x)) + absi(t.y - int(selected.y))
		var adjacent := maxi(absi(t.x - int(selected.x)), absi(t.y - int(selected.y))) == 1
		if (command == "remote" and d >= 1 and d <= 5 and int(rec.get("code", rec.get("mine_id", 0))) / 10 == 3) or (adjacent and (command == "recover" or (command == "timer" and int(rec.get("low", 1)) > 1))):
			attack_tiles[t] = 1
	_log("选择地雷目标" if not attack_tiles.is_empty() else "范围内没有可操作的地雷")
	update_hud()


func _choose_mine_transfer(code: int) -> void:
	_close_action_panel()
	mine_kind = code
	mode = "mine_give"
	_set_native_range(RangeMask.mine_geometry(map_w,map_h,Vector2i(selected.x,selected.y)),"mine-target")
	move_tiles.clear()
	attack_tiles.clear()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var t := Vector2i(selected.x + dx, selected.y + dy)
			var target = _unit_at(t)
			if target != null and target != selected:
				attack_tiles[t] = target
	update_hud()


func _choose_timer(tile: Vector2i, placing: bool) -> void:
	_close_context_menu();_close_action_panel()
	var picker=preload("res://scripts/ui/OriginalChoice.gd").new()
	hud_root.add_child(picker);action_panel=picker
	picker.chosen.connect(func(index:int):_set_mine_timer(tile,index+1,placing))
	# Timer cancellation only closes this popup: retain target mode/mask,
	# inventory and low. Swallow the matching right-UP before map handling.
	picker.cancelled.connect(func():_ignore_right_release=true;_close_action_panel())
	picker.setup(font,["一回合","二回合","三回合","四回合","五回合","六回合","七回合","八回合","九回合","十回合"],Vector2(276,112))


func _set_mine_timer(tile: Vector2i, rounds: int, placing: bool) -> void:
	_close_action_panel()
	if placing:
		_place_mine(tile, rounds)
	else:
		var index := _mine_at(tile)
		if index >= 0 and int(mines[index].get("low", 1)) > 1:
			_clear_native_range("action")
			mines[index]["low"] = rounds + 1
			_finish_mine_action()


func _mine_click(tile: Vector2i) -> void:
	if not RangeMask.allows(native_dark_mask,map_w,map_h,tile):return
	match mode:
		"mine_place":
			if mine_kind / 10 == 2:
				_choose_timer(tile, true)
			else:
				_place_mine(tile)
		"mine_recover":
			var index:=_mine_at(tile)
			if index<0 or int(mines[index].get("low",1))==0:return
			var code:=int(mines[index].get("code",mines[index].get("mine_id",0)))
			_clear_native_range("action")
			_remove_mine(index)
			if not _add_carried_mine(selected,code):_log("携带已满，起出的地雷丢失")
			_finish_mine_action()
		"mine_timer":
			var index:=_mine_at(tile)
			if index>=0 and int(mines[index].get("low",1))>1:_choose_timer(tile,false)
		"mine_remote":
			var index:=_mine_at(tile)
			if index<0 or int(mines[index].get("low",1))==0 or int(mines[index].get("code",mines[index].get("mine_id",0)))/10!=3:return
			_clear_native_range("action")
			await _detonate_mines(tile)
			_finish_mine_action()
		"mine_give":
			var target = _unit_at(tile)
			if target==null:return
			_clear_native_range("action")
			if _consume_inventory("mines",mine_kind):
				if not _add_carried_mine(target,mine_kind):_log("对方携带已满，交给的地雷丢失")
				_finish_mine_action()


func _effect_clip_material() -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=preload("res://scripts/battle/EffectClip.gdshader")
	var rect:=map_rect()
	var viewport:=get_viewport_rect().size
	material.set_shader_parameter("clip_bounds",Vector4(rect.position.x/viewport.x,rect.position.y/viewport.y,rect.end.x/viewport.x,rect.end.y/viewport.y))
	return material


func _play_anm_sheet(path: String, world: Vector2) -> void:
	if path.is_empty() or fast_sim or not animations_enabled or (DisplayServer.get_name()=="headless" and not presentation_in_headless) or not ResourceLoader.exists(path):return
	var tex:Texture2D=load(path)
	if tex==null:return
	var n:=int(tex.get_width()/320)
	if n<=0:return
	var frames:=SpriteFrames.new()
	frames.remove_animation("default");frames.add_animation("default")
	frames.set_animation_speed("default",20.0)
	frames.set_animation_loop("default",false)
	for i in range(n):
		var at:=AtlasTexture.new();at.atlas=tex;at.region=Rect2(i*320,0,320,200)
		frames.add_frame("default",at)
	var anim:=AnimatedSprite2D.new()
	anim.sprite_frames=frames;anim.position=world;anim.scale=Vector2.ONE
	anim.material=_effect_clip_material();anim.visible=false
	fx_root.add_child(anim)
	presentation_step.emit("anm_begin",{"path":path,"frames":n})
	# 426451 waits 50ms BEFORE each decoded frame, independent of FLM speed.
	# Battle sheets contain N-1 records (404AA7); do not subtract again here.
	for i in range(n):
		await _wait_presentation_time(0.05)
		anim.frame=i;anim.visible=true
		presentation_step.emit("anm_frame",{"path":path,"frame":i})
	await get_tree().process_frame
	anim.queue_free()
	presentation_step.emit("anm_end",{"path":path,"frames":n})


func _play_action_effect(path:String,flm:int,world:Vector2,cells:Array,wave:int) -> void:
	_play_sfx(wave)
	if fast_sim or not animations_enabled or (DisplayServer.get_name()=="headless" and not presentation_in_headless):return
	await _play_anm_sheet(path,world)
	var duration:=0.0
	for cell in cells:
		var tile:Vector2i=cell.tile
		duration=maxf(duration,_play_flm(flm,Vector2(tile.x*TILE+24,tile.y*TILE+24)))
	if duration>0:await _wait_presentation_time(duration)


func _play_mine_effect(mine_id:int,tile:Vector2i) -> void:
	var mine:Dictionary=data.mines[mine_id]
	await _play_action_effect("res://assets/m5/anm/mine%02d_sheet.png"%mine_id,int(mine.get("flm_index",-1)),Vector2(tile.x*TILE+24,tile.y*TILE+24),_mine_area(tile,int(mine.get("apply_fw",0))),int(mine.get("audio_index",-1)))


func _mine_area(t: Vector2i, apply_fw: int) -> Array:
	var ranges: Dictionary = data.get("apply_ranges", {})
	var mat = ranges.get(str(apply_fw), null)
	if mat == null or not (mat is Array) or (mat as Array).size() < 7:
		return [{"tile": t, "pct": 100}]
	var out: Array = []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var pct := int(mat[dy + 3][dx + 3])
			if pct <= 0:
				continue
			var tt := Vector2i(t.x + dx, t.y + dy)
			if _in_bounds(tt):
				out.append({"tile": tt, "pct": pct})
	return out


func _trigger_mine(t: Vector2i, u: Node2D, focus_camera := true) -> bool:
	if u == null or not u.alive:
		return false
	var idx := _mine_at(t)
	if idx < 0:
		return false
	if int(u.bingzhong) == 46:
		_remove_mine(idx)
		return false
	if int(mines[idx].get("code", mines[idx].get("mine_id", 0))) / 10 != 0:
		return false
	_clear_native_range("action")
	await _detonate_mines(t,focus_camera)
	return true


func _remove_mine(index: int) -> void:
	var tile: Vector2i = mines[index]["tile"]
	mines.remove_at(index)
	if mine_nodes.has(tile):
		if is_instance_valid(mine_nodes[tile]):
			mine_nodes[tile].queue_free()
		mine_nodes.erase(tile)


func _detonate_mines(tile: Vector2i, focus_camera := true) -> void:
	var previous_busy:=busy
	busy=true
	action_resolution_depth += 1
	var queue: Array = [tile]
	var seen := {}
	while not queue.is_empty():
		var t: Vector2i = queue.pop_front()
		if seen.has(t):
			continue
		seen[t] = true
		var index := _mine_at(t)
		if index < 0:
			continue
		var rec: Dictionary = mines[index]
		var m: Dictionary = rec["mine"]
		_remove_mine(index)
		if focus_camera:_native_camera_focus(t,"mine")
		_trace_resolution("mine_effect",-1,t)
		await _play_mine_effect(int(rec.get("mine_id", 0)) % 10,t)
		var deaths: Array = []
		for cell in _mine_area(t, int(m.get("apply_fw", 0))):
			var tt: Vector2i = cell["tile"]
			if _mine_at(tt) >= 0 and not seen.has(tt):
				queue.append(tt)
			var target = _unit_at(tt)
			if target == null:
				continue
			var amount := maxi(0, int(m.get("weili", 0)) * int(cell["pct"]) / 100)
			target.last_damage_kind = "mine"
			if int(m.get("shiqi_or_tili", 0)) == 0:
				amount = mini(amount, int(target.hp))
				_apply_hp_damage(target, amount, "mine")
			else:
				amount = mini(amount, int(target.morale))
				target.morale -= amount
				_queue_damage_number(amount,target.position,"morale")
			if amount > 0 and (target.hp <= 0 or target.morale <= 0):
				deaths.append(target)
		_trace_resolution("mine_numbers",-1,t)
		await _wait_damage_numbers("mine")
		var penalty := false
		for target in deaths:
			_trace_resolution("mine_death",int(target.slot),t)
			_retire_unit(target)
			if target.side != "player":
				var count := 0
				for ally in units:
					if ally.alive and ally.side == "player" and ally.slot >= 0 and ally.slot < 40:
						count += 1
				var raw := maxi(4, (int(target.data.get("level", 1)) - int(level.get("index", 0))) * 8 + 12)
				if count>0:
					var award := mini(12, maxi(1, raw / count) + 8)
					var recipients := units.duplicate()
					recipients.sort_custom(func(a,b):return a.slot<b.slot)
					for ally in recipients:
						if ally.alive and ally.side == "player" and ally.slot >= 0 and ally.slot < 60:
							await _gain_xp(ally, award)
			penalty = _record_unit_loss(target) or penalty
			await _complete_unit_death(target)
		if penalty:await _play_loss_penalty()
		_log("%s爆炸" % m.get("name", "地雷"))
		await _wait_for_progress_fx()
	action_resolution_depth -= 1
	busy=previous_busy or finished_flag
	_trace_resolution("mine_done",-1,tile)


func _round_maintenance() -> void:
	# 新轮：T750之后，携带书籍逐本恢复，再处理定时雷，最后T510。
	for u in units:
		if not u.alive:
			continue
		var mods: Array = data.get("terrain_modifiers",[])[_terrain_at(Vector2i(u.x,u.y))]
		u.hp = mini(u.max_hp,u.hp+u.max_hp*int(mods[3])/100)
		u.morale = mini(100,u.morale+int(mods[4]))
		for raw in (u.item_slots if u.is_player() else []):
			match int(raw) - 1:
				31:
					u.hp = mini(int(u.max_hp), int(u.hp) + int(u.max_hp) / 4)
					u.morale = mini(100, int(u.morale) + 10)
				32:
					u.hp = mini(int(u.max_hp), int(u.hp) + int(u.max_hp) * 15 / 100)
		u.refresh()
	# 41F2E2 scans the current grid in row-major order, detonating immediately.
	# A chain may remove later cells before their countdown is visited.
	var ordered:Array=[]
	for rec in mines:ordered.append(rec.tile)
	ordered.sort_custom(func(a,c):return a.y<c.y or (a.y==c.y and a.x<c.x))
	for tile in ordered:
		var index:=_mine_at(tile)
		if index<0:continue
		var low:=int(mines[index].get("low",1))
		if low>2:mines[index].low=low-1
		elif low==2:await _detonate_mines(tile)


func _unit_skills(u: Node2D) -> Dictionary:
	return u.skill_counts


func available_skills(u: Node2D) -> Array:
	var out: Array = []
	var defs: Array = data.get("skills", [])
	var flags := _unit_skills(u)
	for i in range(defs.size()):
		if i >= SKILL_KEYS.size():
			break
		if int(flags.get(SKILL_KEYS[i], 0)) > 0:
			out.append(i)
	return out


func _skill_count(u: Node2D, skill_id: int) -> int:
	if skill_id < 0 or skill_id >= SKILL_KEYS.size():
		return 0
	return int(u.skill_counts.get(SKILL_KEYS[skill_id], 0))


func _select_tiles(u: Node2D, select_fw: int, include_self: bool = false) -> Array:
	var out: Array = []
	var ranges: Dictionary = data.get("select_ranges", {})
	var mat = ranges.get(str(select_fw), null)
	if mat == null or not (mat is Array) or (mat as Array).size() < 9:
		return out
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if int(mat[dy + 4][dx + 4]) != 1:
				continue
			var t := Vector2i(u.x + dx, u.y + dy)
			if _in_bounds(t):
				out.append(t)
	if include_self:
		var st := Vector2i(u.x, u.y)
		if not out.has(st):
			out.append(st)
	return out


func _facing(from: Vector2i, to: Vector2i) -> int:
	# 427A0A: ties use the vertical direction; self returns -1 (unrotated).
	var d := to - from
	if d == Vector2i.ZERO: return -1
	if absi(d.x) > absi(d.y): return 3 if d.x > 0 else 2
	return 1 if d.y > 0 else 0


func _face_target(caster, tile: Vector2i) -> int:
	var facing := _facing(Vector2i(caster.x,caster.y),tile)
	caster.direction = facing
	return facing


func _apply_tiles(center: Vector2i, apply_fw: int, direction := 0) -> Array:
	var ranges: Dictionary = data.get("apply_ranges", {})
	var mat = ranges.get(str(apply_fw), null)
	if mat == null or not (mat is Array) or (mat as Array).size() < 7:
		return [{"tile": center, "pct": 100}]
	var out: Array = []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var pct := int(mat[dy + 3][dx + 3])
			if pct <= 0:
				continue
			# 427A71: templates face north; rotate source cells, not percentages.
			var offset := Vector2i(dx,dy)
			match direction:
				1: offset = Vector2i(-dx,-dy)
				2: offset = Vector2i(dy,-dx)
				3: offset = Vector2i(-dy,dx)
			var t := center + offset
			if _in_bounds(t):
				out.append({"tile": t, "pct": pct})
	# Native effect/retirement loops scan the map rows after the mask rotates.
	# Source-template order reverses deaths when facing south/east/west, which
	# changes the next victim's per-item XP and mine casualty denominators.
	out.sort_custom(func(a,b):return a.tile.y<b.tile.y or (a.tile.y==b.tile.y and a.tile.x<b.tile.x))
	return out


func _skill_targets(caster: Node2D, skill: Dictionary, occupied_only := false) -> Dictionary:
	var out := {}
	var tid := int(skill.get("type", 0))
	var support := tid in [0, 1, 2, 10]
	var tiles := _select_tiles(caster, int(skill.get("select_fw", 1)), tid in [0,1,2])
	for t in tiles:
		var target := _unit_at(t)
		# 4214AA only tests the mask. AI separately chooses occupied targets;
		# players may aim an upgraded AoE between units or in front of a cone.
		if not occupied_only:
			out[t] = target
			continue
		if target == null or not target.alive:
			continue
		if support and same_faction(target,caster):
			out[t] = target
		elif not support and not same_faction(target,caster):
			out[t] = target
	return out


func _skill_success_chance(caster, target, sid:int, count:int) -> int:
	# Actual roll probability, not the template's effect-strength percentage.
	# Keep the theft bonus after the original lower clamp (4138EA).
	if sid in [0,1,2,15]:return 100
	var chance:=maxi(0,30+2*(int(caster.data.get("zhili",0))-int(target.data.get("zhili",0))))
	if sid==9:chance+=CombatRules.skill_level(count)
	return mini(100,chance)


func _skill_would_affect(caster, target, sid:int, count:int, pct:int) -> bool:
	# Pure hover prediction. Do not use this to skip resolver iterations:
	# native rolls/practice still occur for several no-change status effects.
	var e1:=CombatRules.skill_effect(int(caster.data.get("zhili",0)),int(active_skill.get("para1",0)),count)*pct/100
	var e2:=CombatRules.skill_effect(int(caster.data.get("zhili",0)),int(active_skill.get("para2",0)),count)*pct/100
	match sid:
		0,1,2:
			return (sid!=1 and mini(e1,int(target.max_hp)-int(target.hp))>0) or (sid!=0 and mini(e2,100-int(target.morale))>0)
		3,4,5,13,14,15:
			var modifier:=0
			if sid in [3,4,5]:
				var terrain_id:=_terrain_at(Vector2i(target.x,target.y))
				var modifiers:Array=data.get("terrain_modifiers",[])
				if terrain_id>=0 and terrain_id<modifiers.size():modifier=int(modifiers[terrain_id][0 if sid==3 else 1])
			return mini(int(target.hp),maxi(0,e1*(100+modifier)/100))>0 or (sid==14 and maxi(0,int(target.morale)-e2)<int(target.morale))
		6:
			return mini(int(target.morale),e2)>0
		7:
			return maxi(20,int(target.defense_integrity)*7/10)!=int(target.defense_integrity)
		8:
			return maxi(50,int(target.integrity)*7/10)!=int(target.integrity)
		9:
			for raw in target.item_slots:
				if int(raw)>0:return true # A full caster bag sends theft to battle loot.
			return false
		10:
			var old_level:=int(target.data.get("level",1))
			var new_level:=maxi(1,old_level-1)
			var new_max_hp:=maxi(1,int(unit_class(target).get("tili",50))+(new_level-1)*int(unit_class(target).get("tili_plus",0)))
			return new_level!=old_level or new_max_hp!=int(target.max_hp) or int(target.hp)>new_max_hp
		11:
			return not target.acted or not target.moved
		12:
			return target.acted or target.moved or int(target.integrity)!=100 or int(target.defense_integrity)!=100
	return false


func skill_preview_cells() -> Array:
	if mode!="skill" or busy or phase!="player" or finished_flag or progress_fx_active:return []
	if is_instance_valid(action_panel) or is_instance_valid(context_menu):return []
	if selected==null or not is_instance_valid(selected) or not selected.alive or selected.acted:return []
	if active_skill.is_empty() or active_skill_id<0 or active_skill_id>=SKILL_KEYS.size():return []
	if not attack_tiles.has(hover_tile) or not RangeMask.allows(native_dark_mask,map_w,map_h,hover_tile):return []
	var sid:=active_skill_id
	var count:=_skill_count(selected,sid)
	var apply:=CombatRules.skill_apply(int(active_skill.get("apply_fw",0)),count)
	# _face_target mutates direction; hover must only compute a facing.
	var cells:=_apply_tiles(hover_tile,apply,_facing(Vector2i(selected.x,selected.y),hover_tile))
	var support:=sid in [0,1,2,12]
	for cell in cells:
		var target:=_unit_at(cell.tile)
		var chance:=0
		if target!=null and support==same_faction(target,selected) and not (sid==12 and int(target.bingzhong)==45):
			if _skill_would_affect(selected,target,sid,count,int(cell.pct)):
				chance=_skill_success_chance(selected,target,sid,count)
		cell["chance"]=chance
		cell["effective"]=chance>0
	return cells


func _open_skill_menu() -> void:
	if selected == null or busy or phase != "player" or selected.acted:return
	var ids:=available_skills(selected)
	if ids.is_empty():_return_action_menu();return
	_close_context_menu();_close_action_panel();_clear_native_range("menu")
	var lines:Array=[]
	for sid in ids:
		# 41F6B9: name + one space + printf("%2d",419CA4(count)).
		lines.append("%s %2d"%[str(data.skills[sid].name),CombatRules.skill_level(_skill_count(selected,sid))])
	var picker=preload("res://scripts/ui/OriginalChoice.gd").new()
	hud_root.add_child(picker);action_panel=picker
	picker.chosen.connect(func(index:int):_choose_skill(int(ids[index])))
	picker.cancelled.connect(_cancel_native_choice)
	picker.setup(font,lines,Vector2(276,236-12*ids.size()))


func _choose_skill(skill_id: int) -> void:
	_close_action_panel()
	if selected == null or busy:
		return
	var defs: Array = data.get("skills", [])
	if skill_id < 0 or skill_id >= defs.size():
		return
	active_skill_id = skill_id
	active_skill = defs[skill_id]
	active_item_id = -1
	var targets := _skill_targets(selected, active_skill)
	_target_native_range(selected,int(active_skill.get("select_fw",1)),skill_id<3,"skill-target")
	mode = "skill"
	move_tiles.clear()
	attack_tiles = targets
	_log("选择「%s」的目标" % active_skill.get("name", "技能"))
	update_hud()


func _rand100() -> int:
	rng_state = (rng_state * 214013 + 2531011) & 0xffffffff
	return ((rng_state >> 16) & 0x7fff) % 100


func _refresh_equipment(u) -> void:
	u.attack_bonus = 0
	u.defense_bonus = 0
	var movement := 0
	var valid: Array = data.get("item_valid", [])
	for raw in u.item_slots:
		var iid := int(raw) - 1
		if iid < 81 or iid >= valid.size() or u.bingzhong >= valid[iid].size() or int(valid[iid][u.bingzhong]) == 0:
			continue
		var it: Dictionary = data.get("items", {}).get(str(iid), {})
		u.attack_bonus = maxi(u.attack_bonus, int(it.get("para3", 0)))
		u.defense_bonus = maxi(u.defense_bonus, int(it.get("para4", 0)))
		movement = maxi(movement, int(it.get("para1", 0)))
	u.move = int(unit_class(u).get("yidong", 4)) + movement


func _execute_skill_at(tile: Vector2i) -> void:
	if selected == null or active_skill.is_empty():
		return
	var caster = selected
	if not _skill_targets(caster, active_skill).has(tile):
		return
	busy = true
	action_resolution_depth += 1
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	_clear_native_range("action")
	var sid := active_skill_id
	var count := _skill_count(caster, sid)
	var support := sid in [0, 1, 2, 12]
	# 4138EA：当前次数先算等级，整次施法不变；每个有效目标各累计一次。
	var effect1 := CombatRules.skill_effect(int(caster.data.get("zhili", 0)), int(active_skill.get("para1", 0)), count)
	var effect2 := CombatRules.skill_effect(int(caster.data.get("zhili", 0)), int(active_skill.get("para2", 0)), count)
	var affected := 0
	var base_xp := 0
	var kill_xp := 0
	var deaths: Array = []
	var apply := CombatRules.skill_apply(int(active_skill.get("apply_fw",0)),count)
	var cells:=_apply_tiles(tile,apply,_face_target(caster,tile))
	caster.display_action_lock=true
	if phase=="player":caster.display_state=0;caster.refresh()
	var aidx:=int(active_skill.get("anm_index",-1))
	await _play_action_effect("res://assets/m5/anm/ffpact%02d_sheet.png"%aidx if aidx>=0 else "",int(active_skill.get("flm_index",-1)),Vector2(tile.x*TILE+24,tile.y*TILE+24),cells,int(active_skill.get("audio_index",-1)))
	for cell in cells:
		var target = _unit_at(cell["tile"])
		if target == null or not target.alive or support != (same_faction(target,caster)):
			continue
		if sid not in [0, 1, 2, 15]:
			var chance := _skill_success_chance(caster,target,sid,count)
			if _rand100() >= chance:
				_spawn_float("未奏效", target.position, Color("#b0b0b0"))
				continue
		if sid == 12 and int(target.bingzhong) == 45:
			continue
		var pct := int(cell["pct"])
		var e1 := effect1 * pct / 100
		var e2 := effect2 * pct / 100
		var hp_before := int(target.hp)
		var morale_before := int(target.morale)
		var effective := true
		var xp := 8 if caster.side == "player" else 2
		match sid:
			0, 1, 2:
				if sid != 1:
					target.hp += mini(e1, int(target.max_hp) - int(target.hp))
				if sid != 0:
					target.morale += mini(e2, 100 - int(target.morale))
				effective = target.hp > hp_before or target.morale > morale_before
				if sid == 0:
					xp = maxi(4 if caster.side == "player" else 2, (int(target.hp) - hp_before) * (12 if caster.side == "player" else 4) / maxi(1, effect1))
				elif sid == 1:
					xp = maxi(4 if caster.side == "player" else 1, (int(target.morale) - morale_before) * (12 if caster.side == "player" else 4) / maxi(1, effect2))
			3, 4, 5, 13, 14, 15:
				var modifier := 0
				if sid in [3, 4, 5]:
					var terrain_id := _terrain_at(Vector2i(target.x, target.y))
					var modifiers: Array = data.get("terrain_modifiers", [])
					if terrain_id >= 0 and terrain_id < modifiers.size():
						modifier = int(modifiers[terrain_id][0 if sid == 3 else 1])
				var dmg := mini(int(target.hp), maxi(0, e1 * (100 + modifier) / 100))
				_apply_hp_damage(target, dmg, "skill")
				if sid == 14:
					target.morale = maxi(0, int(target.morale) - e2)
				effective = target.hp < hp_before or target.morale < morale_before
				if sid in [3, 4, 5]:
					xp = maxi(4 if caster.side == "player" else 2, dmg * (8 if caster.side == "player" else 4) / maxi(1, effect1))
			6:
				var loss := mini(int(target.morale), e2)
				target.morale -= loss
				target.last_damage_kind = "skill"
				effective = loss > 0
				xp = maxi(4 if caster.side == "player" else 2, loss * (8 if caster.side == "player" else 4) / maxi(1, effect2))
			7:
				target.defense_integrity = maxi(20, int(target.defense_integrity) * 7 / 10)
			8:
				target.integrity = maxi(50, int(target.integrity) * 7 / 10)
			9:
				for i in range(target.item_slots.size()):
					if int(target.item_slots[i]) > 0:
						var raw := int(target.item_slots[i])
						target.item_slots[i] = 0
						if caster.item_slots.has(0):
							InventorySlots.add_id(caster.item_slots,raw)
						else:
							_battle_loot(raw - 1, false)
						_refresh_equipment(caster)
						_refresh_equipment(target)
						break
			10:
				target.data["level"] = maxi(1, int(target.data.get("level", 1)) - 1)
				target.max_hp = maxi(1, int(unit_class(target).get("tili", 50)) + (int(target.data["level"]) - 1) * int(unit_class(target).get("tili_plus", 0)))
				target.hp = mini(int(target.hp), int(target.max_hp))
			11:
				target.acted = true
				target.moved = true
			12:
				target.acted = false
				target.moved = false
				target.integrity += mini(20, 100 - int(target.integrity))
				target.defense_integrity += mini(20, 100 - int(target.defense_integrity))
		_queue_damage_number(absi(int(target.hp)-hp_before),target.position,"hp",target.hp>hp_before)
		_queue_damage_number(absi(int(target.morale)-morale_before),target.position,"morale",target.morale>morale_before)
		if effective:
			if sid in [0,1,2]: _skill_relationship(caster,target)
			if sid >= 3: target.data["last_attacker_slot"] = int(caster.slot)
			affected += 1
			base_xp += xp
			if (target.hp <= 0 or target.morale <= 0) and not deaths.has(target):
					deaths.append(target)
		target.refresh()
	caster.skill_counts[SKILL_KEYS[sid]] = count + affected
	caster.acted = true
	caster.refresh()
	_log("%s 使用「%s」，影响 %d 个目标" % [caster.unit_name, active_skill.get("name", "技能"), affected])
	await _wait_damage_numbers("skill")
	var penalty := false
	for d in deaths:
		_retire_unit(d)
		kill_xp += CombatRules.kill_experience(int(caster.data.get("level", 1)), int(d.data.get("level", 1)))
		_collect_native_casualty_loot(d)
		penalty = _record_unit_loss(d) or penalty
		await _complete_unit_death(d)
	if penalty:await _play_loss_penalty()
	await _gain_xp(caster,mini(16,base_xp)+kill_xp)
	caster.display_action_lock=false
	caster.display_state=0;caster.refresh()
	action_resolution_depth -= 1
	busy = finished_flag
	active_skill = {}
	active_skill_id = -1
	selected = null
	update_hud()
	await _after_completed_action(caster)


func _skill_relationship(caster, target) -> void:
	if scenario == null: return
	var slot := -1
	var amount := 0
	if target.slot == 7 and caster.slot in [0,8]:
		slot = 3 if caster.slot == 0 else 4
		amount = 2
	elif caster.slot == 7 and target.slot in [0,8]:
		slot = 3 if target.slot == 0 else 4
		amount = 1
	if slot >= 0:
		var addr := "0x%x" % (0x7d06c8+slot*4)
		scenario._set_global(addr,(scenario._global_value(addr)+amount)&0xffffffff)


func _battle_loot(item_id: int, permanent := true) -> void:
	if item_id < 0:
		return
	var key := "items" if permanent else "temporary_loot"
	var items: Dictionary = battle_context.get(key, {})
	var quantity:=int(items.get(str(item_id),0))+1
	items[str(item_id)] = quantity & 0xffff
	battle_context[key] = items
	stats["loot_count"] = int(stats.get("loot_count", 0)) + 1
	if permanent: looted.emit(item_id)
	var it: Dictionary = data.get("items", {}).get(str(item_id), {})
	_log("已收入行囊：%s ×1（点击右侧行囊查看）" % it.get("name", "物品"))


func _open_inventory() -> void:
	if busy or finished_flag:
		return
	_close_action_panel()
	var inv := preload("res://scripts/ui/InventoryPanel.gd").new()
	hud_root.add_child(inv)
	action_panel = inv
	inv.setup(font, data, _carried_stock(selected, "items"), _carried_stock(selected, "mines"))
	inv.closed.connect(_close_action_panel)


func _item_actor_allowed() -> bool:
	return selected!=null and selected.alive and selected.is_player() and selected.control and not selected.acted and not busy and phase=="player"


func _cancel_native_choice() -> void:
	_ignore_right_release=true
	_return_action_menu()


func _return_action_menu() -> void:
	_close_action_panel()
	mode="idle";active_item_id=-1
	_clear_native_range("menu")
	_open_context_menu();update_hud()


func _open_item_menu() -> void:
	if not _item_actor_allowed():return
	_close_context_menu();_close_action_panel();_clear_native_range("menu")
	var picker=preload("res://scripts/ui/OriginalItemPicker.gd").new()
	hud_root.add_child(picker);action_panel=picker
	picker.chosen.connect(_item_options)
	picker.cancelled.connect(_return_action_menu)
	picker.setup(font,data,selected.item_slots)


func _item_options(id:int) -> void:
	if not _item_actor_allowed():return
	_close_action_panel()
	var picker=preload("res://scripts/ui/OriginalChoice.gd").new()
	hud_root.add_child(picker);action_panel=picker
	picker.chosen.connect(func(index:int):_close_action_panel();_item_option(id,index))
	picker.cancelled.connect(_cancel_native_choice)
	picker.setup(font,["使 用","交 给","丢 弃","察 看"],Vector2(360,280))


func _item_option(id:int,index:int) -> void:
	if not _item_actor_allowed() or not selected.item_slots.has(id+1):return
	match index:
		0:
			if id>=81 or id in [31,32]:_return_action_menu()
			else:_choose_item(id)
		1:
			active_item_id=id;mode="item_give"
			_set_native_range(RangeMask.mine_geometry(map_w,map_h,Vector2i(selected.x,selected.y)),"item-give")
			move_tiles.clear();attack_tiles.clear();update_hud()
		2:_confirm_touch_ending_action("丢弃结束行动？",_discard_item.bind(id))
		3:
			var info=preload("res://scripts/ui/OriginalInfo.gd").new();add_child(info)
			busy=true
			info.closed.connect(func():busy=false;_return_action_menu())
			info.setup(font,data,"item",id)


func _discard_item(id:int) -> void:
	if not _item_actor_allowed() or not _consume_inventory("items",id):return
	var actor=selected
	actor.acted=true;actor.refresh()
	active_item_id=-1;_clear_selection()
	await _after_completed_action(actor)


func _execute_item_transfer(tile:Vector2i) -> void:
	if not _item_actor_allowed() or not RangeMask.allows(native_dark_mask,map_w,map_h,tile):return
	var target=_unit_at(tile)
	if target==null or target==selected or active_item_id<0:return
	var actor=selected;var id:=active_item_id
	if not _consume_inventory("items",id):return
	# 421978 -> 4219A1: source removes first; target-full failure is ignored.
	InventorySlots.add_id(target.item_slots,id+1)
	_refresh_equipment(actor);_refresh_equipment(target)
	actor.acted=true;actor.refresh();target.refresh()
	active_item_id=-1;_clear_selection()
	await _after_completed_action(actor)


func _item_kind(item_id: int) -> String:
	if item_id >= 81 and item_id <= 155:
		return "equip"
	if item_id >= 61 and item_id <= 80:
		return "manual"
	if item_id >= 31 and item_id <= 40:
		return "book"
	if item_id >= 41 and item_id <= 56:
		return "throw"
	if item_id >= 0 and item_id <= 30:
		return "food"
	return "other"


func _choose_item(item_id: int) -> void:
	_close_action_panel()
	if item_id>=81 or item_id in [31,32]:_return_action_menu();return
	if item_id>=61 and item_id<=80:
		_confirm_touch_ending_action("尝试耗行动？",_use_manual_item.bind(item_id));return
	if selected == null or busy:
		return
	var it: Dictionary = (data.get("items", {}) as Dictionary).get(str(item_id), {})
	if it.is_empty() or _inventory_count("items", item_id) <= 0:
		return
	active_item_id = item_id
	active_skill = {}
	active_skill_id = -1
	var kind := _item_kind(item_id)
	var targets := _item_targets(selected, it, kind)
	_target_native_range(selected,int(it.get("select_fw",1)),true,"item-target")
	mode = "item"
	move_tiles.clear()
	attack_tiles = targets
	_log("选择「%s」的目标" % it.get("name", "物品"))
	update_hud()


func _manual_plan(actor,id:int) -> Dictionary:
	var state=preload("res://scripts/m2/GameState.gd").new()
	var classes:Dictionary={}
	var source:Variant=data.get("unit_types",{})
	if source is Array:
		for index in range(source.size()):classes[str(index)]=source[index]
	else:classes=source
	state.data={"units":classes,"items":data.get("items",{}),"item_valid":data.get("item_valid",[])}
	var plan:Dictionary=state.can_promote(actor.state_record(),id)
	if not bool(plan.get("ok",false)):
		plan["low_level"]=str(plan.get("msg","")).begins_with("晋升需要等级")
	return plan


func _apply_manual_item(actor,id:int,plan:Dictionary) -> void:
	_play_sfx(15)
	actor.bingzhong=int(plan.target);actor.data["bingzhong"]=actor.bingzhong
	var cls:Dictionary=unit_class(actor)
	actor.max_hp=maxi(1,int(cls.get("tili",50))+(int(actor.data.get("level",1))-1)*int(cls.get("tili_plus",0)))
	if not bool(plan.promotion):actor.hp=mini(actor.hp,actor.max_hp)
	actor.data["max_hp"]=actor.max_hp
	actor.data["unit_name"]=str(cls.get("name",""))
	actor.select=int(cls.get("select",1));actor.skills=cls.get("skills",{}).duplicate()
	for key in actor.skills:
		if int(actor.skills[key])!=0 and int(actor.skill_counts.get(key,0))==0:actor.skill_counts[key]=1
	var path:="res://assets/army/army_%03d.png"%int(cls.get("img_index",0))
	actor.data["army_png"]=path
	if ResourceLoader.exists(path):
		actor.sprite.texture=load(path);actor.frame_count=maxi(1,int(actor.sprite.texture.get_width()/TILE))
	_consume_inventory("items",id)
	_refresh_equipment(actor);actor.refresh()


func _manual_notice(value:String) -> void:
	var notice=preload("res://scripts/ui/OriginalNotice.gd").new()
	hud_root.add_child(notice);action_panel=notice;notice.setup(font,value)
	await notice.closed
	_close_action_panel()


func _use_manual_item(id:int) -> void:
	if not _item_actor_allowed() or not selected.item_slots.has(id+1):return
	var actor=selected
	var plan:Dictionary=_manual_plan(actor,id)
	busy=true;action_resolution_depth+=1
	if bool(plan.get("ok",false)):
		var confirm=preload("res://scripts/ui/OriginalConfirm.gd").new()
		hud_root.add_child(confirm);action_panel=confirm
		confirm.setup(font,"升级吗？" if bool(plan.promotion) else "转职吗？")
		var accepted:bool=await confirm.answered
		_close_action_panel()
		if accepted:
			_apply_manual_item(actor,id,plan)
			await _manual_notice(actor.unit_name+("升级为" if bool(plan.promotion) else "转职为")+str(plan.target_name))
	elif bool(plan.get("low_level",false)):
		await _manual_notice("升级等级不够！")
	# Original 41FC6E ignores the function result: cancellation/incompatibility/
	# low level still end the action, but only success removes the carried book.
	actor.acted=true;actor.refresh()
	action_resolution_depth-=1;busy=false;active_item_id=-1
	_clear_selection()
	await _after_completed_action(actor)


func _item_targets(caster: Node2D, it: Dictionary, kind: String) -> Dictionary:
	var out := {}
	if kind == "book":
		out[Vector2i(caster.x, caster.y)] = caster
		return out
	# 418B79/421677: the landing mask accepts empty/enemy/friendly cells and
	# always self. Allegiance is filtered in the effect loop, not at selection.
	var tiles := _select_tiles(caster, int(it.get("select_fw", 1)), true)
	for t in tiles:
		out[t] = _unit_at(t)
	return out


func _execute_item_at(tile: Vector2i) -> void:
	if selected == null or active_item_id < 0 or active_item_id>=61 or active_item_id in [31,32]:
		return
	var caster = selected
	var it: Dictionary = (data.get("items", {}) as Dictionary).get(str(active_item_id), {})
	if it.is_empty() or _inventory_count("items", active_item_id) <= 0:
		return
	var kind := _item_kind(active_item_id)
	if kind == "book":
		if tile != Vector2i(caster.x, caster.y) or active_item_id in [31, 32]:
			return
		_clear_native_range("action")
		caster.data["wuli"] = mini(100, int(caster.data.get("wuli", 0)) + int(it.get("para1", 0)))
		caster.data["zhili"] = mini(100, int(caster.data.get("zhili", 0)) + int(it.get("para2", 0)))
		_consume_inventory("items", active_item_id)
		caster.acted = true
		caster.refresh()
		_log("%s 研读%s：武力%d 智力%d" % [caster.unit_name, it.get("name", ""),
				int(caster.data["wuli"]), int(caster.data["zhili"])])
		active_item_id = -1
		_clear_selection()
		await _after_completed_action(caster)
		return
	var support := kind == "food"
	var targets := _item_targets(caster, it, kind)
	if not targets.has(tile):
		return
	_clear_native_range("action")
	busy = true
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	action_resolution_depth += 1
	var area := _apply_tiles(tile, int(it.get("apply_fw", 0)), int(caster.direction))
	var aidx:=int(it.get("anm_index",it.get("para3",-1))) if kind=="throw" else -1
	await _play_action_effect("res://assets/m5/anm/ffpact%02d_sheet.png"%aidx if aidx>=0 else "",int(it.get("para4",-1)),Vector2(tile.x*TILE+24,tile.y*TILE+24),area,int(it.get("audio_apply",-1)))
	var affected := 0
	var deaths: Array = []
	for cell in area:
		var t: Vector2i = cell["tile"]
		var pct := int(cell["pct"])
		var target := _unit_at(t)
		if target == null or not target.alive:
			continue
		if support and not same_faction(target,caster):
			continue
		if not support and same_faction(target,caster):
			continue
		var p1 := int(it.get("para1", 0)) * pct / 100
		var p2 := int(it.get("para2", 0)) * pct / 100
		if kind == "food":
			# 415D4E: original wine21..30 consumes an action/item but restores
			# neither channel. Keep that known original bug, not an invented buff.
			if active_item_id >= 21: continue
			if p1 > 0:
				var heal := mini(p1, target.max_hp - target.hp)
				target.hp += heal
				_queue_damage_number(heal,target.position,"hp",true)
			if p2 > 0:
				var add := mini(p2, max(0, 100 - target.morale))
				target.morale += add
				_queue_damage_number(add,target.position,"morale",true)
			affected += 1
		elif kind == "throw":
			var dmg := mini(int(target.hp),maxi(0,int(p1)))
			_apply_hp_damage(target, dmg, "throw")
			_queue_damage_number(mini(int(target.morale),int(p2)),target.position,"morale")
			target.morale = max(0, target.morale - p2)
			target.data["last_attacker_slot"] = int(caster.slot)
			# Both channels first; the original only retires on actual HP damage.
			if dmg > 0 and (target.hp <= 0 or target.morale <= 0): deaths.append(target)
			affected += 1
		target.refresh()
	caster.acted = true
	caster.refresh()
	_log("%s 使用「%s」，影响 %d 个目标" % [caster.unit_name, it.get("name", ""), affected])
	await _wait_damage_numbers("item")
	for d in deaths:
		_retire_unit(d)
		await _gain_xp(caster, CombatRules.kill_experience(caster.data.get("level", 1), d.data.get("level", 1)) >> 1)
		_collect_native_casualty_loot(d)
		if _record_unit_loss(d,true):await _play_loss_penalty()
		await _complete_unit_death(d)
	_consume_inventory("items",active_item_id)
	action_resolution_depth -= 1
	busy = finished_flag
	active_item_id = -1
	selected = null
	update_hud()
	await _after_completed_action(caster)


func _after_completed_action(caster) -> void:
	# 421816/421823 and book42038B: synchronous T510 before auto-turn test.
	if caster.alive and not finished_flag: await _after_unit_step(caster)
	if scenario != null and not finished_flag: await scenario.on_tick()
	if not _check_end() and not fast_sim and phase == "player":
		call_deferred("_auto_end_if_ready")


func _auto_end_if_ready() -> void:
	# One frame lets story/choice handlers claim busy; do not advance behind a modal.
	if _auto_end_pending: return
	_auto_end_pending = true
	await get_tree().process_frame
	_auto_end_pending = false
	if phase != "player" or busy or finished_flag or fast_sim: return
	for u in units:
		if u.alive and u.control and u.is_player() and not u.acted: return
	await _on_end_turn()


func _close_action_panel() -> void:
	if action_panel != null and is_instance_valid(action_panel):
		action_panel.visible = false
		action_panel.queue_free()
	action_panel = null


func _open_mine_menu() -> void:
	_open_carried_mine_picker(false)


func _open_carried_mine_picker(giving:bool) -> void:
	if not _item_actor_allowed():return
	_close_context_menu();_close_action_panel()
	var codes:Array=[];var lines:Array=[]
	for raw in selected.mine_slots:
		var code:=int(raw)-1
		if code<0:continue
		codes.append(code)
		lines.append(str(data.mines[code%10].get("name","地雷"))+["普","引","定","遥"][code/10])
	if codes.is_empty():_return_action_menu();return
	var picker=preload("res://scripts/ui/OriginalChoice.gd").new()
	hud_root.add_child(picker);action_panel=picker
	picker.chosen.connect(func(index:int):
		_close_action_panel()
		if giving:_choose_mine_transfer(int(codes[index]))
		else:_choose_mine(int(codes[index]))
	)
	picker.cancelled.connect(_cancel_native_choice)
	picker.setup(font,lines,Vector2(276,224 if codes.size()==1 else 236-12*codes.size()))


func _choose_mine(mid: int) -> void:
	_close_action_panel()
	mine_kind = mid
	_place_mine()


func _begin_player_phase(log_text: String = "") -> void:
	_clear_native_range()
	_selection_origin.clear()
	phase = "player"
	busy = false
	for u in units:
		if u.alive:
			u.acted = false
			u.moved = false
			u.status_stun = 0
			u.refresh()
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	if scenario != null:
		busy=true
		await scenario.on_turn_start(turn)
		busy=finished_flag or scenario.start_phase_pending
	if progress_fx_active:
		busy=true
		await _wait_for_progress_fx()
		busy=finished_flag or (scenario!=null and scenario.start_phase_pending)
	if finished_flag:
		return
	if log_text != "":
		_log(log_text)
	update_hud()


func _show_roster(side: String) -> void:
	var members:Array=units.filter(func(u):return u.alive and (u.is_player() if side=="player" else not u.is_player()))
	members.sort_custom(func(a,c):return a.slot<c.slot)
	var pages:Array=[]
	for start in range(0,members.size(),12):
		var entries:Array=[]
		for row in range(mini(12,members.size()-start)):
			var u=members[start+row];var y:int=100+26*row
			var hp_color:int=0x48 if u.hp>u.max_hp*2/3 else 0x8a if u.hp>u.max_hp/3 else 0xb7
			var fields:Array=[[92,u.unit_name],[184,str(data.unit_types[u.bingzhong].get("name",""))],
				[248,"LV"],[264,str(int(u.data.get("level",1)))],[284,str(u.hp),hp_color],
				[324,"/"],[340,str(u.max_hp)],[384,str(u.morale)],[408,"/"],[424,"100"],[464,"完" if u.acted else "未"]]
			if u.behavior==11:fields.append([484,"乱",0xb7])
			for field in fields:entries.append({"text":str(field[1]),"at":Vector2(int(field[0]),y),"color":int(field[2]) if field.size()>2 else 0x48})
		pages.append(entries)
	_open_readout(pages)


func _open_unit_info(inspected: Node2D = null) -> void:
	var actor = selected if inspected == null else inspected
	if actor==null or busy:return
	_close_context_menu()
	var info=preload("res://scripts/ui/OriginalInfo.gd").new()
	add_child(info)
	# 419CDF compacts owned bags before rendering; state_record is a snapshot.
	InventorySlots.compact(actor.item_slots)
	InventorySlots.compact(actor.mine_slots)
	var person:Dictionary=actor.state_record()
	person["name"]=actor.unit_name
	person["terrain_bonus"]=_terrain_defense(actor)
	var tables:=data.duplicate(false)
	tables["units"]=data.get("unit_types",{})
	busy=true
	info.closed.connect(func():
		busy=false
		if inspected != null:
			update_hud()
			return
		if selected!=null and (not selected.is_player() or not selected.control or selected.acted):_clear_selection()
		elif native_range_phase=="menu":_open_context_menu()
	)
	info.setup(font,tables,"person",int(actor.slot),person)


func _ask_end_turn(system_menu:=false) -> void:
	if busy or finished_flag or phase != "player": return
	_open_toolbar_choice(["原地待命","跟随主将","各自为战"],Vector2(320,200) if system_menu else Vector2(500,32),_end_turn_order)


func _end_turn_order(order: int) -> void:
	if order<0 or order>2:return
	_close_action_panel()
	var hero=unit_by_slot(0)
	if hero==null or not hero.alive:order=0
	for u in player_units:
		if not u.alive or u.acted or not u.control: continue
		if order == 0:
			u.acted = true
		elif order == 1:
			u.behavior = 5
			u.target_x = hero.x; u.target_y = hero.y
		else: u.behavior = 1
	await _on_end_turn(order != 0)


func _on_end_turn(remaining_ai := false) -> void:
	if phase != "player" or busy or finished_flag: return
	_clear_native_range()
	_selection_origin.clear()
	_close_context_menu()
	_close_action_panel()
	if _check_end(): return
	var previous_camera := camera.position if camera != null else Vector2.ZERO
	camera_follow=false;camera_follow_target=null
	if not remaining_ai:
		for u in player_units:
			if u.alive and u.control and not u.auto: u.acted = true
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	# 40479D: one ascending People slot queue, not all allies then all enemies.
	var actions := 0
	while not finished_flag:
		var next = null
		for u in units:
			if not u.alive or u.acted: continue
			if next == null or u.slot < next.slot: next = u
		if next == null: break
		phase = "ally" if next.is_player() else "enemy"
		update_hud()
		await _ai_act(next,"enemy" if next.is_player() else "player")
		actions += 1
		if actions >= 4096:
			push_error("AI行动超过安全上限，检查督战循环")
			break
		if not fast_sim: await get_tree().create_timer(ai_delay).timeout
	if not finished_flag:
		turn += 1
		_accumulate_relationships()
		await _begin_player_phase("第 %d 回合，我方行动" % turn)
	# 4048D5 saves once before automatic actions; 40499B restores after T750/T510.
	_restore_round_camera(previous_camera)
	_trace_resolution("round_done")


func _accumulate_relationships() -> void:
	if scenario == null: return
	var girl = unit_by_slot(7)
	if girl == null: return
	for slot in [0,8]:
		var other = unit_by_slot(slot)
		if other != null and absi(other.x-girl.x)+absi(other.y-girl.y) == 1:
			var addr := "0x7d06d4" if slot == 0 else "0x7d06d8"
			scenario._set_global(addr,(scenario._global_value(addr)+1)&0xffffffff)


func _has_auto_allies() -> bool:
	for u in player_units:
		if u.alive and u.auto:
			return true
	return false


func _run_ally_turn() -> void:
	await _run_ai_side("player",true)


func _run_enemy_turn() -> void:
	var previous_camera := camera.position if camera != null else Vector2.ZERO
	await _run_ai_side("enemy",false)
	if not finished_flag:
		turn += 1
		await _begin_player_phase("第 %d 回合，我方行动" % turn)
	_restore_round_camera(previous_camera)


func _run_ai_side(side: String, only_auto: bool) -> void:
	var actions := 0
	while not finished_flag:
		var next = null
		for u in units:
			if not u.alive or u.acted or u.side != side or (only_auto and not u.auto): continue
			if next == null or int(u.slot) < int(next.slot): next = u
		if next == null: break
		await _ai_act(next,"enemy" if side == "player" else "player")
		actions += 1
		if actions >= 4096:
			push_error("AI行动超过安全上限，检查督战循环")
			break
		if not fast_sim: await get_tree().create_timer(ai_delay).timeout


func _nearest_side(u: Node2D, side: String) -> Node2D:
	var arr: Array = player_units if side == "player" else enemy_units
	var best: Node2D = null
	var bestd := 99999
	var fallback: Node2D = null
	var fallbackd := 99999
	for p in arr:
		if not p.alive:
			continue
		var d: int = abs(p.x - u.x) + abs(p.y - u.y)
		if d < fallbackd:
			fallbackd = d
			fallback = p
		if p.protected:
			continue
		if d < bestd:
			bestd = d
			best = p
	return best if best != null else fallback


func _nearest_player(u: Node2D) -> Node2D:
	return _nearest_side(u, "player")


func _enemy_act(e: Node2D) -> void:
	await _ai_act(e, "player")


func _ai_act(u, _enemy_side: String) -> void:
	if u == null or not u.alive or u.acted or finished_flag:
		return
	_active_ai_slot=int(u.slot)
	_trace_resolution("ai_plan",int(u.slot),Vector2i(u.x,u.y))
	await _execute_ai_act(u)
	_trace_resolution("ai_done",int(u.slot),Vector2i(u.x,u.y))
	_active_ai_slot=-1


func _execute_ai_act(u) -> void:
	var plan: Dictionary = preload("res://scripts/battle/OriginalAI.gd").plan(self,u)
	var destination: Vector2i = plan.get("station",Vector2i(u.x,u.y))
	var start := Vector2i(u.x,u.y)
	var kind := str(plan.get("kind","wait"))
	if destination!=start or kind in ["attack","skill"]:
		camera_follow=false;camera_follow_target=null
		_native_camera_actor(start)
	if destination != start:
		_movement_active = true
		compute_reachable(u)
		var path := _path_to(destination,start)
		if not path.is_empty():_native_camera_focus(start,"move_start")
		for step in path:
			_native_camera_move_step(Vector2i(u.x,u.y))
			await u.move_visual(step.x,step.y,0.055)
			if await _trigger_mine(step,u):
				u.acted = true
				u.moved = true
				u.refresh()
				_movement_active = false
				await _after_completed_action(u)
				return
			if not u.alive or finished_flag:
				_movement_active = false
				return
		_movement_active = false
	u.moved = destination != start
	var target = unit_by_slot(int(plan.get("target",-1)))
	if kind == "attack" and target != null:
		_native_camera_focus(Vector2i(target.x,target.y),"attack_target")
		await _perform_attack(u,target)
	elif kind == "skill" and target != null:
		_native_camera_focus(Vector2i(target.x,target.y),"skill_target")
		selected = u
		active_skill_id = int(plan["skill"])
		active_skill = data["skills"][active_skill_id]
		await _execute_skill_at(Vector2i(target.x,target.y))
	else:
		u.acted = true
		u.refresh()
		# 40479D: only a real move enters the execution/pickup/T510 tail.
		# Pure wait (and the native move2 skip) bypasses that entire block.
		if u.moved:await _after_completed_action(u)
	# Attack/skill already run their synchronous completion hook exactly once.
	update_hud()


func _adjacent_free(goal: Vector2i, u) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bestd := 99999
	for step in DIRS:
		var t: Vector2i = goal + step
		if _in_bounds(t) and not _is_occupied(t, u) 				and move_cost(u.bingzhong, _terrain_at(t)) < 99:
			var d: int = absi(t.x - u.x) + absi(t.y - u.y)
			if d < bestd:
				bestd = d
				best = t
	return best


func _greedy_step(u, goal: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bestd := 99999
	for d in DIRS:
		var t: Vector2i = Vector2i(u.x, u.y) + d
		if not _in_bounds(t) or _is_occupied(t, u):
			continue
		if move_cost(u.bingzhong, _terrain_at(t)) >= 99:
			continue
		var dist: int = absi(t.x - goal.x) + absi(t.y - goal.y)
		if dist < bestd:
			bestd = dist
			best = t
	return best


func _astar(start: Vector2i, goal: Vector2i, u, pass_allies := false) -> Array:
	if start == goal:
		return []
	if not _in_bounds(goal):
		return []
	var open: Array = [start]
	var g: Dictionary = {start: 0}
	var f: Dictionary = {start: abs(start.x - goal.x) + abs(start.y - goal.y)}
	var prev: Dictionary = {}
	var nodes := 0
	while not open.is_empty() and nodes < 6000:
		nodes += 1
		var bi := 0
		for i in range(1, open.size()):
			if int(f.get(open[i], 999999)) < int(f.get(open[bi], 999999)):
				bi = i
		var cur: Vector2i = open[bi]
		if cur == goal:
			var path: Array = []
			while cur != start:
				path.append(cur)
				cur = prev[cur]
			path.reverse()
			return path
		open.remove_at(bi)
		for d in DIRS:
			var n: Vector2i = cur + d
			if not _in_bounds(n):
				continue
			if _is_occupied(n, u, pass_allies, u) and n != goal:
				continue
			var c := move_cost(u.bingzhong, _terrain_at(n))
			if c >= 99:
				continue
			var ng := int(g[cur]) + c
			if ng < int(g.get(n, 999999)):
				g[n] = ng
				prev[n] = cur
				f[n] = ng + abs(n.x - goal.x) + abs(n.y - goal.y)
				if not open.has(n):
					open.append(n)
	return []


func _in_attack_range(attacker: Node2D, defender: Node2D) -> bool:
	var targets := attack_targets(attacker)
	return targets.has(Vector2i(defender.x, defender.y))


# ---------------- 无头全通 bot ----------------

func _bot_pick_target(u: Node2D, targets: Dictionary):
	if targets.is_empty():
		return null
	var obj: Dictionary = level.get("objective", {})
	var wanted: Array = obj.get("name_keys", [])
	for t in targets:
		var e = targets[t]
		if str(e.key) in wanted:
			return e
	var best = null
	var bd := 999999
	for t in targets:
		var e = targets[t]
		var d: int = absi(e.x - u.x) + absi(e.y - u.y)
		if d < bd:
			bd = d
			best = e
	return best


func _bot_move_to(u: Node2D, goal: Vector2i, _pass_allies := false) -> bool:
	if not _in_bounds(goal): return false
	var start := Vector2i(u.x,u.y)
	if start==goal:return false
	var destinations := compute_reachable(u)
	var destination := start
	var best := 999999
	# Global route chooses an intention only; legal Dijkstra/ZOC determines all actual steps.
	var route := _astar(start,goal,u,true)
	for index in range(route.size()):
		if destinations.has(route[index]):
			destination = route[index]
			best = route.size()-index
	if destination == start:
		for tile in destinations:
			var score: int = absi(tile.x-goal.x)+absi(tile.y-goal.y)
			if score < best: destination = tile; best=score
	if destination == start: return false
	var path := _path_to(destination,start)
	for step in path:
		u.direction = _facing(Vector2i(u.x,u.y),step)
		u.advance_display(4)
		u.set_tile(step.x,step.y)
		u.moved = true
		if await _trigger_mine(step,u): u.acted = true; break
		if not u.alive or finished_flag: break
	if u.acted:await _after_completed_action(u)
	u.refresh()
	return not path.is_empty()


func _approach_tile(goal: Vector2i, u: Node2D, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bestd := 999999
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			var t := goal + Vector2i(dx, dy)
			if not _in_bounds(t) or _is_occupied(t, u):
				continue
			if move_cost(u.bingzhong, _terrain_at(t)) >= 99:
				continue
			var d: int = absi(t.x - goal.x) + absi(t.y - goal.y)
			if d < bestd:
				bestd = d
				best = t
	return best


func _bot_norm(text: String) -> String:
	return str(text).replace("\u3000", "").replace(" ", "")


func _bot_is_protected(u: Node2D) -> bool:
	for n in level.get("protect", []):
		if _bot_norm(str(n)) == _bot_norm(u.unit_name) \
				or _bot_norm(str(n)) == _bot_norm(u.key):
			return true
	return u.protected


func _bot_retreat(u: Node2D) -> void:
	var nearest := _nearest_side(u, "enemy")
	if nearest == null:
		selected=u
		await _on_wait()
		return
	var best := Vector2i(u.x, u.y)
	var bestd := -1
	for d in [Vector2i(8, 0), Vector2i(-8, 0), Vector2i(0, 8), Vector2i(0, -8),
			Vector2i(6, 6), Vector2i(-6, 6), Vector2i(6, -6), Vector2i(-6, -6)]:
		var t: Vector2i = Vector2i(clampi(u.x + d.x, 0, map_w - 1),
				clampi(u.y + d.y, 0, map_h - 1))
		var dd: int = absi(t.x - nearest.x) + absi(t.y - nearest.y)
		if dd > bestd and not _is_occupied(t, u) \
				and move_cost(u.bingzhong, _terrain_at(t)) < 99:
			bestd = dd
			best = t
	if best != Vector2i(u.x, u.y):
		await _bot_move_to(u, best)
	if u.alive and not u.acted and not finished_flag:
		selected=u
		await _on_wait()


func _bot_unit(u: Node2D) -> void:
	if u == null or not u.alive or finished_flag:
		return
	var obj_type := str(level.get("objective", {}).get("type", "annihilate"))
	var focused := obj_type in ["reach", "reach_unit", "kill", "collect", "race",
			"capture_or_annihilate"]
	var goal := {"kind": "hold", "tile": Vector2i(u.x, u.y)}
	if scenario != null:
		goal = scenario.bot_goal(u)
	if _bot_is_protected(u) and obj_type in ["kill", "annihilate", "survive"]:
		await _bot_retreat(u)
		return
	# 主角阵亡会触发原版 hero_lost；bot 不让主角主动接敌，残血/近敌先脱离。
	if scenario != null and scenario.protagonist == u and player_units.size() > 1 \
			and (obj_type != "reach_unit" or scenario.objective_satisfied()):
		var near = _nearest_side(u, "enemy")
		var danger := near != null and absi(near.x - u.x) + absi(near.y - u.y) <= 3
		if danger or int(u.hp) * 10 < int(u.max_hp) * 9:
			await _bot_retreat(u)
			return
	# 目标关先赶路；只有目标本身或挡路敌人值得停下来打。
	if not focused:
		var targets0 := attack_targets(u)
		var target0 = _bot_pick_target(u, targets0)
		if target0 != null:
			await _perform_attack(u, target0)
			return
	var moved := false
	if str(goal.get("kind", "")) == "unit":
		var tu = goal.get("unit", null)
		if tu != null and is_instance_valid(tu) and tu.alive:
			var dist := absi(tu.x - u.x) + absi(tu.y - u.y)
			if dist <= 1 and obj_type == "reach_unit":
				if scenario != null:
					await scenario.on_unit_moved(u)
					scenario.check_end()
				u.acted = true
				return
			if dist > 1:
				# reach_unit 的目标单位通常被友军围住；bot 允许从友军
				# 之间穿过，否则 L01 会在最后一格前反复卡住到回合上限。
				moved = await _bot_move_to(u, Vector2i(tu.x, tu.y),
						obj_type == "reach_unit")
	elif str(goal.get("kind", "")) == "tile":
		var tt: Vector2i = goal.get("tile", Vector2i(-1, -1))
		moved = await _bot_move_to(u, tt, true)
	if finished_flag or not u.alive:
		return
	var after := attack_targets(u)
	var target2 = _bot_pick_target(u, after)
	if target2 != null and (not focused or moved or _bot_is_goal_target(target2, goal) \
			or (scenario != null and scenario.trigger_authoritative \
				and obj_type in ["annihilate", "reach", "collect", "capture_or_annihilate"])):
		await _perform_attack(u, target2)
		return
	u.acted = true
	u.refresh()


func _bot_is_goal_target(target: Node2D, goal: Dictionary) -> bool:
	if str(goal.get("kind", "")) != "unit":
		return false
	var gu = goal.get("unit", null)
	return gu != null and target == gu

func _bot_player_turn() -> void:
	for u in player_units:
		if finished_flag:
			return
		if not u.alive or u.auto or u.acted:
			continue
		await _bot_unit(u)


func autoplay(max_turns: int = 80) -> Dictionary:
	fast_sim = true
	ai_delay = 0.0
	stats["bot_trace"] = []
	while not finished_flag and turn <= max_turns:
		if turn % 5 == 1:
			var tr := {"turn": turn, "players": [], "enemies": _alive_count(enemy_units)}
			for pu in player_units:
				if pu.alive:
					tr["players"].append([pu.unit_name, pu.x, pu.y])
			stats["bot_trace"].append(tr)
		await _bot_player_turn()
		if scenario != null and not finished_flag:
			await scenario.on_tick()
		if finished_flag:
			break
		await _on_end_turn()
		if scenario != null and not finished_flag:
			await scenario.on_tick()
		if finished_flag:
			break
	var out := {"result": last_result, "message": last_message, "turn": turn,
			"stats": stats.duplicate(true),
			"finished": finished_flag, "phase": phase}
	fast_sim = false
	return out


# ---------------- 按钮 ----------------

func _on_attack() -> void:
	if selected == null or busy or phase != "player":
		return
	if selected.acted or not selected.is_player() or not selected.control:
		return
	_close_context_menu()
	_target_native_range(selected,int(selected.select),false,"attack-target")
	attack_tiles.clear()
	for tile in RangeMask.cells(native_dark_mask,map_w,map_h):attack_tiles[tile]=_unit_at(tile)
	mode = "attack"
	move_tiles.clear()
	_log("选择落点（橙格为伤害范围）")
	update_hud()


func _on_mine() -> void:
	if not can_mine(selected):return
	_close_context_menu();_close_action_panel();_clear_native_range("menu")
	var picker=preload("res://scripts/ui/OriginalChoice.gd").new()
	hud_root.add_child(picker);action_panel=picker
	var commands:=["place","recover","timer","remote","give"]
	picker.chosen.connect(func(index:int):_mine_command(commands[index]))
	picker.cancelled.connect(_cancel_native_choice)
	picker.setup(font,["埋 设","起 出","定 时","遥 控","交 给"],Vector2(300,280))


func _on_skill() -> void:
	_open_skill_menu()


func _on_item() -> void:
	_open_item_menu()


func _confirm_touch_ending_action(title: String, commit: Callable) -> void:
	# Guard UI entry points only: automated resolvers and the desktop keep their
	# original semantics. Cancellation never reaches the irreversible callback.
	if not _touch_mode():
		commit.call()
		return
	if selected == null or busy or selected.acted or phase != "player":return
	var actor = selected
	_close_context_menu()
	_close_action_panel()
	touch_cancel()
	var confirm = preload("res://scripts/ui/OriginalConfirm.gd").new()
	hud_root.add_child(confirm)
	action_panel = confirm
	confirm.answered.connect(func(yes: bool):
		if action_panel != confirm:return
		_close_action_panel()
		if not is_instance_valid(actor) or selected != actor or actor.acted or not actor.alive:return
		if yes:commit.call()
		else:_return_action_menu()
	)
	confirm.setup(font,title,Vector2(256,176))

func _request_wait() -> void:
	_confirm_touch_ending_action("休息结束行动？",_on_wait)


func _on_wait() -> void:
	if selected == null or busy or phase != "player":
		return
	if not selected.is_player() or not selected.control:
		return
	var caster = selected
	_clear_native_range()
	_selection_origin.clear()
	selected.acted = true
	selected.moved = true
	selected.refresh()
	_log("%s 待机" % selected.unit_name)
	selected.set_selected(false)
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	update_hud()

	await _after_completed_action(caster)


func _on_cancel() -> void:
	_cancel()


# ---------------- 绘制 / 特效 ----------------

func draw_overlay(ci: CanvasItem) -> void:
	# Modern aim-only aid: the native light mask is SELECTABLE LANDINGS, not
	# the effect area. Normal attacks retain their strength percentages;
	# skills show actual success probability, gray for no possible effect.
	# Never paint over HUD.
	var skill_preview:=mode=="skill"
	var cells:=skill_preview_cells() if skill_preview else attack_preview_cells()
	if cells.is_empty():
		_draw_touch_aim(ci)
		return
	var clip:=Rect2(Vector2.ZERO,Vector2(map_w*TILE,map_h*TILE))
	if camera!=null:
		clip=Rect2(camera.position+map_rect().position-Vector2(320,240),map_rect().size)
	for cell in cells:
		var rect:=Rect2(Vector2(cell.tile*TILE)+Vector2(1,1),Vector2(TILE-2,TILE-2))
		var visible:=rect.intersection(clip)
		if not visible.has_area():continue
		var effective:=not skill_preview or bool(cell.effective)
		ci.draw_rect(visible,Color(1.0,0.52,0.1,0.25) if effective else Color(0.42,0.45,0.49,0.34))
		ci.draw_rect(visible,Color(1.0,0.68,0.22,0.95) if effective else Color(0.64,0.67,0.7,0.9),false,1.0)
		var label_pos:=rect.position+Vector2(4,16)
		if font!=null and clip.encloses(Rect2(label_pos-Vector2(0,13),Vector2(38,16))):
			var text:=str(int(cell.chance) if skill_preview else int(cell.pct))+"%"
			# HZK16's native size keeps probability digits crisp at 1:1 zoom.
			var label_size:=16 if skill_preview else 12
			ci.draw_string_outline(font,label_pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size,3,Color(0.12,0.1,0.05,0.95))
			ci.draw_string(font,label_pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size,Color(1.0,0.92,0.65) if effective else Color(0.86,0.88,0.9))
	var aim:=Rect2(Vector2(hover_tile*TILE)+Vector2(3,3),Vector2(TILE-6,TILE-6)).intersection(clip)
	if aim.has_area():ci.draw_rect(aim,Color(1.0,0.95,0.65),false,2.0)


func _spawn_float(text: String, world: Vector2, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	l.position = world - Vector2(24, 30)
	l.z_index = 100
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_root.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position", l.position + Vector2(0, -26), 0.75)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.75)
	tw.tween_callback(l.queue_free)


func _finish(result: String, message: String) -> void:
	if finished_flag or _finishing:
		return
	_finishing = true
	_clear_native_range()
	_selection_origin.clear()
	finished_flag = true
	last_result = result
	last_result_condition = message
	last_message = message if result == "victory" else "战斗失败！"
	emit_story_event("victory" if result == "victory" else "defeat",
			{"message": last_message})
	phase = "done"
	busy = true
	selected = null
	move_tiles.clear()
	attack_tiles.clear()
	stats["turns"] = turn
	stats["enemies_left"] = _alive_count(enemy_units)
	stats["players_left"] = _alive_count(player_units)
	stats["log"] = log_history.duplicate()
	if playtest_mode:
		_append_playtest_report(result, last_message)
	update_hud()
	finished.emit(result, last_message)
