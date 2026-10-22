extends Node2D

## M1 战斗核心：地图、单位、Dijkstra 移动、普通攻击、地雷、回合与简单 AI。

signal finished(result: String, message: String)
signal looted(item_id: int)
signal story_event(kind: String, data: Dictionary)

const CombatRules = preload("res://scripts/battle/CombatRules.gd")
const TILE := 48
const SIDEBAR_SHIFT := 100.0
const TOP_SHIFT := 40.0
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

var map_sprite: Sprite2D
var units_root: Node2D
var fx_root: Node2D
var overlay: Node2D
var camera: Camera2D

var hud_layer: CanvasLayer
var hud_root: Control
var level_label: Label
var turn_label: Label
var phase_label: Label
var objective_label: Label
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
var battle_context: Dictionary = {}
var consumed_mines: Dictionary = {}
var consumed_items: Dictionary = {}
var active_skill: Dictionary = {}
var active_skill_id := -1
var active_item_id := -1
var mine_texture: Texture2D
var chest_nodes: Dictionary = {}
var chests: Array = []
var scenario
var stats := {"kills": 0, "losses": 0, "chests": 0, "deployed": 0}
var ai_delay := 0.02
var _finishing := false
var fast_sim := false
var last_result := ""
var last_message := ""
var log_history: Array = []
var pending_story: Array = []
var sfx_nodes: Array = []


func setup(d: Dictionary, lv: Dictionary, f: Font, ctx: Dictionary = {}) -> void:
	data = d
	level = lv
	font = f
	map_w = int(level["map"]["width"])
	map_h = int(level["map"]["height"])
	terrain = level["map"]["terrain"]
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
	chests.clear()
	for c in level.get("chests", []):
		var cc: Dictionary = (c as Dictionary).duplicate(true)
		cc["opened"] = false
		chests.append(cc)
	_build_world()
	# 目标单位必须在单位生成后缓存；否则 reach_unit 会永远找不到目标。
	scenario.setup(self, level)
	_spawn_level_markers()
	if scenario != null:
		scenario.on_start()
	_build_hud()
	turn = 1
	phase = "player"
	stats["deployed"] = player_units.size()
	stats["enemies_total"] = enemy_units.size()
	_begin_player_phase("第 1 回合，我方行动")


func _build_world() -> void:
	map_sprite = Sprite2D.new()
	map_sprite.centered = false
	map_sprite.position = Vector2.ZERO
	map_sprite.z_index = -100
	var mp := str(level["map"]["png"])
	if ResourceLoader.exists(mp):
		map_sprite.texture = load(mp)
	add_child(map_sprite)

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
	# 让 640×480 的可见地图区（左侧 440×450）尽量多看到战场：
	# 小图整图入镜，大图至少 20+ tile，避免 65×60 的关卡只看到一角。
	var fit := minf(440.0 / float(max(1, map_w * TILE)),
			450.0 / float(max(1, map_h * TILE)))
	var z := clampf(fit, 0.35, 1.0)
	camera.zoom = Vector2(z, z)
	camera.position = _initial_camera()
	add_child(camera)
	camera.make_current()
	_clamp_camera()


func _spawn_unit(ud: Dictionary) -> Node2D:
	var u = preload("res://scripts/BattleUnit.gd").new()
	units_root.add_child(u)
	u.setup(ud, self)
	if u.protected:
		# 保护目标使用战役耐久：原版 96 HP 的剧情人物在 40 级敌军面前
		# 会被一击带走，导致护送/坚守关无法完成。这里只提高“被保护者”
		# 的耐久，不改变其攻击/移动/技能。
		u.max_hp = maxi(u.max_hp, 2000)
		u.hp = u.max_hp
	units.append(u)
	if u.is_player():
		player_units.append(u)
	else:
		enemy_units.append(u)
	return u


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
	u.moved = true
	u.acted = true
	u.refresh()
	return u


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
	chest_nodes.clear()
	for i in range(chests.size()):
		var c: Dictionary = chests[i]
		var s := Sprite2D.new()
		if ResourceLoader.exists("res://assets/ui/chest_sheet.png"):
			var at := AtlasTexture.new()
			at.atlas = load("res://assets/ui/chest_sheet.png")
			at.region = Rect2(0, 0, 48, 48)
			s.texture = at
		s.centered = true
		s.position = Vector2(int(c["x"]) * TILE + TILE / 2.0,
				int(c["y"]) * TILE + TILE / 2.0)
		s.z_index = 150
		units_root.add_child(s)
		chest_nodes[i] = s


func _chest_at(t: Vector2i) -> int:
	for i in range(chests.size()):
		var c: Dictionary = chests[i]
		if not bool(c.get("opened", false)) and int(c["x"]) == t.x and int(c["y"]) == t.y:
			return i
	return -1


func _open_chest(u, i: int) -> void:
	_play_sfx(514)
	var c: Dictionary = chests[i]
	c["opened"] = true
	stats["chests"] = int(stats.get("chests", 0)) + 1
	if chest_nodes.has(i):
		var node = chest_nodes[i]
		if is_instance_valid(node):
			node.modulate = Color(0.4, 0.4, 0.4, 0.35)
	if scenario != null:
		scenario.on_chest(u, c)
	update_hud()


func _after_unit_step(u) -> void:
	if u == null or not u.alive or finished_flag:
		return
	var t := Vector2i(u.x, u.y)
	if u.is_player():
		var ci := _chest_at(t)
		if ci >= 0:
			_open_chest(u, ci)
	if scenario != null:
		scenario.on_unit_moved(u)
	if not _check_end():
		update_hud()


func _initial_camera() -> Vector2:
	if not player_units.is_empty():
		var sx := 0.0
		var sy := 0.0
		for u in player_units:
			sx += float(u.x)
			sy += float(u.y)
		return Vector2(sx / player_units.size() * TILE + TILE / 2.0 + _cam_shift(),
				sy / player_units.size() * TILE + TILE / 2.0 - _cam_shift_y())
	var p = level["map"].get("player_focus", [0, 0])
	return Vector2(float(p[0]) * TILE + TILE / 2.0,
			float(p[1]) * TILE + TILE / 2.0)


func _cam_shift() -> float:
	if camera == null:
		return SIDEBAR_SHIFT
	return SIDEBAR_SHIFT / maxf(0.01, camera.zoom.x)


func _cam_shift_y() -> float:
	if camera == null:
		return TOP_SHIFT
	return TOP_SHIFT / maxf(0.01, camera.zoom.y)


