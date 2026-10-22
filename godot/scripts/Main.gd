extends Control

## M1 主界面：关卡选择、Battle 装载、胜负重开。

const M1_PATH := "res://data/m1.json"

var data: Dictionary = {}
var font: Font
var screen: Control
var battle: Node2D
var campaign: Control
var result_layer: Control
var result_canvas: CanvasLayer
var current_level := -1


func _ready() -> void:
	var font_path := "res://assets/font/hzk16.fnt"
	if ResourceLoader.exists(font_path):
		font = load(font_path)
	else:
		font = ThemeDB.fallback_font
		push_warning("HZK16 字体缺失，先用系统字体占位；请运行 tools/prepare_m1.py")
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 16
	theme = t
	data = _load_data()
	if data.is_empty():
		_show_fatal("找不到 res://data/m1.json\n请先运行 python3 tools/prepare_m1.py")
		return
	_show_menu()
	var args := OS.get_cmdline_user_args()
	if args.has("--capture-menu"):
		call_deferred("_capture", "menu")
	elif args.has("--capture-battle"):
		call_deferred("_capture", "battle")
	elif args.has("--capture-battle8"):
		call_deferred("_capture", "battle8")
	elif args.has("--capture-result"):
		call_deferred("_capture", "result")
	elif args.has("--capture-m2-world"):
		call_deferred("_capture_m2", "world")
	elif args.has("--capture-m2-town"):
		call_deferred("_capture_m2", "town")
	elif args.has("--capture-m2-shop"):
		call_deferred("_capture_m2", "shop")
	elif args.has("--capture-m2-party"):
		call_deferred("_capture_m2", "party")
	elif args.has("--capture-m2-forge"):
		call_deferred("_capture_m2", "forge")
	elif args.has("--capture-m2-recruit"):
		call_deferred("_capture_m2", "recruit")
	elif args.has("--capture-m2-save"):
		call_deferred("_capture_m2", "save")
	elif args.has("--capture-m2-battle"):
		call_deferred("_capture_m2", "battle")
	elif args.has("--capture-m2-battle-result"):
		call_deferred("_capture_m2", "battle-result")


func _capture(mode: String) -> void:
	var lidx := 8 if mode == "battle8" else 14
	if mode == "battle" or mode == "battle8" or mode == "result":
		_start_level(lidx)
	if mode == "result":
		for i in range(5):
			await get_tree().process_frame
		if is_instance_valid(battle):
			for e in battle.enemy_units:
				e.alive = false
			battle._check_end()
	for i in range(5):
		await get_tree().process_frame
	if (mode == "battle" or mode == "battle8") and is_instance_valid(battle) and not battle.player_units.is_empty():
		battle._select_unit(battle.player_units[0])
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "/tmp/m1_%s.png" % mode
	img.save_png(path)
	print("CAPTURE ", path, " ", img.get_size())
	get_tree().quit()


func _capture_m2(mode: String) -> void:
	_start_campaign()
	for i in range(5):
		await get_tree().process_frame
	if is_instance_valid(campaign):
		if mode == "town":
			campaign._show_town(0)
		elif mode == "shop":
			campaign._show_town(1)
			campaign._open_shop("junxie", false)
		elif mode == "party":
			campaign._show_town(0)
			campaign._open_party()
		elif mode == "forge":
			campaign._show_town(0)
			campaign._open_forge()
		elif mode == "recruit":
			campaign._show_town(0)
			campaign._open_recruit()
		elif mode == "save":
			campaign._show_town(0)
			campaign._open_save()
		elif mode == "battle" or mode == "battle-result":
			campaign._show_town(0)
			campaign._start_battle(14)
			for i in range(5):
				await get_tree().process_frame
			if mode == "battle-result" and is_instance_valid(campaign.battle):
				for e in campaign.battle.enemy_units:
					e.alive = false
				campaign.battle._check_end()
	for i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "/tmp/m2_%s.png" % mode
	img.save_png(path)
	print("CAPTURE ", path, " ", img.get_size())
	get_tree().quit()


