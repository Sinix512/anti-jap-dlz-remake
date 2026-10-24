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
var slot := -1
var pid := -1
var key := ""
var behavior := 1
var target_slot := 0
var target_x := 0
var target_y := 0
# Fighter +0x14/+0x18：原版 behavior 8 的“家”坐标，到达目标后与
# target_x/y 交换，形成两点巡逻。对非 behavior 8 单位仅作记录。
var home_x := 0
var home_y := 0
var control := true
var auto := false
var protected := false
var is_boss := false
var acted := false
var moved := false
var alive := true
var selected := false
# 战斗数值（M6）：士气/装备完整度/技能次数/装备加成/状态
var last_damage_kind := ""  # gun / mine / skill / throw
var morale := 100
var integrity := 100
var attack_count := 0
var skill_counts: Dictionary = {}
var skills: Dictionary = {}
var attack_bonus := 0
var defense_bonus := 0
var equip := -1
var equip_name := ""
var item_slots: Array = []
var mine_slots: Array = []
var gained_xp := 0
var status_def_down := 0
var status_atk_down := 0
var status_stun := 0
var status_disarm := 0

var sprite: Sprite2D
var _flash_tween: Tween
var frame_count := 1
var _anim_active := false
var _anim_from := 0
var _anim_to := 0
var _anim_fps := 10.0
var _anim_t := 0.0
var _anim_loop := false


func setup(d: Dictionary, b: Node) -> void:
	data = d
	battle = b
	side = str(d.get("side", "enemy"))
	unit_name = str(d.get("name", "?"))
	key = str(d.get("key", unit_name.replace("\u3000", "").replace(" ", "")))
	x = int(d.get("x", 0))
	y = int(d.get("y", 0))
	hp = int(d.get("hp", 1))
	max_hp = max(1, int(d.get("max_hp", hp)))
	move = int(d.get("move", 4))
	select = int(d.get("select", 1))
	bingzhong = int(d.get("bingzhong", 0))
	direction = int(d.get("direction", 1))
	slot = int(d.get("slot", -1))
	pid = int(d.get("pid", -1))
	behavior = int(d.get("behavior", 1))
	target_slot = int(d.get("target_slot", 0))
	target_x = int(d.get("target_x", 0))
	target_y = int(d.get("target_y", 0))
	home_x = int(d.get("home_x", x))
	home_y = int(d.get("home_y", y))
	control = bool(d.get("control", true))
	auto = bool(d.get("auto", false))
	protected = bool(d.get("protected", false))
	is_boss = bool(d.get("is_boss", false))
	morale = int(d.get("morale", 100))
	integrity = int(d.get("integrity", 100))
	attack_count = int(d.get("attack_count", 0))
	skill_counts = (d.get("skill_counts", {}) as Dictionary).duplicate(true)
	skills = (d.get("skills", {}) as Dictionary).duplicate(true)
	attack_bonus = int(d.get("attack_bonus", 0))
	defense_bonus = int(d.get("defense_bonus", 0))
	equip = int(d.get("equip", -1))
	equip_name = str(d.get("equip_name", ""))
	item_slots = (d.get("item_slots", []) as Array).duplicate()
	mine_slots = (d.get("mine_slots", []) as Array).duplicate()
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
	frame_count = maxi(1, int(sprite.texture.get_width() / TILE))
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


func _process(delta: float) -> void:
	if not _anim_active:
		return
	_anim_t += delta * _anim_fps
	var f := int(_anim_t)
	if f > _anim_to:
		if _anim_loop:
			_anim_t = 0.0
			f = _anim_from
		else:
			_anim_active = false
			f = _anim_from
	sprite.region_rect = Rect2(f * TILE, 0, TILE, TILE)


func play_anim(from_frame: int, to_frame: int, fps: float = 10.0,
		loop: bool = false) -> void:
	if battle != null and bool(battle.fast_sim):
		return
	_anim_from = clampi(from_frame, 0, frame_count - 1)
	_anim_to = clampi(to_frame, _anim_from, frame_count - 1)
	_anim_fps = fps
	_anim_loop = loop
	_anim_t = 0.0
	_anim_active = _anim_to > _anim_from
	sprite.region_rect = Rect2(_anim_from * TILE, 0, TILE, TILE)


func play_attack() -> void:
	play_anim(0, frame_count - 1, 16.0, false)


func play_walk() -> void:
	play_anim(0, mini(4, frame_count - 1), 9.0, true)


func stop_anim() -> void:
	_anim_active = false
	sprite.region_rect = Rect2(0, 0, TILE, TILE)


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
	if battle != null and bool(battle.fast_sim):
		set_tile(tx, ty)
		return
	play_walk()
	var tw := create_tween()
	tw.tween_property(self, "position", _tile_center(tx, ty), dur)
	tw.parallel().tween_property(self, "z_index", int(_tile_center(tx, ty).y), dur)
	await tw.finished
	stop_anim()


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
	var c := Color("#69b7ff") if side == "player" else Color("#ff5a5a")
	if auto and side == "player":
		c = Color("#8fd18f")
	draw_circle(Vector2(-19, -30), 4.0, c)
	if protected:
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 24, Color("#e8ba4c"), 1.0)
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
