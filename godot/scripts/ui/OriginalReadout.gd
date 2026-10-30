extends Control
# 41D03E / 41CA3E / 41CC90: read-only framebuffer page + 425A08 UP wait.
signal closed
const UI=preload("res://scripts/ui/OriginalUI.gd")
const AREA=Rect2i(80,60,480,360)
var skip_left:=true
var done:=false
var _touch_pressed:=false
var page:=0
var pages:Array=[]
var labels:Array[Label]=[]
var text_font:Font
var palette:Array=[]
var backdrop:TextureRect

static func darken(source:Image,colors:Array,lut:Array) -> Image:
	# Decode the rendered palette colors, then apply the exact 6223B0 index LUT.
	# A nearest source-index fallback is explicit for non-original renderer colors.
	var cache:Dictionary={}
	for index in range(256):
		var key:int=(int(colors[index*3])<<16)|(int(colors[index*3+1])<<8)|int(colors[index*3+2])
		if not cache.has(key):cache[key]=index
	var result:Image=source.duplicate()
	result.convert(Image.FORMAT_RGBA8)
	var bytes:PackedByteArray=result.get_data()
	for offset in range(0,bytes.size(),4):
		var r:int=bytes[offset];var g:int=bytes[offset+1];var b:int=bytes[offset+2]
		var key:int=(r<<16)|(g<<8)|b
		if not cache.has(key):
			var distance:=0x7fffffff;var nearest:=0
			for index in range(256):
				var dr:int=r-int(colors[index*3]);var dg:int=g-int(colors[index*3+1]);var db:int=b-int(colors[index*3+2])
				var candidate:int=(30*dr*dr+59*dg*dg+11*db*db)/100
				if candidate<distance:distance=candidate;nearest=index
			cache[key]=nearest
		var target:int=int(lut[int(cache[key])])*3
		bytes[offset]=int(colors[target]);bytes[offset+1]=int(colors[target+1]);bytes[offset+2]=int(colors[target+2]);bytes[offset+3]=255
	return Image.create_from_data(result.get_width(),result.get_height(),false,Image.FORMAT_RGBA8,bytes)

func setup(font:Font,colors:Array,content:Array,background:Image=null,lut:Array=[]) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	text_font=font;palette=colors;pages=content
	backdrop=TextureRect.new();backdrop.position=Vector2(AREA.position);backdrop.size=Vector2(AREA.size);backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(backdrop)
	if background!=null:backdrop.texture=ImageTexture.create_from_image(darken(background,colors,lut))
	show_page(0)
	UI.touch_back(self,font,_advance,"继续")

func show_page(index:int) -> void:
	page=index;skip_left=true;_touch_pressed=false;UI.native_wait_left_blocked=true
	for label in labels:label.free()
	labels.clear()
	if pages.is_empty():_close();return
	for entry in pages[page]:
		var rgb:int=int(entry.get("color",0x48))*3
		var color:=Color8(int(palette[rgb]),int(palette[rgb+1]),int(palette[rgb+2]))
		var label:=UI.label(str(entry.text),text_font,16,color)
		label.position=entry.at;label.size=Vector2(0,16);label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
		add_child(label);labels.append(label)

func _input(event:InputEvent) -> void:
	if done or not visible:return
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey:get_viewport().set_input_as_handled()
	if UI.touch_mode(self):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_advance();return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_touch_pressed=true;return
			if _touch_pressed:_touch_pressed=false;UI.native_wait_left_blocked=false;_advance();return
			return # A release without its fresh DOWN belongs to the opening gesture.
	if event is InputEventKey and not event.pressed:_advance()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:_advance()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if skip_left:skip_left=false;UI.native_wait_left_blocked=false
			else:_advance()

func _advance() -> void:
	if page+1<pages.size():show_page(page+1)
	else:_close()

func _close() -> void:
	if done:return
	done=true;closed.emit()
