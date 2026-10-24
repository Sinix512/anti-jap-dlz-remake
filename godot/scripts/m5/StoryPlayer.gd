extends Control

## M5 剧情播放器：TXT 478 条、说话人/头像、占位符替换、逐字显示。
## 也提供“剧情回顾”档案模式。

signal finished

var font: Font
var data: Dictionary = {}
var player_name := "李勇"
var mode := "scene"
var ids: Array = []
var lines: Array = []
var line_index := 0
var typing := false
var visible_chars := 0.0
var speed := 52.0
var _on_done: Callable
var _records: Dictionary = {}

var _portrait: TextureRect
var _big_portrait: TextureRect
var _speaker: Label
var _text_label: Label
var _hint: Label
var _counter: Label
var _indicator: Label
var _panel: Control
var _archive_root: Control
var _preview_name: Label
var archive_levels_only := false
var _preview_text: Label
var _preview_portrait: TextureRect
var _selected_record := 0


func setup(f: Font, m5: Dictionary, scene_ids: Array = [],
		name_text: String = "李勇", on_done: Callable = Callable()) -> void:
	font = f
	data = m5
	player_name = name_text if name_text != "" else "李勇"
	_on_done = on_done
	theme = OriginalUI.make_theme(font)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for r in data.get("records", []):
		_records[int(r["n"])] = r
	if scene_ids.is_empty():
		mode = "archive"
		_build_archive()
	else:
		mode = "scene"
		ids = scene_ids.duplicate()
		_build_scene()
		_build_lines()


func _build_scene() -> void:
	var lv := -1
	for n in ids:
		var rec: Dictionary = _records.get(int(n), {})
		if not rec.is_empty() and int(rec.get("level", -1)) >= 0:
			lv = int(rec["level"])
			break
	var npic_ids := [1, 2, 3, 4, 5, 6, 7, 8, 18, 19, 20, 21, 22, 25, 29]
	var bg_path := "res://assets/ui/story_bg.png"
	if lv >= 0 and lv < npic_ids.size():
		var np := "res://assets/ui/npic_%02d.png" % int(npic_ids[lv])
		if ResourceLoader.exists(np):
			bg_path = np
	var bg := TextureRect.new()
	bg.texture = load(bg_path) if ResourceLoader.exists(bg_path) else null
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.modulate = Color(0.72, 0.68, 0.60, 1.0)
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var head := OriginalUI.header("剧 情", font, Rect2(0, 0, 640, 30))
	add_child(head)
	_counter = OriginalUI.label("", font, 14, Color("#d8c39a"))
	_counter.position = Vector2(520, 5)
	_counter.size = Vector2(110, 20)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_counter)
	_big_portrait = TextureRect.new()
	_big_portrait.position = Vector2(18, 62)
	_big_portrait.size = Vector2(150, 190)
	_big_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_big_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_big_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_big_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_portrait.visible = false
	add_child(_big_portrait)

	_panel = Control.new()
	_panel.position = Vector2(20, 276)
	_panel.size = Vector2(600, 168)
	add_child(_panel)
	_panel.add_child(OriginalUI.nine_patch(OriginalUI.PANEL_RED,
			Rect2(0, 0, 600, 168), 12))
	var head2 := OriginalUI.header("", font, Rect2(0, 0, 600, 30))
	_panel.add_child(head2)
	_portrait = TextureRect.new()
	_portrait.position = Vector2(12, 38)
	_portrait.size = Vector2(78, 98)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel.add_child(_portrait)
	_speaker = OriginalUI.label("", font, 16, OriginalUI.GOLD_LIGHT)
	_speaker.position = Vector2(24, 36)
	_speaker.size = Vector2(552, 22)
	_panel.add_child(_speaker)
	_text_label = OriginalUI.label("", font, 16, OriginalUI.INK)
	_text_label.position = Vector2(24, 62)
	_text_label.size = Vector2(552, 94)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_panel.add_child(_text_label)
	_hint = OriginalUI.label("点击 / 空格 继续    Esc 跳过", font, 14,
			Color("#d8c39a"))
	_hint.position = Vector2(8, 450)
	_hint.size = Vector2(624, 20)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_indicator = OriginalUI.label("▼", font, 16, OriginalUI.GOLD)
	_indicator.position = Vector2(584, 420)
	_indicator.size = Vector2(20, 20)
	_indicator.visible = false
	add_child(_indicator)
	gui_input.connect(_on_gui_input)


