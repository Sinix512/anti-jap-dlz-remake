extends Control
signal chosen(index:int)
signal cancelled
const UI=preload("res://scripts/ui/OriginalUI.gd")
var frame:Rect2
var entries:Array=[]
var labels:Array[Label]=[]
var choice:=0
var selected_row:TextureRect
var done:=false
var allow_cancel:=true
var palette:Array=[]
var normal_color:=Color("#a4fcfc")
var selected_color:=Color("#fc8c00")
var selected_textures:Array=[]
var raster_root:Control
var drawn_heights:Array=[]
var restore_count:=0
var saved_background:Texture2D
var interactive:=false
var roll_open:=true
func setup(font:Font,lines:Array,origin:Vector2,can_cancel:=true,colors:Array=[],animated:=true) -> void:
	palette=colors
	if not palette.is_empty():
		normal_color=preload("res://scripts/ui/OriginalPalette.gd").color_at(palette,0x48)
		selected_color=preload("res://scripts/ui/OriginalPalette.gd").color_at(palette,0xBF)
	allow_cancel=can_cancel
	# 426A05 rolls; L22's separate426E7D paints the complete panel at once.
	# Presentation must not be inferred merely from cancellability.
	roll_open=animated and lines.size()>1
	entries=lines.duplicate()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	frame=Rect2(origin,Vector2(88,32 if lines.size()==1 else 24*lines.size()+16))
	# 426A9C flushes queued entry input, then saves the original display rect.
	preload("res://scripts/ui/OriginalPaletteFade.gd").discard_buffered_input(get_tree())
	if DisplayServer.get_name()!="headless":
		RenderingServer.force_sync();RenderingServer.force_draw()
		var pixels:=get_viewport().get_texture().get_image()
		if pixels!=null:saved_background=ImageTexture.create_from_image(pixels.get_region(Rect2i(frame)))
	raster_root=Control.new();raster_root.clip_contents=true;raster_root.size=Vector2(640,origin.y+frame.size.y)
	raster_root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(raster_root)
	var panel:=UI.panel("res://assets/ui/choice_%d_original.png"%lines.size(),frame)
	if not palette.is_empty():
		var p=preload("res://scripts/ui/OriginalPalette.gd")
		var raw:=FileAccess.get_file_as_bytes("res://assets/ui/choice_%d_indices.bin"%lines.size())
		panel.texture=p.texture(raw,88,int(frame.size.y),palette)
		for row in range(lines.size()):selected_textures.append(p.selected(raw,88,Rect2i(4,8+row*24,80,24),palette))
	raster_root.add_child(panel)
	selected_row=TextureRect.new();selected_row.mouse_filter=Control.MOUSE_FILTER_IGNORE;raster_root.add_child(selected_row);selected_row.hide()
	for index in range(lines.size()):
		var label:=UI.label(str(lines[index]),font,16,normal_color)
		label.position=origin+Vector2(12,(4 if lines.size()==1 else 12)+24*index);label.size=Vector2(72,16)
		label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT);label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		labels.append(label);raster_root.add_child(label)
	if entries.size()>1 and DisplayServer.get_name()!="headless":get_viewport().warp_mouse(origin+Vector2(44,16))
	# 426C6A copies normal offscreen text at heights2,6,...,H-2. No Sleep,
	# frame timer, scaling or invented final full-height blit. The bottom two
	# rows stay original background, even after the menu is fully open.
	if roll_open:
		for height in range(2,int(frame.size.y)+1,4):
			drawn_heights.append(height);raster_root.size.y=origin.y+height
			if DisplayServer.get_name()!="headless":RenderingServer.force_sync();RenderingServer.force_draw()
	_select(0);interactive=true
func _select(index:int) -> void:
	choice=index
	selected_row.visible=entries.size()>1
	if entries.size()>1:
		selected_row.texture=load("res://assets/ui/choice_%d_selected_%d.png"%[entries.size(),index]) if palette.is_empty() else selected_textures[index]
		selected_row.position=frame.position+Vector2(4,8+24*index)
	for row in range(labels.size()):labels[row].add_theme_color_override("font_color",selected_color if row==choice else normal_color)
func _input(event:InputEvent) -> void:
	if done:return
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey:get_viewport().set_input_as_handled()
	if not interactive:return
	if event is InputEventMouseMotion:
		# 426A05/426E7D use the entire 640px-wide hover strip. Leaving
		# that strip preserves the last row; the click never recalculates it.
		var top:float=frame.position.y+(0 if entries.size()==1 else 8)
		if event.position.x>=0 and event.position.x<640 and event.position.y>=top and event.position.y<top+24*entries.size():
			_select(int((event.position.y-top)/24))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT and allow_cancel:
			done=true;_restore_background();cancelled.emit()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			done=true;_restore_background();chosen.emit(choice)

func _restore_background() -> void:
	if restore_count>0:return
	restore_count+=1;raster_root.hide();UI.native_text_index=0x48
	if saved_background!=null:
		var restored:=TextureRect.new();restored.texture=saved_background;restored.position=frame.position;restored.size=frame.size
		restored.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(restored)
		RenderingServer.force_sync();RenderingServer.force_draw()

func row_rect(index:int) -> Rect2:
	return Rect2(frame.position+Vector2(4,(0 if entries.size()==1 else 8)+24*index),Vector2(80,24))
