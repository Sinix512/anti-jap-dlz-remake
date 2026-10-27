extends Node2D

# This canvas is strictly above the map and below ALL native map markers.
# The generated texture is palette-LUT-remapped, not RGB multiplied/alpha dimmed.
var battle:Node
var texture:Texture2D

func _draw() -> void:
	if battle==null or texture==null:return
	var mask:PackedByteArray=battle.native_dark_mask
	var width:int=battle.map_w
	var height:int=battle.map_h
	if mask.size()!=width*height:return
	for y in range(height):
		var x:=0
		while x<width:
			if mask[y*width+x]==0:x+=1;continue
			var start:=x
			while x<width and mask[y*width+x]!=0:x+=1
			var rect:=Rect2(start*48,y*48,(x-start)*48,48)
			draw_texture_rect_region(texture,rect,rect)
