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
# 0x446510 逐关触发器：数据在 m4.json，逻辑只在这里解释一次。
var trigger_rules: Array = []
var trigger_flags: Dictionary = {}
var trigger_done: Dictionary = {}
var trigger_texts: Dictionary = {}
var trigger_authoritative := false
# 仅无头 bot 验收使用的旧目标胜利捷径；人类游玩仍只认触发器。
var bot_objective_fallback := false
var protagonist = null
var pending_choice: Dictionary = {}
var _choice_rng := RandomNumberGenerator.new()
var _last_dead_side := ""
var _last_dead_slot := -1
# AI behavior 运行时轨迹：手动试玩/无头回归都可读取。
var ai_log: Array[String] = []
var ai_trace := false


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
	var trig: Dictionary = lv.get("triggers", {})
	trigger_rules = (trig.get("rules", []) as Array).duplicate(true)
	trigger_texts = (trig.get("texts", {}) as Dictionary).duplicate(true)
	trigger_authoritative = bool(trig.get("authoritative", false))
	trigger_flags.clear()
	trigger_done.clear()
	pending_choice.clear()
	protagonist = null
	for u in battle.units:
		if is_instance_valid(u) and str(u.side) == "player" and int(u.slot) < 0:
			protagonist = u
			break
	if protagonist == null:
		for u in battle.units:
			if is_instance_valid(u) and str(u.side) == "player":
				protagonist = u
				break
	_choice_rng.randomize()


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
	on_tick()


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
	if (not trigger_authoritative or bot_objective_fallback) and objective.get("type", "") == "survive" \
			and survive_turns > 0 and turn > survive_turns:
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
	if u.side == "player" and objective.get("type", "") in ["reach", "capture_or_annihilate"]:
		for i in range(targets.size()):
			var tt: Array = targets[i]
			if int(tt[0]) == t.x and int(tt[1]) == t.y:
				reached[i] = true
		if (not trigger_authoritative or bot_objective_fallback) and objective.get("type", "") == "capture_or_annihilate":
			if not reached.is_empty():
				_finish("victory", "占领目标")
				return
		elif (not trigger_authoritative or bot_objective_fallback) and reached.size() >= target_count:
			if battle != null:
				battle.emit_story_event("reach", {"tile": [t.x, t.y]})
			_finish("victory", str(level.get("success", "到达目标")))
			return
	if u.side == "player" and objective.get("type", "") == "collect":
		for i in range(targets.size()):
			var tt: Array = targets[i]
			if int(tt[0]) == t.x and int(tt[1]) == t.y and not searched.has(i):
				searched[i] = true
				collected += 1
				battle._log("搜集到%s %d/%d" % [
					objective.get("label", "物资"), collected, target_count])
		if (not trigger_authoritative or bot_objective_fallback) and collected >= target_count:
			_finish("victory", "物资搜集完成")
			return
	if u.side == "player" and objective.get("type", "") == "reach_unit":
		for tu in target_units:
			if not is_instance_valid(tu) or not tu.alive:
				continue
			if tu == u:
				continue
			var d: int = abs(tu.x - u.x) + abs(tu.y - u.y)
			var radius := int(objective.get("radius", 1))
			if d <= radius and (not trigger_authoritative or bot_objective_fallback):
				if battle != null:
					battle.emit_story_event("reach", {"unit": tu.unit_name})
				_finish("victory", "已接近 %s" % tu.unit_name)
				return
	if objective.get("type", "") == "race":
		for i in range(targets.size()):
			var tt: Array = targets[i]
			if int(tt[0]) == t.x and int(tt[1]) == t.y:
				race_winner = _key(u.unit_name)
				if not trigger_authoritative or bot_objective_fallback:
					if u.side == "player":
						_finish("victory", str(level.get("success", "抢先到达")))
					else:
						_finish("defeat", "敌人抢先到达山神庙")
				return
	# 原版每帧都跑触发器；复刻在每一步移动后也跑一次，避免单位只是
	# 路过目标格、tick 时已经离开而漏掉占格事件。
	if not finished:
		_run_triggers("tick")
	if finished:
		return
	_update_status()


