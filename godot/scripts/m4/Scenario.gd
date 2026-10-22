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
	if battle != null:
		battle.emit_story_event("start", {})
	# 赛跑关：柳忻获得兔子速度，龟田按乌龟速度走。原版赛跑关的脚本
	# 不在 FIGHT.DAT 里，这里是可玩性补足，不是已确认数值。
	if objective.get("type", "") == "race":
		for u in battle.player_units:
			if _key(u.unit_name) in unit_keys:
				u.move += 8
		for e in battle.enemy_units:
			if _key(e.unit_name) == rival_key:
				e.move = maxi(1, int(e.move) - 2)
			else:
				# 赛跑关只保留龟田作为对手；其他静态敌军在原版脚本里并未
				# 参与赛跑，当前数据无法还原其脚本，直接退场避免堵死路线。
				e.alive = false
				e.visible = false
				e.behavior = 0
				e.target_slot = 0
				e.target_x = 0
				e.target_y = 0
				e.status_stun = 999
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
	if battle != null:
		battle.emit_story_event("turn", {"turn": turn})
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
			if battle != null:
				battle.emit_story_event("reach", {"tile": [t.x, t.y]})
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
				if battle != null:
					battle.emit_story_event("reach", {"unit": tu.unit_name})
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
	if battle != null:
		battle.emit_story_event("unit_died", {"key": k, "name": u.unit_name})
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
		if bool(level.get("protect_all", false)):
			var any_alive := false
			for p in battle.player_units:
				if p.alive and _key(p.unit_name) in protected_keys:
					any_alive = true
					break
			if not any_alive:
				_finish("defeat", "五壮士全部阵亡")
				return
		else:
			_finish("defeat", "%s 阵亡" % u.unit_name)
			return
	_update_status()


func on_chest(u, chest: Dictionary) -> void:
	chests_opened += 1
	var item := str(chest.get("item_name", "物资"))
	if battle != null:
		battle.emit_story_event("chest", {"item": item, "x": int(chest.get("x", 0)),
				"y": int(chest.get("y", 0))})
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


func bot_goal(u) -> Dictionary:
	"""给无头全通 bot 的目标：返回 {kind:"tile"|"unit"|"hold", tile, unit}。"""
	var t := str(objective.get("type", "annihilate"))
	if t == "reach":
		var best_tile := Vector2i(-1, -1)
		var bestd := 999999
		for i in range(targets.size()):
			if reached.has(i):
				continue
			var tt: Array = targets[i]
			var d: int = absi(int(tt[0]) - u.x) + absi(int(tt[1]) - u.y)
			if d < bestd:
				bestd = d
				best_tile = Vector2i(int(tt[0]), int(tt[1]))
		if best_tile.x >= 0:
			return {"kind": "tile", "tile": best_tile}
	if t == "capture_or_annihilate":
		if not targets.is_empty() and reached.is_empty():
			var tt0: Array = targets[0]
			return {"kind": "tile", "tile": Vector2i(int(tt0[0]), int(tt0[1]))}
	if t == "collect":
		var bestc := Vector2i(-1, -1)
		var bestcd := 999999
		for i in range(targets.size()):
			if searched.has(i):
				continue
			var tt: Array = targets[i]
			var d: int = absi(int(tt[0]) - u.x) + absi(int(tt[1]) - u.y)
			if d < bestcd:
				bestcd = d
				bestc = Vector2i(int(tt[0]), int(tt[1]))
		if bestc.x >= 0:
			return {"kind": "tile", "tile": bestc}
	if t == "kill":
		for e in battle.enemy_units:
			if e.alive and _key(e.unit_name) in name_keys:
				return {"kind": "unit", "unit": e}
	if t == "race" and _key(u.unit_name) in unit_keys:
		if not targets.is_empty():
			var tr: Array = targets[0]
			return {"kind": "tile", "tile": Vector2i(int(tr[0]), int(tr[1]))}
	if t == "reach_unit":
		for tu in target_units:
			if is_instance_valid(tu) and tu.alive and tu != u:
				return {"kind": "unit", "unit": tu}
	# 默认：最近敌人
	var best_enemy: Node2D = null
	var bd := 999999
	for e in battle.enemy_units:
		if not e.alive:
			continue
		var d: int = absi(e.x - u.x) + absi(e.y - u.y)
		if d < bd:
			bd = d
			best_enemy = e
	if best_enemy != null:
		return {"kind": "unit", "unit": best_enemy}
	return {"kind": "hold", "tile": Vector2i(u.x, u.y)}


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
		if u.target_x >= 0 and u.target_x < battle.map_w 				and u.target_y >= 0 and u.target_y < battle.map_h:
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
