extends Control
signal answered(yes:bool)
const UI=preload("res://scripts/ui/OriginalUI.gd")
var origin:Vector2
var choice:=0
var options:Array[Label]=[]
var selected_row:TextureRect
var done:=false
var row_height:=24
var palette:Array=[]
var selected_textures:Array=[]
var normal_color:=Color("#a4fcfc")
func setup(font:Font,title:String,at:=Vector2(320,200),ink:=Color("#a4fcfc"),colors:Array=[]) -> void:
	palette=colors
	normal_color=ink
	row_height=40 if UI.touch_mode(self) else 24
	origin=at;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	var panel:=UI.panel("res://assets/ui/retry_original.png",Rect2(at,Vector2(128,32+row_height*2+8)))
	if not palette.is_empty():
		var p=preload("res://scripts/ui/OriginalPalette.gd")
		var raw:=FileAccess.get_file_as_bytes("res://assets/ui/menu03_indices.bin")
		panel.texture=p.texture(raw,128,88,palette)
		for row in range(2):selected_textures.append(p.selected(raw,128,Rect2i(4,32+row*24,120,24),palette))
	add_child(panel)
	selected_row=TextureRect.new();selected_row.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(selected_row)
	var byte_count:=0
	for character in title:byte_count+=1 if character.unicode_at(0)<128 else 2
	add_child(_label(font,title,at+Vector2((128-mini(byte_count,14)*8)/2,4),Vector2(112,16)))
	for row in range(2):
		var label:=_label(font,"是" if row==0 else "否",at+Vector2(56,32+(row_height-16)/2+row_height*row),Vector2(16,16))
		options.append(label);add_child(label)
	_select(0)
	UI.touch_back(self,font,_touch_cancel,"取消")
	UI.native_text_index=0x48
	if DisplayServer.get_name()!="headless":get_viewport().warp_mouse(at+Vector2(64,44))
func _label(font:Font,value:String,at:Vector2,bounds:Vector2) -> Label:
	var label:=UI.label(value,font,16,normal_color);label.position=at;label.size=bounds
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
	return label
func _select(row:int) -> void:
	choice=row;selected_row.texture=load("res://assets/ui/retry_selected_%d.png"%row) if palette.is_empty() else selected_textures[row];selected_row.position=origin+Vector2(4,32+row_height*row)
	if row_height==40:selected_row.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;selected_row.size=Vector2(120,40)
	for index in range(options.size()):options[index].add_theme_color_override("font_color",Color("#fc8c00") if index==row else normal_color)
func _input(event:InputEvent) -> void:
	if done:return
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey:get_viewport().set_input_as_handled()
	if UI.touch_mode(self) and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_touch_cancel();return
	if event is InputEventMouseMotion:
		var top:float=origin.y+32
		if event.position.x>=0 and event.position.x<640 and event.position.y>=top and event.position.y<top+row_height*2:
			_select(int((event.position.y-top)/row_height))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:done=true;answered.emit(false)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if UI.touch_mode(self):
				if not Rect2(origin+Vector2(4,32),Vector2(120,row_height*2)).has_point(event.position):return
				_select(int((event.position.y-origin.y-32)/row_height))
			done=true;answered.emit(choice==0)

func _touch_cancel() -> void:
	if done:return
	done=true;answered.emit(false)
