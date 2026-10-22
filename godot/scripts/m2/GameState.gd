extends RefCounted

## M2 战役状态：金钱、天数、队伍、库存、解放城镇、存档。
## 纯逻辑，不依赖场景；Campaign/面板调用。

const SAVE_VERSION := 3
const CombatRules = preload("res://scripts/battle/CombatRules.gd")

var data: Dictionary = {}
var money := 0
var day := 1
var party: Array = []
var items: Dictionary = {}
var materials: Dictionary = {}
var mines: Dictionary = {}
var liberated: Array = []
var current_town := 0
var saved_at := ""

# M4/M5 战役进度
var campaign_index := 0
var campaign_completed: Array = []
var level_scores: Dictionary = {}
var score_total := 0
var hidden_unlocked := false
var hidden_done: Array = []
var ending_id := 0
var player_name := "李勇"
var story_variant := false
var m4_data: Dictionary = {}


func new_game(m2: Dictionary) -> void:
	data = m2
	var meta: Dictionary = data.get("meta", {})
	money = int(meta.get("starting_money", 6000))
	day = int(meta.get("starting_day", 1))
	current_town = int(meta.get("starting_town", 0))
	party.clear()
	items.clear()
	materials.clear()
	mines.clear()
	liberated.clear()
	campaign_index = 0
	campaign_completed.clear()
	level_scores.clear()
	score_total = 0
	hidden_unlocked = false
	hidden_done.clear()
	ending_id = 0
	if player_name == "":
		player_name = "李勇"
	var start: Dictionary = data.get("starting", {})
	for pid in start.get("party", []):
		_add_member(int(pid))
	for k in start.get("items", {}):
		items[str(k)] = int(start["items"][k])
	for k in start.get("materials", {}):
		materials[str(k)] = int(start["materials"][k])
	for k in start.get("mines", {}):
		mines[str(k)] = int(start["mines"][k])
	auto_equip_party()


func _add_member(pid: int) -> void:
	var people: Array = data.get("people", [])
	if pid < 0 or pid >= people.size():
		return
	var p: Dictionary = people[pid]
	var u: Dictionary = p.get("unit", {})
	var max_hp := int(p.get("max_hp", 1))
	var start_equip := -1
	for v in p.get("wupin", []):
		if int(v) > 0 and item_kind(int(v)) == "equip":
			start_equip = int(v)
			break
	party.append({
		"pid": pid,
		"name": p.get("name", "?"),
		"face": int(p.get("face", 0)),
		"face_png": p.get("face_png", ""),
		"bingzhong": int(p.get("bingzhong", 0)),
		"unit_name": p.get("unit_name", ""),
		"level": int(p.get("level", 1)),
		"wuli": int(p.get("wuli", 0)),
		"zhili": int(p.get("zhili", 0)),
		"xp": int(p.get("jingyan", 0)),
		"level_cap": 99,
		"skills": (p.get("skills", {}) as Dictionary).duplicate(true),
		"attack_count": int(p.get("gongji", 0)),
		"item_slots": (p.get("wupin", []) as Array).duplicate(),
		"mine_slots": (p.get("dilei", []) as Array).duplicate(),
		"equip": start_equip,
		"hp": max_hp,
		"max_hp": max_hp,
	})
	# 角色初始携带物进公共库存（0 是空槽）
	for v in p.get("wupin", []):
		if int(v) > 0:
			add_item(int(v), 1)


func unit_of(member: Dictionary) -> Dictionary:
	var units: Dictionary = data.get("units", {})
	return units.get(str(member.get("bingzhong", 0)), {})


func max_hp_for(bingzhong: int, level: int) -> int:
	var u: Dictionary = data.get("units", {}).get(str(bingzhong), {})
	return max(1, int(u.get("tili", 50)) + (level - 1) * int(u.get("tili_plus", 0)))


func meta() -> Dictionary:
	return data.get("meta", {})


func max_party() -> int:
	return int(meta().get("max_party", 10))


