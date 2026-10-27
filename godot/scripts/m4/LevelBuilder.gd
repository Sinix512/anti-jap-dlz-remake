extends RefCounted

## 原版People槽0..39和Fighter槽保持同一身份；合成主角PID映射slot0。
## 不补等级、不增援造人、不改敌方坐标或剧情单位HP。

static func build(m4: Dictionary, m2: Dictionary, idx: int, party: Array,
		_force_party := false, max_party := -1, deploy_pids: Array = []) -> Dictionary:
	# Public builders are also used directly by import/tests, not only Main's loader.
	m4 = preload("res://scripts/battle/StateCodec.gd").integers(m4)
	m2 = preload("res://scripts/battle/StateCodec.gd").integers(m2)
	party = preload("res://scripts/battle/StateCodec.gd").integers(party)
	deploy_pids = preload("res://scripts/battle/StateCodec.gd").integers(deploy_pids)
	var levels: Array = m4.get("levels", [])
	if idx < 0 or idx >= levels.size():
		return {}
	var lv: Dictionary = (levels[idx] as Dictionary).duplicate(true)
	var dep: Dictionary = lv.get("deployment", {})
	var limit := max_party if max_party >= 0 else int(dep.get("max_units", lv.get("max_deploy", 0)))
	# Native direct-entry battles keep the active Fighter template. In L45
	# the raw Special count is17 despite never running party placement.
	if not bool(lv.get("party_deploy",limit not in [0,999])):limit=0
	var excluded: Array = dep.get("excluded_slots", [])
	var forced_slots:Array=dep.get("forced_slots",[])
	var chosen: Array = []
	var explicit_slots:=deploy_pids.size()==32
	var special_by_pid:Dictionary={}
	if explicit_slots:
		for i in range(32):
			if int(deploy_pids[i])!=-999:special_by_pid[int(deploy_pids[i])]=i
	for slot in ([] if explicit_slots else dep.get("forced_slots", [])):
		chosen.append(-100 if int(slot) == 0 else int(slot))
	var ordered: Array = party
	if not deploy_pids.is_empty():
		ordered = []
		for pid in deploy_pids:
			for member in party:
				if int(member.get("pid",-1)) == int(pid): ordered.append(member); break
	for m in ordered:
		var pid := int(m.get("pid", -1))
		var slot := 0 if pid == -100 else pid
		if slot < 0 or slot >= 32:
			continue
		if not (explicit_slots and forced_slots.has(slot)) and (slot in excluded or int(m.get("faction", 0)) != 0):
			continue
		if not deploy_pids.is_empty() and not deploy_pids.has(pid):
			continue
		if not chosen.has(pid) and chosen.size() < limit:
			chosen.append(pid)
	var members := {}
	for m in party:
		members[0 if int(m.get("pid", -1)) == -100 else int(m.get("pid", -1))] = m
	var units: Array = []
	var occupied_slots := {}
	for rec in lv.get("units", []):
		var d: Dictionary = rec.duplicate(true)
		var slot := int(d.get("slot", -1))
		if members.has(slot):
			d = _merge_member(m2, members[slot], d)
		_sync_side(d)
		units.append(d)
		occupied_slots[slot] = true
	if limit > 0 and limit != 999:
		var pos := 0
		for pid in chosen:
			var special_index:int=special_by_pid.get(int(pid),pos)
			var slot := 0 if int(pid) == -100 else int(pid)
			if not members.has(slot):
				continue
			if not occupied_slots.has(slot):
				var deploy: Array = lv.get("deploy", [])
				var point: Dictionary = _pick_deploy(deploy, special_index, lv, units)
				if point.is_empty():
					push_error("原版部署位置周围25格均占用: L%d Special%d"%[idx,special_index])
					continue
				units.append(member_unit(m2, members[slot], point))
				occupied_slots[slot] = true
			pos += 1
	# 未出场槽同样用持久人物更新，保证后续spawn不退回模板等级/装备。
	var pool: Array = []
	for rec in lv.get("slot_pool", []):
		var d: Dictionary = rec.duplicate(true)
		var slot := int(d.get("slot", -1))
		if members.has(slot):
			d = _merge_member(m2, members[slot], d)
		_sync_side(d)
		pool.append(d)
	lv["slot_pool"] = pool
	lv["spawn_pool"] = pool.duplicate(true)
	lv["units"] = units
	lv["players"] = _count_side(units, "player")
	lv["enemies"] = _count_side(units, "enemy")
	return lv


static func _sync_side(d: Dictionary) -> void:
	# The current People.side after party overlay is authoritative. Named slot
	# numbers and pad3e/control must never reclassify unrecruited NPCs as allies.
	if d.has("faction"):
		d["side"] = "player" if int(d["faction"]) == 0 else "enemy"
		d["auto"] = d["side"] == "player" and not bool(d.get("control",true))


