extends Node2D

## M1 战斗核心：地图、单位、Dijkstra 移动、普通攻击、地雷、回合与简单 AI。

signal finished(result: String, message: String)

const TILE := 48
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
var btn_wait: Button
var btn_cancel: Button
var btn_end: Button

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
var mine_texture: Texture2D


func setup(d: Dictionary, lv: Dictionary, f: Font) -> void:
	data = d
	level = lv
	font = f
	map_w = int(level["map"]["width"])
	map_h = int(level["map"]["height"])
	terrain = level["map"]["terrain"]
	mines_left = int(data["meta"].get("mines", 3))
	mine_texture = load(str(data.get("mine_png", ""))) if ResourceLoader.exists(str(data.get("mine_png", ""))) else null
	_build_world()
	_build_hud()
	turn = 1
	phase = "player"
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
		var u = preload("res://scripts/BattleUnit.gd").new()
		units_root.add_child(u)
		u.setup(ud, self)
		units.append(u)
		if u.is_player():
			player_units.append(u)
		else:
			enemy_units.append(u)

	camera = Camera2D.new()
	camera.enabled = true
	if map_h <= 14:
		var fit := (480.0 - 82.0 - 96.0) / float(max(1, map_h * TILE))
		var z := clampf(fit, 0.55, 0.95)
		camera.zoom = Vector2(z, z)
	camera.position = _initial_camera()
	add_child(camera)
	camera.make_current()
	_clamp_camera()


func _initial_camera() -> Vector2:
	var p = level["map"].get("player_focus", [0, 0])
	return Vector2(float(p[0]) * TILE + TILE / 2.0,
			float(p[1]) * TILE + TILE / 2.0)


func _clamp_camera() -> void:
	if camera == null:
		return
	var half := Vector2(320.0, 240.0) / camera.zoom
	var w := map_w * TILE
	var h := map_h * TILE
	var pos := camera.position
	if w <= half.x * 2.0:
		pos.x = w / 2.0
	else:
		pos.x = clampf(pos.x, half.x, w - half.x)
	if h <= half.y * 2.0:
		pos.y = h / 2.0
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
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.custom_minimum_size = size
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 16)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	hud_root.add_child(b)
	return b


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 30
	add_child(hud_layer)
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 16
	hud_root.theme = t
	hud_layer.add_child(hud_root)

	var top := ColorRect.new()
	top.color = Color(0.04, 0.055, 0.08, 0.94)
	top.position = Vector2.ZERO
	top.size = Vector2(640, 82)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top)
	var line := ColorRect.new()
	line.color = Color("#f2c14e")
	line.position = Vector2(0, 80)
	line.size = Vector2(640, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(line)

	level_label = _hud_label("", Vector2(8, 4), Vector2(360, 22), 16, Color("#f2c14e"))
	turn_label = _hud_label("", Vector2(8, 28), Vector2(120, 20), 16)
	phase_label = _hud_label("", Vector2(128, 28), Vector2(140, 20), 16, PLAYER_COLOR)
	objective_label = _hud_label("", Vector2(300, 4), Vector2(332, 20), 16, Color("#c8d3e2"))
	enemy_label = _hud_label("", Vector2(300, 28), Vector2(200, 20), 16)
	mine_label = _hud_label("", Vector2(500, 28), Vector2(132, 20), 16, Color("#f2c14e"))
	message_label = _hud_label("", Vector2(8, 56), Vector2(624, 20), 16, Color("#8796aa"))

	var bottom := ColorRect.new()
	bottom.color = Color(0.04, 0.055, 0.08, 0.96)
	bottom.position = Vector2(0, 384)
	bottom.size = Vector2(640, 96)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bottom)
	var bline := ColorRect.new()
	bline.color = Color("#2c3442")
	bline.position = Vector2(0, 384)
	bline.size = Vector2(640, 1)
	bline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bline)

	portrait = TextureRect.new()
	portrait.position = Vector2(8, 392)
	portrait.size = Vector2(48, 60)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(portrait)

	unit_label = _hud_label("", Vector2(64, 390), Vector2(304, 56), 16)

	btn_attack = _hud_button("攻击", Vector2(372, 440), Vector2(62, 32), _on_attack)
	btn_mine = _hud_button("埋雷", Vector2(438, 440), Vector2(62, 32), _on_mine)
	btn_wait = _hud_button("待机", Vector2(504, 440), Vector2(62, 32), _on_wait)
	btn_cancel = _hud_button("取消", Vector2(570, 440), Vector2(62, 32), _on_cancel)
	btn_end = _hud_button("结束回合", Vector2(372, 404), Vector2(260, 32), _on_end_turn)
	btn_end.add_theme_color_override("font_color", Color("#f2c14e"))


