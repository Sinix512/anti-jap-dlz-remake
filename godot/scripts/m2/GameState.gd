extends RefCounted

## M2 战役状态：金钱、天数、队伍、库存、解放城镇、存档。
## 纯逻辑，不依赖场景；Campaign/面板调用。

const SAVE_VERSION := 1

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
	var start: Dictionary = data.get("starting", {})
	for pid in start.get("party", []):
		_add_member(int(pid))
	for k in start.get("items", {}):
		items[str(k)] = int(start["items"][k])
	for k in start.get("materials", {}):
		materials[str(k)] = int(start["materials"][k])
	for k in start.get("mines", {}):
		mines[str(k)] = int(start["mines"][k])


func _add_member(pid: int) -> void:
	var people: Array = data.get("people", [])
	if pid < 0 or pid >= people.size():
		return
	var p: Dictionary = people[pid]
	var u: Dictionary = p.get("unit", {})
	var max_hp := int(p.get("max_hp", 1))
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
		"xp": 0,
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
		"saved_at": Time.get_datetime_string_from_system(),
	}


func from_dict(d: Dictionary) -> bool:
	if int(d.get("version", 0)) != SAVE_VERSION:
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
	saved_at = str(d.get("saved_at", ""))
	return true


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
