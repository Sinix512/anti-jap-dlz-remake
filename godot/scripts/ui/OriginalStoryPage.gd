extends Control
# 43CFE1 / 43D82F: 1..99 vertical scroll;425A08 release wait;200ms tail.
# Windows GetMessage scheduling is not emulated. Native6ms steps, max8 per
# pump, are advanced by Godot frames; inputs during the roll never cross WAIT.
signal scroll_started
signal confirmed
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
var font:Font
var palette:Array=[]
var stage:="scroll"
var height:=1
var shown_height:=0
var elapsed:=0.0
var wait_frame:=-1
var tail:=0.0
var frame:TextureRect
var portrait:TextureRect
var clip:Control
var raster:Control
var done:=false
var record_end:=true
var battle_profile:=false

func setup(f:Font,glyphs:Array,face:=-1,palette_key:="KUANG04",width:=36) -> void:
	font=f;palette=Palette.colors(palette_key)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	frame=TextureRect.new();frame.texture=Palette.asset("frame00",404,127,palette,0)
	frame.position=Vector2(118,296);frame.size=Vector2(404,127);frame.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(frame)
	portrait=TextureRect.new();portrait.position=Vector2(130,308);portrait.size=Vector2(80,100);portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	portrait.visible=face>=0
	if face>=0:
		var faces:=FileAccess.get_file_as_bytes("res://assets/ui/face_indices.bin")
		if (face+1)*8000<=faces.size():portrait.texture=Palette.texture(faces.slice(face*8000,(face+1)*8000),80,100,palette)
	add_child(portrait)
	clip=Control.new();clip.position=Vector2(222 if face>=0 else 142,312);clip.size=Vector2(width*8,99);clip.clip_contents=true;clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(clip)
	raster=preload("res://scripts/ui/OriginalTextRaster.gd").new();raster.font=f;raster.palette=palette;raster.glyphs=glyphs;raster.position=Vector2(0,99);raster.mouse_filter=Control.MOUSE_FILTER_IGNORE;clip.add_child(raster)

func _process(delta:float) -> void:_advance(delta)

func _advance(delta:float) -> void:
	if stage=="tail":
		tail+=delta
		if not record_end or tail+0.0000001>=0.2:_close()
		return
	if stage!="scroll":return
	elapsed+=delta
	var count:=mini(8,int(floor((elapsed+0.0000001)/0.006)))
	for i in range(count):
		elapsed=maxf(0,elapsed-0.006);_scroll_step()
		if stage!="scroll":break

func _scroll_step() -> void:
	if stage!="scroll":return
	if shown_height==0:scroll_started.emit()
	shown_height=height;raster.position.y=99-height
	height+=1
	if height>99:
		stage="wait";wait_frame=Engine.get_process_frames()+1;OriginalUI.native_text_index=0x48

func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if stage=="scroll":
		if event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:height=99
		return
	if stage!="wait" or Engine.get_process_frames()<wait_frame:return
	if event is InputEventKey and not event.pressed:_accept()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:_accept()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if OriginalUI.native_wait_left_blocked:OriginalUI.native_wait_left_blocked=false
			else:_accept()

func _accept() -> void:
	stage="tail";tail=0.0
	if record_end and battle_profile:hide()

func _close() -> void:
	if done:return
	done=true;stage="done";confirmed.emit()