func update_hud() -> void:
	if hud_root == null:
		return
	level_label.text = "L%02d  %s" % [int(level["index"]), level["name"]]
	turn_label.text = "第 %d 回合" % turn
	if phase == "player":
		phase_label.text = "我方回合"
		phase_label.add_theme_color_override("font_color", PLAYER_COLOR)
	elif phase == "enemy":
		phase_label.text = "敌方行动"
		phase_label.add_theme_color_override("font_color", ENEMY_COLOR)
	else:
		phase_label.text = "战斗结束"
		phase_label.add_theme_color_override("font_color", Color("#f2c14e"))
	objective_label.text = "目标：%s" % level["success"]
	enemy_label.text = "敌军 %d / 我军 %d" % [_alive_count(enemy_units), _alive_count(player_units)]
	mine_label.text = "地雷 %d 颗" % mines_left
	message_label.text = str(level.get("message", ""))
	if selected != null and is_instance_valid(selected):
		var u = selected
		var atk := int(round(float(u.data["gongji"]) + float(u.data["wuli"]) * 0.6))
		var df := int(round(float(u.data["fangyu"]) + float(u.data["zhili"]) * 0.3))
		var tag := "我方" if u.is_player() else "敌方"
		var state := "已行动" if u.acted else ("已移动" if u.moved else "待命")
		unit_label.text = "%s [%s]\nHP %d/%d  攻%d 防%d\n移%d  %s" % [
			u.unit_name, tag, u.hp, u.max_hp, atk, df, u.move, state
		]
		if u.data.get("face_png", "") != "" and ResourceLoader.exists(u.data["face_png"]):
			portrait.texture = load(u.data["face_png"])
			portrait.visible = true
		else:
			portrait.visible = false
	else:
		unit_label.text = "点击我方单位开始行动\n左键移动 / 攻击 / 右键取消"
		portrait.visible = false

	var can_act: bool = phase == "player" and not busy and not finished_flag
	btn_attack.disabled = not (can_act and selected != null and selected.is_player()
			and not selected.acted and not attack_targets(selected).is_empty())
	btn_mine.disabled = not can_act or selected == null or not can_mine(selected)
	btn_wait.disabled = not (can_act and selected != null and selected.is_player()
			and not selected.acted)
	btn_cancel.disabled = mode == "idle" and selected == null
	btn_end.disabled = not can_act
	if phase == "player":
		btn_end.text = "结束回合"
	elif phase == "enemy":
		btn_end.text = "敌方行动中…"
	else:
		btn_end.text = "战斗结束"
	if overlay != null:
		overlay.queue_redraw()


func _log(text: String) -> void:
	level["message"] = text
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


func _zoom_at(factor: float) -> void:
	if camera == null:
		return
	var z := clampf(camera.zoom.x * factor, 0.55, 2.0)
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
			and not selected.moved and move_tiles.has(t):
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
	if u.is_player() and not u.acted:
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
	if mode != "idle":
		mode = "idle"
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
	camera.position = Vector2(u.x * TILE + 24, u.y * TILE + 24)
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
	for step in path:
		await u.move_visual(step.x, step.y, 0.075)
	u.moved = true
	u.refresh()
	attack_tiles = attack_targets(u)
	busy = false
	_log("%s 移动到 (%d,%d)" % [u.unit_name, u.x, u.y])
	update_hud()


# ---------------- 攻击 ----------------