func party_size() -> int:
	return party.size()


func has_member(pid: int) -> bool:
	for m in party:
		if int(m["pid"]) == pid:
			return true
	return false


func get_member(pid: int):
	for m in party:
		if int(m["pid"]) == pid:
			return m
	return null


func people() -> Array:
	return data.get("people", [])


func candidates() -> Array:
	var out: Array = []
	for p in people():
		# 孙悟空/神仙队留给隐藏彩蛋，不在常规招募池
		if int(p.get("pid", -1)) == 0:
			continue
		if not has_member(int(p["pid"])):
			out.append(p)
	out.sort_custom(func(a, b):
		return int(a["level"]) < int(b["level"]))
	return out


func recruit_cost(pid: int) -> int:
	var p = people()[pid] if pid >= 0 and pid < people().size() else {}
	return int(p.get("recruit_cost", 1000)) if not p.is_empty() else 0


func join_member(pid: int) -> Dictionary:
	if has_member(pid):
		return {"ok": false, "msg": "该角色已在队伍中"}
	if party_size() >= max_party():
		return {"ok": false, "msg": "队伍已满，%s 暂未加入" % people()[pid].get("name", "")}
	_add_member(pid)
	return {"ok": true, "msg": "%s 加入队伍" % people()[pid].get("name", "")}


func recruit(pid: int) -> Dictionary:
	if has_member(pid):
		return {"ok": false, "msg": "该角色已在队伍中"}
	if party_size() >= max_party():
		return {"ok": false, "msg": "队伍已满（%d 人）" % max_party()}
	var cost := recruit_cost(pid)
	if money < cost:
		return {"ok": false, "msg": "资金不足（需要 %d）" % cost}
	money -= cost
	_add_member(pid)
	return {"ok": true, "msg": "招募成功：%s" % people()[pid]["name"]}


func can_promote(member: Dictionary) -> Dictionary:
	var u := unit_of(member)
	var target := int(u.get("zhuanzhi", -1))
	if target < 0:
		return {"ok": false, "msg": "%s 无转职路线" % u.get("name", "该兵种")}
	var target_u: Dictionary = data.get("units", {}).get(str(target), {})
	if target_u.is_empty() or str(target_u.get("name", "")) == "":
		return {"ok": false, "msg": "转职目标为空"}
	var item_id := int(u.get("zhuanzhidaoju", -1))
	if item_id >= 0:
		if item_count(item_id) <= 0:
			var it: Dictionary = data.get("items", {}).get(str(item_id), {})
			return {"ok": false,
					"msg": "需要《%s》×1" % str(it.get("name", "转职道具"))}
	return {
		"ok": true,
		"msg": "",
		"target": target,
		"target_name": target_u.get("name", ""),
		"item_id": item_id,
	}


func promote(member: Dictionary) -> Dictionary:
	var c := can_promote(member)
	if not bool(c.get("ok", false)):
		return c
	var item_id := int(c.get("item_id", -1))
	if item_id >= 0:
		add_item(item_id, -1)
	member["bingzhong"] = int(c["target"])
	member["unit_name"] = str(c["target_name"])
	var max_hp := max_hp_for(int(member["bingzhong"]), int(member["level"]))
	member["max_hp"] = max_hp
	member["hp"] = max_hp
	return {"ok": true, "msg": "转职成功：%s → %s" % [member["name"], member["unit_name"]]}


func item_count(pid: int) -> int:
	return int(items.get(str(pid), 0))


func item_kind(item_id: int) -> String:
	"""把 WuPin 的 para3/para4 解释成可执行类别。
	16/17/18=体力/士气/两者；26-29=投掷/毒虫类攻击物；
	131..155=坐骑/车辆/鞋靴装备；61..80=转职/兵书，不在战斗内使用。
	这是按字段相关性做的可玩性解释，原版完整语义仍待反汇编确认。"""
	if item_id >= 81 and item_id <= 155:
		return "equip"
	if item_id >= 61 and item_id <= 80:
		return "manual"
	if item_id >= 31 and item_id <= 40:
		return "book"
	if item_id >= 41 and item_id <= 56:
		return "throw"
	if item_id >= 0 and item_id <= 30:
		return "food"
	return "other"


