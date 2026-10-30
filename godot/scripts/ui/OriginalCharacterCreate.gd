extends Control
# 42D686 / 42E2D6 / 42F938 / 42FACA. See the source-bound contract in extract/.
# Cold title-entry foreground is 7F (405560/446460); other historical entry
# color inheritance and OS presentation remain outside the evidence scope.
signal confirmed(values:Dictionary)
signal cancelled
const CLASSES=[1,4,8,11]
const ARMY=[30,40,32,54]
const BUTTONS=[Rect2(138,425,88,32),Rect2(275,426,88,32),Rect2(412,427,88,32)]
const BUTTON_TEXT=["更  改","确  定","取  消"]
const LETTERS="ＡＢＣＤＥＦＧＨＪＫＬＭＮＯＰＱＲＳＴＷＸＹＺ"
var font:Font
var data:Dictionary
var classes:Dictionary
var face_index:=0
var unit_index:=0
var wuli:=80
var difficulty:=1
var player_name:="主　角"
var pressed_button:=-1
var name_mode:=false
var name_buffer:=""
var section:=0
var name_ticks:=0
var tick_elapsed:=0.0
var flash_index:=-1
var flash_remaining:=0.0
var done:=false
var erased_units:Dictionary={}
var background:Texture2D
var faces:Array[Texture2D]=[]
var armies:Array[Texture2D]=[]
var normal:Texture2D
var pressed:Texture2D
var slider:Texture2D
func setup(f:Font,unit_data:Dictionary) -> void:
	font=f;classes=unit_data
	data=JSON.parse_string(FileAccess.get_file_as_string("res://data/character_creation.json"))
	background=load("res://assets/ui/menu01.png")
	for i in range(6):faces.append(load("res://assets/ui/creation_face_%d.png"%(103+i)))
	for id in ARMY:armies.append(load("res://assets/ui/creation_army_%d.png"%id))
	normal=load("res://assets/ui/creation_button_normal.png")
	pressed=load("res://assets/ui/creation_button_pressed.png")
	slider=load("res://assets/ui/creation_slider.png")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	OriginalUI.touch_back(self,font,_touch_back)
	queue_redraw()
func color_at(index:int,naming:=false) -> Color:
	var rgb:Array=data["name_palette" if naming else "palette"][index]
	return Color8(int(rgb[0]),int(rgb[1]),int(rgb[2]))
func text_at(value:String,point:Vector2,naming:=false) -> void:
	draw_string(font,point+Vector2(0,font.get_ascent(16)),value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color_at(0x7F,naming))
func outline(rect:Rect2,index:int) -> void:
	# Rect dimensions describe inclusive native endpoints. Draw 1px fills at
	# integer pixel edges, avoiding the half-pixel stroke antialias convention.
	var c:=color_at(index)
	draw_rect(Rect2(rect.position,Vector2(rect.size.x,1)),c)
	draw_rect(Rect2(rect.position+Vector2(0,rect.size.y-1),Vector2(rect.size.x,1)),c)
	draw_rect(Rect2(rect.position,Vector2(1,rect.size.y)),c)
	draw_rect(Rect2(rect.position+Vector2(rect.size.x-1,0),Vector2(1,rect.size.y)),c)
func slider_position() -> Vector2:
	return Vector2(261+(wuli-60)*100/40,283)
func values() -> Dictionary:
	return {"name":player_name,"face":103+face_index,"unit":CLASSES[unit_index],"wuli":wuli,"difficulty":difficulty}
func _draw() -> void:
	if font==null:return
	if name_mode:_draw_name();return
	draw_texture(background,Vector2.ZERO)
	for i in range(6):draw_texture(faces[i],Vector2(40+96*i,86))
	outline(Rect2(40+96*face_index,86,80,100),0xB7)
	for i in range(4):
		draw_texture(armies[i],Vector2(163+88*i,203))
		if erased_units.has(i):outline(Rect2(163+88*i,203,48,48),0)
		text_at(str(classes[str(CLASSES[i])].name),Vector2(163+88*i,255))
	outline(Rect2(163+88*unit_index,203,48,48),0xB7)
	var left:int=(wuli-60)*128/40
	draw_rect(Rect2(255,287,left,16),color_at(0xED))
	draw_rect(Rect2(255+left,287,128-left,16),color_at(0xB7))
	draw_texture(slider,slider_position())
	text_at(str(160-wuli),Vector2(217,287));text_at(str(wuli),Vector2(392,287))
	text_at(player_name,Vector2(108,374))
	draw_rect(Rect2(249,371,344,22),color_at(0xF0))
	if difficulty>0:draw_rect(Rect2(249,371,172*difficulty,22),color_at(0xB7))
	text_at(["容  易","普  通","困  难"][difficulty],Vector2(499,331))
	for i in range(3):
		draw_texture(pressed if pressed_button==i else normal,BUTTONS[i].position)
		text_at(BUTTON_TEXT[i],BUTTONS[i].position+Vector2(20,8))
