extends Control
# 425A08: clear entry input, then wait for a fresh release. The frame barrier
# is a Godot queue adapter, not a claim to emulate the Win32 message queue.
signal confirmed
var wait_frame:=-1
var done:=false
var _touch_pressed:=false
func begin_wait() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	preload("res://scripts/ui/OriginalPaletteFade.gd").discard_buffered_input(get_tree())
	wait_frame=Engine.get_process_frames()+1
	OriginalUI.touch_back(self,load("res://assets/font/hzk16.fnt"),_touch_advance,"继续")
func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if OriginalUI.touch_mode(self):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_touch_advance();return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_touch_pressed=true;return
			if _touch_pressed:_touch_pressed=false;OriginalUI.native_wait_left_blocked=false;_touch_advance();return
			return # A release without its fresh DOWN belongs to the opening gesture.
	if Engine.get_process_frames()<wait_frame:return
	if event is InputEventKey and not event.pressed:_accept()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:_accept()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if OriginalUI.native_wait_left_blocked:OriginalUI.native_wait_left_blocked=false
			else:_accept()
func _accept() -> void:
	if done:return
	done=true;confirmed.emit()

func _touch_advance() -> void:
	if not done and Engine.get_process_frames()>=wait_frame:_accept()