func _clamp_camera() -> void:
	if camera == null:
		return
	var half := Vector2(220.0, 225.0) / camera.zoom
	var w := map_w * TILE
	var h := map_h * TILE
	var pos := camera.position
	if w <= half.x * 2.0:
		pos.x = w / 2.0 + _cam_shift()
	else:
		pos.x = clampf(pos.x, half.x, w - half.x)
	if h <= half.y * 2.0:
		pos.y = h / 2.0 - _cam_shift_y()
	else:
		pos.y = clampf(pos.y, half.y, h - half.y)
	camera.position = pos


# ---------------- HUD ----------------

func _hud_label(text: String, pos: Vector2, size: Vector2,
		fs: int = 16, color: Color = Color("#e8edf4")) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
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

	# 原版 KUANG00 战斗框；绿色色键已在 prepare_m3 里抠掉
	var frame := TextureRect.new()
	frame.texture = load("res://assets/ui/hud_battle.png") \
			if ResourceLoader.exists("res://assets/ui/hud_battle.png") else null
	frame.position = Vector2.ZERO
	frame.size = Vector2(640, 480)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(frame)

	# 顶部战报条
	var top := ColorRect.new()
	top.color = Color(0.16, 0.025, 0.025, 0.94)
	top.position = Vector2.ZERO
	top.size = Vector2(440, 54)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top)
	var line := ColorRect.new()
	line.color = OriginalUI.GOLD
	line.position = Vector2(0, 53)
	line.size = Vector2(440, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(line)
	level_label = _hud_label("", Vector2(8, 3), Vector2(424, 22), 16,
			OriginalUI.GOLD_LIGHT)
	objective_label = _hud_label("", Vector2(8, 26), Vector2(424, 24), 16,
			Color("#f2ead6"))
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 右侧状态栏
	turn_label = _hud_label("", Vector2(452, 36), Vector2(176, 20), 16,
			OriginalUI.GOLD_LIGHT)
	phase_label = _hud_label("", Vector2(452, 56), Vector2(176, 20), 16,
			PLAYER_COLOR)
	enemy_label = _hud_label("", Vector2(452, 76), Vector2(176, 20), 16)
	mine_label = _hud_label("", Vector2(452, 96), Vector2(176, 20), 16,
			OriginalUI.GOLD)

	portrait = TextureRect.new()
	portrait.position = Vector2(456, 122)
	portrait.size = Vector2(72, 90)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(portrait)
	unit_label = _hud_label("", Vector2(452, 214), Vector2(178, 82), 14)

	btn_attack = _hud_button("攻击", Vector2(450, 300), Vector2(84, 28), _on_attack)
	btn_skill = _hud_button("技能", Vector2(542, 300), Vector2(84, 28), _on_skill)
	btn_mine = _hud_button("埋雷", Vector2(450, 334), Vector2(84, 28), _on_mine)
	btn_item = _hud_button("物品", Vector2(542, 334), Vector2(84, 28), _on_item)
	btn_wait = _hud_button("待机", Vector2(450, 368), Vector2(84, 28), _on_wait)
	btn_cancel = _hud_button("取消", Vector2(542, 368), Vector2(84, 28), _on_cancel)
	btn_end = _hud_button("结束回合", Vector2(450, 404), Vector2(176, 28), _on_end_turn)
	btn_end.add_theme_color_override("font_color", OriginalUI.GOLD_LIGHT)

	# 底部战斗记录
	var log_bg := ColorRect.new()
	log_bg.color = Color(0.02, 0.015, 0.01, 0.78)
	log_bg.position = Vector2(8, 392)
	log_bg.size = Vector2(432, 66)
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(log_bg)
	var log_line := ColorRect.new()
	log_line.color = Color(0.61, 0.45, 0.18, 0.75)
	log_line.position = Vector2(8, 391)
	log_line.size = Vector2(432, 1)
	log_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(log_line)
	message_label = _hud_label("", Vector2(14, 396), Vector2(420, 58), 16,
			Color("#d9c9a8"))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


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
	enemy_label.text = "敌军 %d / 我军 %d" % [_alive_count(enemy_units), _alive_count(player_units)]
	var cur_mine := "?"
	var mine_defs: Array = data.get("mines", [])
	if mine_kind >= 0 and mine_kind < mine_defs.size():
		cur_mine = str(mine_defs[mine_kind].get("name", "?"))
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
		unit_label.text = "%s [%s] Lv%d\nHP %d/%d  士气%d\n攻%d 防%d 移%d\nEXP %d/100  装备:%s\n%s" % [
			u.unit_name, tag, int(u.data.get("level", 1)), u.hp, u.max_hp, u.morale,
			atk, df, u.move, int(u.gained_xp) % 100, equip_txt, state
		]
		if u.data.get("face_png", "") != "" and ResourceLoader.exists(u.data["face_png"]):
			portrait.texture = load(u.data["face_png"])
			portrait.visible = true
		else:
			portrait.visible = false
	else:
		unit_label.text = "点击我方单位开始行动\n左键移动 / 右键取消"
		portrait.visible = false

	var can_act: bool = phase == "player" and not busy and not finished_flag
	var controllable: bool = selected != null and selected.is_player() and selected.control
	btn_attack.disabled = not (can_act and controllable and not selected.acted
			and not attack_targets(selected).is_empty())
	btn_mine.disabled = not can_act or not controllable or not can_mine(selected)
	btn_skill.disabled = not (can_act and controllable and not selected.acted
			and not available_skills(selected).is_empty())
	btn_item.disabled = not (can_act and controllable and not selected.acted)
	btn_wait.disabled = not (can_act and controllable and not selected.acted)
	btn_cancel.disabled = mode == "idle" and selected == null and action_panel == null
	btn_end.disabled = not can_act
	if phase == "player":
		btn_end.text = "结束回合"
	elif phase == "enemy":
		btn_end.text = "敌方行动中…"
	else:
		btn_end.text = "战斗结束"
	if overlay != null:
		overlay.queue_redraw()


func _play_flm(flm_index: int, world: Vector2, scale_factor: float = 1.0) -> void:
	if flm_index < 0:
		return
	var path := "res://assets/flm/flm_%03d.png" % flm_index
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("default")
	frames.set_animation_speed("default", 24.0)
	frames.set_animation_loop("default", false)
	for i in range(16):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * TILE, 0, TILE, TILE)
		frames.add_frame("default", at)
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = frames
	anim.position = world
	anim.scale = Vector2(scale_factor, scale_factor)
	anim.z_index = 0
	anim.animation_finished.connect(anim.queue_free)
	fx_root.add_child(anim)
	anim.play("default")


func _play_sfx(wave_id: int, volume_db: float = -6.0) -> void:
	if wave_id < 0:
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

