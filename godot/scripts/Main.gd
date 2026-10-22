extends Control

## M3-M5 入口：标题 / 战役 / 47 关演练 / 剧情回顾 / 设置。

const M2_PATH := "res://data/m2.json"
const M3_PATH := "res://data/m3.json"
const M4_PATH := "res://data/m4.json"
const M5_PATH := "res://data/m5.json"
const FONT_PATH := "res://assets/font/hzk16.fnt"
const LevelBuilder = preload("res://scripts/m4/LevelBuilder.gd")

var font: Font
var theme_ref: Theme
var m2: Dictionary = {}
var m3: Dictionary = {}
var m4: Dictionary = {}
var m5: Dictionary = {}
var free_state

var title_screen: Control
var campaign: Control
var battle: Node2D
var story_player: Control
var menu_root: Control
var result_canvas: CanvasLayer
var result_layer: Control
var free_level := -1
var bgm: AudioStreamPlayer
var creation_difficulty := 1
var _diff_buttons: Array = []


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH)
	else:
		font = ThemeDB.fallback_font
		push_warning("HZK16 字体缺失；请运行 tools/prepare_m1.py")
	theme_ref = OriginalUI.make_theme(font)
	theme = theme_ref
	OriginalUI.apply_cursor()
	OriginalUI.make_sfx(self)
	_apply_saved_audio()
	_start_bgm()
	m2 = _load_json(M2_PATH)
	m3 = _load_json(M3_PATH)
	m4 = _load_json(M4_PATH)
	m5 = _load_json(M5_PATH)
	if m2.is_empty() or m4.is_empty():
		_show_fatal("缺少 res://data/m2.json 或 m4.json\n"
				+ "请先运行 tools/prepare_m2.py 与 prepare_m4.py")
		return
	free_state = load("res://scripts/m2/GameState.gd").new()
	free_state.setup_m4(m4)
	free_state.new_game(m2)
	_show_title()
	_handle_capture()


func _handle_capture() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--capture"):
			call_deferred("_capture", a.trim_prefix("--capture-"))
			return


func _capture(mode: String) -> void:
	for i in range(4):
		await get_tree().process_frame
	match mode:
		"menu", "m3-title":
			pass
		"character":
			_show_character_create()
		"battle":
			_start_free_level(14)
		"battle8":
			_start_free_level(8)
		"result":
			_start_free_level(14)
			for i in range(8):
				await get_tree().process_frame
			if is_instance_valid(battle):
				for e in battle.enemy_units:
					e.alive = false
				battle._check_end()
		"m2-world", "m4-world":
			_start_campaign()
		"m2-town", "m4-town":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_town(0)
		"m4-deploy":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_deployment(0)
		"m5-levelup":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_levelups([
					{"name": "张嘎", "from": 3, "to": 5, "hp": 130, "max_hp": 130},
					{"name": "赵虎", "from": 3, "to": 4, "hp": 129, "max_hp": 129},
				])
		"m2-k04", "m4-k04":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_k04_status()
		"m2-k03", "m4-k03":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_k03_workshop()
		"m2-house", "m4-house":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_house()
		"m4-briefing":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_town(0)
				campaign._open_mission()
		"m4-shop":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_town(1)
				campaign._open_shop("junxie", false)
		"m4-party":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_town(0)
				campaign._open_party()
		"m4-forge":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_town(0)
				campaign._open_forge()
		"m4-save":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_town(0)
				campaign._open_save()
		"m4-battle", "m2-battle":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._launch_level(0, true)
		"m4-launch":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._show_town(0)
				campaign._open_mission()
				campaign._launch_campaign_level()
				for i in range(20):
					await get_tree().process_frame
				if is_instance_valid(campaign.cutscene):
					campaign.cutscene._finish()
					for i in range(20):
						await get_tree().process_frame
				if is_instance_valid(campaign.story_player):
					campaign.story_player._finish()
					for i in range(30):
						await get_tree().process_frame
		"m2-battle-result", "m4-result":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._launch_level(0, true)
				for i in range(8):
					await get_tree().process_frame
				if is_instance_valid(campaign.battle):
					for e in campaign.battle.enemy_units:
						e.alive = false
					campaign.battle._check_end()
		"m4-report":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign._launch_level(0, true)
				for i in range(8):
					await get_tree().process_frame
				if is_instance_valid(campaign.battle) and not campaign.battle.player_units.is_empty():
					var p = campaign.battle.player_units[0]
					var tt: Array = campaign.battle.level["objective"]["targets"][0]
					p.set_tile(int(tt[0]), int(tt[1]))
					campaign.battle.scenario.on_unit_moved(p)
		"m5-story":
			_show_story_preview()
		"m5-archive":
			_show_story_archive()
		"m5-ending":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign.state.ending_id = 2
				campaign.state.score_total = 3100
				campaign._show_ending(2)
		"m5-ending-gallery":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign.state.ending_id = 2
				campaign.state.endings_seen = [0, 1, 2, 3, 4, 5]
				campaign._show_ending_gallery()
		"m5-ending-hidden":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign.state.campaign_index = 36
				campaign.state.ending_id = 4
				campaign.state.score_total = 3600
				campaign.state.hidden_unlocked = true
				campaign._show_ending(4)
		"m4-world-hidden":
			_start_campaign()
			for i in range(3):
				await get_tree().process_frame
			if is_instance_valid(campaign):
				campaign.state.campaign_index = 36
				campaign.state.score_total = 3600
				campaign.state.hidden_unlocked = true
				campaign._show_world()
		"m5-cutscene":
			_show_cutscene_preview()
		"m5-gallery":
			_show_gallery_preview()
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "/tmp/m35_%s.png" % mode.replace("/", "_")
	img.save_png(path)
	print("CAPTURE ", path, " ", img.get_size())
	get_tree().quit()


