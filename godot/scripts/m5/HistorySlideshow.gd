extends Control

## 原版历史照片轮播。
## 文件名顺序来自 DLZ.exe 0x447DB0；切换循环在 0x42DC9E（WM_TIMER）。
## ticks 为原版计时器阈值，这里按 10ms/tick 估算显示时长并夹在 2.4–7s。

signal closed

var font: Font
var photos: Array = []
var index := 0
var _tex: TextureRect
var _count: Label
var _caption: Label
var _timer: Timer
var _fade: ColorRect


func setup(f: Font, entries: Array, start_index: int = 0) -> void:
	font = f
	photos = entries.duplicate(true)
	index = clampi(start_index, 0, max(0, photos.size() - 1))
	theme = OriginalUI.make_theme(font)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_show(index)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.012, 0.010, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_tex = TextureRect.new()
	_tex.position = Vector2(0, 28)
	_tex.size = Vector2(640, 410)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_tex)

	add_child(OriginalUI.header("历史照片 / 一九三一 — 一九四五", font,
			Rect2(0, 0, 640, 28)))
	_count = OriginalUI.label("", font, 14, OriginalUI.GOLD_LIGHT)
	_count.position = Vector2(500, 4)
	_count.size = Vector2(128, 20)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count)

	_caption = OriginalUI.label("", font, 14, Color("#d8c39a"))
	_caption.position = Vector2(20, 440)
	_caption.size = Vector2(420, 22)
	add_child(_caption)

	var prev := OriginalUI.button("上一张", font, Vector2(84, 26),
			_prev, 14)
	prev.position = Vector2(346, 440)
	add_child(prev)
	var next := OriginalUI.button("下一张", font, Vector2(84, 26),
			_next, 14)
	next.position = Vector2(436, 440)
	add_child(next)
	var skip := OriginalUI.button("跳过", font, Vector2(76, 26),
			_close, 14)
	skip.position = Vector2(552, 440)
	add_child(skip)
	var hint := OriginalUI.label("空格/→ 下一张    ← 上一张    Esc 跳过", font, 12,
			Color("#9f8a68"))
	hint.position = Vector2(0, 466)
	hint.size = Vector2(640, 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_next)
	add_child(_timer)


func _show(i: int) -> void:
	if photos.is_empty():
		_close()
		return
	index = posmod(i, photos.size())
	var e: Dictionary = photos[index]
	var path := str(e.get("path", ""))
	_tex.texture = load(path) if ResourceLoader.exists(path) else null
	_count.text = "%d / %d" % [index + 1, photos.size()]
	_caption.text = str(e.get("id", ""))
	var ticks := int(e.get("ticks", 0))
	var secs := 4.0
	if ticks > 0:
		var prev_ticks := 0
		if index > 0:
			prev_ticks = int(photos[index - 1].get("ticks", 0))
		var delta := ticks - prev_ticks
		if delta <= 0:
			delta = 175
		secs = clampf(float(delta) * 0.01, 2.4, 7.0)
	_timer.start(secs)
	# 淡入，避免硬切
	_fade.color = Color(0, 0, 0, 0.65)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.28)


func _prev() -> void:
	_show(index - 1)


func _next() -> void:
	if index >= photos.size() - 1:
		_close()
		return
	_show(index + 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_next()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT or event.keycode == KEY_SPACE:
			_next()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_LEFT:
			_prev()
			get_viewport().set_input_as_handled()


func _close() -> void:
	if is_instance_valid(_timer):
		_timer.stop()
	closed.emit()
	queue_free()
