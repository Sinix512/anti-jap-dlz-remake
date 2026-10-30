extends Control
# Source-bound title destinations: 42CFEA, 42D217/42D274, 430253/4303B8,
# and 430084/4300E1. No modern close/skip buttons or automatic ZYB timeout.
signal closed
signal exit_confirmed
signal load_ready
const Scores=preload("res://scripts/ui/OriginalHighScores.gd")
var font:Font
var mode:=""
var rows:Array=[]
var background:Texture2D
var credits:Texture2D
var counter:=0
var elapsed:=0.0
var entry_hold:=0.0
var waiting:=false
var done:=false
var confirm:Control
var palettes:Dictionary
var foreground_index:=0x7F
func setup(f:Font,page:String,table:Array=[]) -> void:
	font=f;mode=page
	entry_hold=0.5 if page=="supporters" else 0.0
	foreground_index=OriginalUI.native_text_index
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	palettes=JSON.parse_string(FileAccess.get_file_as_string("res://data/title_pages.json"))
	background=load("res://assets/ui/title_transition.png")
	if page=="scores":rows=Scores.read_table() if table.is_empty() else table
	elif page=="supporters":credits=load("res://assets/ui/title_supporters.png")
	if mode in ["scores","supporters"]:OriginalUI.touch_back(self,font,_touch_close)
	queue_redraw()
func color_at(index:int,battle:=false) -> Color:
	var rgb:Array=palettes["battle_palette" if battle else "bg01_palette"][index]
	return Color8(int(rgb[0]),int(rgb[1]),int(rgb[2]))
func text_at(value:String,point:Vector2) -> void:
	draw_string(font,point+Vector2(0,font.get_ascent(16)),value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color_at(foreground_index))
func _draw() -> void:
	match mode:
		"scores":
			draw_texture(background,Vector2.ZERO)
			text_at("排行榜",Vector2(320,20))
			for i in range(10):
				text_at(str(i+1),Vector2(20,60+40*i));text_at(str(rows[i].name),Vector2(80,60+40*i));text_at(str(rows[i].score),Vector2(500,60+40*i))
		"supporters":draw_texture_rect_region(credits,Rect2(0,0,640,480),Rect2(0,mini(counter,3541)*2,640,480))
		"exit":draw_rect(Rect2(0,0,640,480),color_at(0xFF,true))
		"load":draw_texture(background,Vector2.ZERO)
func tick() -> void:
	if done:return
	if mode=="supporters":
		if counter<=3540:counter+=1;queue_redraw()
	elif mode in ["exit","load"] and not waiting:
		counter+=1
		if counter>10:
			waiting=true
			if mode=="load":load_ready.emit()
			else:
				confirm=preload("res://scripts/ui/OriginalConfirm.gd").new();add_child(confirm)
				confirm.setup(font,"退出吗?",Vector2(320,200),color_at(foreground_index,true))
				confirm.answered.connect(func(yes:bool):
					done=true
					if yes:exit_confirmed.emit()
					else:closed.emit())
func _process(delta:float) -> void:
	if done or not is_visible_in_tree():return
	if entry_hold>0.0:
		var held:=minf(entry_hold,delta)
		entry_hold-=held;delta-=held
		if delta<=0.0:return
	elapsed+=delta
	while elapsed>=0.055:elapsed-=0.055;tick()
func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree() or is_instance_valid(confirm):return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if mode in ["scores","supporters"]:
		if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed):
			done=true;closed.emit()

func _touch_close() -> void:
	if done:return
	done=true;closed.emit()
