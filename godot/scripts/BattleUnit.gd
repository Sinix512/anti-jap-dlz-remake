extends Node2D

## 战场单位：原状态精灵、乱字、受击/死亡表现。

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
var acted := false:
	set(value):
		acted=value
		if not display_action_lock:display_state=0 if value else 1
		if sprite!=null:refresh()
var moved := false
var alive := true
# 429CC8 sets stage1 before searching; an exhausted 25-cell search leaves a
# live, unplaced slot, not a teleport to some other part of the map.
var placed := true
var selected := false
# 战斗数值（M6）：士气/装备完整度/技能次数/装备加成/状态
var last_damage_kind := ""  # gun / mine / skill / throw
var morale := 100
var integrity := 100
var defense_integrity := 100
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
# Original Fighter +00/+3F. direction is this runtime's destination direction.
# Keep these independent of the current Sprite region; deaths sample them.
var display_counter := 0
var display_state := 1
var display_action_lock := false
var _damage_display_backup := -1
var _flash_tween: Tween
var frame_count := 1
var _anim_active := false
var _anim_from := 0
var _anim_to := 0
var _anim_fps := 10.0
var _anim_t := 0.0
var _anim_loop := false

const STATE_FIELDS := ["side","unit_name","x","y","hp","max_hp","move","select",
	"bingzhong","direction","slot","pid","key","behavior","target_slot","target_x",
	"target_y","home_x","home_y","control","auto","protected","is_boss","acted",
	"moved","alive","placed","last_damage_kind","morale","integrity","defense_integrity",
	"attack_count","skill_counts","skills","attack_bonus","defense_bonus","equip",
	"equip_name","item_slots","mine_slots","gained_xp","status_def_down",
	"status_atk_down","status_stun","status_disarm","display_counter","display_state"]

func state_record() -> Dictionary:
	var result := data.duplicate(true)
	result["_runtime_state"] = true
	for field in STATE_FIELDS: result[field] = get(field)
	return result.duplicate(true)


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
	defense_integrity = int(d.get("defense_integrity", 100))
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
	sprite.show_behind_parent=true # army before the parent's behavior11 glyph
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
	sprite.flip_h = false
	# Resume is not a fresh deployment. Retain action availability and departed units.
	if bool(d.get("_runtime_state",false)):
		for field in STATE_FIELDS:
			if d.has(field): set(field,d[field])
	# Hydration is also used by JSON resumes and late spawns, bypassing Builder.
	# Older records can contain a contradictory cached side; derive it only after
	# all runtime fields are restored, before Battle builds its enemy/ally lists.
	if data.has("faction"):
		side = "player" if int(data["faction"]) == 0 else "enemy"
		data["side"] = side
		auto = side == "player" and not control
		data["auto"] = auto
	visible = alive and placed
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


func native_frame() -> int:
	return preload("res://scripts/battle/OriginalDeathMix.gd").army_frame(display_state,direction,display_counter)


func advance_display(amount:=1) -> void:
	display_counter=(display_counter+amount)&0xffffffff
	refresh()


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


func play_attack(present:=true) -> void:
	# 41F10A: five pairs of same-cell draws, one p++ per pair. No lunge.
	display_state=2
	for i in range(5):
		refresh()
		if present:await get_tree().create_timer(0.1).timeout
		advance_display()
		if present:await get_tree().create_timer(0.1).timeout


func play_walk() -> void:
	play_anim(0, mini(4, frame_count - 1), 9.0, true)


func stop_anim() -> void:
	_anim_active = false
	refresh()


func refresh() -> void:
	if sprite == null:
		return
	sprite.flip_h = false
	sprite.modulate = Color.WHITE
	sprite.region_rect = Rect2(native_frame()*TILE,0,TILE,TILE)
	queue_redraw()


func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()


func set_tile(tx: int, ty: int) -> void:
	x = tx
	y = ty
	placed = true
	visible = alive
	position = _tile_center(tx, ty)
	z_index = int(position.y)


func move_visual(tx: int, ty: int, dur: float = 0.10) -> void:
	if battle != null: direction = battle._facing(Vector2i(x,y),Vector2i(tx,ty))
	x = tx
	y = ty
	placed = true
	visible = alive
	var from:=position
	var to:=_tile_center(tx,ty)
	var present:=battle==null or (not bool(battle.fast_sim) and bool(battle.animations_enabled))
	if battle != null:
		dur=float(battle.animation_speed)*0.08
	# 41E5F1:12/24/36/48px, p++ BEFORE each step, s unchanged.
	for step in range(1,5):
		advance_display()
		sprite.region_rect=Rect2((2+2*posmod(direction,4)+display_counter%2)*TILE,0,TILE,TILE)
		position=from.lerp(to,step/4.0)
		z_index=int(position.y)
		if present and dur>0:await get_tree().create_timer(dur/4.0).timeout
	refresh()


func take_damage(amount: int) -> bool:
	hp = max(0, hp - amount)
	queue_redraw()
	if amount>0:
		if _damage_display_backup<0:_damage_display_backup=display_state
		display_state=3
		refresh()
	return hp <= 0


func restore_damage_display() -> void:
	if _damage_display_backup<0:return
	# 419B0D restores temporary2/3 only; doubt/supervise0/1 persist.
	if display_state in [2,3]:display_state=_damage_display_backup
	_damage_display_backup=-1
	refresh()


func die() -> void:
	if not alive:return
	alive = false
	disappear()


func disappear() -> void:
	if _flash_tween != null and _flash_tween.is_valid():_flash_tween.kill()
	stop_anim()
	visible = false


func _draw() -> void:
	if not alive:
		return
	# 4170AA uses this one raw HZK16 glyph for behavior11, not all stuns.
	if behavior==11 and battle!=null:
		var glyph:Array=battle.data.meta.get("luan_glyph",[])
		var pal:Array=battle.data.meta.get("battle_palette",[])
		if glyph.size()==32 and pal.size()==768:
			var color:=Color8(int(pal[0xB7*3]),int(pal[0xB7*3+1]),int(pal[0xB7*3+2]))
			for gy in range(16):
				for gx in range(16):
					if int(glyph[gy*2+gx/8]) & (128>>(gx%8)):draw_rect(Rect2(gx-8,gy-8,1,1),color)
	# 417547/4170AA do not add modern circles, faction dots, or HP bars.