func _process(delta: float) -> void:
	if camera == null:
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
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * 420.0 * delta / camera.zoom.x
		_clamp_camera()
	var mouse := get_global_mouse_position()
	var t := _tile_of(mouse)
	if t != hover_tile:
		hover_tile = t
		if overlay != null:
			overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if finished_flag or busy or phase != "player":
				return
			_on_map_click(_tile_of(get_global_mouse_position()))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
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
			_on_wait()
		elif event.keycode == KEY_6:
			_on_end_turn()


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
		if u.alive and u.x == t.x and u.y == t.y:
			return u
	return null


func _is_occupied(t: Vector2i, ignore: Node2D = null) -> bool:
	for u in units:
		if u == ignore or not u.alive:
			continue
		if u.x == t.x and u.y == t.y:
			return true
	return false


func _on_map_click(t: Vector2i) -> void:
	if not _in_bounds(t):
		return
	if mode == "skill":
		if attack_tiles.has(t):
			_execute_skill_at(t)
			return
		_cancel()
		return
	if mode == "item":
		if attack_tiles.has(t):
			_execute_item_at(t)
			return
		_cancel()
		return
	if mode == "attack":
		if attack_tiles.has(t):
			var target := _unit_at(t)
			if target != null and target.side != "player":
				_player_attack(target)
				return
		_cancel()
		return
	if mode == "move":
		if move_tiles.has(t):
			_player_move(t)
			return
		_cancel()
		return
	# 已选中单位时，点击蓝色可达格直接移动（mode 仍为 idle）
	if selected != null and is_instance_valid(selected) and selected.is_player() \
			and selected.control and not selected.moved and move_tiles.has(t):
		_player_move(t)
		return
	var u := _unit_at(t)
	if u != null and u.alive:
		_select_unit(u)
	else:
		_clear_selection()


func _select_unit(u: Node2D) -> void:
	if selected != null and is_instance_valid(selected):
		selected.set_selected(false)
	selected = u
	u.set_selected(true)
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	if u.is_player() and not u.acted and u.control:
		if not u.moved:
			move_tiles = compute_reachable(u)
		attack_tiles = attack_targets(u)
	_log("%s：HP %d/%d" % [u.unit_name, u.hp, u.max_hp])
	update_hud()


func _clear_selection() -> void:
	if selected != null and is_instance_valid(selected):
		selected.set_selected(false)
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	update_hud()


func _cancel() -> void:
	if action_panel != null:
		_close_action_panel()
		update_hud()
		return
	if mode != "idle":
		mode = "idle"
		active_skill = {}
		active_skill_id = -1
		active_item_id = -1
		move_tiles.clear()
		attack_tiles.clear()
		if selected != null and selected.is_player() and not selected.moved:
			move_tiles = compute_reachable(selected)
		update_hud()
	else:
		_clear_selection()


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
	camera.position = Vector2(u.x * TILE + 24 + _cam_shift(),
			u.y * TILE + 24 - _cam_shift_y())
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
		for d in DIRS:
			var n: Vector2i = cur + d
			if not _in_bounds(n):
				continue
			if _is_occupied(n, u):
				continue
			var c := move_cost(u.bingzhong, _terrain_at(n))
			if c >= 99:
				continue
			var nd := int(dist[cur]) + c
			if nd > u.move:
				continue
			if not dist.has(n) or nd < int(dist[n]):
				dist[n] = nd
				prev[n] = cur
				if not open.has(n):
					open.append(n)
	dist.erase(start)
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


func attack_targets(u: Node2D) -> Dictionary:
	var out := {}
	var ranges: Dictionary = data.get("select_ranges", {})
	var m = ranges.get(str(u.select), ranges.get("1", []))
	if m == null or m.is_empty():
		m = ranges.get("1", [])
	var sum := 0
	if m.size() >= 9:
		for row in m:
			for v in row:
				sum += int(v)
	if sum == 0 and m.size() >= 9:
		m = ranges.get("1", m)
	if m.size() < 9:
		return out
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if int(m[dy + 4][dx + 4]) <= 0:
				continue
			var t := Vector2i(u.x + dx, u.y + dy)
			if not _in_bounds(t):
				continue
			var target := _unit_at(t)
			if target != null and target.side != u.side:
				out[t] = target
	return out


func _player_move(t: Vector2i) -> void:
	if selected == null or busy:
		return
	var u = selected
	var start := Vector2i(u.x, u.y)
	var path := _path_to(t, start)
	if path.is_empty():
		return
	busy = true
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	update_hud()
	_play_sfx(int(unit_class(u).get("audio_yidong", -1)), -10.0)
	for step in path:
		await u.move_visual(step.x, step.y, 0.075)
	u.moved = true
	u.refresh()
	attack_tiles = attack_targets(u)
	busy = false
	_log("%s 移动到 (%d,%d)" % [u.unit_name, u.x, u.y])
	_after_unit_step(u)
	update_hud()


# ---------------- 攻击 ----------------

func compute_damage(attacker: Node2D, defender: Node2D) -> int:
	return clampi(CombatRules.damage(_effective_attack(attacker),
			_effective_defense(defender)), 1, defender.hp)


func _attack_anim(attacker: Node2D, defender: Node2D) -> void:
	if fast_sim:
		return
	if attacker.has_method("play_attack"):
		attacker.play_attack()
	var from: Vector2 = attacker.position
	var dir: Vector2 = (defender.position - from).normalized()
	var tw := create_tween()
	tw.tween_property(attacker, "position", from + dir * 18.0, 0.07)
	tw.tween_property(attacker, "position", from, 0.09)
	await tw.finished


func _perform_attack(attacker: Node2D, defender: Node2D, counter: bool = false) -> void:
	if attacker == null or defender == null or not attacker.alive or not defender.alive:
		return
	if int(attacker.status_stun) > 0:
		attacker.acted = true
		attacker.refresh()
		_log("%s 被疑兵压制，无法攻击" % attacker.unit_name)
		return
	busy = true
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	update_hud()
	_play_sfx(int(unit_class(attacker).get("audio_gongji", -1)))
	_play_flm(int(unit_class(attacker).get("flm_gongji", -1)),
			(defender.position + attacker.position) * 0.5)
	await _attack_anim(attacker, defender)
	attacker.attack_count += 1
	var dmg := compute_damage(attacker, defender)
	var died := _apply_hp_damage(defender, dmg)
	_log("%s 攻击 %s，造成 %d 伤害（士气 %d）" % [
		attacker.unit_name, defender.unit_name, dmg, defender.morale])
	attacker.acted = true
	attacker.refresh()
	busy = false
	if died:
		_gain_xp(attacker, CombatRules.kill_experience(attacker.data.get("level", 1),
				defender.data.get("level", 1)))
		_on_unit_died(defender)
	elif not counter and _in_attack_range(defender, attacker) 			and int(defender.status_stun) <= 0 and defender.side != attacker.side:
		# 受击方在射程内且未被压制时反击一次。原版反击公式仍待抽样复核。
		await _perform_attack(defender, attacker, true)
	update_hud()
	if not _check_end():
		if selected != null and is_instance_valid(selected):
			if selected.acted:
				selected.set_selected(false)
				selected = null
				update_hud()


