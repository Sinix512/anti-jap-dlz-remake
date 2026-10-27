extends Control

## M5 剧情播放器：TXT 478 条、说话人/头像、占位符替换、原纵向卷页。
## 也提供“剧情回顾”档案模式。

signal finished

var context: Dictionary = {}
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
const NativePalette=preload("res://scripts/ui/OriginalPalette.gd")
var _native_palette:Array=[]
static var _native_faces:PackedByteArray
var native_page:Control
var old_native_page:Control
const Layout=preload("res://scripts/ui/OriginalStoryLayout.gd")

var _portrait: TextureRect
var _big_portrait: TextureRect
var _speaker: Label
var _text_label: RichTextLabel
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
var _finished := false


func setup(f: Font, m5: Dictionary, scene_ids: Array = [],
		name_text: String = "李勇", on_done: Callable = Callable(), scene_context: Dictionary = {}) -> void:
	font = f
	context = scene_context
	_native_palette=NativePalette.colors(str(context.get("native_palette_key","KUANG04")))
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
	# Only the original404x127 frame; no typewriter, ▼, click sound or dimmer.
	if context.has("backdrop"):
		var bg:=TextureRect.new();bg.texture=load(str(context.backdrop))
		bg.position=Vector2.ZERO;bg.size=Vector2(640,480);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
	_speaker=Label.new();_speaker.hide();add_child(_speaker)
	_counter=Label.new();_counter.hide();add_child(_counter)
	_big_portrait=TextureRect.new();_big_portrait.hide();add_child(_big_portrait)

func _build_lines() -> void:
	lines.clear()
	for n in ids:
		var rec:Dictionary=_records.get(int(n),{})
		for source in rec.get("lines",[]):
			var line:Dictionary=source.duplicate(true);line["n"]=int(n)
			var code:=int(line.get("code",-1))
			var identity:Dictionary=context.get("people_by_slot",{}).get(str(code),{})
			if not identity.is_empty():
				line["speaker"]=identity.get("name",line.get("speaker",""));line["face"]=identity.get("face",-1)
			if code==0:line["speaker"]=player_name
			var width:=36 if code>=0 or bool(context.get("battle_profile",false)) else 46
			var pages:=Layout.pages(_fmt(str(line.get("text",""))),str(line.get("speaker","")) if code>=0 else "",width)
			for j in range(pages.size()):
				var copy:=line.duplicate(true);copy["glyphs"]=pages[j];copy["width"]=width;copy["record_end"]=j==pages.size()-1;copy["continues"]=j>0;lines.append(copy)
	line_index=0
	if lines.is_empty():_finish()
	else:_show_line(0)


func _fmt(text: String) -> String:
	var out:="";var i:=0
	while i<text.length():
		var char:=text.substr(i,1)
		if char in ["G","T"]:
			out+=_red_name(player_name if char=="G" else str(context.get("level_name","当前战斗")));i+=2
		else:out+=char;i+=1
	return out

func _red_name(value:String) -> String:
	var out:=""
	for char in value:out+=("AA" if char.unicode_at(0)>=128 else "")+char
	return out


func _show_line(i:int) -> void:
	if i<0 or i>=lines.size():_finish();return
	line_index=i
	var line:Dictionary=lines[i]
	if is_instance_valid(native_page):
		if bool(line.get("continues",false)):
			old_native_page=native_page;old_native_page.set_process(false);old_native_page.set_process_input(false)
		else:native_page.hide();native_page.queue_free()
	native_page=preload("res://scripts/ui/OriginalStoryPage.gd").new();add_child(native_page)
	native_page.setup(font,line.glyphs,int(line.get("face",-1)) if int(line.get("code",-1))>=0 else -1,str(context.get("native_palette_key","KUANG04")),int(line.width))
	native_page.record_end=bool(line.record_end);native_page.battle_profile=bool(context.get("battle_profile",false))
	if is_instance_valid(old_native_page):
		native_page.hide()
		native_page.scroll_started.connect(func():
			native_page.show()
			if is_instance_valid(old_native_page):old_native_page.queue_free();old_native_page=null)
	_speaker.text=str(line.get("speaker","旁白"))
	native_page.confirmed.connect(func():
		if line_index+1<lines.size():_show_line(line_index+1)
		else:_finish())

func _advance() -> void:
	# Explicit QA/archive stepping only; real input lives in OriginalStoryPage.
	if mode!="scene" or not is_instance_valid(native_page):return
	if native_page.stage=="scroll":native_page.height=99;native_page._scroll_step()
	elif native_page.stage=="wait":native_page._accept()


func _finish() -> void:
	if _finished: return
	_finished = true
	process_mode=Node.PROCESS_MODE_DISABLED;hide()
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