func equip_bonus(item_id: int) -> Dictionary:
	var it := item(item_id)
	if it.is_empty() or item_kind(item_id) != "equip":
		return {"attack": 0, "defense": 0}
	return {"attack": max(0, int(it.get("para3", 0))),
			"defense": max(0, int(it.get("para4", 0)))}


func can_equip(member: Dictionary, item_id: int) -> Dictionary:
	if member == null or item(item_id).is_empty():
		return {"ok": false, "msg": "没有这件装备"}
	if item_kind(item_id) != "equip":
		return {"ok": false, "msg": "这不是可装备物品"}
	if item_count(item_id) <= 0:
		return {"ok": false, "msg": "库存没有这件装备"}
	return {"ok": true, "msg": ""}


func equip_item(member: Dictionary, item_id: int) -> Dictionary:
	var c := can_equip(member, item_id)
	if not bool(c.get("ok", false)):
		return c
	member["equip"] = item_id
	return {"ok": true, "msg": "%s 装备 %s" % [
			member.get("name", ""), item(item_id).get("name", "")]}


func unequip_item(member: Dictionary) -> Dictionary:
	if member == null or int(member.get("equip", -1)) < 0:
		return {"ok": false, "msg": "没有装备"}
	var old: String = str(item(int(member["equip"])).get("name", ""))
	member["equip"] = -1
	return {"ok": true, "msg": "卸下 %s" % old}


func auto_equip_party() -> void:
	"""把库存里最好的装备分配给未装备的队员；同一件装备按库存数量限用。"""
	var used := {}
	for m in party:
		var e := int(m.get("equip", -1))
		if e >= 0:
			used[str(e)] = int(used.get(str(e), 0)) + 1
	for m in party:
		if int(m.get("equip", -1)) >= 0:
			continue
		var best := -1
		var best_score := -1
		for k in items:
			var iid := int(k)
			if item_kind(iid) != "equip":
				continue
			if int(used.get(k, 0)) >= item_count(iid):
				continue
			var b := equip_bonus(iid)
			var score := int(b["attack"]) + int(b["defense"])
			if score > best_score:
				best_score = score
				best = iid
		if best >= 0:
			m["equip"] = best
			used[str(best)] = int(used.get(str(best), 0)) + 1


func battle_context() -> Dictionary:
	"""进入战斗时的只读/消耗快照。Battle 只改 consumed_*，战后由本对象写回。"""
	return {
		"mines": mines.duplicate(true),
		"items": items.duplicate(true),
		"consumed_mines": {},
		"consumed_items": {},
	}


func apply_battle_context(ctx: Dictionary) -> void:
	for k in ctx.get("consumed_mines", {}):
		add_mine(int(k), -int(ctx["consumed_mines"][k]))
	for k in ctx.get("consumed_items", {}):
		add_item(int(k), -int(ctx["consumed_items"][k]))


func grant_battle_experience(units: Array, victory: bool) -> void:
	if not victory:
		return
	var avg := 0
	if not party.is_empty():
		for m in party:
			avg += int(m.get("level", 1))
		avg = int(round(float(avg) / party.size()))
	for u in units:
		if int(u.pid) >= 0:
			u.gained_xp += CombatRules.battle_experience(int(u.data.get("level", 1)), avg)