func _player_attack(target: Node2D) -> void:
	if selected == null or busy:
		return
	var attacker = selected
	await _perform_attack(attacker, target)


func _on_unit_died(u: Node2D) -> void:
	if u == null or not u.alive:
		return
	u.die()
	stats["kills" if u.side == "enemy" else "losses"] = int(
			stats.get("kills" if u.side == "enemy" else "losses", 0)) + 1
	_log("%s 阵亡" % u.unit_name)
	if scenario != null:
		scenario.on_unit_died(u)
		if finished_flag:
			return
	# M1 兼容：关卡文本里的失败单位
	for name in level.get("fail_units", []):
		if u.unit_name == str(name):
			_finish("defeat", "%s 阵亡" % u.unit_name)
			return
	_check_end()


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
	var src: Dictionary = battle_context.get(kind, {})
	return int(src.get(str(id), 0))


func _consume_inventory(kind: String, id: int) -> bool:
	if _inventory_count(kind, id) <= 0:
		return false
	var src: Dictionary = battle_context.get(kind, {})
	src[str(id)] = int(src.get(str(id), 0)) - 1
	battle_context[kind] = src
	var used: Dictionary = consumed_mines if kind == "mines" else consumed_items
	used[str(id)] = int(used.get(str(id), 0)) + 1
	if kind == "mines":
		consumed_mines = used
		battle_context["consumed_mines"] = used
		_refresh_mine_left()
	else:
		consumed_items = used
		battle_context["consumed_items"] = used
	return true


func _refresh_mine_left() -> void:
	var total := 0
	for k in battle_context.get("mines", {}):
		total += int(battle_context["mines"][k])
	mines_left = total


func _gain_xp(u: Node2D, amount: int) -> void:
	if u == null or amount <= 0 or u.side != "player":
		return
	u.gained_xp += amount
	stats["xp"] = int(stats.get("xp", 0)) + amount


func _attack_level(u: Node2D) -> int:
	return CombatRules.skill_level(int(u.attack_count))


func _terrain_defense(u: Node2D) -> int:
	return terrain_bonus(Vector2i(u.x, u.y))


func _effective_defense(u: Node2D) -> int:
	var cls := unit_class(u)
	var penalty := 0.7 if int(u.status_def_down) > 0 else 1.0
	return int(CombatRules.defense_power(u.data, cls, u.morale,
			_terrain_defense(u), u.defense_bonus) * penalty)


func _effective_attack(u: Node2D) -> int:
	var cls := unit_class(u)
	var penalty := 0.7 if int(u.status_atk_down) > 0 else 1.0
	var atk := CombatRules.attack_power(u.data, cls, u.morale, u.integrity,
			int(u.attack_count), u.attack_bonus)
	return max(1, int(atk * penalty))


func _morale_loss(damage: int, max_hp: int) -> int:
	return max(1, 20 * damage / max(1, max_hp))


func _apply_hp_damage(target: Node2D, damage: int) -> bool:
	var died: bool = target.take_damage(damage)
	if not died:
		target.morale = max(0, int(target.morale) - _morale_loss(damage, target.max_hp))
	_spawn_float("-%d" % damage, target.position, Color("#ff6b6b"))
	return died


# ---------------- 地雷 ----------------

func _mine_at(t: Vector2i) -> int:
	for i in range(mines.size()):
		if mines[i]["tile"] == t:
			return i
	return -1


func can_mine(u: Node2D) -> bool:
	if u == null or phase != "player" or busy or finished_flag:
		return false
	if not u.is_player() or not u.control or u.acted or mines_left <= 0:
		return false
	if _inventory_count("mines", mine_kind) <= 0:
		return false
	var t := Vector2i(u.x, u.y)
	if _mine_at(t) >= 0:
		return false
	var rows: Array = data.get("mine_terrain", [])
	if mine_kind < 0 or mine_kind >= rows.size():
		return false
	var terr := _terrain_at(t)
	if terr < 0 or terr >= rows[mine_kind].size():
		return false
	return int(rows[mine_kind][terr]) == 1


func _place_mine() -> void:
	if not can_mine(selected):
		return
	var u = selected
	var t := Vector2i(u.x, u.y)
	if not _consume_inventory("mines", mine_kind):
		_log("库存没有这种地雷")
		return
	var m: Dictionary = (data.get("mines", []) as Array)[mine_kind]
	mines.append({"tile": t, "mine": m, "owner": u, "owner_side": u.side,
			"mine_id": mine_kind, "apply_fw": int(m.get("apply_fw", 0))})
	var icon := str(m.get("icon", ""))
	var tex := mine_texture
	if icon != "" and ResourceLoader.exists(icon):
		tex = load(icon)
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = true
		s.position = Vector2(t.x * TILE + 24, t.y * TILE + 24)
		s.z_index = 200
		s.modulate = Color(1, 1, 1, 0.82)
		units_root.add_child(s)
		mine_nodes[t] = s
	u.acted = true
	u.refresh()
	_log("%s 在 (%d,%d) 埋下%s，库存 %d 颗" % [
		u.unit_name, t.x, t.y, m["name"], _inventory_count("mines", mine_kind)])
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	_close_action_panel()
	update_hud()


func _play_anm_sheet(path: String, world: Vector2, scale_factor: float = 0.6) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var tex: Texture2D = load(path)
	if tex == null:
		return false
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("default")
	frames.set_animation_speed("default", 12.0)
	frames.set_animation_loop("default", false)
	var n := int(tex.get_width() / 320)
	for i in range(n):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * 320, 0, 320, 200)
		frames.add_frame("default", at)
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = frames
	anim.position = world
	anim.scale = Vector2(scale_factor, scale_factor)
	anim.z_index = 0
	anim.animation_finished.connect(anim.queue_free)
	fx_root.add_child(anim)
	anim.play("default")
	return true


