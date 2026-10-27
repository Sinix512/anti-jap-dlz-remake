extends RefCounted
# 425AD4/425D7C: synchronous palette writes, default +/-4 RGB components;
# END/JZ entering and JZ-2 exit use step1. No artificial frame timer.
# Godot adapter draws the corresponding captured RGB surface synchronously;
# it does not invent a55ms/one-frame-per-step animation or dispatch input.
class Drain extends Node:
	func _input(event:InputEvent) -> void:
		if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
static func colors_at(colors:Array,step:int,entering:bool,increment:=4) -> Array:
	var out:Array=[]
	for value in colors:out.append(mini(int(value),step*increment) if entering else maxi(0,int(value)-step*increment))
	return out
static func capture(owner_node:Control) -> TextureRect:
	if DisplayServer.get_name()=="headless":return null
	RenderingServer.force_sync();RenderingServer.force_draw()
	var pixels:=owner_node.get_viewport().get_texture().get_image()
	if pixels==null:return null
	return surface(owner_node,ImageTexture.create_from_image(pixels))
static func surface(owner_node:Control,source:Texture2D) -> TextureRect:
	var overlay:=TextureRect.new();overlay.texture=source
	overlay.position=Vector2.ZERO;overlay.size=Vector2(640,480);overlay.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	var shader:=ShaderMaterial.new();shader.shader=preload("res://scripts/ui/OriginalPaletteFade.gdshader");overlay.material=shader
	owner_node.add_child(overlay)
	return overlay
static func phase(overlay:TextureRect,step:int,entering:bool,increment:=4) -> void:
	(overlay.material as ShaderMaterial).set_shader_parameter("amount",step*float(increment)/255.0)
	(overlay.material as ShaderMaterial).set_shader_parameter("entering",entering)
static func play(owner_node:Control,entering:bool,increment:=4,keep_black:=false,source:Texture2D=null) -> void:
	if DisplayServer.get_name()=="headless":return
	# A freshly attached Control is not guaranteed to have painted yet in the
	# current SceneTree pump. END/JZ supply their known full-screen source,
	# rather than accidentally capturing the previous page or clear colour.
	var overlay:=surface(owner_node,source) if source!=null else capture(owner_node)
	if overlay==null:return
	for step in range(1,int(ceil(256.0/increment))+1):
		phase(overlay,step,entering,increment);RenderingServer.force_sync();RenderingServer.force_draw()
	# Palette black persists until the next surface load. Keep the final black
	# snapshot on exiting END/JZ pages so a second capture cannot re-light them.
	if not keep_black or entering:overlay.free()
static func discard_buffered_input(tree:SceneTree) -> void:
	# Godot-buffer equivalent only: OS/Win32 PeekMessage queues are not emulated.
	var drain:=Drain.new();tree.root.add_child(drain);Input.flush_buffered_events();drain.free()