func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if OriginalUI.touch_mode(self) and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_touch_back();return
	if name_mode:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and flash_index<0:_name_release(event.position)
		return
	if event is InputEventMouseMotion:
		if event.button_mask&MOUSE_BUTTON_MASK_LEFT and pressed_button<0 and Rect2(255,287,128,16).has_point(event.position):_attribute_at(event.position.x)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			for i in range(3):
				if BUTTONS[i].has_point(event.position):pressed_button=i;queue_redraw();return
			if Rect2(249,371,344,22).has_point(event.position):difficulty=int((event.position.x-249)*3/344);queue_redraw()
		else:_creation_release(event.position)
func _attribute_at(x:float) -> void:
	# Native signed integer division truncates towards zero, not floor.
	wuli=clampi(60+int((int(x)-269)*40/100),60,100);queue_redraw()
func _creation_release(point:Vector2) -> void:
	if pressed_button>=0:
		var old:=pressed_button;pressed_button=-1;queue_redraw()
		if not BUTTONS[old].has_point(point):return
		OriginalUI.play_native_sfx(7 if old==2 else 6)
		if old==0:open_name()
		elif old==1:done=true;confirmed.emit(values())
		else:done=true;cancelled.emit()
		return
	for i in range(6):
		if Rect2(40+96*i,86,80,100).has_point(point):face_index=i;queue_redraw();return
	for i in range(4):
		if Rect2(163+88*i,203,48,48).has_point(point):
			erased_units[unit_index]=true;unit_index=i;queue_redraw();return
	if Rect2(255,287,128,16).has_point(point):_attribute_at(point.x)
func open_name() -> void:
	name_mode=true;name_buffer="";section=0;name_ticks=0;tick_elapsed=0;flash_index=-1
	queue_redraw()
func _draw_name() -> void:
	draw_rect(Rect2(0,0,640,480),color_at(0xFF,true))
	for y in [42,66]:draw_rect(Rect2(0,y,640,1),color_at(0x7F,true))
	for i in range(5):text_at(["确  定","返  回","上一页","下一页","退  格"][i],Vector2(160+80*i,16),true)
	text_at(name_buffer,Vector2(0,16),true)
	if name_buffer.length()<4 and (name_ticks/13)%2==0:draw_rect(Rect2(name_buffer.length()*16,33,17,1),color_at(0x7F,true))
	for i in range(23):text_at(LETTERS[i],Vector2(i*27,48),true)
	var chars:String=data.name_groups[section]
	for i in range(chars.length()):
		var point:=Vector2((i%20)*32,(i/20)*24+72)
		if flash_index==i:draw_rect(Rect2(point,Vector2(16,16)),color_at(0x7F,true))
		text_at(chars[i],point,true)
func _name_release(point:Vector2) -> void:
	for i in range(5):
		if not Rect2(160+80*i,16,64,16).has_point(point):continue
		match i:
			0:
				if not name_buffer.is_empty():player_name=name_buffer
				name_mode=false;pressed_button=-1
			1:name_mode=false;pressed_button=-1
			2:section=maxi(0,section-1)
			3:section=mini(22,section+1)
			4:name_buffer=name_buffer.left(maxi(0,name_buffer.length()-1))
		queue_redraw();return
	if Rect2(0,48,621,24).has_point(point):section=int(point.x)/27;queue_redraw();return
	if not Rect2(0,72,640,408).has_point(point) or name_buffer.length()>=4:return
	var index:int=int((point.y-72)/24)*20+int(point.x/32)
	if index>=str(data.name_groups[section]).length():return
	flash_index=index;flash_remaining=0.1;queue_redraw()
func _process(delta:float) -> void:
	_advance(delta)
func _advance(delta:float) -> void:
	if not name_mode:return
	tick_elapsed+=delta
	while tick_elapsed>=0.055:tick_elapsed-=0.055;name_ticks+=1;queue_redraw()
	if flash_index<0:return
	flash_remaining-=delta
	if flash_remaining<=0:
		name_buffer+=str(data.name_groups[section])[flash_index];flash_index=-1;queue_redraw()

func _touch_back() -> void:
	if done:return
	if name_mode:name_mode=false;pressed_button=-1;queue_redraw()
	else:done=true;cancelled.emit()