func compute_damage(attacker: Node2D, defender: Node2D) -> int:
	var atk := float(attacker.data["gongji"]) + float(attacker.data["wuli"]) * 0.6
	var df := float(defender.data["fangyu"]) + float(defender.data["zhili"]) * 0.3
	var mods: Array = data.get("terrain_modifiers", [])
	var t := _terrain_at(Vector2i(defender.x, defender.y))
	if t >= 0 and t < mods.size():
		var m = mods[t]
		if m is Array and m.size() >= 3:
			df *= (100.0 + float(m[2])) / 100.0
	var dmg := int(round(max(1.0, atk - df * 0.75 + float(randi_range(-3, 3)))))
	return clampi(dmg, 1, defender.hp)


func _attack_anim(attacker: Node2D, defender: Node2D) -> void:
	var from: Vector2 = attacker.position
	var dir: Vector2 = (defender.position - from).normalized()
	var tw := create_tween()
	tw.tween_property(attacker, "position", from + dir * 18.0, 0.07)
	tw.tween_property(attacker, "position", from, 0.09)
	await tw.finished


func _perform_attack(attacker: Node2D, defender: Node2D) -> void:
	if attacker == null or defender == null or not attacker.alive or not defender.alive:
		return
	busy = true
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	update_hud()
	await _attack_anim(attacker, defender)
	var dmg := compute_damage(attacker, defender)
	var died: bool = defender.take_damage(dmg)
	_spawn_float("-%d" % dmg, defender.position, Color("#ff6b6b"))
	_log("%s 攻击 %s，造成 %d 伤害" % [attacker.unit_name, defender.unit_name, dmg])
	attacker.acted = true
	attacker.refresh()
	busy = false
	if died:
		_on_unit_died(defender)
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
	if not u.alive:
		return
	u.die()
	_log("%s 阵亡" % u.unit_name)
	# 失败单位（如 L08 李霜泗）
	for name in level.get("fail_units", []):
		if u.unit_name == str(name):
			_finish("defeat", "%s 阵亡" % u.unit_name)
			return
	if _check_end():
		return


func _check_end() -> bool:
	if finished_flag:
		return true
	if _alive_count(enemy_units) == 0:
		_finish("victory", str(level["success"]))
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


# ---------------- 地雷 ----------------

func _mine_at(t: Vector2i) -> int:
	for i in range(mines.size()):
		if mines[i]["tile"] == t:
			return i
	return -1


func can_mine(u: Node2D) -> bool:
	if u == null or phase != "player" or busy or finished_flag:
		return false
	if not u.is_player() or u.acted or mines_left <= 0:
		return false
	var t := Vector2i(u.x, u.y)
	if _mine_at(t) >= 0:
		return false
	var rows: Array = data.get("mine_terrain", [])
	var mi := int(data["meta"].get("mine_type", 0))
	if mi < 0 or mi >= rows.size():
		return false
	var terr := _terrain_at(t)
	if terr < 0 or terr >= rows[mi].size():
		return false
	return int(rows[mi][terr]) == 1


func _place_mine() -> void:
	if not can_mine(selected):
		return
	var u = selected
	var t := Vector2i(u.x, u.y)
	var mi := int(data["meta"].get("mine_type", 0))
	var m: Dictionary = data["mines"][mi]
	mines.append({"tile": t, "mine": m, "owner": u})
	if mine_texture != null:
		var s := Sprite2D.new()
		s.texture = mine_texture
		s.region_enabled = true
		s.region_rect = Rect2(0, 0, TILE, TILE)
		s.position = Vector2(t.x * TILE + 24, t.y * TILE + 24)
		s.z_index = 200
		s.modulate = Color(1, 1, 1, 0.82)
		units_root.add_child(s)
		mine_nodes[t] = s
	mines_left -= 1
	u.acted = true
	u.refresh()
	_log("%s 在 (%d,%d) 埋下%s，剩余 %d 颗" % [u.unit_name, t.x, t.y, m["name"], mines_left])
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	update_hud()