func on_unit_died(u) -> void:
	if finished or u == null:
		return
	_last_dead_side = str(u.side)
	_last_dead_slot = int(u.slot)
	_run_triggers("death")
	if finished:
		return
	var k := _key(u.unit_name)
	if battle != null:
		battle.emit_story_event("unit_died", {"key": k, "name": u.unit_name})
	if u.side == "enemy":
		killed[k] = true
		if objective.get("type", "") == "kill" and (not trigger_authoritative or bot_objective_fallback):
			var all := true
			for n in name_keys:
				if not killed.has(n):
					all = false
			if all:
				_finish("victory", "击毙 " + "、".join(objective.get("names", [])))
				return
	if u.side == "player" and k in protected_keys and (not trigger_authoritative or bot_objective_fallback):
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
	# 有 result 动作的关卡由 0x446510 触发器权威判胜；旧 objective 只作
	# HUD 提示和 bot 导航，不再抢在触发器前结束战斗。
	if not trigger_authoritative or bot_objective_fallback:
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


func objective_satisfied() -> bool:
	var t := str(objective.get("type", "annihilate"))
	match t:
		"reach":
			return reached.size() >= target_count
		"capture_or_annihilate":
			return not reached.is_empty() or battle.alive_enemies() == 0
		"collect":
			return collected >= target_count
		"kill":
			for n in name_keys:
				if not killed.has(n):
					return false
			return not name_keys.is_empty()
		"reach_unit":
			for tu in target_units:
				if not is_instance_valid(tu) or not tu.alive:
					continue
				if protagonist != null and is_instance_valid(protagonist) \
						and protagonist.alive:
					if protagonist != tu and absi(protagonist.x - tu.x) \
							+ absi(protagonist.y - tu.y) <= int(objective.get("radius", 1)):
						return true
				else:
					for p in battle.player_units:
						if p != tu and p.alive \
								and absi(p.x - tu.x) + absi(p.y - tu.y) <= int(objective.get("radius", 1)):
							return true
			return false
		"survive":
			return int(battle.turn) > survive_turns
		"race":
			return race_winner != ""
		_:
			return battle.alive_enemies() == 0


func _nearest_enemy_goal(u) -> Dictionary:
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


func _closest_player_to(t: Vector2i):
	var best = null
	var bd := 999999
	for p in battle.player_units:
		if not p.alive or p.auto:
			continue
		var d: int = absi(p.x - t.x) + absi(p.y - t.y)
		if d < bd:
			bd = d
			best = p
	return best


func bot_trigger_tile() -> Vector2i:
	"""从“胜利规则”里找第一个尚未满足的占格/到达条件。"""
	for r in trigger_rules:
		var is_win := false
		for a in (r as Dictionary).get("then", []):
			if str((a as Dictionary).get("result", "")) == "victory":
				is_win = true
				break
		if not is_win:
			continue
		var t := _positional_gap((r as Dictionary).get("when", {}))
		if t.x >= 0:
			return t
	return Vector2i(-1, -1)


func _positional_gap(c) -> Vector2i:
	if not (c is Dictionary):
		return Vector2i(-1, -1)
	var d: Dictionary = c
	if d.has("all"):
		for x in d["all"]:
			if _cond(x):
				continue
			var t := _positional_gap(x)
			if t.x >= 0:
				return t
		return Vector2i(-1, -1)
	if d.has("any") or d.has("not"):
		return Vector2i(-1, -1)
	if d.has("map_cell_occupied") and not _cond(d):
		var q: Dictionary = d["map_cell_occupied"]
		return Vector2i(int(q["x"]), int(q["y"]))
	if d.has("slot_pos_cell_occupied") and not _cond(d):
		return _slot_pos(int(d["slot_pos_cell_occupied"]["slot"]))
	if d.has("unit_dest") and not _cond(d):
		var q: Dictionary = d["unit_dest"]
		return Vector2i(int(q["x"]), int(q["y"]))
	return Vector2i(-1, -1)