func _play_mine_effect(mine_id: int, tile: Vector2i) -> void:
	var world := Vector2(tile.x * TILE + TILE / 2.0, tile.y * TILE + TILE / 2.0)
	if _play_anm_sheet("res://assets/m5/anm/mine%02d_sheet.png" % mine_id, world, 0.6):
		return
	var path := "res://assets/m5/anm/mine%02d.ogv" % mine_id
	if not ResourceLoader.exists(path):
		return
	var vp := VideoStreamPlayer.new()
	vp.stream = load(path)
	vp.expand = true
	vp.position = Vector2(tile.x * TILE - 72, tile.y * TILE - 36)
	vp.size = Vector2(192, 120)
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.z_index = 0
	vp.finished.connect(vp.queue_free)
	fx_root.add_child(vp)
	vp.play()


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


func _trigger_mine(t: Vector2i, u: Node2D) -> bool:
	if u == null or not u.alive or u.is_player():
		return false
	var idx := _mine_at(t)
	if idx < 0:
		return false
	var rec: Dictionary = mines[idx]
	var m: Dictionary = rec["mine"]
	var owner_side := str(rec.get("owner_side", "player"))
	mines.remove_at(idx)
	if mine_nodes.has(t):
		var node = mine_nodes[t]
		if is_instance_valid(node):
			node.queue_free()
		mine_nodes.erase(t)
	_play_sfx(int(m.get("audio_index", -1)), -2.0)
	_play_mine_effect(int(rec.get("mine_id", 0)), t)
	_play_flm(int(m.get("flm_index", -1)), Vector2(t.x * TILE + TILE / 2.0,
			t.y * TILE + TILE / 2.0), 1.4)
	var area := _mine_area(t, int(rec.get("apply_fw", m.get("apply_fw", 0))))
	var total := 0
	var deaths: Array = []
	for cell in area:
		var tt: Vector2i = cell["tile"]
		var pct := int(cell["pct"])
		var target := u if tt == Vector2i(u.x, u.y) else _unit_at(tt)
		if target == null or not target.alive or target.side == owner_side:
			continue
		var base := int(m.get("weili", 1)) * pct / 100
		if int(m.get("shiqi_or_tili", 0)) == 1:
			var ml := maxi(1, int(base))
			target.morale = max(0, target.morale - ml)
			_spawn_float("士气-%d" % ml, target.position, Color("#d18cff"))
			total += ml
		else:
			var dmg := maxi(1, int(base - _effective_defense(target) * 30 / 100))
			total += dmg
			if _apply_hp_damage(target, dmg):
				deaths.append(target)
	_log("%s 引爆%s！范围伤害 %d" % [u.unit_name, m["name"], total])
	for d in deaths:
		if is_instance_valid(d) and d.alive:
			_on_unit_died(d)
		elif is_instance_valid(d):
			_on_unit_died(d)
	return true


# ---------------- 技能 / 物品 ----------------

const SKILL_KEYS := ["buji", "jili", "yiliao", "huogong", "gunmu", "leishi",
		"weishe", "saorao", "pohuai", "lueduo", "fanjian", "yibing",
		"duzhan", "ansha", "shidu", "kongxi"]


func _unit_skills(u: Node2D) -> Dictionary:
	var flags: Dictionary = u.skills
	if flags.is_empty():
		flags = (unit_class(u).get("skills", {}) as Dictionary)
	return flags


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
			if int(mat[dy + 4][dx + 4]) <= 0:
				continue
			var t := Vector2i(u.x + dx, u.y + dy)
			if _in_bounds(t):
				out.append(t)
	if include_self:
		var st := Vector2i(u.x, u.y)
		if not out.has(st):
			out.append(st)
	return out


func _apply_tiles(center: Vector2i, apply_fw: int) -> Array:
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
			var t := Vector2i(center.x + dx, center.y + dy)
			if _in_bounds(t):
				out.append({"tile": t, "pct": pct})
	return out


func _skill_targets(caster: Node2D, skill: Dictionary) -> Dictionary:
	var out := {}
	var tid := int(skill.get("type", 0))
	var support := tid in [0, 1, 2, 10]
	var tiles := _select_tiles(caster, int(skill.get("select_fw", 1)), support)
	for t in tiles:
		var target := _unit_at(t)
		if target == null or not target.alive:
			continue
		if support and target.side == caster.side:
			out[t] = target
		elif not support and target.side != caster.side:
			out[t] = target
	return out


func _open_skill_menu() -> void:
	if selected == null or busy or phase != "player" or selected.acted:
		return
	var ids := available_skills(selected)
	if ids.is_empty():
		_log("%s 没有可用技能" % selected.unit_name)
		return
	var defs: Array = data.get("skills", [])
	var rows: Array = []
	for sid in ids:
		var sk: Dictionary = defs[sid]
		rows.append({
			"text": "%s  等级%d / 次数%d" % [
				sk.get("name", "?"), CombatRules.skill_level(_skill_count(selected, sid)),
				_skill_count(selected, sid)],
			"cb": _choose_skill.bind(sid),
		})
	_open_action_panel("选择技能", rows)


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
	mode = "skill"
	move_tiles.clear()
	attack_tiles = targets
	if targets.is_empty():
		_log("技能范围内没有目标")
		mode = "idle"
	else:
		_log("选择「%s」的目标" % active_skill.get("name", "技能"))
	update_hud()