func _load_data() -> Dictionary:
	var f := FileAccess.open(M1_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("m1.json 解析失败")
	return {}


func _clear_all() -> void:
	if is_instance_valid(campaign):
		campaign.queue_free()
		campaign = null
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
		result_canvas = null
	elif is_instance_valid(result_layer):
		result_layer.queue_free()
	result_layer = null
	if is_instance_valid(battle):
		battle.queue_free()
		battle = null
	if is_instance_valid(screen):
		screen.queue_free()
		screen = null


func _new_screen() -> Control:
	_clear_all()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = theme
	add_child(screen)
	var bg := ColorRect.new()
	bg.color = Color("#12151a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)
	return screen


func _label(text: String, size: int = 16, color: Color = Color("#f0f2f6")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _show_menu() -> void:
	_new_screen()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(540, 0)
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := _label("抗日：地雷战", 32, Color("#f2c14e"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("M2 战役 / M1 自由战斗", 16, Color("#9fb0c8"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(HSeparator.new())

	var m2btn := Button.new()
	m2btn.text = "M2 战役：19 城镇 / 招兵 / 锻造 / 转职"
	m2btn.custom_minimum_size = Vector2(520, 42)
	m2btn.add_theme_font_override("font", font)
	m2btn.add_theme_font_size_override("font_size", 16)
	m2btn.pressed.connect(_start_campaign)
	box.add_child(m2btn)
	var free_label := _label("自由战斗（M1）", 16, Color("#8796aa"))
	free_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(free_label)

	for lv in data["levels"]:
		var idx: int = int(lv["index"])
		var b := Button.new()
		b.text = "L%02d  %s     %d 我方 / %d 敌军" % [
			idx, lv["name"], int(lv["players"]), int(lv["enemies"])
		]
		b.custom_minimum_size = Vector2(520, 38)
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_start_level.bind(idx))
		box.add_child(b)

	box.add_child(HSeparator.new())
	var hint := _label(
		"左键选择/移动/攻击 / 右键或 Esc 取消\n"
		+ "方向键/WASD 平移 / 滚轮缩放 / Tab 看敌军\n"
		+ "目标：全歼敌人。地雷只给玩家 3 颗，敌人踩中即爆。",
		16, Color("#8796aa"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(520, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var foot := _label("数据：M0 的 data/*.json + out/*.png / 字体：原版 HZK16 点阵",
			16, Color("#5f6c7d"))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(foot)


func _start_campaign() -> void:
	_clear_all()
	campaign = preload("res://scripts/m2/Campaign.gd").new()
	add_child(campaign)
	campaign.exit_requested.connect(_show_menu)
	campaign.setup(font)


func _level_by_index(idx: int) -> Dictionary:
	for lv in data["levels"]:
		if int(lv["index"]) == idx:
			return lv
	return {}


func _start_level(idx: int) -> void:
	var lv := _level_by_index(idx)
	if lv.is_empty():
		return
	_clear_all()
	current_level = idx
	battle = preload("res://scripts/Battle.gd").new()
	add_child(battle)
	battle.finished.connect(_on_battle_finished)
	battle.setup(data, lv, font)


func _on_battle_finished(result: String, message: String) -> void:
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
	result_canvas = CanvasLayer.new()
	result_canvas.layer = 100
	add_child(result_canvas)
	result_layer = Control.new()
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.theme = theme
	result_canvas.add_child(result_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.68)
	result_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	result_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var ok := result == "victory"
	var head := _label("胜  利" if ok else "失  败", 32,
			Color("#f2c14e") if ok else Color("#ff6b6b"))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var msg := _label(message, 16, Color("#e8edf4"))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var again := Button.new()
	again.text = "重来"
	again.custom_minimum_size = Vector2(120, 36)
	again.pressed.connect(func(): _start_level(current_level))
	row.add_child(again)
	var back := Button.new()
	back.text = "返回关卡"
	back.custom_minimum_size = Vector2(120, 36)
	back.pressed.connect(_show_menu)
	row.add_child(back)


func _show_fatal(msg: String) -> void:
	_new_screen()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var l := _label(msg, 16, Color("#ff8a8a"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	center.add_child(l)
