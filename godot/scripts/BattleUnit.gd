extends Node2D

## 战场单位：精灵、HP 条、选择框、受击/死亡表现。

const TILE := 48

var data: Dictionary = {}
var battle: Node
var side := "enemy"
var unit_name := ""
var x := 0
var y := 0
var hp := 1
var max_hp := 1
var move := 4
var select := 1
var bingzhong := 0
var direction := 1
var acted := false
var moved := false
var alive := true
var selected := false

var sprite: Sprite2D
var _flash_tween: Tween


func setup(d: Dictionary, b: Node) -> void:
	data = d
	battle = b
	side = str(d.get("side", "enemy"))
	unit_name = str(d.get("name", "?"))
	x = int(d.get("x", 0))
	y = int(d.get("y", 0))
	hp = int(d.get("hp", 1))
	max_hp = max(1, hp)
	move = int(d.get("move", 4))
	select = int(d.get("select", 1))
	bingzhong = int(d.get("bingzhong", 0))
	direction = int(d.get("direction", 1))
	position = _tile_center(x, y)
	z_index = int(position.y)

	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, TILE, TILE)
	var p := str(d.get("army_png", ""))
	if p != "" and ResourceLoader.exists(p):
		sprite.texture = load(p)
	else:
		sprite.texture = _fallback_texture()
	add_child(sprite)
	sprite.flip_h = direction == 2
	refresh()


func _fallback_texture() -> Texture2D:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color("#4a5568"))
	return ImageTexture.create_from_image(img)


func _tile_center(tx: int, ty: int) -> Vector2:
	return Vector2(tx * TILE + TILE / 2.0, ty * TILE + TILE / 2.0)


func is_player() -> bool:
	return side == "player"


func refresh() -> void:
	if sprite == null:
		return
	sprite.flip_h = direction == 2
	if acted:
		sprite.modulate = Color(0.58, 0.58, 0.62, 1.0)
	else:
		sprite.modulate = Color.WHITE
	queue_redraw()


func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()


func set_tile(tx: int, ty: int) -> void:
	x = tx
	y = ty
	position = _tile_center(tx, ty)
	z_index = int(position.y)


func move_visual(tx: int, ty: int, dur: float = 0.10) -> void:
	x = tx
	y = ty
	var tw := create_tween()
	tw.tween_property(self, "position", _tile_center(tx, ty), dur)
	tw.parallel().tween_property(self, "z_index", int(_tile_center(tx, ty).y), dur)
	await tw.finished


func take_damage(amount: int) -> bool:
	hp = max(0, hp - amount)
	queue_redraw()
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate",
			Color(0.58, 0.58, 0.62, 1.0) if acted else Color.WHITE, 0.28)
	return hp <= 0


func die() -> void:
	if not alive:
		return
	alive = false
	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(sprite, "scale", Vector2(0.6, 0.6), 0.25)
	await tw.finished
	visible = false


func _draw() -> void:
	if not alive:
		return
	# 选择圈
	if selected:
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 24, Color("#ffd166"), 2.0)
	# 阵营点
	var c := Color("#4da3ff") if side == "player" else Color("#ff5a5a")
	draw_circle(Vector2(-19, -30), 4.0, c)
	# HP 条
	var w := 38.0
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	draw_rect(Rect2(-w / 2, -25, w, 4), Color(0, 0, 0, 0.8))
	var col := Color("#53d769")
	if ratio < 0.35:
		col = Color("#ff5a5a")
	elif ratio < 0.65:
		col = Color("#f2c14e")
	draw_rect(Rect2(-w / 2, -25, w * ratio, 4), col)
