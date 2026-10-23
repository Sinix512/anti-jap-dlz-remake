extends Control

## M5 影像馆：MPEG 过场 / FLC / ANM 预览索引。
## Godot 4.7 只支持 Theora，所以优先播放 .ogv；WebM 作为交付格式保留。

signal closed

var font: Font
var media: Dictionary = {}
var anm: Dictionary = {}
var _list: VBoxContainer
var _title: Label
var _detail: Label
var _player: Control
var _history_player: Control
var _history: Array = []
var _kind := "mpeg"


func setup(f: Font, media_data: Dictionary, anm_data: Dictionary = {}) -> void:
	font = f
	media = media_data
	anm = anm_data
	var hp := "res://data/m5_history.json"
	if FileAccess.file_exists(hp):
		var hd = JSON.parse_string(FileAccess.get_file_as_string(hp))
		if hd is Dictionary:
			_history = hd.get("photos", [])
	theme = OriginalUI.make_theme(font)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.025, 0.02, 0.015, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	add_child(OriginalUI.header("影像馆 / 过场 / FLC / ANM", font,
			Rect2(0, 0, 640, 30)))
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(14, 38)
	tabs.add_theme_constant_override("separation", 4)
	add_child(tabs)
	for pair in [["过场影片", "mpeg"], ["FLC", "flc"], ["ANM", "anm"],
			["历史照片", "history"]]:
		var b := OriginalUI.button(pair[0], font, Vector2(100, 28),
				_switch.bind(pair[1]), 14)
		tabs.add_child(b)
	_title = OriginalUI.label("", font, 16, OriginalUI.GOLD_LIGHT)
	_title.position = Vector2(430, 40)
	_title.size = Vector2(190, 24)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(14, 74)
	scroll.size = Vector2(390, 350)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	var right := Control.new()
	right.position = Vector2(414, 74)
	right.size = Vector2(212, 350)
	add_child(right)
	right.add_child(OriginalUI.nine_patch(OriginalUI.PANEL_BLUE,
			Rect2(0, 0, 212, 350), 10))
	_detail = OriginalUI.label("", font, 16, OriginalUI.INK)
	_detail.position = Vector2(12, 12)
	_detail.size = Vector2(188, 300)
	_detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	right.add_child(_detail)
	var back := OriginalUI.button("返回", font, Vector2(90, 28), _close, 14)
	back.position = Vector2(12, 314)
	right.add_child(back)
	_switch("mpeg")


func _switch(kind: String) -> void:
	_kind = kind
	for c in _list.get_children():
		c.queue_free()
	_title.text = {"mpeg": "MPEG 过场", "flc": "FLC 动画",
			"anm": "ANM 精灵动画", "history": "历史照片轮播"}.get(kind, "")
	if kind == "mpeg":
		var n := 0
		for c in media.get("clips", []):
			if str(c.get("kind", "")) != "mpeg":
				continue
			n += 1
			var b := OriginalUI.button("[%s] %s  %.1fs" % [
				str(c.get("id", "")).to_upper(), str(c.get("source", "")),
				float(c.get("duration", 0.0))], font, Vector2(370, 26),
				_play.bind(c), 14)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_list.add_child(b)
		_detail.text = "MPEG 共 %d 段。\n\n原版 352×288/4:3 已转 640×480。\nWebM 为交付格式；内嵌播放使用 OGV（Theora）。" % n
	elif kind == "flc":
		var n := 0
		for c in media.get("clips", []):
			if str(c.get("kind", "")) != "flc":
				continue
			n += 1
			var b := OriginalUI.button("[FLC] %s  %.1fs" % [
				str(c.get("source", "")), float(c.get("duration", 0.0))],
				font, Vector2(370, 26), _play.bind(c), 14)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_list.add_child(b)
		_detail.text = "FLC 共 %d 段。\n\nKINGSOFT / KR-1 / TEST01 / TRAIN 已由 ffmpeg flic 解码，输出 WebM + OGV。" % n
	elif kind == "history":
		var n := 0
		for e in _history:
			n += 1
			var b := OriginalUI.button("[%02d] %s" % [
				n, str(e.get("id", ""))], font, Vector2(370, 26),
				_open_history.bind(n - 1), 14)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_list.add_child(b)
		_detail.text = "历史照片共 %d 张。\n\n顺序来自原版文件名表 0x447DB0，切换循环 0x42DC9E（WM_TIMER）。\n含 918-2/918-3、77-1/77-2 与 NPIC 01–29。\n点击任意一张进入轮播，可跳过。" % n
	else:
		var files: Array = anm.get("files", [])
		var n := 0
		for e in files:
			n += 1
			var ok := bool(e.get("decoded", false))
			var b := OriginalUI.button("[ANM] %s  %s" % [
				str(e.get("id", "")), "已解码" if ok else "未解码"],
				font, Vector2(370, 26), _show_anm.bind(e), 14)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_list.add_child(b)
		_detail.text = "ANM 共 %d 个。\n\nLPF/ANIM 容器，320×200 调色板 + 增量 RLE；已解码为 WebM 预览。\n详见 data/m5_anm.json。" % n


func _open_history(start: int) -> void:
	if _history.is_empty():
		return
	if is_instance_valid(_history_player):
		_history_player.queue_free()
	var hs = load("res://scripts/m5/HistorySlideshow.gd").new()
	add_child(hs)
	_history_player = hs
	hs.setup(font, _history, start)
	hs.closed.connect(func(): _history_player = null)


func _play(c: Dictionary) -> void:
	var p := str(c.get("ogv_path", ""))
	if p == "" or not ResourceLoader.exists(p):
		p = str(c.get("path", ""))
	if p == "" or not ResourceLoader.exists(p):
		_detail.text = "播放文件不存在。\n请先运行 tools/prepare_m5_media.py。"
		return
	if p.get_extension().to_lower() == "webm":
		_detail.text = "Godot 4.7 不支持 WebM 内嵌播放。\nWebM 已生成；请查看同目录 OGV。"
		return
	var cp = load("res://scripts/m5/CutscenePlayer.gd").new()
	add_child(cp)
	_player = cp
	cp.setup(p, font, func():
		_player = null)
	cp.finished.connect(func(): pass)


func _show_anm(e: Dictionary) -> void:
	var d: Dictionary = e.get("decode", {})
	var webm := str(d.get("webm_path", d.get("webm", "")))
	var ogv := webm.replace(".webm", ".ogv")
	_detail.text = "ANM: %s\n\n帧数 %d\n尺寸 %d×%d\n解码: %s\nWebM: %s" % [
		str(e.get("source", "")), int(e.get("header", {}).get("frames", 0)),
		int(e.get("header", {}).get("width", 320)),
		int(e.get("header", {}).get("height", 200)),
		"成功" if bool(e.get("decoded", false)) else str(e.get("decode_error", "失败")),
		webm]
	if ogv != "" and FileAccess.file_exists(ogv):
		_play({"ogv_path": ogv, "path": ogv})


func _close() -> void:
	closed.emit()
	queue_free()