func apply_battle_progress(units: Array) -> void:
	"""把战斗内获得的经验/等级/技能使用次数写回队伍。"""
	for u in units:
		var pid := int(u.pid)
		if pid < 0:
			continue
		var m = get_member(pid)
		if m == null or not (m is Dictionary):
			continue
		var member: Dictionary = m
		var gained := int(u.gained_xp)
		var xp := int(member.get("xp", 0)) + gained
		var levels := int(xp / 100)
		xp = xp % 100
		var lv := mini(99, int(member.get("level", 1)) + levels)
		member["level"] = lv
		member["xp"] = xp
		var old_max := int(member.get("max_hp", 1))
		var new_max := max_hp_for(int(member.get("bingzhong", 0)), lv)
		member["max_hp"] = new_max
		member["hp"] = clampi(int(member.get("hp", new_max)) + max(0, new_max - old_max),
				0, new_max)
		member["skills"] = (u.skill_counts as Dictionary).duplicate(true)
		member["attack_count"] = int(u.attack_count)


func material_count(mid: int) -> int:
	return int(materials.get(str(mid), 0))


func mine_count(mid: int) -> int:
	return int(mines.get(str(mid), 0))


func add_item(pid: int, n: int) -> void:
	var k := str(pid)
	items[k] = max(0, int(items.get(k, 0)) + n)
	if int(items[k]) == 0:
		items.erase(k)


func add_material(mid: int, n: int) -> void:
	var k := str(mid)
	materials[k] = max(0, int(materials.get(k, 0)) + n)
	if int(materials[k]) == 0:
		materials.erase(k)


func add_mine(mid: int, n: int) -> void:
	var k := str(mid)
	mines[k] = max(0, int(mines.get(k, 0)) + n)
	if int(mines[k]) == 0:
		mines.erase(k)


func item(pid: int) -> Dictionary:
	return data.get("items", {}).get(str(pid), {})


func material(mid: int) -> Dictionary:
	return data.get("materials", {}).get(str(mid), {})


func mine(mid: int) -> Dictionary:
	return data.get("mines", {}).get(str(mid), {})


func buy_item(pid: int) -> Dictionary:
	var it := item(pid)
	if it.is_empty():
		return {"ok": false, "msg": "没有这件物品"}
	var price := int(it.get("price", 0))
	if money < price:
		return {"ok": false, "msg": "资金不足"}
	money -= price
	add_item(pid, 1)
	return {"ok": true, "msg": "买入 %s（%d）" % [it["name"], price]}


func sell_item(pid: int) -> Dictionary:
	if item_count(pid) <= 0:
		return {"ok": false, "msg": "库存没有这件物品"}
	var it := item(pid)
	var price: int = max(1, int(it.get("price", 0) / 2.0))
	add_item(pid, -1)
	money += price
	return {"ok": true, "msg": "卖出 %s（+%d）" % [it.get("name", ""), price]}


func buy_material(mid: int) -> Dictionary:
	var m := material(mid)
	if m.is_empty():
		return {"ok": false, "msg": "没有这种材料"}
	var price := int(m.get("price", 1))
	if money < price:
		return {"ok": false, "msg": "资金不足"}
	money -= price
	add_material(mid, 1)
	return {"ok": true, "msg": "买入 %s（%d）" % [m["name"], price]}


func sell_material(mid: int) -> Dictionary:
	if material_count(mid) <= 0:
		return {"ok": false, "msg": "库存不足"}
	var m := material(mid)
	var price: int = max(1, int(m.get("price", 1) / 2.0))
	add_material(mid, -1)
	money += price
	return {"ok": true, "msg": "卖出 %s（+%d）" % [m.get("name", ""), price]}


func can_craft(mid: int) -> Dictionary:
	var m := mine(mid)
	if m.is_empty():
		return {"ok": false, "msg": "未知配方"}
	var recipe: Array = m.get("recipe", [])
	var need := {}
	for i in range(recipe.size()):
		var n := int(recipe[i])
		if n > 0:
			need[i] = n
	for i in need:
		if material_count(i) < int(need[i]):
			return {"ok": false, "msg": "材料不足：%s %d/%d" % [
				material(i).get("name", str(i)), material_count(i), int(need[i])]}
	return {"ok": true, "msg": "", "need": need}


