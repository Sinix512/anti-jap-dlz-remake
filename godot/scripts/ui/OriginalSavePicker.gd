extends Control
# 4282F9: five-slot MENU09 overlay, not a combined save/load/developer menu.
signal chosen(slot:int)
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
const GBK=preload("res://scripts/m2/GBK.gd")
var font:Font
var palette:Array
var previews:Array=[]
var load_mode:=true
var choice:=-1
var done:=false
var background:Texture2D
var highlight:Control
class SelectedRow extends Control:
	var entries:Array=[]
	var font:Font
	var ink:Color
	func _draw() -> void:
		for entry in entries:draw_string(font,Vector2(entry.x,font.get_ascent(16)),str(entry.text),HORIZONTAL_ALIGNMENT_LEFT,-1,16,ink)
func setup(f:Font,colors:Array,slots:Array,loading:=true) -> void:
	font=f;palette=colors;previews=slots;load_mode=loading
	OriginalUI.native_text_index=0x48
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	background=Palette.texture(FileAccess.get_file_as_bytes("res://assets/ui/menu09_indices.bin"),456,227,palette)
	highlight=SelectedRow.new();highlight.font=font;highlight.ink=Palette.color_at(palette,0xB7)
	highlight.clip_contents=true;highlight.size=Vector2(400,18);highlight.mouse_filter=Control.MOUSE_FILTER_IGNORE;highlight.visible=false;add_child(highlight)
	queue_redraw()
	OriginalUI.touch_back(self,font,_finish.bind(-1),"取消")
func entries(row:int) -> Array:
	var result:Array=[{"x":36,"text":"进度"},{"x":68,"text":["一","二","三","四","五"][row]}]
	var info:Dictionary=previews[row]
	if info.is_empty():return result
	result.append({"x":100,"text":"任务"})
	result.append({"x":286,"text":"第  回合" if int(info.get("mode",57))==150 else "休息关"})
	result.append({"x":132,"text":"%2d"%(int(info.get("level",0))+1)})
	result.append({"x":368,"text":["简单","普通","困难"][posmod(int(info.get("difficulty",1)),3)]})
	if int(info.get("mode",57))==150:result.append({"x":302,"text":"%2d"%int(info.get("turn",1))})
	result.append({"x":180,"text":str(info.get("intro",""))})
	return result
func _draw() -> void:
	if background==null:return
	draw_texture(background,Vector2(92,126))
	for row in range(5):
		for entry in entries(row):draw_string(font,Vector2(92+int(entry.x),158+36*row+font.get_ascent(16)),str(entry.text),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Palette.color_at(palette,0x48))
func _select(row:int) -> void:
	choice=row;highlight.position=Vector2(92,158+36*row);highlight.entries=entries(row);highlight.visible=true;highlight.queue_redraw()
func _finish(slot:int) -> void:
	if done:return
	done=true;chosen.emit(slot)
func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if OriginalUI.touch_mode(self) and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_finish(-1);return
	if event is InputEventMouseMotion:
		if Rect2(0,158,640,180).has_point(event.position):
			var row:int=int((event.position.y-158)/36)
			if choice!=row:_select(row)
	elif event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed:_finish(-1)
		elif event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			if OriginalUI.touch_mode(self):
				if not Rect2(92,158,456,180).has_point(event.position):return
				_select(int((event.position.y-158)/36))
			_finish(-1 if choice<0 or (load_mode and previews[choice].is_empty()) else choice)
