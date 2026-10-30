extends RefCounted
## Touch-only chrome. The original desktop framebuffer/input contracts stay intact.
const BACK_RECT:=Rect2(560,436,76,40)
class BackAction extends Control:
	var text_font:Font
	var action:Callable
	var caption:="返回"
	var held:=0
	func _draw() -> void:
		draw_style_box(_style(),Rect2(Vector2.ZERO,size))
		draw_string(text_font,Vector2(10,12+text_font.get_ascent(16)),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x-12,16,Color("#fff1cf"))
	func _style() -> StyleBoxFlat:
		var style:=StyleBoxFlat.new();style.bg_color=Color("#263445");style.border_color=Color("#d9aa63");style.set_border_width_all(1)
		return style
	func _input(event:InputEvent) -> void:
		if not is_visible_in_tree() or not action.is_valid():return
		if not event is InputEventMouseButton or event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:return
		var inside:=get_global_rect().has_point(event.position)
		if event.pressed:
			if not inside:return
			held=event.button_index;get_viewport().set_input_as_handled()
		elif held==event.button_index:
			held=0;get_viewport().set_input_as_handled()
			if inside:action.call()

static func enabled(owner:Node) -> bool:
	var bridge=owner.get_node_or_null("/root/TouchInput") if owner.is_inside_tree() else null
	return bool(bridge.is_touch_mode()) if bridge!=null and bridge.has_method("is_touch_mode") else OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch-ui")

static func add_back(owner:Node,font:Font,callback:Callable,caption:="返回",at:=Vector2(560,436)) -> Control:
	if not enabled(owner):return null
	var back:=BackAction.new();back.name="TouchBack";back.text_font=font;back.action=callback;back.caption=caption
	back.position=at;back.size=BACK_RECT.size;back.mouse_filter=Control.MOUSE_FILTER_IGNORE;back.z_index=100
	owner.add_child(back);return back
