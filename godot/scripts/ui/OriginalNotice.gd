extends Control
# 43D56B/425A08. Item notices explicitly set57BD44; story/result notices inherit it.
signal closed
const UI=preload("res://scripts/ui/OriginalUI.gd")
const GBK=preload("res://scripts/m2/GBK.gd")
var skip_left:=true
var done:=false
var _touch_pressed:=false
func setup(font:Font,value:String,palette:Array=[]) -> void:
	UI.native_wait_left_blocked=true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	var frame:=UI.panel("res://assets/ui/frame00_original.png",Rect2(118,296,404,127))
	if not palette.is_empty():frame.texture=preload("res://scripts/ui/OriginalPalette.gd").asset("frame00",404,127,palette,0)
	add_child(frame)
	var rows:=preload("res://scripts/ui/OriginalStoryLayout.gd").plain_rows(value)
	for row in range(rows.size()):
		var label:=UI.label(str(rows[row]),font,16,Color("#a4fcfc"))
		label.position=Vector2(142,312+20*row);label.size=Vector2(368,20);label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT);add_child(label)
	UI.touch_back(self,font,_close,"知道了")

func _input(event:InputEvent) -> void:
	if done:return
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey:get_viewport().set_input_as_handled()
	if UI.touch_mode(self):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_close();return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_touch_pressed=true;return
			if _touch_pressed:_touch_pressed=false;UI.native_wait_left_blocked=false;_close();return
			return # A release without its fresh DOWN belongs to the opening gesture.
	if event is InputEventKey and not event.pressed:_close()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:_close()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if skip_left:skip_left=false;UI.native_wait_left_blocked=false
			else:_close()
func _close() -> void:
	if done:return
	done=true;closed.emit()