func _show_story_preview() -> void:
	if is_instance_valid(story_player):
		story_player.queue_free()
	story_player = load("res://scripts/m5/StoryPlayer.gd").new()
	add_child(story_player)
	story_player.setup(font, m5, [521, 0, 1, 2], "李勇", Callable())


func _show_gallery_preview() -> void:
	var media = _load_json("res://data/m5_media.json")
	var anm = _load_json("res://data/m5_anm.json")
	var g = load("res://scripts/m5/MediaGallery.gd").new()
	add_child(g)
	g.setup(font, media if media is Dictionary else {}, anm if anm is Dictionary else {})


func _show_cutscene_preview() -> void:
	var path := _first_cutscene()
	if path != "":
		var cp = load("res://scripts/m5/CutscenePlayer.gd").new()
		add_child(cp)
		cp.setup(path, font, Callable())


func _first_cutscene() -> String:
	var media: Dictionary = m5.get("media", {})
	for c in media.get("clips", []):
		var p := str(c.get("ogv_path", c.get("ogv", "")))
		if p != "" and ResourceLoader.exists(p):
			return p
	return ""


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _clear_all() -> void:
	if is_instance_valid(campaign):
		campaign.queue_free()
		campaign = null
	if is_instance_valid(battle):
		battle.queue_free()
		battle = null
	if is_instance_valid(story_player):
		story_player.queue_free()
		story_player = null
	if is_instance_valid(title_screen):
		title_screen.queue_free()
		title_screen = null
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
		result_canvas = null
	if is_instance_valid(menu_root):
		menu_root.queue_free()
		menu_root = null