func _execute_skill_at(tile: Vector2i) -> void:
	if selected == null or active_skill.is_empty():
		return
	var caster = selected
	var center := _unit_at(tile)
	if center == null:
		return
	var tid := int(active_skill.get("type", 0))
	var support := tid in [0, 1, 2, 10]
	if support != (center.side == caster.side):
		return
	var targets := _skill_targets(caster, active_skill)
	if not targets.has(tile):
		return
	busy = true
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	var sid := active_skill_id
	var count := _skill_count(caster, sid)
	# 原版先累计使用次数，再用累计后的等级算效果；第一次使用即 1 级。
	var effect1 := CombatRules.skill_effect(int(caster.data.get("zhili", 0)),
			int(active_skill.get("para1", 0)), count + 1)
	var effect2 := CombatRules.skill_effect(int(caster.data.get("zhili", 0)),
			int(active_skill.get("para2", 0)), count + 1)
	var area := _apply_tiles(Vector2i(center.x, center.y), int(active_skill.get("apply_fw", 0)))
	var affected := 0
	var deaths: Array = []
	for cell in area:
		var t: Vector2i = cell["tile"]
		var pct := int(cell["pct"])
		var target := _unit_at(t)
		if target == null or not target.alive:
			continue
		if support and target.side != caster.side:
			continue
		if not support and target.side == caster.side:
			continue
		var e1 := effect1 * pct / 100
		var e2 := effect2 * pct / 100
		match tid:
			0:
				var heal := mini(e1, target.max_hp - target.hp)
				if heal > 0:
					target.hp += heal
					_spawn_float("+%d" % heal, target.position, Color("#6bff8a"))
					affected += 1
					_gain_xp(caster, 2 + int(2.0 * heal / max(1, target.max_hp)))
			1:
				var add := mini(e2, max(0, 100 - target.morale))
				if add > 0:
					target.morale += add
					_spawn_float("士气+%d" % add, target.position, Color("#7fd8ff"))
					affected += 1
					_gain_xp(caster, 1 + int(2.0 * add / 100.0))
			2:
				var heal2 := mini(e1, target.max_hp - target.hp)
				var add2 := mini(e2, max(0, 100 - target.morale))
				if heal2 > 0:
					target.hp += heal2
					_spawn_float("+%d" % heal2, target.position, Color("#6bff8a"))
					affected += 1
				if add2 > 0:
					target.morale += add2
					affected += 1
				_gain_xp(caster, 2 if affected > 0 else 0)
			3:
				var dmg := maxi(1, int(e1))
				if _apply_hp_damage(target, dmg):
					deaths.append(target)
				target.morale = max(0, target.morale - e2)
				affected += 1
			5:
				target.status_def_down = 3
				affected += 1
				_spawn_float("防-70%", target.position, Color("#ffb347"))
			6:
				target.status_atk_down = 3
				affected += 1
				_spawn_float("攻-70%", target.position, Color("#ffb347"))
			7:
				if int(target.equip) >= 0:
					var stolen := int(target.equip)
					target.equip = -1
					target.attack_bonus = 0
					target.defense_bonus = 0
					_battle_loot(stolen)
					affected += 1
			8:
				target.status_atk_down = 3
				affected += 1
			9:
				target.status_stun = 2
				affected += 1
				_spawn_float("停攻", target.position, Color("#d18cff"))
			10:
				target.status_atk_down = 0
				target.status_def_down = 0
				target.status_stun = 0
				target.status_disarm = 0
				affected += 1
			4:
				target.morale = max(0, target.morale - max(1, e2))
				_spawn_float("士气-%d" % max(1, e2), target.position, Color("#d18cff"))
				affected += 1
		target.refresh()
	if affected > 0:
		var center_world := Vector2(center.x * TILE + TILE / 2.0,
				center.y * TILE + TILE / 2.0)
		_play_flm(int(active_skill.get("flm_index", -1)), center_world, 1.2)
		var aidx := int(active_skill.get("anm_index", -1))
		if aidx >= 0:
			_play_anm_sheet("res://assets/m5/anm/ffpact%02d_sheet.png" % aidx,
					center_world, 0.75)
		caster.skill_counts[SKILL_KEYS[sid]] = count + 1
		caster.acted = true
		caster.refresh()
		_log("%s 使用「%s」，影响 %d 个目标" % [
			caster.unit_name, active_skill.get("name", "技能"), affected])
		for d in deaths:
			_gain_xp(caster, CombatRules.kill_experience(caster.data.get("level", 1),
					d.data.get("level", 1)))
			_on_unit_died(d)
	else:
		_log("技能没有产生效果")
	busy = false
	active_skill = {}
	active_skill_id = -1
	selected = null
	update_hud()
	_check_end()


func _battle_loot(item_id: int) -> void:
	if item_id < 0:
		return
	var items: Dictionary = battle_context.get("items", {})
	items[str(item_id)] = int(items.get(str(item_id), 0)) + 1
	battle_context["items"] = items
	looted.emit(item_id)


func _open_item_menu() -> void:
	if selected == null or busy or phase != "player" or selected.acted:
		return
	var rows: Array = []
	var inv: Dictionary = battle_context.get("items", {})
	var keys: Array = inv.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		if int(inv[k]) <= 0:
			continue
		var iid := int(k)
		var kind := _item_kind(iid)
		if kind in ["equip", "manual", "book", "other"]:
			continue
		var it: Dictionary = (data.get("items", {}) as Dictionary).get(str(iid), {})
		rows.append({
			"text": "%s ×%d%s" % [it.get("name", "?"), int(inv[k]),
					"（投掷）" if kind == "throw" else ""],
			"cb": _choose_item.bind(iid),
		})
	if rows.is_empty():
		_log("没有可在战斗内使用的物品")
		return
	_open_action_panel("选择物品", rows)


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
	mode = "item"
	move_tiles.clear()
	attack_tiles = targets
	if targets.is_empty():
		_log("物品范围内没有目标")
		mode = "idle"
	else:
		_log("选择「%s」的目标" % it.get("name", "物品"))
	update_hud()


func _item_targets(caster: Node2D, it: Dictionary, kind: String) -> Dictionary:
	var out := {}
	var support := kind == "food"
	var tiles := _select_tiles(caster, int(it.get("select_fw", 1)), support)
	for t in tiles:
		var target := _unit_at(t)
		if target == null or not target.alive:
			continue
		if support and target.side == caster.side:
			out[t] = target
		elif not support and target.side != caster.side:
			out[t] = target
	return out


func _execute_item_at(tile: Vector2i) -> void:
	if selected == null or active_item_id < 0:
		return
	var caster = selected
	var it: Dictionary = (data.get("items", {}) as Dictionary).get(str(active_item_id), {})
	if it.is_empty() or _inventory_count("items", active_item_id) <= 0:
		return
	var kind := _item_kind(active_item_id)
	var support := kind == "food"
	var center := _unit_at(tile)
	if center == null or (support and center.side != caster.side) \
			or (not support and center.side == caster.side):
		return
	var targets := _item_targets(caster, it, kind)
	if not targets.has(tile):
		return
	busy = true
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	var area := _apply_tiles(tile, int(it.get("apply_fw", 0)))
	var affected := 0
	var deaths: Array = []
	for cell in area:
		var t: Vector2i = cell["tile"]
		var pct := int(cell["pct"])
		var target := _unit_at(t)
		if target == null or not target.alive:
			continue
		if support and target.side != caster.side:
			continue
		if not support and target.side == caster.side:
			continue
		var p1 := int(it.get("para1", 0)) * pct / 100
		var p2 := int(it.get("para2", 0)) * pct / 100
		if kind == "food":
			var p4 := int(it.get("para4", 16))
			if p4 in [16, 18] and p1 > 0:
				var heal := mini(p1, target.max_hp - target.hp)
				target.hp += heal
				_spawn_float("+%d" % heal, target.position, Color("#6bff8a"))
				affected += 1
			if p4 in [17, 18] and p2 > 0:
				var add := mini(p2, max(0, 100 - target.morale))
				target.morale += add
				_spawn_float("士气+%d" % add, target.position, Color("#7fd8ff"))
				affected += 1
			_gain_xp(caster, 1)
		elif kind == "throw":
			var dmg := maxi(1, int(p1))
			if _apply_hp_damage(target, dmg):
				deaths.append(target)
			target.morale = max(0, target.morale - p2)
			affected += 1
		target.refresh()
	_play_sfx(int(it.get("audio_apply", -1)))
	_consume_inventory("items", active_item_id)
	caster.acted = true
	caster.refresh()
	_log("%s 使用「%s」，影响 %d 个目标" % [caster.unit_name, it.get("name", ""), affected])
	for d in deaths:
		_gain_xp(caster, CombatRules.kill_experience(caster.data.get("level", 1),
				d.data.get("level", 1)))
		_on_unit_died(d)
	busy = false
	active_item_id = -1
	selected = null
	update_hud()
	_check_end()


