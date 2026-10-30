extends Control
# 43A903 / 43B0B5 / 43B373 / 43B4F1 / 43B680. Right slots are NOT
# compact PIDs: a hole is a real unused Intro.special slot until reused.
signal confirmed(slots:Array)
signal selection_changed
const EMPTY=-999
var font:Font
var state
var level_index:=0
var limit:=0
var left:Array=[]
var right:Array=[]
var pages:=[0,0]
var drag:Dictionary={}
var drag_point:=Vector2.ZERO
var button_pressed:=false
var done:=false
var info:CanvasLayer
var background:Texture2D
var buttons:Array=[]
var icons:Dictionary={}
const NORMAL=Color("#a4fcfc")
const FORCED=Color("#fc0000")
const GO=Rect2(524,390,50,25)

func setup(f:Font,game_state,index:int) -> void:
	font=f;state=game_state;level_index=index
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	background=load("res://assets/ui/strategy_k00.png")
	buttons=[load("res://assets/ui/strategy_button0.png"),load("res://assets/ui/strategy_button1.png")]
	var dep:Dictionary=state.m4_level(index).get("deployment",{})
	limit=int(dep.get("max_units",0))
	var forced:Array=dep.get("forced_slots",[])
	for m in state.deployment_roster(index):
		var pid:=int(m.pid);var slot:=0 if pid==state.PROTAGONIST_PID else pid
		if not forced.has(slot):left.append({"active":true,"pid":pid})
	while left.size()<32:left.append({"active":false,"pid":EMPTY})
	for slot in forced:right.append({"status":2,"value":state.PROTAGONIST_PID if int(slot)==0 else int(slot)})
	while right.size()<32:right.append({"status":0,"value":EMPTY})
	OriginalUI.touch_back(self,font,_touch_submit,"确定")
	OriginalUI.native_text_index=0x48
	queue_redraw()

func member(side:int,index:int) -> Dictionary:
	if index<0 or index>=32:return {}
	var pid:=EMPTY
	if side==0:
		if not bool(left[index].active):return {}
		pid=int(left[index].pid)
	else:
		var entry:Dictionary=right[index]
		if int(entry.status)==0:return {}
		pid=int(entry.value) if int(entry.status)==2 else int(left[int(entry.value)].pid)
	var person=state.person(pid)
	return person if person!=null else {}

func selected_slots() -> Array:
	var slots:Array=[]
	for i in range(32):
		var m:=member(1,i)
		slots.append(int(m.pid) if not m.is_empty() else EMPTY)
	return slots

func count() -> int:
	var total:=0
	for r in right:
		if int(r.status)!=0:total+=1
	return total

func _icon(m:Dictionary) -> Texture2D:
	var cls:Dictionary=state.data.get("units",{}).get(str(m.get("bingzhong",0)),{})
	var index:=int(cls.get("img_index",0))
	if not icons.has(index):icons[index]=load("res://assets/ui/strategy_army_%03d.png"%index)
	return icons[index]

func _text(value:String,point:Vector2,color:=NORMAL) -> void:
	draw_string(font,point+Vector2(0,font.get_ascent(16)),value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)

func _draw() -> void:
	if background==null:return
	draw_texture(background,Vector2.ZERO)
	for side in range(2):
		for i in range(16):
			var slot:int=pages[side]*16+i
			var m:=member(side,slot)
			if m.is_empty():continue
			var p:=Vector2((32 if side==0 else 360)+72*(i%4),74+64*(i/4))
			var color:=FORCED if side==1 and int(right[slot].status)==2 else NORMAL
			draw_texture(_icon(m),p)
			_text("LV  "+str(m.get("level",1)),p+Vector2(0,32),color)
			_text(str(m.get("name","")),p+Vector2(0,48),color)
		_text("下一页" if pages[side]==0 else "上一页",Vector2(246 if side==0 else 396,361))
	draw_texture(buttons[1 if button_pressed else 0],GO.position)
	_text("确定",Vector2(530,394))
	_text(str(count()),Vector2(460,440));_text("/",Vector2(476,440));_text(str(limit),Vector2(492,440))
	if not drag.is_empty():
		var m:=member(int(drag.side),int(drag.slot))
		_summary(m)
		draw_texture(_icon(m),drag_point)

