extends Control

## 42DC9E: tick0 NPIC25, 18 transitions, 55ms/tick; final NPIC01 waits for click.
signal closed
var font: Font
var photos: Array = []
var index := 0
var _background: ColorRect
var _tex: TextureRect
var _timer: Timer
var _closed := false
# 42E0F1 creation history exits on left-DOWN, not release/keyboard.
var creation_entry := false
func setup(f: Font, entries: Array, start_index: int = 0) -> void:
	font=f
	photos=entries.duplicate(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	_background=ColorRect.new()
	_background.color=Color.BLACK
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_tex=TextureRect.new()
	_tex.size=Vector2(640,480)
	_tex.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode=TextureRect.STRETCH_SCALE
	_tex.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_tex)
	_timer=Timer.new()
	_timer.one_shot=true
	_timer.timeout.connect(_next)
	add_child(_timer)
	gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed==creation_entry: _close())
	var music = get_node_or_null("/root/Music")
	if music != null:
		music.loop_enabled = false
		music.play_scene(46)
	_show(clampi(start_index,0,maxi(0,photos.size()-1)))
func _show(i: int) -> void:
	if photos.is_empty(): _close(); return
	index=clampi(i,0,photos.size()-1)
	var path := str(photos[index].get("path",""))
	_tex.texture=load(path) if ResourceLoader.exists(path) else null
	if _tex.texture!=null:
		_tex.size=_tex.texture.get_size()
		_tex.position=Vector2((640-int(_tex.size.x))/2,(480-int(_tex.size.y))/2)
	var rgb:Array=photos[index].get("background_rgb",[0,0,0])
	_background.color=Color8(int(rgb[0]),int(rgb[1]),int(rgb[2]))
	_timer.stop()
	if index+1 < photos.size():
		_timer.start(maxf(0.055,(int(photos[index+1].get("ticks",0))-int(photos[index].get("ticks",0)))*0.055))
func _next() -> void:
	if index+1 < photos.size(): _show(index+1)
func _prev() -> void:
	_show(index-1)
func _unhandled_input(event: InputEvent) -> void:
	if creation_entry:return
	if event is InputEventKey and not event.pressed:
		if event.keycode == KEY_ESCAPE: _close()
		elif event.keycode == KEY_LEFT: _prev()
		elif event.keycode in [KEY_RIGHT,KEY_SPACE,KEY_ENTER]:
			if index == photos.size()-1: _close()
			else: _next()
		get_viewport().set_input_as_handled()
func _close() -> void:
	if _closed: return
	_closed=true
	_timer.stop()
	var music = get_node_or_null("/root/Music")
	if music != null:
		music.stop()
		music.loop_enabled = true
	closed.emit()
	queue_free()