func _trigger_mine(t: Vector2i, u: Node2D) -> bool:
	if u == null or not u.alive or u.is_player():
		return false
	var idx := _mine_at(t)
	if idx < 0:
		return false
	var m: Dictionary = mines[idx]["mine"]
	mines.remove_at(idx)
	if mine_nodes.has(t):
		var node = mine_nodes[t]
		if is_instance_valid(node):
			node.queue_free()
		mine_nodes.erase(t)
	var dmg := int(round(max(1.0, float(m["weili"]) - float(u.data["fangyu"]) * 0.3
			+ float(randi_range(-2, 2)))))
	var died: bool = u.take_damage(dmg)
	_spawn_float("地雷 -%d" % dmg, u.position, Color("#ffb347"))
	_log("%s 踩中%s！%d 伤害" % [u.unit_name, m["name"], dmg])
	if died:
		_on_unit_died(u)
	return true


# ---------------- 回合 / AI ----------------

func _begin_player_phase(log_text: String = "") -> void:
	phase = "player"
	busy = false
	for u in player_units:
		if u.alive:
			u.acted = false
			u.moved = false
			u.refresh()
	selected = null
	mode = "idle"
	move_tiles.clear()
	attack_tiles.clear()
	if log_text != "":
		_log(log_text)
	update_hud()


func _on_end_turn() -> void:
	if phase != "player" or busy or finished_flag:
		return
	if _check_end():
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
	await get_tree().create_timer(0.18).timeout
	await _run_enemy_turn()


func _run_enemy_turn() -> void:
	for e in enemy_units:
		if finished_flag:
			return
		if not e.alive:
			continue
		await _enemy_act(e)
		if finished_flag:
			return
		await get_tree().create_timer(0.10).timeout
	if finished_flag:
		return
	turn += 1
	var limit := int(level.get("turn_limit", 0))
	if limit > 0 and turn > limit:
		_finish("defeat", "超过%d个回合" % limit)
		return
	_begin_player_phase("第 %d 回合，我方行动" % turn)


func _nearest_player(u: Node2D) -> Node2D:
	var best: Node2D = null
	var bestd := 99999
	for p in player_units:
		if not p.alive:
			continue
		var d: int = abs(p.x - u.x) + abs(p.y - u.y)
		if d < bestd:
			bestd = d
			best = p
	return best


func _enemy_act(e: Node2D) -> void:
	var target := _nearest_player(e)
	if target == null:
		return
	if _in_attack_range(e, target):
		await _perform_attack(e, target)
		return
	var reach := compute_reachable(e)
	if reach.is_empty():
		e.acted = true
		e.refresh()
		return
	var best := Vector2i(e.x, e.y)
	var bestd := 99999
	for t in reach:
		var d: int = abs(t.x - target.x) + abs(t.y - target.y)
		if d < bestd:
			bestd = d
			best = t
	if best == Vector2i(e.x, e.y):
		e.acted = true
		e.refresh()
		if _in_attack_range(e, target):
			await _perform_attack(e, target)
		return
	var path := _path_to(best, Vector2i(e.x, e.y))
	for step in path:
		await e.move_visual(step.x, step.y, 0.05)
		if _trigger_mine(step, e):
			break
		if not e.alive or finished_flag:
			return
	e.moved = true
	e.refresh()
	if _in_attack_range(e, target):
		await _perform_attack(e, target)
	else:
		e.acted = true
		e.refresh()


func _in_attack_range(attacker: Node2D, defender: Node2D) -> bool:
	var targets := attack_targets(attacker)
	return targets.has(Vector2i(defender.x, defender.y))


# ---------------- 按钮 ----------------

func _on_attack() -> void:
	if selected == null or busy or phase != "player":
		return
	if selected.acted or not selected.is_player():
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
	_place_mine()


func _on_wait() -> void:
	if selected == null or busy or phase != "player":
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
	if finished_flag:
		return
	finished_flag = true
	phase = "done"
	busy = true
	selected = null
	move_tiles.clear()
	attack_tiles.clear()
	update_hud()
	finished.emit(result, message)
