extends Control

## M5 过场视频播放器。Godot 4.7 只能播 Theora (.ogv)，所以 M5 媒体管线
## 同时产出 WebM（交付）与 OGV（引擎播放）。

signal finished

var _video: VideoStreamPlayer
var _on_done: Callable
var _path := ""


func setup(path: String, font: Font, on_done: Callable = Callable()) -> void:
	_path = path
	_on_done = on_done
	theme = OriginalUI.make_theme(font)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if path == "" or not ResourceLoader.exists(path):
		_finish()
		return
	var stream = load(path)
	if stream == null:
		_finish()
		return
	_video = VideoStreamPlayer.new()
	_video.stream = stream
	_video.position = Vector2.ZERO
	_video.size = Vector2(640, 480)
	_video.expand = true
	_video.autoplay = true
	_video.finished.connect(_finish)
	add_child(_video)
	var hint := OriginalUI.label("Esc / 点击 跳过", font, 14, Color("#d8c39a"))
	hint.position = Vector2(500, 454)
	hint.size = Vector2(132, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(hint)
	gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_finish())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_finish()


func _finish() -> void:
	if _video != null and is_instance_valid(_video):
		_video.stop()
	if _on_done.is_valid():
		_on_done.call()
	finished.emit()
	queue_free()
