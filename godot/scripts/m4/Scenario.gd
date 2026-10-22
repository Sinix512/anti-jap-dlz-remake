extends RefCounted

## M4 通用关卡目标 / 触发器 / 增援。
## Battle 只负责地图、移动、攻击；这里解释 level["objective"]。

var battle
var level: Dictionary = {}
var objective: Dictionary = {}
var protected_keys: Array = []
var name_keys: Array = []
var unit_keys: Array = []
var rival_key := ""
var targets: Array = []
var target_units: Array = []
var search_tiles: Array = []
var waves: Array = []
var wave_done: Array = []
var reached: Dictionary = {}
var searched: Dictionary = {}
var killed: Dictionary = {}
var collected := 0
var chests_opened := 0
var target_count := 1
var survive_turns := 0
var race_winner := ""
var started := false
var finished := false
var status_text := ""
var _target_sprites: Array = []


func setup(b, lv: Dictionary) -> void:
	battle = b
	level = lv
	objective = lv.get("objective", {})
	if objective.is_empty():
		objective = {"type": "annihilate", "label": "全歼敌人"}
	name_keys = objective.get("name_keys", [])
	unit_keys = objective.get("unit_keys", [])
	rival_key = str(objective.get("rival_key", ""))
	targets = (objective.get("targets", []) as Array).duplicate(true)
	target_count = int(objective.get("count", targets.size() if targets.size() > 0 else 1))
	survive_turns = int(objective.get("turns", 0))
	protected_keys.clear()
	for n in lv.get("protect", []):
		protected_keys.append(_key(n))
	for w in lv.get("waves", []):
		waves.append(w)
	waves.sort_custom(func(a, b): return int(a.get("turn", 0)) < int(b.get("turn", 0)))
	# 目标单位按 key 缓存
	for u in battle.units:
		if u.side == "player" and _key(u.unit_name) in unit_keys:
			target_units.append(u)
	status_text = str(objective.get("label", ""))
	if objective.get("type", "") == "reach_unit":
		status_text = "接近 " + "、".join(objective.get("units", []))


func _key(text: String) -> String:
	return str(text).replace("\u3000", "").replace(" ", "")


func on_start() -> void:
	started = true
	# 目标点/搜索点标记
	if objective.get("type", "") in ["reach", "capture_or_annihilate", "race"]:
		for t in targets:
			_add_target_marker(int(t[0]), int(t[1]))
	if objective.get("type", "") == "collect":
		for t in targets:
			_add_search_marker(int(t[0]), int(t[1]))
	_update_status()


func _add_target_marker(tx: int, ty: int) -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists("res://assets/ui/target.png"):
		tex = load("res://assets/ui/target.png")
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.position = Vector2(tx * battle.TILE + battle.TILE / 2.0,
			ty * battle.TILE + battle.TILE / 2.0)
	s.z_index = 180
	s.modulate = Color(1, 1, 1, 0.85)
	battle.units_root.add_child(s)
	_target_sprites.append(s)


func _add_search_marker(tx: int, ty: int) -> void:
	var s := Sprite2D.new()
	if ResourceLoader.exists("res://assets/ui/chest_sheet.png"):
		var at := AtlasTexture.new()
		at.atlas = load("res://assets/ui/chest_sheet.png")
		at.region = Rect2(0, 0, 48, 48)
		s.texture = at
	s.centered = true
	s.position = Vector2(tx * battle.TILE + battle.TILE / 2.0,
			ty * battle.TILE + battle.TILE / 2.0)
	s.z_index = 190
	battle.units_root.add_child(s)
	_target_sprites.append(s)


func on_turn_start(turn: int) -> void:
	if finished:
		return
	# 增援
	for wi in range(waves.size()):
		var wave: Dictionary = waves[wi]
		if wi in wave_done:
			continue
		if turn >= int(wave.get("turn", 0)):
			wave_done.append(wi)
			_spawn_wave(wave)
	# 坚持 N 回合
	if objective.get("type", "") == "survive" and survive_turns > 0 \
			and turn > survive_turns:
		battle._finish("victory", "坚持 %d 回合，任务完成" % survive_turns)
		return
	_update_status()


func _spawn_wave(wave: Dictionary) -> void:
	var units: Array = wave.get("units", [])
	var side := str(wave.get("side", "enemy"))
	for rec in units:
		var d: Dictionary = (rec as Dictionary).duplicate(true)
		d["side"] = side
		var u = battle.spawn_reserve(d)
		if u != null:
			if side == "player" and _key(u.unit_name) in protected_keys:
				u.protected = true
			if side == "player" and _key(u.unit_name) in unit_keys:
				target_units.append(u)
	battle._log("敌方增援出现！" if side == "enemy" else "我方增援赶到！")
	battle.update_hud()