func _build_lines() -> void:
	lines.clear()
	for n in ids:
		var rec: Dictionary = _records.get(int(n), {})
		if rec.is_empty():
			continue
		for line in rec.get("lines", []):
			var l: Dictionary = (line as Dictionary).duplicate(true)
			l["n"] = int(n)
			lines.append(l)
	line_index = 0
	if lines.is_empty():
		_finish()
		return
	_show_line(0)


func _fmt(text: String) -> String:
	text = text.replace("GG", player_name)
	for p in ["AA", "BB", "CC", "DD", "TT"]:
		text = text.replace(p, "")
	return text


func _show_line(i: int) -> void:
	if i < 0 or i >= lines.size():
		_finish()
		return
	line_index = i
	var l: Dictionary = lines[i]
	var speaker := str(l.get("speaker", "旁白"))
	if speaker == "GG":
		speaker = player_name
	var text := _fmt(str(l.get("text", "")))
	_speaker.text = speaker
	_text_label.text = text
	_text_label.visible_characters = 0
	visible_chars = 0.0
	typing = true
	_indicator.visible = false
	var face := int(l.get("face", -1))
	if face >= 0 and ResourceLoader.exists("res://assets/face/face_%03d.png" % face):
		var ft: Texture2D = load("res://assets/face/face_%03d.png" % face)
		_portrait.texture = null
		_portrait.visible = false
		_big_portrait.texture = ft
		_big_portrait.visible = true
	else:
		_portrait.texture = null
		_portrait.visible = false
		_big_portrait.texture = null
		_big_portrait.visible = false
		if speaker == "旁白":
			_speaker.text = ""
			_text_label.position = Vector2(24, 40)
			_text_label.size = Vector2(552, 116)
		else:
			_text_label.position = Vector2(24, 62)
			_text_label.size = Vector2(552, 94)
	_counter.text = "%d / %d" % [i + 1, lines.size()]


func _process(delta: float) -> void:
	if mode != "scene" or not typing:
		return
	visible_chars += speed * delta
	var total := _text_label.text.length()
	if visible_chars >= total:
		visible_chars = total
		typing = false
		_indicator.visible = true
	_text_label.visible_characters = int(visible_chars)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_advance()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER \
				or event.keycode == KEY_KP_ENTER:
			_advance()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_finish()


func _advance() -> void:
	if mode != "scene":
		return
	if typing:
		typing = false
		_text_label.visible_characters = -1
		_indicator.visible = true
		return
	OriginalUI.play_sfx("click")
	if line_index + 1 < lines.size():
		_show_line(line_index + 1)
	else:
		_finish()


func _finish() -> void:
	if _on_done.is_valid():
		_on_done.call()
	finished.emit()
	queue_free()


# ---------------- 剧情回顾 ----------------

