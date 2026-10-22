extends RefCounted

## M4 关卡装载：把战役队伍放进原版关卡数据。
## 固定剧情单位来自 m4.json；队伍按 deploy 点补入；不改变关卡数据本身。


static func build(m4: Dictionary, m2: Dictionary, idx: int, party: Array,
		force_party := false, max_party := -1) -> Dictionary:
	var levels: Array = m4.get("levels", [])
	if idx < 0 or idx >= levels.size():
		return {}
	var lv: Dictionary = (levels[idx] as Dictionary).duplicate(true)
	var units: Array = []
	for u in lv.get("units", []):
		var d: Dictionary = (u as Dictionary).duplicate(true)
		d["side"] = str(d.get("side", "enemy"))
		units.append(d)
	var deploy: Array = []
	for p in lv.get("deploy", []):
		deploy.append([int(p[0]), int(p[1])])
	var allow_party := force_party or bool(lv.get("party_deploy", false))
	var limit := max_party if max_party >= 0 else int(lv.get("max_deploy", 10))
	if allow_party and not party.is_empty():
		var fixed_keys := {}
		for u in units:
			if str(u.get("side", "")) == "player":
				fixed_keys[str(u.get("key", _key(u.get("name", ""))))] = true
		var added := 0
		for m in party:
			if added >= limit:
				break
			if int(m.get("hp", 0)) <= 0:
				continue
			var k := _key(m.get("name", ""))
			if fixed_keys.has(k):
				continue
			var spawn := _pick_deploy(deploy, added, lv, units)
			# 战役等级同步：低等级队伍在后期主线会被原版高等级敌军压死。
			# 这是可玩性补足，不改变存档等级；隐藏/彩蛋关不启用。
			var floor := mini(60, 5 + idx * 2) if idx < 36 else 0
			var d := member_unit(m2, m, spawn, floor)
			units.append(d)
			fixed_keys[k] = true
			added += 1
	# 兜底：没有任何玩家单位时，放一个队伍成员到部署点/地图边缘
	if not _has_side(units, "player") and not party.is_empty():
		var spawn := _pick_deploy(deploy, 0, lv, units)
		var floor0 := mini(60, 5 + idx * 2) if idx < 36 else 0
		units.append(member_unit(m2, party[0], spawn, floor0))
	lv["units"] = units
	lv["players"] = _count_side(units, "player")
	lv["enemies"] = _count_side(units, "enemy")
	return lv


static func member_unit(m2: Dictionary, m: Dictionary, spawn: Dictionary,
		level_floor: int = 0) -> Dictionary:
	var people: Array = m2.get("people", [])
	var pid := int(m.get("pid", -1))
	var p: Dictionary = people[pid] if pid >= 0 and pid < people.size() else {}
	var u: Dictionary = p.get("unit", {})
	var lv := maxi(int(m.get("level", 1)), int(level_floor))
	var max_hp := int(m.get("max_hp", max(1, int(u.get("tili", 50)))))
	if lv > int(m.get("level", 1)):
		max_hp = max(1, int(u.get("tili", 50)) + (lv - 1) * int(u.get("tili_plus", 0)))
	var equip_id := int(m.get("equip", -1))
	var equip_item: Dictionary = {}
	var equip_bonus := {"attack": 0, "defense": 0}
	if equip_id >= 0:
		equip_item = (m2.get("items", {}) as Dictionary).get(str(equip_id), {})
		if not equip_item.is_empty():
			equip_bonus = {"attack": max(0, int(equip_item.get("para3", 0))),
					"defense": max(0, int(equip_item.get("para4", 0)))}
	return {
		"pid": pid,
		"slot": -1,
		"side": "player",
		"name": str(m.get("name", "游击队员")),
		"key": _key(m.get("name", "")),
		"unit_name": str(m.get("unit_name", u.get("name", ""))),
		"bingzhong": int(m.get("bingzhong", p.get("bingzhong", 0))),
		"level": lv,
		"wuli": int(m.get("wuli", 0)),
		"zhili": int(m.get("zhili", 0)),
		"xp": int(m.get("xp", 0)),
		"skills": (u.get("skills", {}) as Dictionary).duplicate(true),
		"skill_counts": (m.get("skills", {}) as Dictionary).duplicate(true),
		"attack_count": int(m.get("attack_count", 0)),
		"item_slots": (m.get("item_slots", []) as Array).duplicate(),
		"mine_slots": (m.get("mine_slots", []) as Array).duplicate(),
		"equip": equip_id,
		"equip_name": str(equip_item.get("name", "")),
		"attack_bonus": int(equip_bonus["attack"]),
		"defense_bonus": int(equip_bonus["defense"]),
		"hp": max_hp if lv > int(m.get("level", 1)) else max(1, int(m.get("hp", max_hp))),
		"max_hp": max_hp,
		"raw_hp": int(m.get("hp", max_hp)),
		"hp_source": "party",
		"x": int(spawn.get("x", 0)),
		"y": int(spawn.get("y", 0)),
		"direction": 1,
		"behavior": 1,
		"target_slot": 0,
		"target_x": 0,
		"target_y": 0,
		"face": int(m.get("face", 0)),
		"face_png": str(m.get("face_png", "")),
		"army_png": str(p.get("army_png", "")),
		"select": int(u.get("select", 1)),
		"apply": int(u.get("apply", 0)),
		"move": int(u.get("yidong", 4)),
		"gongji": int(u.get("gongji", 0)),
		"fangyu": int(u.get("fangyu", 0)),
		"tili": int(u.get("tili", 50)),
		"tili_plus": int(u.get("tili_plus", 0)),
		"is_boss": false,
		"protected": true if str(m.get("name", "")) in ["村民", "老百姓"] else false,
		"control": true,
		"auto": false,
	}


static func _pick_deploy(deploy: Array, i: int, lv: Dictionary, units: Array) -> Dictionary:
	var w := int(lv.get("map", {}).get("width", 1))
	var h := int(lv.get("map", {}).get("height", 1))
	var used := {}
	for u in units:
		used["%d,%d" % [int(u.get("x", -1)), int(u.get("y", -1))]] = true
	if i < deploy.size():
		var p: Array = deploy[i]
		if not used.has("%d,%d" % [int(p[0]), int(p[1])]):
			return {"x": int(p[0]), "y": int(p[1])}
	# 围绕部署点找空位
	for j in range(deploy.size()):
		var p: Array = deploy[j]
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := int(p[0]) + dx
				var y := int(p[1]) + dy
				if x >= 0 and y >= 0 and x < w and y < h \
						and not used.has("%d,%d" % [x, y]):
					return {"x": x, "y": y}
	# 底部兜底
	for y in range(h - 1, 0, -1):
		for x in range(w):
			if not used.has("%d,%d" % [x, y]):
				return {"x": x, "y": y}
	return {"x": 0, "y": 0}


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