func _open_action_panel(title: String, rows: Array) -> void:
	_close_action_panel()
	action_panel = Control.new()
	action_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(action_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	action_panel.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(170, 110)
	panel.size = Vector2(300, 260)
	panel.add_theme_stylebox_override("panel", OriginalUI._style("panel_red.png"))
	action_panel.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	var head := HBoxContainer.new()
	var tl := OriginalUI.label(title, font, 16, OriginalUI.GOLD_LIGHT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var close := OriginalUI.button("关闭", font, Vector2(58, 24),
			_close_action_panel, 14)
	close.custom_minimum_size = Vector2(58, 24)
	head.add_child(close)
	v.add_child(head)
	v.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for row in rows:
		var b := OriginalUI.button(str(row.get("text", "")), font,
				Vector2(270, 28), row.get("cb", Callable()), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)


func _close_action_panel() -> void:
	if action_panel != null and is_instance_valid(action_panel):
		action_panel.queue_free()
	action_panel = null


func _open_mine_menu() -> void:
	if selected == null or busy or phase != "player" or selected.acted:
		return
	var rows: Array = []
	var inv: Dictionary = battle_context.get("mines", {})
	for i in range((data.get("mines", []) as Array).size()):
		var n := int(inv.get(str(i), 0))
		if n <= 0:
			continue
		var m: Dictionary = data["mines"][i]
		rows.append({
			"text": "%s ×%d" % [m.get("name", "?"), n],
			"cb": _choose_mine.bind(i),
		})
	if rows.is_empty():
		_log("地雷库存为空")
		return
	_open_action_panel("选择地雷（库存）", rows)


func _choose_mine(mid: int) -> void:
	_close_action_panel()
	mine_kind = mid
	if not can_mine(selected):
		var m: Dictionary = (data.get("mines", []) as Array)[mid]
		_log("%s 不能在当前地形埋设（或库存不足）" % m.get("name", "地雷"))
		return
	_place_mine()


# ---------------- 回合 / AI ----------------

func _begin_player_phase(log_text: String = "") -> void:
	phase = "player"
	busy = false
	for u in units:
		if not u.alive:
			continue
		u.status_def_down = max(0, int(u.status_def_down) - 1)
		u.status_atk_down = max(0, int(u.status_atk_down) - 1)
		u.status_stun = max(0, int(u.status_stun) - 1)
		u.status_disarm = max(0, int(u.status_disarm) - 1)
	for u in player_units:
		if u.alive:
			if u.auto:
				u.acted = true
				u.moved = true
			else:
				u.acted = false
				u.moved = false
			u.refresh()
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	if scenario != null:
		scenario.on_turn_start(turn)
	if finished_flag:
		return
	if log_text != "":
		_log(log_text)
	update_hud()


func _on_end_turn() -> void:
	if phase != "player" or busy or finished_flag:
		return
	_close_action_panel()
	if _check_end():
		return
	# 友军 AI
	if _has_auto_allies():
		phase = "ally"
		selected = null
		mode = "idle"
		move_tiles.clear()
		attack_tiles.clear()
		_log("友军行动…")
		update_hud()
		if not fast_sim:
			await get_tree().create_timer(0.12).timeout
		await _run_ally_turn()
		if finished_flag:
			return
	phase = "enemy"
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	for u in enemy_units:
		if u.alive:
			u.acted = false
			u.moved = false
			u.refresh()
	_log("敌方行动…")
	update_hud()
	if not fast_sim:
		await get_tree().create_timer(0.18).timeout
	await _run_enemy_turn()


func _has_auto_allies() -> bool:
	for u in player_units:
		if u.alive and u.auto:
			return true
	return false


func _run_ally_turn() -> void:
	for p in player_units:
		if finished_flag:
			return
		if not p.alive or not p.auto:
			continue
		await _ai_act(p, "enemy")
		if finished_flag:
			return
		if not fast_sim:
			await get_tree().create_timer(ai_delay).timeout


func _run_enemy_turn() -> void:
	for e in enemy_units:
		if finished_flag:
			return
		if not e.alive:
			continue
		await _ai_act(e, "player")
		if finished_flag:
			return
		if not fast_sim:
			await get_tree().create_timer(ai_delay + 0.03).timeout
	if finished_flag:
		return
	turn += 1
	var limit := int(level.get("turn_limit", 0))
	if limit > 0 and turn > limit:
		_finish("defeat", "超过%d个回合" % limit)
		return
	_begin_player_phase("第 %d 回合，我方行动" % turn)


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


func _ai_act(u, enemy_side: String) -> void:
	if u == null or not u.alive or finished_flag:
		return
	u.acted = false
	u.moved = false
	if int(u.status_stun) > 0:
		u.acted = true
		u.refresh()
		return
	var target = _nearest_side(u, enemy_side)
	var goal := Vector2i(-1, -1)
	if u.side == "enemy" and scenario != null:
		goal = scenario.ai_goal(u)
	var peaceful: bool = u.auto and u.protected and int(u.data.get("gongji", 0)) <= 0
	if peaceful:
		# 非战斗人员：只躲，不主动攻击，避免被反击致死。
		if target != null:
			var dx := int(sign(u.x - target.x))
			var dy := int(sign(u.y - target.y))
			goal = Vector2i(clampi(u.x + dx * 4, 0, map_w - 1),
					clampi(u.y + dy * 4, 0, map_h - 1))
	elif u.auto and (u.behavior == 8 or u.key in ["村民", "老百姓"]):
		# 村民/百姓：往远离敌人的方向躲
		if target != null:
			var dx := int(sign(u.x - target.x))
			var dy := int(sign(u.y - target.y))
			goal = Vector2i(clampi(u.x + dx * 4, 0, map_w - 1),
					clampi(u.y + dy * 4, 0, map_h - 1))
	if goal.x < 0 and target != null:
		goal = Vector2i(target.x, target.y)
	if goal.x < 0:
		u.acted = true
		u.refresh()
		return
	# 守卫/炮楼/首领：有目标在射程内才打
	if u.side == "enemy" and u.behavior in [0, 7, 9, 12, 13]:
		if target != null and _in_attack_range(u, target):
			await _perform_attack(u, target)
		else:
			u.acted = true
			u.refresh()
		return
	if not peaceful and target != null and _in_attack_range(u, target):
		await _perform_attack(u, target)
		return
	var goal_tile := goal
	if _is_occupied(goal_tile, u):
		goal_tile = _adjacent_free(goal_tile, u)
	if goal_tile.x < 0:
		u.acted = true
		u.refresh()
		return
	var path := _astar(Vector2i(u.x, u.y), goal_tile, u)
	if path.is_empty():
		var step := _greedy_step(u, goal_tile)
		if step.x >= 0:
			path = [step]
	var steps: Array = []
	var budget := int(u.move)
	var spent := 0
	for t in path:
		var c := move_cost(u.bingzhong, _terrain_at(t))
		if c >= 99 or spent + c > budget:
			break
		spent += c
		steps.append(t)
	for step in steps:
		await u.move_visual(step.x, step.y, 0.055)
		if u.side == "enemy" and _trigger_mine(step, u):
			break
		if not u.alive or finished_flag:
			return
		if scenario != null:
			scenario.on_unit_moved(u)
		if finished_flag:
			return
	u.moved = not steps.is_empty()
	u.refresh()
	if not peaceful and target != null and _in_attack_range(u, target):
		await _perform_attack(u, target)
	else:
		u.acted = true
		u.refresh()


func _adjacent_free(goal: Vector2i, u) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bestd := 99999
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var t := goal + Vector2i(dx, dy)
			if _in_bounds(t) and not _is_occupied(t, u) 					and move_cost(u.bingzhong, _terrain_at(t)) < 99:
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


func _astar(start: Vector2i, goal: Vector2i, u) -> Array:
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
			if _is_occupied(n, u) and n != goal:
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


func _bot_move_to(u: Node2D, goal: Vector2i) -> bool:
	if not _in_bounds(goal):
		return false
	var dest := goal
	if _is_occupied(dest, u):
		dest = _adjacent_free(dest, u)
	if dest.x < 0:
		dest = _approach_tile(goal, u, 4)
	if dest.x < 0:
		return false
	var path := _astar(Vector2i(u.x, u.y), dest, u)
	if path.is_empty():
		var step := _greedy_step(u, dest)
		if step.x < 0:
			return false
		path = [step]
	var budget := int(u.move)
	var spent := 0
	for t in path:
		var c := move_cost(u.bingzhong, _terrain_at(t))
		if c >= 99 or spent + c > budget:
			break
		spent += c
		u.set_tile(t.x, t.y)
		u.moved = true
		u.refresh()
		if finished_flag:
			return true
		if scenario != null:
			scenario.on_unit_moved(u)
		if finished_flag:
			return true
		if u.is_player():
			var ci := _chest_at(t)
			if ci >= 0:
				_open_chest(u, ci)
		if not u.alive:
			return true
	return spent > 0


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
		u.acted = true
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
		_bot_move_to(u, best)
	u.acted = true
	u.refresh()


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
		_bot_retreat(u)
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
			if dist <= 1:
				if scenario != null:
					scenario.on_unit_moved(u)
					scenario.check_end()
				u.acted = true
				return
			moved = _bot_move_to(u, Vector2i(tu.x, tu.y))
	elif str(goal.get("kind", "")) == "tile":
		var tt: Vector2i = goal.get("tile", Vector2i(-1, -1))
		moved = _bot_move_to(u, tt)
	if finished_flag or not u.alive:
		return
	var after := attack_targets(u)
	var target2 = _bot_pick_target(u, after)
	if target2 != null and (not focused or moved or _bot_is_goal_target(target2, goal)):
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
		if finished_flag:
			break
		await _on_end_turn()
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
	attack_tiles = attack_targets(selected)
	if attack_tiles.is_empty():
		_log("没有可攻击的目标")
		return
	mode = "attack"
	move_tiles.clear()
	_log("选择攻击目标")
	update_hud()


func _on_mine() -> void:
	if selected == null or busy or phase != "player":
		return
	var types := 0
	for k in battle_context.get("mines", {}):
		if int(battle_context["mines"][k]) > 0:
			types += 1
	if types > 1:
		_open_mine_menu()
	else:
		_place_mine()


func _on_skill() -> void:
	_open_skill_menu()


func _on_item() -> void:
	_open_item_menu()


func _on_wait() -> void:
	if selected == null or busy or phase != "player":
		return
	if not selected.is_player() or not selected.control:
		return
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


func _on_cancel() -> void:
	_cancel()


# ---------------- 绘制 / 特效 ----------------

func draw_overlay(ci: CanvasItem) -> void:
	if finished_flag:
		return
	if selected != null and is_instance_valid(selected):
		var r := Rect2(selected.x * TILE, selected.y * TILE, TILE, TILE)
		ci.draw_rect(r, Color(1.0, 0.82, 0.30, 0.15))
		ci.draw_rect(r, Color(1.0, 0.82, 0.30, 0.8), false, 1.0)
	for t in move_tiles:
		var r := Rect2(t.x * TILE, t.y * TILE, TILE, TILE)
		ci.draw_rect(r, Color(0.25, 0.60, 1.0, 0.22))
		ci.draw_rect(r, Color(0.35, 0.70, 1.0, 0.35), false, 1.0)
	for t in attack_tiles:
		var r := Rect2(t.x * TILE, t.y * TILE, TILE, TILE)
		ci.draw_rect(r, Color(1.0, 0.22, 0.22, 0.26))
		ci.draw_rect(r, Color(1.0, 0.35, 0.35, 0.45), false, 1.0)
	if _in_bounds(hover_tile):
		var r := Rect2(hover_tile.x * TILE, hover_tile.y * TILE, TILE, TILE)
		ci.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)


func _spawn_float(text: String, world: Vector2, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	l.position = world - Vector2(24, 30)
	l.z_index = 100
	fx_root.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position", l.position + Vector2(0, -26), 0.75)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.75)
	tw.tween_callback(l.queue_free)


func _finish(result: String, message: String) -> void:
	if finished_flag or _finishing:
		return
	_finishing = true
	finished_flag = true
	last_result = result
	last_message = message
	emit_story_event("victory" if result == "victory" else "defeat",
			{"message": message})
	phase = "done"
	busy = true
	selected = null
	move_tiles.clear()
	attack_tiles.clear()
	stats["turns"] = turn
	stats["enemies_left"] = _alive_count(enemy_units)
	stats["players_left"] = _alive_count(player_units)
	stats["log"] = log_history.duplicate()
	update_hud()
	finished.emit(result, message)
