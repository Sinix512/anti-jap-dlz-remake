extends Control
# Transparent, unscaled HZK16 glyph surface. Positions are GBK-byte advances.
var font:Font
var palette:Array=[]
var glyphs:Array=[]
func _draw() -> void:
	if font==null:return
	for glyph in glyphs:
		draw_string(font,Vector2(glyph.x,glyph.y+font.get_ascent(16)),str(glyph.text),HORIZONTAL_ALIGNMENT_LEFT,-1,16,preload("res://scripts/ui/OriginalPalette.gd").color_at(palette,int(glyph.color)))