func _show_title() -> void:
	_clear_all()
	title_screen = load("res://scripts/ui/TitleScreen.gd").new()
	add_child(title_screen)
	title_screen.setup(font)
	title_screen.new_game.connect(_show_character_create)
	title_screen.continue_game.connect(_continue_campaign)
	title_screen.battle_select.connect(_open_battle_select)
	title_screen.story_archive.connect(_show_story_archive)
	title_screen.settings.connect(_show_settings)
	title_screen.quit_game.connect(func(): get_tree().quit())
	# M1 回归兼容：隐藏的 L14 快速入口（不参与视觉，仅测试/调试）
	var debug := Button.new()
	debug.text = "L14 地道战"
	debug.visible = false
	debug.pressed.connect(_start_free_level.bind(14, 0))
	title_screen.add_child(debug)
	var debug2 := Button.new()
	debug2.text = "M2 战役：19 城镇 / 招兵 / 锻造 / 转职"
	debug2.visible = false
	debug2.pressed.connect(_start_campaign)
	title_screen.add_child(debug2)


func _show_character_create() -> void:
	_clear_all()
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = theme_ref
	add_child(menu_root)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/menu01.png") 			if ResourceLoader.exists("res://assets/ui/menu01.png") else null
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	menu_root.add_child(bg)
	var cfg := ConfigFile.new()
	cfg.load("user://dlz_config.cfg")
	var name := str(cfg.get_value("player", "name", "李勇"))
	var edit := LineEdit.new()
	edit.text = name
	edit.position = Vector2(52, 390)
	edit.size = Vector2(190, 34)
	edit.add_theme_font_override("font", font)
	edit.add_theme_font_size_override("font_size", 16)
	menu_root.add_child(edit)
	var tip := OriginalUI.label("形象/兵种：默认（后续开放）", font, 14,
			Color("#e5d4ad"))
	tip.position = Vector2(52, 168)
	tip.size = Vector2(260, 20)
	menu_root.add_child(tip)
	creation_difficulty = int(cfg.get_value("gameplay", "difficulty", 1))
	_diff_buttons.clear()
	for i in range(3):
		var b := OriginalUI.button(["简 单", "普 通", "困 难"][i], font,
				Vector2(76, 28), _pick_difficulty.bind(i), 14)
		b.position = Vector2(260 + i * 82, 394)
		menu_root.add_child(b)
		_diff_buttons.append(b)
	_refresh_difficulty_buttons()
	var start := OriginalUI.button("开始战役", font, Vector2(120, 30),
			func(): _save_player_name(edit.text, creation_difficulty); _start_campaign(), 16)
	start.position = Vector2(240, 438)
	menu_root.add_child(start)
	var back := OriginalUI.button("返回", font, Vector2(90, 30),
			_show_title, 16)
	back.position = Vector2(420, 438)
	menu_root.add_child(back)


func _pick_difficulty(v: int) -> void:
	creation_difficulty = v
	_refresh_difficulty_buttons()


func _refresh_difficulty_buttons() -> void:
	for i in range(_diff_buttons.size()):
		var b: Button = _diff_buttons[i]
		b.modulate = Color(1.25, 1.1, 0.65) if i == creation_difficulty else Color.WHITE


func _save_player_name(text: String, diff: int = 1) -> void:
	var c := ConfigFile.new()
	c.load("user://dlz_config.cfg")
	var nm := text.strip_edges()
	c.set_value("player", "name", nm if nm != "" else "李勇")
	c.set_value("gameplay", "difficulty", diff)
	c.save("user://dlz_config.cfg")


func _start_campaign() -> void:
	_clear_all()
	campaign = load("res://scripts/m4/Campaign.gd").new()
	add_child(campaign)
	campaign.exit_requested.connect(_show_title)
	campaign.setup(font)


func _continue_campaign() -> void:
	_start_campaign()
	if is_instance_valid(campaign):
		campaign._open_save_load()


