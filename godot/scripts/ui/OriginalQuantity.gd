extends Control
# 428B8F. Only local 160x100 background, fixed startup LUT, no GUI slider.
signal chosen(quantity:int)
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
var font:Font
var palette:Array=[]
var background:Texture2D
var quantity:=0
var maximum:=0
var unit:=""
var material_name:=""
var done:=false
func setup(f:Font,colors:Array,raw:PackedByteArray,limit:int,label:String,measure:String) -> void:
	font=f;palette=colors;maximum=maxi(0,limit);material_name=label;unit=measure
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var lut:=FileAccess.get_file_as_bytes("res://assets/ui/service_quantity_lut.bin")
	var mapped:=PackedByteArray();mapped.resize(raw.size())
	for i in range(raw.size()):mapped[i]=lut[raw[i]]
	background=Palette.texture(mapped,160,100,palette)
	queue_redraw()
func _text(value:String,x:int,y:int) -> void:
	draw_string(font,Vector2(x,y+font.get_ascent(16)),value.replace("\\u3000","　"),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Palette.color_at(palette,0x48))
func _draw() -> void:
	if background==null:return
	draw_texture(background,Vector2(240,160))
	_text("买多少",264,168);_text(unit,312,168);_text(material_name,328,168)
	_text("当前",272,216);_text(str(quantity),320,216);_text(unit,352,216)
	_text("最大",272,236);_text(str(maximum),320,236);_text(unit,352,236)
	var ink:=Palette.color_at(palette,0x8B)
	draw_rect(Rect2(255,191,130,1),ink);draw_rect(Rect2(255,191,1,14),ink)
	draw_rect(Rect2(384,191,1,14),ink);draw_rect(Rect2(255,204,130,1),ink)
	var width_:int=quantity*128/maximum if maximum>0 else 0
	if width_>0:draw_rect(Rect2(256,192,width_,12),Palette.color_at(palette,0xAB))
func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		quantity=0 if event.position.x<256 else (maximum if event.position.x>=383 else int((event.position.x-256)*maximum/128))
		queue_redraw()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT:done=true;chosen.emit(quantity)
		elif event.button_index==MOUSE_BUTTON_RIGHT:done=true;chosen.emit(0)