func craft_mine(mid: int) -> Dictionary:
	var c := can_craft(mid)
	if not bool(c.get("ok", false)):
		return c
	var m := mine(mid)
	for i in c["need"]:
		add_material(int(i), -int(c["need"][i]))
	add_mine(mid, 1)
	return {"ok": true, "msg": "锻造成功：%s" % m.get("name", "")}


func heal_all() -> void:
	for m in party:
		m["hp"] = int(m["max_hp"])


func town(index: int) -> Dictionary:
	var towns: Array = data.get("towns", [])
	if index < 0 or index >= towns.size():
		return {}
	return towns[index]


func town_name(index: int) -> String:
	return str(town(index).get("name", ""))


func is_liberated(index: int) -> bool:
	return index in liberated


func battle_tables() -> Dictionary:
	return data.get("battle", {})


func apply_battle(victory: bool, battle_units: Array, town_index: int) -> Dictionary:
	var by_pid := {}
	for u in battle_units:
		if u.get("side", "") == "player" and u.has("pid"):
			by_pid[int(u["pid"])] = u
	for m in party:
		var pid := int(m["pid"])
		if by_pid.has(pid):
			m["hp"] = max(0, int(by_pid[pid].get("hp", m["hp"])))
	day += 1
	var reward := 0
	if victory:
		reward = int(meta().get("battle_reward", 800))
		money += reward
		if not is_liberated(town_index):
			liberated.append(town_index)
	return {"reward": reward, "liberated": victory}


func setup_m4(m4: Dictionary) -> void:
	m4_data = m4


func m4_levels() -> Array:
	return m4_data.get("levels", [])


func m4_level(index: int) -> Dictionary:
	var arr := m4_levels()
	if index < 0 or index >= arr.size():
		return {}
	return arr[index]


func campaign_level() -> Dictionary:
	if campaign_index >= 36:
		return {}
	return m4_level(campaign_index)


func campaign_finished() -> bool:
	return campaign_index >= 36


func level_town(index: int) -> int:
	var lv := m4_level(index)
	return int(lv.get("town", 0))


func town_unlocked(town_index: int) -> bool:
	if campaign_finished() or hidden_unlocked:
		return true
	for i in range(min(campaign_index + 1, 36)):
		if level_town(i) == town_index:
			return true
	for i in campaign_completed:
		if level_town(int(i)) == town_index:
			return true
	return false


func is_level_completed(index: int) -> bool:
	return index in campaign_completed


func level_score(index: int) -> int:
	return int(level_scores.get(str(index), 0))


func _add_score(index: int, score: int) -> void:
	var old := level_score(index)
	if score > old:
		level_scores[str(index)] = score
		score_total += score - old


func complete_level(index: int, score: int, victory: bool) -> Dictionary:
	var lv := m4_level(index)
	if lv.is_empty():
		return {"ok": false}
	var reward := 0
	if victory:
		reward = int(lv.get("reward_money", 0)) + 600 + index * 20
		money += reward
		_add_score(index, clampi(score, 0, 100))
		if not campaign_completed.has(index):
			campaign_completed.append(index)
		if index < 36 and index == campaign_index:
			while campaign_index < 36 and campaign_completed.has(campaign_index):
				campaign_index += 1
		elif index >= 36:
			if not hidden_done.has(index):
				hidden_done.append(index)
		var town := level_town(index)
		if town >= 0 and not liberated.has(town):
			liberated.append(town)
		if campaign_index >= 36:
			hidden_unlocked = score_total >= 2800 or not hidden_done.is_empty()
			ending_id = ending_for_score(score_total)
	day += 1
	return {"ok": true, "reward": reward, "score": level_score(index),
			"total": score_total, "hidden": hidden_unlocked,
			"ending": ending_id}


func ending_for_score(score: int) -> int:
	if score >= 3600:
		return 4
	if score >= 3300:
		return 3
	if score >= 3000:
		return 2
	if score >= 2800:
		return 1
	return 0