func _build_archive() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.03, 0.025, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var recs: Array = data.get("records", [])
	var shown := 0
	for r in recs:
		if not archive_levels_only or int(r.get("level", -1)) >= 0:
			shown += 1
	add_child(OriginalUI.header("剧情回顾 / %d 条" % shown, font, Rect2(0, 0, 640, 30)))
	var toggle := CheckButton.new()
	toggle.text = "只看关卡剧情"
	toggle.button_pressed = archive_levels_only
	toggle.position = Vector2(390, 2)
	toggle.size = Vector2(150, 26)
	toggle.add_theme_font_override("font", font)
	toggle.add_theme_font_size_override("font_size", 16)
	toggle.toggled.connect(func(v: bool):
		archive_levels_only = v
		_rebuild_archive())
	add_child(toggle)
	var left := ScrollContainer.new()
	left.position = Vector2(14, 42)
	left.size = Vector2(268, 392)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(left)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 1)
	left.add_child(list)
	for r in recs:
		if archive_levels_only and int(r.get("level", -1)) < 0:
			continue
		var first := ""
		if not (r.get("lines", []) as Array).is_empty():
			first = str(r["lines"][0].get("text", ""))
		var b := OriginalUI.button("n%03d  %s" % [int(r["n"]), _fmt(first).substr(0, 12)],
				font, Vector2(250, 24), _preview.bind(int(r["n"])), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	var right := Control.new()
	right.position = Vector2(292, 42)
	right.size = Vector2(334, 392)
	add_child(right)
	right.add_child(OriginalUI.nine_patch(OriginalUI.PANEL_BLUE,
			Rect2(0, 0, 334, 392), 10))
	_preview_portrait = TextureRect.new()
	_preview_portrait.position = Vector2(12, 46)
	_preview_portrait.size = Vector2(72, 90)
	_preview_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_preview_portrait)
	_preview_name = OriginalUI.label("选择左侧条目", font, 16, OriginalUI.GOLD_LIGHT)
	_preview_name.position = Vector2(94, 46)
	_preview_name.size = Vector2(228, 22)
	right.add_child(_preview_name)
	_preview_text = OriginalUI.label("", font, 16, OriginalUI.INK)
	_preview_text.position = Vector2(12, 146)
	_preview_text.size = Vector2(310, 190)
	_preview_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	right.add_child(_preview_text)
	var play := OriginalUI.button("播放本段", font, Vector2(92, 30),
			_play_selected, 16)
	play.position = Vector2(12, 348)
	right.add_child(play)
	var media := OriginalUI.button("影像馆", font, Vector2(92, 30),
			_open_media, 16)
	media.position = Vector2(110, 348)
	right.add_child(media)
	var back := OriginalUI.button("返回", font, Vector2(90, 30),
			_finish, 16)
	back.position = Vector2(208, 348)
	right.add_child(back)
	for r in recs:
		if archive_levels_only and int(r.get("level", -1)) < 0:
			continue
		_preview(int(r["n"]))
		break


func _rebuild_archive() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build_archive()


func _preview(n: int) -> void:
	_selected_record = n
	var rec: Dictionary = _records.get(n, {})
	if rec.is_empty():
		return
	var lines_arr: Array = rec.get("lines", [])
	var speaker := ""
	var face := -1
	var text := ""
	for l in lines_arr:
		var sp := str(l.get("speaker", "旁白"))
		if sp == "GG":
			sp = player_name
		speaker = sp
		face = int(l.get("face", -1))
		text += "%s：%s\n" % [sp, _fmt(str(l.get("text", "")))]
	var lv := int(rec.get("level", -1))
	var tag := str(rec.get("trigger", "archive"))
	_preview_name.text = "n=%d %s %s  %s" % [n,
			("L%02d" % lv) if lv >= 0 else "档案", tag, speaker]
	_preview_text.text = text
	if face >= 0 and ResourceLoader.exists("res://assets/face/face_%03d.png" % face):
		_preview_portrait.texture = load("res://assets/face/face_%03d.png" % face)
		_preview_portrait.visible = true
	else:
		_preview_portrait.texture = null
		_preview_portrait.visible = false


func _open_media() -> void:
	var media: Dictionary = data.get("media", {})
	if media.is_empty() or (media.get("clips", []) as Array).is_empty():
		var f := FileAccess.open("res://data/m5_media.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				media = parsed
	var anm: Dictionary = {}
	var af := FileAccess.open("res://data/m5_anm.json", FileAccess.READ)
	if af != null:
		var pa = JSON.parse_string(af.get_as_text())
		if pa is Dictionary:
			anm = pa
	var parent: Node = get_parent()
	var g = load("res://scripts/m5/MediaGallery.gd").new()
	parent.add_child(g)
	g.setup(font, media, anm)
	visible = false
	g.closed.connect(func():
		g.queue_free()
		visible = true)


func _play_selected() -> void:
	# 关闭档案，重开为单条播放
	var parent: Node = get_parent()
	var scene: Control = load("res://scripts/m5/StoryPlayer.gd").new()
	var m5 := data
	var f := font
	var nm := player_name
	parent.add_child(scene)
	scene.setup(f, m5, [_selected_record], nm, Callable())
	queue_free()