static func _merge_member(m2: Dictionary, m: Dictionary, fighter: Dictionary) -> Dictionary:
	var d := member_unit(m2, m, {"x": fighter.get("x", 0), "y": fighter.get("y", 0)})
	for key in ["slot", "direction", "behavior", "target_slot", "target_x", "target_y", "home_x", "home_y", "control", "auto", "protected"]:
		if fighter.has(key):
			d[key] = fighter[key]
	return d


static func member_unit(m2: Dictionary, m: Dictionary, spawn: Dictionary,
		_unused_level_floor: int = 0) -> Dictionary:
	var pid := int(m.get("pid", -1))
	var bz := int(m.get("bingzhong", 0))
	var cls: Dictionary = m2.get("units", {}).get(str(bz), {})
	var lv := int(m.get("level", 1))
	var hp := maxi(1, int(cls.get("tili", 50)) + (lv - 1) * int(cls.get("tili_plus", 0)))
	var slots: Array = (m.get("item_slots", []) as Array).duplicate()
	var valid: Array = m2.get("item_valid", [])
	var atk := 0
	var df := 0
	var movement := 0
	var equip := -1
	for raw in slots:
		var iid := int(raw) - 1
		if iid < 81 or iid >= valid.size() or bz >= valid[iid].size() or int(valid[iid][bz]) == 0:
			continue
		var item: Dictionary = m2.get("items", {}).get(str(iid), {})
		atk = maxi(atk, int(item.get("para3", 0)))
		df = maxi(df, int(item.get("para4", 0)))
		movement = maxi(movement, int(item.get("para1", 0)))
		equip = iid
	return {"pid": pid, "slot": 0 if pid == -100 else pid,
		"hero": pid == -100, "side": "player" if int(m.get("faction", 0)) == 0 else "enemy",
		"faction": int(m.get("faction", 0)), "name": str(m.get("name", "游击队员")),
		"key": _key(m.get("name", "")), "unit_name": str(cls.get("name", "")),
		"bingzhong": bz, "level": lv, "wuli": int(m.get("wuli", 0)), "zhili": int(m.get("zhili", 0)),
		"xp": int(m.get("xp", 0)), "skills": (m.get("skills", {}) as Dictionary).duplicate(true),
		"skill_counts": (m.get("skills", {}) as Dictionary).duplicate(true),
		"attack_count": int(m.get("attack_count", 1)), "item_slots": slots,
		"mine_slots": (m.get("mine_slots", []) as Array).duplicate(),
		"equip": equip, "equip_name": str(m2.get("items", {}).get(str(equip), {}).get("name", "")),
		"attack_bonus": atk, "defense_bonus": df,
		"hp": hp, "max_hp": hp, "raw_hp": hp, "hp_source": "formula",
		"x": int(spawn.get("x", 0)), "y": int(spawn.get("y", 0)), "direction": int(spawn.get("direction",1)),
		"behavior": 1, "target_slot": 0, "target_x": 0, "target_y": 0,
		"face": int(m.get("face", 0)), "face_png": str(m.get("face_png", "")),
		"army_png": "res://assets/army/army_%03d.png" % int(cls.get("img_index", 0)),
		"select": int(cls.get("select", 1)), "apply": int(cls.get("apply", 0)),
		"move": int(cls.get("yidong", 4)) + movement,
		"gongji": int(cls.get("gongji", 0)), "fangyu": int(cls.get("fangyu", 0)),
		"tili": int(cls.get("tili", 50)), "tili_plus": int(cls.get("tili_plus", 0)),
		"is_boss": false, "protected": false, "control": true, "auto": false}


static func _pick_deploy(deploy: Array, i: int, lv: Dictionary, units: Array) -> Dictionary:
	var w := int(lv.get("map", {}).get("width", 1))
	var h := int(lv.get("map", {}).get("height", 1))
	var used := {}
	for u in units:
		used[Vector2i(int(u.get("x", -1)), int(u.get("y", -1)))] = true
	if i >= deploy.size(): return {}
	var p: Array = deploy[i]
	var specials: Array = lv.get("specials",[])
	var direction := int(specials[i].get("direction",1)) if i<specials.size() else 1
	# 43B3E2/447390: own Special and exact 25-offset order, not other people's
	# positions and not a terrain-aware/global-search convenience fallback.
	var tile := preload("res://scripts/battle/OriginalPlacement.gd").find_cell(Vector2i(int(p[0]),int(p[1])),Vector2i(w,h),used)
	if tile.x >= 0:return {"x":tile.x,"y":tile.y,"direction":direction}
	return {}


static func _has_side(units: Array, side: String) -> bool:
	for u in units:
		if str(u.get("side", "")) == side:
			return true
	return false


static func _count_side(units: Array, side: String) -> int:
	var n := 0
	for u in units:
		if str(u.get("side", "")) == side:
			n += 1
	return n


static func _key(text: String) -> String:
	return str(text).replace("\u3000", "").replace(" ", "")