func bot_goal(u) -> Dictionary:
	"""给无头全通 bot 的目标：返回 {kind:"tile"|"unit"|"hold", tile, unit}。"""
	# 触发器权威关：先满足旧目标（它已对齐触发器坐标），之后按触发器
	# 胜利条件找一个占格点；其余单位继续打最近敌人。
	if trigger_authoritative and not bot_objective_fallback and objective_satisfied():
		var trig_tile := bot_trigger_tile()
		if trig_tile.x >= 0 and _closest_player_to(trig_tile) == u:
			return {"kind": "tile", "tile": trig_tile}
		return _nearest_enemy_goal(u)
	var t := str(objective.get("type", "annihilate"))
	if t in ["reach", "collect"] and not unit_keys.is_empty() \
			and not (_key(u.unit_name) in unit_keys):
		return _nearest_enemy_goal(u)
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
		if protagonist != null and u != protagonist:
			return _nearest_enemy_goal(u)
		for tu in target_units:
			if is_instance_valid(tu) and tu.alive and tu != u:
				return {"kind": "unit", "unit": tu}
	return _nearest_enemy_goal(u)


func _valid_ai_tile(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < int(battle.map_w) \
			and t.y >= 0 and t.y < int(battle.map_h)


func _set_behavior(u, value: int, reason: String) -> void:
	if u == null or int(u.behavior) == value:
		return
	var old := int(u.behavior)
	u.behavior = value
	var line := "L%s slot %d %s behavior %d->%d (%s)" % [
		str(level.get("index", "?")), int(u.slot), str(u.unit_name),
		old, value, reason]
	ai_log.append(line)
	if ai_log.size() > 240:
		ai_log.pop_front()
	if ai_trace and battle != null:
		battle._log("AI " + line)


func _at_exact_target(u) -> bool:
	var t := Vector2i(int(u.target_x), int(u.target_y))
	return _valid_ai_tile(t) and int(u.x) == t.x and int(u.y) == t.y


func _at_ai_target(u, exact_only := false) -> bool:
	if _at_exact_target(u):
		return true
	if exact_only:
		return false
	var t := Vector2i(int(u.target_x), int(u.target_y))
	if not _valid_ai_tile(t):
		return false
	# 目标格被别的单位占住时，停在相邻格也算到位；否则 behavior 4/5
	# 会在目标旁反复找空位，永远不切守卫/待机。
	if absi(int(u.x) - t.x) + absi(int(u.y) - t.y) == 1:
		return battle._is_occupied(t, u)
	return false


func _swap_patrol(u) -> void:
	var tx := int(u.target_x)
	var ty := int(u.target_y)
	u.target_x = int(u.home_x)
	u.target_y = int(u.home_y)
	u.home_x = tx
	u.home_y = ty
	ai_log.append("L%s slot %d %s patrol -> (%d,%d)" % [
		str(level.get("index", "?")), int(u.slot), str(u.unit_name),
		int(u.target_x), int(u.target_y)])
	if ai_log.size() > 240:
		ai_log.pop_front()
	if ai_trace and battle != null:
		battle._log("AI patrol -> (%d,%d)" % [int(u.target_x), int(u.target_y)])


func ai_target(u):
	"""behavior 2/3/6 的指定槽目标；目标消失时按原版切行为。"""
	if u == null:
		return null
	var b := int(u.behavior)
	if b != 2 and b != 3 and b != 6:
		return null
	var t = _slot_unit(int(u.target_slot))
	if t != null and (b == 3 or t.side != u.side):
		return t
	_set_behavior(u, 7 if b == 3 else 1, "target_slot_%d_gone" % int(u.target_slot))
	return null


func ai_prepare(u) -> bool:
	"""回合开始按 Fighter.behavior 做原版切换；返回 true 表示本回合已消耗。"""
	if u == null:
		return false
	var b := int(u.behavior)
	if b == 2 or b == 3 or b == 6:
		var old := int(u.behavior)
		ai_target(u)
		return int(u.behavior) != old
	if b == 4 or b == 5:
		if _at_ai_target(u):
			_set_behavior(u, 7 if b == 4 else 0, "reached_target")
			return true
		if not _valid_ai_tile(Vector2i(int(u.target_x), int(u.target_y))):
			_set_behavior(u, 1, "invalid_target")
			return true
		return false
	if b == 8 and _at_exact_target(u):
		_swap_patrol(u)
		return true
	return false


func ai_after_move(u) -> bool:
	"""移动途中到达目标时立即切换，避免越过目标继续走。"""
	if u == null:
		return false
	var b := int(u.behavior)
	if b == 4 and _at_exact_target(u):
		_set_behavior(u, 7, "reached_target_move")
		return true
	if b == 5 and _at_exact_target(u):
		_set_behavior(u, 0, "reached_target_move")
		return true
	if b == 8 and _at_exact_target(u):
		_swap_patrol(u)
		return true
	return false


func ai_goal(u) -> Vector2i:
	"""按 Fighter.behavior 返回显式目标点；(-1,-1) 表示按最近敌人。"""
	if objective.get("type", "") == "race" and _key(u.unit_name) == rival_key \
			and not targets.is_empty():
		return Vector2i(int(targets[0][0]), int(targets[0][1]))
	var b := int(u.behavior)
	if b == 4 or b == 5 or b == 8:
		var t := Vector2i(int(u.target_x), int(u.target_y))
		if _valid_ai_tile(t):
			return t
		if b != 8:
			_set_behavior(u, 1, "invalid_target")
		return Vector2i(-1, -1)
	if b == 2 or b == 3 or b == 6:
		var target = ai_target(u)
		if target != null:
			return Vector2i(int(target.x), int(target.y))
		return Vector2i(-1, -1)
	# behavior 1 的出场数据大量带有 +0x30/+0x34 集结点（L37/L39/L44/L45）；
	# 非零时以集结点为持久目标，射程内有敌人就攻击；0,0 视为无集结点，
	# 此时才追最近敌人。
	if b == 1:
		var t1 := Vector2i(int(u.target_x), int(u.target_y))
		if (t1.x != 0 or t1.y != 0) and _valid_ai_tile(t1):
			return t1
		return Vector2i(-1, -1)
	# behavior 0/7/9/12/13 走守卫分支，不使用 target_x/y。
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- triggers
# 0x446510 的逐关函数被翻译成 m4.json 的 rules；这里只做通用解释。
# 规则顺序重要：原版函数先判失败，再处理事件，最后判胜利。

func on_tick() -> void:
	if finished or not started or not pending_choice.is_empty():
		return
	_run_triggers("tick")


func _run_triggers(event: String) -> void:
	if not pending_choice.is_empty():
		return
	for r in trigger_rules:
		if finished:
			return
		var rule: Dictionary = r
		if str(rule.get("on", "tick")) != event:
			continue
		var rid := str(rule.get("id", ""))
		if bool(rule.get("once", false)) and trigger_done.has(rid):
			continue
		if not _cond(rule.get("when", {})):
			continue
		if bool(rule.get("once", false)):
			trigger_done[rid] = true
		_apply(rule.get("then", []))
		if finished or not pending_choice.is_empty():
			return


func _cond(c) -> bool:
	if not (c is Dictionary):
		return true
	var d: Dictionary = c
	if d.has("all"):
		for x in d["all"]:
			if not _cond(x):
				return false
		return true
	if d.has("any"):
		for x in d["any"]:
			if _cond(x):
				return true
		return false
	if d.has("not"):
		return not _cond(d["not"])
	if d.has("unit_stage"):
		var q: Dictionary = d["unit_stage"]
		return _slot_stage(int(q["slot"])) == int(q.get("eq", 0))
	if d.has("unit_dest"):
		var q: Dictionary = d["unit_dest"]
		return _slot_pos(int(q["slot"])) == Vector2i(int(q["x"]), int(q["y"]))
	if d.has("unit_dest_area"):
		var q: Dictionary = d["unit_dest_area"]
		var p := _slot_pos(int(q["slot"]))
		return p.x >= int(q["x"]) and p.x < int(q["x"]) + int(q["w"]) \
				and p.y >= int(q["y"]) and p.y < int(q["y"]) + int(q["h"])
	if d.has("adjacent"):
		var q: Dictionary = d["adjacent"]
		var a := _slot_pos(int(q["a"]))
		var b := _slot_pos(int(q["b"]))
		return absi(a.x - b.x) + absi(a.y - b.y) == 1
	if d.has("flag"):
		var q: Dictionary = d["flag"]
		var v := int(trigger_flags.get(str(q["addr"]), 0))
		if q.has("eq") and v != int(q["eq"]):
			return false
		if q.has("neq") and v == int(q["neq"]):
			return false
		if q.has("gte") and not (v >= int(q["gte"])):
			return false
		return true
	if d.has("global"):
		var q: Dictionary = d["global"]
		var v := int(trigger_flags.get(str(q["addr"]), 0))
		if q.has("eq") and v != int(q["eq"]):
			return false
		if q.has("neq") and v == int(q["neq"]):
			return false
		return true
	if d.has("turn_gt_flag"):
		var q: Dictionary = d["turn_gt_flag"]
		return int(battle.turn) > int(trigger_flags.get(str(q["addr"]), 0)) + int(q.get("add", 0))
	if d.has("cell_region_gt"):
		var q: Dictionary = d["cell_region_gt"]
		for yy in range(int(q["y"]), int(q["y"]) + int(q["h"])):
			for xx in range(int(q["x"]), int(q["x"]) + int(q["w"])):
				if _cell_code(xx, yy) > int(q.get("count", 1)):
					return true
		return false
	if d.has("slot_pos_cell_occupied"):
		var q: Dictionary = d["slot_pos_cell_occupied"]
		var p := _slot_pos(int(q["slot"]))
		return _cell_code(p.x, p.y) == int(q.get("eq", 1))
	if d.has("flag_bit"):
		var q: Dictionary = d["flag_bit"]
		var v := int(trigger_flags.get(str(q["addr"]), 0))
		var on := (v & int(q["mask"])) != 0
		return on == bool(q.get("set", false))
	if d.has("all_units_dead"):
		var want := bool(d["all_units_dead"])
		return (battle.alive_enemies() == 0) == want
	if d.has("map_cell_occupied"):
		var q: Dictionary = d["map_cell_occupied"]
		var n := _cell_code(int(q["x"]), int(q["y"]))
		return n == int(q.get("eq", 1))
	if d.has("turn"):
		var q: Dictionary = d["turn"]
		if q.has("eq") and int(battle.turn) != int(q["eq"]):
			return false
		if q.has("gt") and not (int(battle.turn) > int(q["gt"])):
			return false
		if q.has("le") and not (int(battle.turn) <= int(q["le"])):
			return false
		return true
	if d.has("unit_count"):
		var q: Dictionary = d["unit_count"]
		var n := _unit_count(q)
		if q.has("eq") and n != int(q["eq"]):
			return false
		if q.has("lt") and not (n < int(q["lt"])):
			return false
		if q.has("gte") and not (n >= int(q["gte"])):
			return false
		return true
	if d.has("any_player_death"):
		return _last_dead_side == "player"
	if d.has("unit_dead"):
		return _last_dead_slot == int(d["unit_dead"])
	return true


func _slot_unit(slot: int):
	if battle == null:
		return null
	# 0 号是原版 Fighter[0]（主角/队长）。不能用“第一个还活着的我方”
	# 兜底，否则主角阵亡后 stage(0) 会被下一个人顶成 1。
	if slot == 0 and protagonist != null:
		if is_instance_valid(protagonist) and protagonist.alive:
			return protagonist
		return null
	for u in battle.units:
		if is_instance_valid(u) and u.alive and int(u.slot) == slot:
			return u
	# 0..39 是 PEOPLE.DAT 名册槽；复刻队伍用 pid 表示同一角色。
	if slot < 40:
		for u in battle.units:
			if is_instance_valid(u) and u.alive and int(u.pid) == slot:
				return u
	# 复刻队伍不一定带 pid 0；原版 Fighter[0] 是“主角位”，这里落到队长。
	# 优先部署队伍（slot=-1），避免把固定剧情 NPC 当成主角。
	if slot == 0:
		for u in battle.units:
			if is_instance_valid(u) and u.alive and str(u.side) == "player" \
					and int(u.slot) < 0:
				return u
		for u in battle.units:
			if is_instance_valid(u) and u.alive and str(u.side) == "player":
				return u
	return null


func _slot_stage(slot: int) -> int:
	return 1 if _slot_unit(slot) != null else 0


func _slot_pos(slot: int) -> Vector2i:
	var u = _slot_unit(slot)
	if u != null:
		return Vector2i(u.x, u.y)
	# 未出场的 Fighter 仍然保留 dest 坐标，原版触发器用它当地图目标点。
	for key in ["spawn_pool", "reserves", "units"]:
		for rec in level.get(key, []):
			if int(rec.get("slot", -1)) == slot:
				return Vector2i(int(rec.get("x", -1)), int(rec.get("y", -1)))
	return Vector2i(-1, -1)


func _cell_code(x: int, y: int) -> int:
	# 原版 0x57BF10 每格 2 字节，低字节 0=空 / 1=我方 / >1=敌方。
	# L12/L26 用 ==1 判定“我方占住”，L38/L42 用 >1 判定“敌军进入出口”。
	var enemy := false
	for u in battle.units:
		if is_instance_valid(u) and u.alive and int(u.x) == x and int(u.y) == y:
			if str(u.side) == "player":
				return 1
			enemy = true
	return 2 if enemy else 0


func _unit_count(q: Dictionary) -> int:
	var n := 0
	if q.has("slots"):
		for s in q["slots"]:
			if _slot_stage(int(s)) != 0:
				n += 1
		return n
	var lo := int(q.get("from", 0))
	var hi := int(q.get("to", 128))
	for u in battle.units:
		if is_instance_valid(u) and u.alive and int(u.slot) >= lo and int(u.slot) < hi:
			n += 1
	return n


func _apply(actions) -> void:
	for a in actions:
		if finished:
			return
		if not (a is Dictionary):
			continue
		var act: Dictionary = a
		if act.has("message"):
			var expr := str(act["message"])
			var record := int(trigger_texts.get(expr, -1))
			if battle != null:
				battle.trigger_message(record, expr)
		elif act.has("flag_set"):
			trigger_flags[str(act["flag_set"]["addr"])] = int(act["flag_set"].get("value", 1))
		elif act.has("flag_or"):
			var addr := str(act["flag_or"]["addr"])
			trigger_flags[addr] = int(trigger_flags.get(addr, 0)) | int(act["flag_or"]["mask"])
		elif act.has("spawn"):
			var su = battle.spawn_slot(int(act["spawn"]))
			if su != null and str(su.side) == "player":
				if _key(su.unit_name) in protected_keys:
					su.protected = true
				if _key(su.unit_name) in unit_keys and not target_units.has(su):
					target_units.append(su)
		elif act.has("spawn_range"):
			for s in range(int(act["spawn_range"]["from"]), int(act["spawn_range"]["to"])):
				battle.spawn_slot(s)
		elif act.has("remove"):
			battle.remove_slot(int(act["remove"]))
		elif act.has("remove_range"):
			var q: Dictionary = act["remove_range"]
			for s in range(int(q["from"]), int(q["to"])):
				if bool(q.get("alive_only", false)) and _slot_stage(s) == 0:
					continue
				battle.remove_slot(s)
		elif act.has("set_field"):
			var q: Dictionary = act["set_field"]
			battle.set_slot_field(int(q["slot"]), str(q["field"]), int(q["value"]))
		elif act.has("set_field_range"):
			var q: Dictionary = act["set_field_range"]
			for s in range(int(q["from"]), int(q["to"])):
				battle.set_slot_field(s, str(q["field"]), int(q["value"]))
		elif act.has("random_slot_dest"):
			var rq: Dictionary = act["random_slot_dest"]
			var opts: Array = rq.get("options", [])
			if not opts.is_empty():
				var pick: Array = opts[_choice_rng.randi_range(0, opts.size() - 1)]
				var slot := int(rq["slot"])
				battle.set_slot_field(slot, "x", int(pick[0]))
				battle.set_slot_field(slot, "y", int(pick[1]))
				battle.set_slot_field(slot, "direction", int(rq.get("direction", 1)))
		elif act.has("party_morale"):
			battle.add_party_morale(int(act["party_morale"]))
		elif act.has("recruit"):
			battle.recruit_slots(act["recruit"])
		elif act.has("choice"):
			var cq: Dictionary = act["choice"]
			var labels: Array = []
			for o in cq.get("options", []):
				labels.append(str((o as Dictionary).get("label", "?")))
			pending_choice = (cq as Dictionary).duplicate(true)
			if battle != null:
				battle.emit_story_event("trigger_choice",
						{"prompt": str(cq.get("prompt", "")), "options": labels})
				if bool(battle.fast_sim):
					resolve_choice(int(cq.get("default", 0)))
				else:
					battle.show_trigger_choice(self, str(cq.get("prompt", "")), labels)
			return
		elif act.has("score"):
			battle.stats["score_bonus"] = int(battle.stats.get("score_bonus", 0)) + int(act["score"])
		elif act.has("global_set"):
			trigger_flags[str(act["global_set"]["addr"])] = int(act["global_set"].get("value", 0))
		elif act.has("global_add"):
			var addr := str(act["global_add"]["addr"])
			trigger_flags[addr] = int(trigger_flags.get(addr, 0)) + int(act["global_add"].get("value", 1))
		elif act.has("flag_set_from_turn"):
			var tq: Dictionary = act["flag_set_from_turn"]
			trigger_flags[str(tq["addr"])] = int(battle.turn) + int(tq.get("add", 0))
		elif act.has("set_map_cell_at_slot"):
			# 原版写 map cell 数组；复刻用单位占位/剧情旗标等价表示。
			trigger_flags["cell_%d" % int(act["set_map_cell_at_slot"]["slot"])] = \
					int(act["set_map_cell_at_slot"].get("value", 1))
		elif act.has("success_text"):
			level["success"] = str(act["success_text"])
		elif act.has("failure_text"):
			level["failure"] = str(act["failure_text"])
		elif act.has("result"):
			_finish(str(act["result"]), str(level.get(
					"success" if str(act["result"]) == "victory" else "failure", "")))
			return


func resolve_choice(index: int) -> void:
	if pending_choice.is_empty():
		return
	var cq: Dictionary = pending_choice
	pending_choice = {}
	var opts: Array = cq.get("options", [])
	if opts.is_empty():
		return
	var idx := clampi(index, 0, opts.size() - 1)
	var picked: Dictionary = opts[idx]
	_apply(picked.get("then", []))
	_update_status()


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
