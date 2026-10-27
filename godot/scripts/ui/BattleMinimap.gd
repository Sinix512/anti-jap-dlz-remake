extends Control

var battle
func cell_scale() -> int:
	return mini(maxi(2,168/battle.map_w),maxi(2,212/battle.map_h))
func actual_rect() -> Rect2:
	var dimensions := Vector2(battle.map_w,battle.map_h)*cell_scale()
	return Rect2((size-dimensions)/2,dimensions)
func tile_at(point: Vector2) -> Vector2i:
	var p := (point-actual_rect().position)/cell_scale()
	return Vector2i(floori(p.x),floori(p.y))
func _draw() -> void:
	if battle == null: return
	var rect := actual_rect()
	if battle.map_sprite != null and battle.map_sprite.texture != null:
		draw_texture_rect(battle.map_sprite.texture,rect,false)
	for u in battle.units:
		if u.alive:
			draw_rect(Rect2(rect.position+Vector2(u.x,u.y)*cell_scale(),Vector2.ONE*cell_scale()),Color("#4da3ff") if u.is_player() else Color("#ff5a5a"))
	if battle.camera != null:
		var origin: Vector2 = battle.camera.position + battle.map_rect().position-Vector2(320,240)
		draw_rect(Rect2(rect.position+origin/48*cell_scale(),battle.map_rect().size/48*cell_scale()),Color.WHITE,false,1)