func _summary(m:Dictionary) -> void:
	var cls:Dictionary=state.data.get("units",{}).get(str(m.get("bingzhong",0)),{})
	for pair in [["姓  名：",str(m.get("name","")),79,143,394],["兵  种：",str(cls.get("name","")),207,271,394],["等  级：",str(m.get("level",1)),335,399,394],["武  力：",str(m.get("wuli",0)),79,143,414],["智  力：",str(m.get("zhili",0)),207,271,414],["物品数：",str(_inventory_count(m.get("item_slots",[]))),79,143,434],["地雷数：",str(_inventory_count(m.get("mine_slots",[]))),207,271,434]]:
		_text(str(pair[0]),Vector2(pair[2],pair[4]));_text(str(pair[1]),Vector2(pair[3],pair[4]))

func _inventory_count(slots:Array) -> int:
	var n:=0
	for value in slots:
		if int(value)>0:n+=1
	return n

func hit_member(point:Vector2,side:int) -> int:
	for i in range(16):
		var p:=Vector2((32 if side==0 else 360)+72*(i%4),74+64*(i/4))
		var slot:int=pages[side]*16+i
		if Rect2(p,Vector2(48,64)).has_point(point) and not member(side,slot).is_empty():return slot
	return -1

func transfer(side:int,slot:int) -> bool:
	if member(side,slot).is_empty():return false
	if side==0:
		if count()>=limit:return false
		for i in range(32):
			if int(right[i].status)==0:
				right[i]={"status":1,"value":slot};left[slot].active=false;pages[1]=i/16
				selection_changed.emit();queue_redraw();return true
	elif int(right[slot].status)==1:
		left[int(right[slot].value)].active=true;right[slot].status=0
		selection_changed.emit();queue_redraw();return true
	return false

func set_page(side:int) -> void:
	pages[side]=1-int(pages[side]);queue_redraw();selection_changed.emit()

func submit() -> void:
	if count()==0:return
	done=true;confirmed.emit(selected_slots())

func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree() or is_instance_valid(info):return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and not drag.is_empty():
		drag_point=(event.position-Vector2(24,24)).clamp(Vector2.ZERO,Vector2(591,431));queue_redraw()
	if OriginalUI.touch_mode(self):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
			drag.clear();queue_redraw();return # Deployment cannot be abandoned without the campaign.
		if event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:_touch_info(event.position);return
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT:return
	if event.pressed:
		for side in range(2):
			var slot:=hit_member(event.position,side)
			if slot<0 or (side==1 and int(right[slot].status)==2) or (side==0 and count()>=limit):continue
			if event.double_click or OriginalUI.touch_mode(self):
				drag.clear();transfer(side,slot)
			else:
				drag={"side":side,"slot":slot};drag_point=(event.position-Vector2(24,24)).clamp(Vector2.ZERO,Vector2(591,431))
			queue_redraw();return
		if GO.has_point(event.position):button_pressed=true;queue_redraw()
	else:
		if not drag.is_empty():
			var target:=Rect2(356,72,264,276) if int(drag.side)==0 else Rect2(20,72,316,276)
			if target.has_point(event.position):transfer(int(drag.side),int(drag.slot))
			drag.clear();queue_redraw();return
		if button_pressed:
			button_pressed=false;queue_redraw()
			if GO.has_point(event.position):submit()
			return
		for side in range(2):
			if Rect2(245 if side==0 else 394,355,50,25).has_point(event.position):set_page(side)

func _touch_submit() -> void:
	if not is_instance_valid(info):submit()

func _touch_info(point:Vector2) -> void:
	for side in range(2):
		var slot:=hit_member(point,side)
		if slot<0:continue
		info=preload("res://scripts/ui/OriginalInfo.gd").new();add_child(info)
		info.closed.connect(func():info=null)
		info.setup(font,state.data,"person",int(member(side,slot).pid),member(side,slot));return
