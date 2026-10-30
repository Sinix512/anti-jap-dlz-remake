extends Control
# 42B49A / 427873: MENU10 + serial counters, then inherited425A08 UP wait.
signal closed
signal counter_step(index:int,value:int)
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
const Y=[152,184,216,248,280,312,403]
const GRADES=["  较  差","  合  格","  良  好","  优  秀","  完  美"]
var font:Font
var palette:Array=[]
var background:Texture2D
var values:Array=[]
var displayed:Array=[]
var grade:=""
var grade_visible:=false
var stage:="background"
var counter:=-1
var current:=0
var remaining:=1.0
var wait_frame:=-1
var done:=false
var _touch_pressed:=false

func setup(f:Font,stats:Dictionary,score:int,total:int,palette_key:="KUANG04") -> void:
	font=f;palette=Palette.colors(palette_key)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	background=Palette.asset("menu10",640,480,palette)
	var mine:=int(stats.get("kills_by_mine",0));var gun:=int(stats.get("kills_by_gun",0))
	values=[mine,gun,mine+gun,int(stats.get("losses",0)),int(stats.get("captured_items",0)),score,total]
	displayed.resize(7);displayed.fill(-1)
	grade=GRADES[0 if score<60 else 1 if score<80 else 2 if score<90 else 3 if score<=100 else 4]
	OriginalUI.touch_back(self,font,_touch_advance,"继续")
	queue_redraw()

func _text(value:String,at:Vector2) -> void:
	draw_string(font,at+Vector2(0,font.get_ascent(16)),value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Palette.color_at(palette,OriginalUI.native_text_index))

func _draw() -> void:
	if background==null:return
	draw_texture(background,Vector2.ZERO)
	for i in range(displayed.size()):
		if int(displayed[i])>=0:_text("%4d"%int(displayed[i]),Vector2(499,Y[i]))
	if grade_visible:_text(grade,Vector2(483,344))

func _process(delta:float) -> void:_advance(delta)

func _interval(value:int) -> float:
	return float(mini(40,3000/maxi(1,value)))/1000.0

func _next_counter() -> void:
	counter+=1
	if counter==6:grade_visible=true
	if counter>=7:
		stage="wait";wait_frame=Engine.get_process_frames()+1;queue_redraw();return
	stage="counter";current=0 if int(values[counter])<=0 else 1
	displayed[counter]=current;counter_step.emit(counter,current)
	remaining=_interval(int(values[counter])) if current>0 else 0.0
	queue_redraw()

func _advance(delta:float) -> void:
	if stage in ["wait","done"]:return
	var budget:=delta
	# Large native counters may have0ms interval. They complete in this call,
	# without synthesizing frame delays or allowing an input skip.
	while stage in ["background","counter"]:
		if budget+0.0000001<remaining:remaining-=budget;return
		budget=maxf(0,budget-remaining)
		if stage=="background":_next_counter()
		elif current>=int(values[counter]):_next_counter()
		else:
			current+=1;displayed[counter]=current;counter_step.emit(counter,current)
			remaining=_interval(int(values[counter]));queue_redraw()

func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if OriginalUI.touch_mode(self):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_touch_advance();return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_touch_pressed=true;return
			if _touch_pressed:_touch_pressed=false;OriginalUI.native_wait_left_blocked=false;_touch_advance();return
			return # A release without its fresh DOWN belongs to the opening gesture.
	if stage!="wait" or Engine.get_process_frames()<wait_frame:return
	if event is InputEventKey and not event.pressed:_close()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:_close()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if OriginalUI.native_wait_left_blocked:OriginalUI.native_wait_left_blocked=false
			else:_close()

func _close() -> void:
	if done:return
	done=true;stage="done";closed.emit()

func _touch_advance() -> void:
	if not done and stage=="wait" and Engine.get_process_frames()>=wait_frame:_close()
