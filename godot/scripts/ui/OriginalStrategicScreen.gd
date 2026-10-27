extends Control
# 4310B9 / 431273 / 4304E0 / 4308F2 / 430C9F / 430DD9.
# No modern buttons: world uses LEFT-UP, PLACE uses LEFT-DOWN.
signal town_enter(index:int)
signal building_enter(slot:int)
signal room_exit
signal system_requested(point:Vector2)
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
var font:Font
var mode:=""
var state
var town_index:=0
var contract:Dictionary
var palette:Array=[]
var background:Texture2D
var mine:Array=[]
var mine_hover:=false
var clock:="00:00:00"
var ticks:=0
var elapsed:=0.0
var enabled:=true
var input_blocked:Callable

func setup(f:Font,kind:String,game_state,index:=0,scene_palette:="BIGMAP") -> void:
	font=f;mode=kind;state=game_state;town_index=index
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	contract=JSON.parse_string(FileAccess.get_file_as_string("res://data/strategic_ui.json"))
	match mode:
		"world":
			OriginalUI.native_text_index=0x48
			palette=Palette.colors("BIGMAP");background=load("res://assets/ui/strategy_bigmap.png")
			mine=[load("res://assets/ui/strategy_mine0.png"),load("res://assets/ui/strategy_mine1.png")]
			_refresh_clock()
		"town":
			OriginalUI.native_text_index=0x48
			palette=Palette.colors("PLACE%02d"%index);background=load("res://assets/ui/strategy_place%02d.png"%index)
		"resident":
			palette=Palette.colors(scene_palette);background=Palette.asset("bg02",640,480,palette)
		"command":
			palette=Palette.colors("BACK19");background=load("res://assets/ui/strategy_back19.png")
	queue_redraw()

func _text(value:String,point:Vector2,color:Color) -> void:
	draw_string(font,point+Vector2(0,font.get_ascent(16)),value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)

func _draw() -> void:
	if background==null:return
	draw_texture(background,Vector2.ZERO)
	if mode=="world":
		for town in contract.world.towns:
			var r:Array=town.rect
			_text(str(town.name),Vector2(r[0],r[1]),Palette.color_at(palette,0xB7 if state.town_unlocked(int(town.index)) else 0x89))
		draw_texture(mine[1 if mine_hover else 0],Vector2(549,20))
		_text(clock,Vector2(400,20),Palette.color_at(palette,OriginalUI.native_text_index))
	elif mode=="town":
		var town:Dictionary=contract.towns[town_index]
		var rgb:Array=town.label_rgb
		for building in town.buildings:
			if bool(building.enabled):_text(str(building.get("label",building.name)),Vector2(building.text_at[0],building.text_at[1]),Color8(int(rgb[0]),int(rgb[1]),int(rgb[2])))
	elif mode=="resident":_text("出  去",Vector2(548,48),Palette.color_at(palette,OriginalUI.native_text_index))

func _refresh_clock() -> void:
	var seconds:int=state.play_seconds
	clock="%02d:%02d:%02d"%[seconds/3600,(seconds/60)%60,seconds%60]
	queue_redraw()

func _process(delta:float) -> void:
	if mode!="world" or not is_visible_in_tree():return
	elapsed+=delta
	while elapsed>=0.055:
		elapsed-=0.055;ticks+=1
		if ticks%18==0:_refresh_clock()

func town_at(point:Vector2) -> int:
	for town in contract.world.towns:
		var r:Array=town.rect
		if Rect2(r[0],r[1],r[2],r[3]).has_point(point):return int(town.index)
	return -1

func building_at(point:Vector2) -> int:
	var buildings:Array=contract.towns[town_index].buildings
	for slot in [0,2,5,3,4,1]:
		var b:Dictionary=buildings[slot];var r:Array=b.rect
		if bool(b.enabled) and Rect2(r[0],r[1],r[2],r[3]).has_point(point):return slot
	return -1

func _input(event:InputEvent) -> void:
	if not enabled or not is_visible_in_tree():return
	if input_blocked.is_valid() and input_blocked.call():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and mode=="world":
		var hover:=Rect2(549,20,70,81).has_point(event.position)
		if hover!=mine_hover:mine_hover=hover;queue_redraw()
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT:return
	match mode:
		"world":
			if event.pressed:
				if Rect2(549,20,70,81).has_point(event.position):system_requested.emit(event.position)
			else:
				var index:=town_at(event.position)
				if index>=0 and state.town_unlocked(index):town_enter.emit(index)
		"town":
			if event.pressed:
				var slot:=building_at(event.position)
				if slot>=0:building_enter.emit(slot)
		"resident":
			if not event.pressed and Rect2(540,40,64,32).has_point(event.position):room_exit.emit()
		"command":
			if not event.pressed and Rect2(459,0,180,100).has_point(event.position):room_exit.emit()
