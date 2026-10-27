extends Control
signal chosen(id:int)
signal cancelled
const UI=preload("res://scripts/ui/OriginalUI.gd")
const GBK=preload("res://scripts/m2/GBK.gd")
var slots:Array=[]
var armed:=false
var done:=false
var opening_release=preload("res://scripts/ui/OpeningReleaseGuard.gd").new()
func setup(font:Font,tables:Dictionary,bag:Array) -> void:
	slots=bag.duplicate()
	opening_release.capture()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(UI.panel("res://assets/ui/item_picker_original.png",Rect2(168,126,304,227)))
	for index in range(mini(8,slots.size())):
		var id:=int(slots[index])-1
		if id<0:continue
		var it:Dictionary=tables.items.get(str(id),{})
		var at:=Vector2(194+67*(index%4),144+100*(index/4))
		var icon:=TextureRect.new();icon.texture=UI.first_frame(str(it.get("icon","res://assets/goods/goods_%03d.png"%int(it.get("goods",0)))))
		icon.position=at;icon.size=Vector2(48,48);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(icon)
		var raw:=GBK.encode(str(it.get("name","")),17)
		for row in range(2):
			var label:=UI.label(GBK.decode(raw.slice(6*row,6*row+6)),font,16,Color("#a4fcfc"))
			label.position=at+Vector2(0,52+16*row);label.size=Vector2(64,16)
			label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT);label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(label)
	call_deferred("_arm")
func _arm() -> void:
	await get_tree().process_frame
	armed=true
func _input(event:InputEvent) -> void:
	if done:return
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey:
		get_viewport().set_input_as_handled()
	if opening_release.consumes(event) or not armed or not event is InputEventMouseButton or event.pressed:return
	if event.button_index==MOUSE_BUTTON_RIGHT:
		done=true;cancelled.emit()
	elif event.button_index==MOUSE_BUTTON_LEFT:
		for index in range(mini(8,slots.size())):
			if int(slots[index])>0 and Rect2(194+67*(index%4),144+100*(index/4),48,48).has_point(event.position):
				done=true;chosen.emit(int(slots[index])-1);return