func ending_image() -> String:
	var id := ending_id
	if id < 0 or id > 5:
		id = 0
	var path := "res://assets/ui/end_%02d.png" % id
	return path if ResourceLoader.exists(path) else ""


func grade_for_score(score: int) -> int:
	if score >= 95:
		return 4
	if score >= 80:
		return 3
	if score >= 60:
		return 2
	if score >= 30:
		return 1
	return 0


func hidden_next(mode: String) -> int:
	var lo := 36 if mode == "simulation" else 40
	var hi := 40 if mode == "simulation" else 44
	for i in range(lo, hi):
		if not hidden_done.has(i):
			return i
	return -1


func hidden_mode_done(mode: String) -> bool:
	return hidden_next(mode) < 0


func available_easter() -> Array:
	if hidden_unlocked or not hidden_done.is_empty():
		return [44, 45, 46]
	return []


func apply_battle_health(units: Array) -> void:
	for u in units:
		var pid := int(u.get("pid", -1))
		if pid < 0:
			continue
		var m = get_member(pid)
		if m != null and m is Dictionary:
			(m as Dictionary)["hp"] = max(0, int(u.get("hp", 0)))


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"money": money,
		"day": day,
		"party": party.duplicate(true),
		"items": items.duplicate(true),
		"materials": materials.duplicate(true),
		"mines": mines.duplicate(true),
		"liberated": liberated.duplicate(),
		"current_town": current_town,
		"campaign_index": campaign_index,
		"campaign_completed": campaign_completed.duplicate(),
		"level_scores": level_scores.duplicate(true),
		"score_total": score_total,
		"hidden_unlocked": hidden_unlocked,
		"hidden_done": hidden_done.duplicate(),
		"ending_id": ending_id,
		"player_name": player_name,
		"saved_at": Time.get_datetime_string_from_system(),
	}


func from_dict(d: Dictionary) -> bool:
	if int(d.get("version", 0)) not in [1, 2, SAVE_VERSION]:
		return false
	money = int(d.get("money", 0))
	day = int(d.get("day", 1))
	party = (d.get("party", []) as Array).duplicate(true)
	items = {}
	for k in d.get("items", {}):
		items[str(k)] = int(d["items"][k])
	materials = {}
	for k in d.get("materials", {}):
		materials[str(k)] = int(d["materials"][k])
	mines = {}
	for k in d.get("mines", {}):
		mines[str(k)] = int(d["mines"][k])
	liberated = (d.get("liberated", []) as Array).duplicate()
	current_town = int(d.get("current_town", 0))
	campaign_index = int(d.get("campaign_index", 0))
	campaign_completed = (d.get("campaign_completed", []) as Array).duplicate()
	level_scores = {}
	for k in d.get("level_scores", {}):
		level_scores[str(k)] = int(d["level_scores"][k])
	score_total = int(d.get("score_total", 0))
	hidden_unlocked = bool(d.get("hidden_unlocked", false))
	hidden_done = (d.get("hidden_done", []) as Array).duplicate()
	ending_id = int(d.get("ending_id", 0))
	player_name = str(d.get("player_name", "李勇"))
	saved_at = str(d.get("saved_at", ""))
	return true


func save_checkpoint() -> bool:
	return save_slot(8)


func load_checkpoint() -> bool:
	return load_slot(8)


func has_checkpoint() -> bool:
	return not slot_info(8).is_empty()


func save_path(slot: int) -> String:
	return "user://%s%d.json" % [meta().get("save_prefix", "dlz_m2_save_"), slot]


func save_slot(slot: int) -> bool:
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true


func slot_info(slot: int) -> Dictionary:
	var p := save_path(slot)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return {}
	return parsed


func load_slot(slot: int) -> bool:
	var d := slot_info(slot)
	if d.is_empty():
		return false
	return from_dict(d)


func delete_slot(slot: int) -> void:
	var p := save_path(slot)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