func on_unit_moved(u) -> void:
	if finished or u == null or not u.alive:
		return
	var t := Vector2i(u.x, u.y)
	if objective.get("type", "") in ["reach", "capture_or_annihilate"]:
		for i in range(targets.size()):
			var tt: Array = targets[i]
			if int(tt[0]) == t.x and int(tt[1]) == t.y:
				reached[i] = true
		if objective.get("type", "") == "capture_or_annihilate":
			if not reached.is_empty():
				_finish("victory", "占领目标")
				return
		elif reached.size() >= target_count:
			_finish("victory", str(level.get("success", "到达目标")))
			return
	if objective.get("type", "") == "collect":
		for i in range(targets.size()):
			var tt: Array = targets[i]
			if int(tt[0]) == t.x and int(tt[1]) == t.y and not searched.has(i):
				searched[i] = true
				collected += 1
				battle._log("搜集到%s %d/%d" % [
					objective.get("label", "物资"), collected, target_count])
		if collected >= target_count:
			_finish("victory", "物资搜集完成")
			return
	if objective.get("type", "") == "reach_unit":
		for tu in target_units:
			if not is_instance_valid(tu) or not tu.alive:
				continue
			if tu == u:
				continue
			var d: int = abs(tu.x - u.x) + abs(tu.y - u.y)
			var radius := int(objective.get("radius", 1))
			if d <= radius:
				_finish("victory", "已接近 %s" % tu.unit_name)
				return
	if objective.get("type", "") == "race":
		for i in range(targets.size()):
			var tt: Array = targets[i]
			if int(tt[0]) == t.x and int(tt[1]) == t.y:
				race_winner = _key(u.unit_name)
				if u.side == "player":
					_finish("victory", str(level.get("success", "抢先到达")))
				else:
					_finish("defeat", "敌人抢先到达山神庙")
				return
	_update_status()


func on_unit_died(u) -> void:
	if finished or u == null:
		return
	var k := _key(u.unit_name)
	if u.side == "enemy":
		killed[k] = true
		if objective.get("type", "") == "kill":
			var all := true
			for n in name_keys:
				if not killed.has(n):
					all = false
			if all:
				_finish("victory", "击毙 " + "、".join(objective.get("names", [])))
				return
	if u.side == "player" and k in protected_keys:
		_finish("defeat", "%s 阵亡" % u.unit_name)
		return
	_update_status()


func on_chest(u, chest: Dictionary) -> void:
	chests_opened += 1
	var item := str(chest.get("item_name", "物资"))
	battle._log("%s 打开宝箱：%s" % [u.unit_name, item])
	battle.looted.emit(int(chest.get("wupin", -1)))
	_update_status()


func check_end() -> bool:
	if finished:
		return true
	if not started:
		return false
	# 目标类型
	match str(objective.get("type", "annihilate")):
		"annihilate":
			if battle.alive_enemies() == 0:
				_finish("victory", str(level.get("success", "全歼敌人")))
				return true
		"kill":
			var all := true
			for n in name_keys:
				if not killed.has(n):
					all = false
			if all:
				_finish("victory", "击毙 " + "、".join(objective.get("names", [])))
				return true
		"capture_or_annihilate":
			if battle.alive_enemies() == 0:
				_finish("victory", "全歼敌人")
				return true
			if not reached.is_empty():
				_finish("victory", "占领目标")
				return true
		"collect":
			if collected >= target_count:
				_finish("victory", "物资搜集完成")
				return true
		"reach_unit":
			for tu in target_units:
				if not is_instance_valid(tu) or not tu.alive:
					continue
				for p in battle.player_units:
					if p == tu or not p.alive:
						continue
					if abs(p.x - tu.x) + abs(p.y - tu.y) <= int(objective.get("radius", 1)):
						_finish("victory", str(level.get("success", "到达目标")))
						return true
		"race":
			# 到达判定在 on_unit_moved 里做；这里不再提前判胜。
			pass
	# 我军全灭
	if battle.alive_players() == 0:
		_finish("defeat", "我军全灭")
		return true
	return false


func ai_goal(u) -> Vector2i:
	"""敌方/友军 AI 的显式目标点；返回 (-1,-1) 表示按最近敌人。"""
	if objective.get("type", "") == "race" and _key(u.unit_name) == rival_key \
			and not targets.is_empty():
		return Vector2i(int(targets[0][0]), int(targets[0][1]))
	if u.target_slot > 0:
		for o in battle.units:
			if o.alive and o.slot == u.target_slot and o.side != u.side:
				return Vector2i(o.x, o.y)
	if u.target_x != 0 or u.target_y != 0:
		if 0 <= u.target_x < battle.map_w and 0 <= u.target_y < battle.map_h:
			return Vector2i(u.target_x, u.target_y)
	return Vector2i(-1, -1)


func _finish(result: String, message: String) -> void:
	if finished:
		return
	finished = true
	battle._finish(result, message)


func _update_status() -> void:
	if finished:
		return
	var t := str(objective.get("type", ""))
	match t:
		"reach":
			status_text = "到达目标 %d/%d" % [reached.size(), target_count]
		"collect":
			status_text = "搜集%s %d/%d" % [objective.get("label", "物资"),
					collected, target_count]
		"survive":
			status_text = "坚持 %d 回合（当前 %d）" % [survive_turns, battle.turn]
		"kill":
			var n := 0
			for k in name_keys:
				if killed.has(k):
					n += 1
			status_text = "击毙 %s %d/%d" % [
				"、".join(objective.get("names", [])), n, name_keys.size()]
		"capture_or_annihilate":
			status_text = "全歼敌人或占领目标"
		"race":
			status_text = "抢先到达山神庙"
		"reach_unit":
			status_text = "接近 " + "、".join(objective.get("units", []))
		_:
			status_text = str(objective.get("label", "全歼敌人"))