func _open_battle_select() -> void:
	if is_instance_valid(menu_root):
		menu_root.queue_free()
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = theme_ref
	add_child(menu_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(dim)
	var panel := OriginalUI.nine_patch(OriginalUI.PANEL_RED,
			Rect2(20, 16, 600, 448), 12)
	menu_root.add_child(panel)
	menu_root.add_child(OriginalUI.header("战斗演练 / 47 关", font,
			Rect2(26, 22, 588, 28)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(36, 58)
	scroll.size = Vector2(560, 352)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for lv in m4.get("levels", []):
		var idx := int(lv["index"])
		var tag := "主线"
		if str(lv.get("kind", "")) == "hidden":
			tag = "隐藏/" + str(lv.get("hidden_mode", ""))
		elif str(lv.get("kind", "")) == "easter":
			tag = "彩蛋"
		var b := OriginalUI.button("L%02d  %-8s  %-14s  敌%d" % [
			idx, str(lv["name"]), tag, int(lv.get("enemies", 0))],
			font, Vector2(540, 28), _start_free_level.bind(idx), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	var back := OriginalUI.button("返回标题", font, Vector2(120, 30),
			_show_title, 16)
	back.position = Vector2(36, 420)
	menu_root.add_child(back)


func _start_free_level(idx: int, party_limit: int = -1) -> void:
	_clear_all()
	free_level = idx
	var level: Dictionary = LevelBuilder.build(m4, m2, idx, free_state.party, false,
			party_limit)
	if level.is_empty():
		_show_title()
		return
	battle = load("res://scripts/Battle.gd").new()
	add_child(battle)
	battle.finished.connect(_on_free_finished)
	battle.setup(m4, level, font)


func _on_free_finished(result: String, message: String) -> void:
	_show_free_result(result == "victory", message)


func _show_free_result(victory: bool, message: String) -> void:
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
	result_canvas = CanvasLayer.new()
	result_canvas.layer = 100
	add_child(result_canvas)
	result_layer = Control.new()
	result_layer.theme = theme_ref
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_canvas.add_child(result_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.add_child(dim)
	var panel := OriginalUI.nine_patch(OriginalUI.PANEL_RED,
			Rect2(90, 120, 460, 240), 12)
	result_layer.add_child(panel)
	var head := OriginalUI.title("胜  利" if victory else "失  败", font, 30,
			OriginalUI.GOLD if victory else Color("#ff6b6b"))
	head.position = Vector2(90, 132)
	head.size = Vector2(460, 36)
	result_layer.add_child(head)
	var idx := free_level
	var lv: Dictionary = m4.get("levels", [])[idx]
	var body := OriginalUI.label("%s\n\n%s\n\n%s" % [
		str(lv.get("name", "")), message,
		"击毙 %d    伤亡 %d    宝箱 %d    回合 %d" % [
			int(battle.stats.get("kills", 0)), int(battle.stats.get("losses", 0)),
			int(battle.stats.get("chests", 0)), int(battle.turn)]],
		font, 16, OriginalUI.INK)
	body.position = Vector2(120, 180)
	body.size = Vector2(400, 100)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_layer.add_child(body)
	var row := HBoxContainer.new()
	row.position = Vector2(160, 302)
	row.add_theme_constant_override("separation", 12)
	var retry := OriginalUI.button("重 试", font, Vector2(100, 30),
			_start_free_level.bind(idx), 16)
	row.add_child(retry)
	var pick := OriginalUI.button("选 关", font, Vector2(100, 30),
			_open_battle_select, 16)
	row.add_child(pick)
	var title := OriginalUI.button("标 题", font, Vector2(100, 30),
			_show_title, 16)
	row.add_child(title)
	result_layer.add_child(row)


func _start_bgm() -> void:
	var path := "res://assets/audio/bgm_title.ogg"
	if not ResourceLoader.exists(path):
		path = "res://assets/audio/bgm_cd.ogg"
	if not ResourceLoader.exists(path):
		return
	bgm = AudioStreamPlayer.new()
	bgm.stream = load(path)
	if bgm.stream is AudioStreamOggVorbis:
		(bgm.stream as AudioStreamOggVorbis).loop = true
	bgm.volume_db = -14.0
	add_child(bgm)
	bgm.play()


func _apply_saved_audio() -> void:
	var c := ConfigFile.new()
	if c.load("user://dlz_config.cfg") != OK:
		return
	var v := float(c.get_value("audio", "master_volume", 0.8))
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(v, 0.0, 1.0)))


func _show_settings() -> void:
	if is_instance_valid(menu_root):
		menu_root.queue_free()
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = theme_ref
	add_child(menu_root)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.01, 0.008, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(dim)
	menu_root.add_child(OriginalUI.header("设 置", font, Rect2(0, 0, 640, 30)))
	var cfg := ConfigFile.new()
	cfg.load("user://dlz_config.cfg")
	var pname := str(cfg.get_value("player", "name", "李勇"))
	var y := 70
	var l1 := OriginalUI.label("主角姓名（替换剧情中的 GG）", font, 16,
			OriginalUI.GOLD_LIGHT)
	l1.position = Vector2(80, y)
	l1.size = Vector2(480, 22)
	menu_root.add_child(l1)
	var edit := LineEdit.new()
	edit.text = pname
	edit.position = Vector2(80, y + 26)
	edit.size = Vector2(240, 30)
	edit.add_theme_font_override("font", font)
	edit.add_theme_font_size_override("font_size", 16)
	edit.max_length = 8
	menu_root.add_child(edit)
	var vol_l := OriginalUI.label("音量（0–100）", font, 16,
			OriginalUI.GOLD_LIGHT)
	vol_l.position = Vector2(360, y)
	vol_l.size = Vector2(220, 22)
	menu_root.add_child(vol_l)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(cfg.get_value("audio", "master_volume", 0.8))
	vol.position = Vector2(360, y + 28)
	vol.size = Vector2(200, 24)
	menu_root.add_child(vol)
	var variant := CheckButton.new()
	variant.text = "使用过场变体（A 版）"
	variant.button_pressed = bool(cfg.get_value("video", "story_variant", false))
	variant.position = Vector2(300, y + 76)
	variant.add_theme_font_override("font", font)
	variant.add_theme_font_size_override("font_size", 14)
	menu_root.add_child(variant)
	var full := CheckButton.new()
	full.text = "全屏"
	full.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	full.position = Vector2(80, y + 76)
	full.add_theme_font_override("font", font)
	full.add_theme_font_size_override("font_size", 16)
	menu_root.add_child(full)
	var save := OriginalUI.button("保存并返回", font, Vector2(160, 34),
			_save_settings.bind(edit, full, vol, variant), 16)
	save.position = Vector2(80, y + 140)
	menu_root.add_child(save)
	var back := OriginalUI.button("返回", font, Vector2(100, 30), _show_title, 16)
	back.position = Vector2(260, y + 142)
	menu_root.add_child(back)
	var note := OriginalUI.label("窗口基准 640×480，整数倍最近邻缩放。", font, 14,
			Color("#b9a98b"))
	note.position = Vector2(80, y + 196)
	note.size = Vector2(480, 22)
	menu_root.add_child(note)


func _save_settings(edit: LineEdit, full: CheckButton, vol: HSlider,
		variant: CheckButton) -> void:
	var c := ConfigFile.new()
	var nm := edit.text.strip_edges()
	c.set_value("player", "name", nm if nm != "" else "李勇")
	c.set_value("video", "fullscreen", full.button_pressed)
	c.set_value("audio", "master_volume", float(vol.value))
	c.set_value("video", "story_variant", variant.button_pressed)
	c.save("user://dlz_config.cfg")
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(vol.value), 0.0, 1.0)))
	if full.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_show_title()


func _show_story_archive() -> void:
	if is_instance_valid(story_player):
		return
	if is_instance_valid(menu_root):
		menu_root.queue_free()
		menu_root = null
	if is_instance_valid(title_screen):
		title_screen.visible = false
	story_player = load("res://scripts/m5/StoryPlayer.gd").new()
	add_child(story_player)
	story_player.setup(font, m5, [], "李勇", func():
		story_player = null
		_show_title())


func _show_fatal(msg: String) -> void:
	_clear_all()
	var bg := ColorRect.new()
	bg.color = Color("#120c08")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var l := OriginalUI.label(msg, font, 16, Color("#ff8a8a"))
	l.position = Vector2(60, 160)
	l.size = Vector2(520, 160)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bg.add_child(l)
