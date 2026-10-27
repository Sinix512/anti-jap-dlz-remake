extends Control
# 425A08: clear entry input, then wait for a fresh release. The frame barrier
# is a Godot queue adapter, not a claim to emulate the Win32 message queue.
signal confirmed
var wait_frame:=-1
var done:=false
func begin_wait() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	preload("res://scripts/ui/OriginalPaletteFade.gd").discard_buffered_input(get_tree())
	wait_frame=Engine.get_process_frames()+1
func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
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
