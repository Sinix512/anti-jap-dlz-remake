extends RefCounted
const InventorySlots=preload("res://scripts/battle/InventorySlots.gd")

## M2 战役状态：金钱、天数、队伍、库存、解放城镇、存档。
## 纯逻辑，不依赖场景；Campaign/面板调用。

const SAVE_VERSION := 7
# 玩家自定义主角（剧情里的 GG）。不占 PEOPLE.DAT 的 0–39 槽，
# 也不写进 5 人初始队伍；出战时可作为固定 leader 临时加入 roster。
const PROTAGONIST_PID := -100
const CombatRules = preload("res://scripts/battle/CombatRules.gd")
const OriginalSave = preload("res://scripts/m2/OriginalSave.gd")

var data: Dictionary = {}
var money := 0
var day := 1
var party: Array = []
var reserve_members: Dictionary = {}
var script_globals: Dictionary = {}
var main_score_snapshot := 0
var next_battle_overrides: Dictionary = {}
var battle_turn := 1
var play_seconds := 0
var town_bgm_scene := 34
var checkpoint_data: Dictionary = {}
var battle_resume: Dictionary = {}
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
var kills_by_gun := 0
var kills_by_mine := 0
var hidden_unlocked := false
var hidden_done: Array = []
var ending_id := 0
var endings_seen: Array = []
var player_name := "李勇"
var protagonist: Dictionary = {}
var story_variant := false
var difficulty := 1
var m4_data: Dictionary = {}
var original_blocks: Dictionary = {}  # 原版28块原字节，JSON以hex持久化未知字段


func new_game(m2: Dictionary) -> void:
	data = preload("res://scripts/battle/StateCodec.gd").integers(m2)
	checkpoint_data.clear()
	battle_resume.clear()
	endings_seen.clear()
	var meta: Dictionary = data.get("meta", {})
	money = int(meta.get("starting_money", 500))
	day = int(meta.get("starting_day", 1))
	current_town = int(meta.get("starting_town", 0))
	party.clear()
	reserve_members.clear()
	script_globals.clear()
	main_score_snapshot = 0
	next_battle_overrides.clear()
	battle_turn = 1
	play_seconds = 0
	town_bgm_scene = 34
	items.clear()
	materials.clear()
	mines.clear()
	liberated.clear()
	liberated.append(0)
	campaign_index = 0
	campaign_completed.clear()
	level_scores.clear()
	score_total = 0
	kills_by_gun = 0
	kills_by_mine = 0
	hidden_unlocked = false
	hidden_done.clear()
	ending_id = 0
	original_blocks.clear()
	if player_name == "":
		player_name = "李勇"
	protagonist.clear()
	configure_protagonist()
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
	if pid <= 0 or pid >= people().size() or has_member(pid):
		return
	var m: Dictionary = person(pid)
	m["faction"] = 0
	party.append(m)


func person(slot: int) -> Dictionary:
	if slot == 0 or slot == PROTAGONIST_PID:
		return protagonist_member()
	var joined = get_member(slot)
	if joined != null:
		return joined
	var key := str(slot)
	if reserve_members.has(key):
		return reserve_members[key]
	if slot < 0 or slot >= people().size():
		return {}
	var p: Dictionary = people()[slot]
	var cls: Dictionary = p.get("unit", {})
	var uses: int = CombatRules.SKILL_THRESHOLDS[mini(int(p.get("level", 1)) / 6, 9)]
	var counts := {}
	for k in cls.get("skills", {}):
		counts[k] = int(cls["skills"][k]) * uses
	var hp := max_hp_for(int(p.get("bingzhong", 0)), int(p.get("level", 1)))
	var m := {"pid": slot, "name": p.get("name", "?"),
		"face": int(p.get("face", 0)), "face_png": p.get("face_png", ""),
		"army_png": p.get("army_png", ""), "faction": int(p.get("unknown_18", 1)),
		"bingzhong": int(p.get("bingzhong", 0)), "unit_name": p.get("unit_name", ""),
		"level": int(p.get("level", 1)), "xp": int(p.get("jingyan", 0)),
		"wuli": int(p.get("wuli", 0)), "zhili": int(p.get("zhili", 0)),
		"skills": counts, "attack_count": uses, "level_cap": 99,
		"item_slots": (p.get("wupin", []) as Array).duplicate(),
		"mine_slots": (p.get("dilei", []) as Array).duplicate(),
		"hp": hp, "max_hp": hp, "equip": -1}
	reserve_members[key] = m
	return m


func all_members() -> Array:
	return [protagonist_member()] + party


func set_person_side(slot: int, faction: int) -> void:
	var m := person(slot)
	if m.is_empty():
		return
	m["faction"] = faction
	if slot == 0:
		return
	if faction == 0 and not has_member(slot):
		party.append(m)
	elif faction != 0:
		for i in range(party.size() - 1, -1, -1):
			if int(party[i]["pid"]) == slot:
				party.remove_at(i)


func deployment_roster(index: int) -> Array:
	var dep: Dictionary = m4_level(index).get("deployment", {})
	var excluded: Array = dep.get("excluded_slots", [])
	var out: Array = []
	for slot in range(32):
		if slot in excluded:
			continue
		var m := person(slot)
		if int(m.get("faction", 1)) == 0:
			out.append(m)
	return out


func apply_phase_state(phase: Dictionary) -> void:
	for write in phase.get("literal_writes", []):
		var table := str(write.get("table", ""))
		if table == "global":
			script_globals[str(write["address"]).to_lower()] = int(write["value"])
		elif table == "people" and int(write["slot"]) < 40:
			var slot := int(write["slot"])
			var m := person(slot)
			match int(write["offset"]):
				24: set_person_side(slot, int(write["value"]))
				44: change_class(m, int(write["value"]), false)
				124:
					var raw := int(write["value"])
					var slots: Array = m.get("mine_slots", [0,0,0,0,0,0,0,0])
					for j in range(4):
						slots[j] = (raw >> (j * 8)) & 255
					m["mine_slots"] = slots
	if phase.has("recompute_skills"):
		var q: Dictionary = phase["recompute_skills"]
		var m := person(int(q["slot"]))
		var cls := unit_of(m)
		var uses: int = CombatRules.SKILL_THRESHOLDS[mini(int(m.get("level", 1)) / 6, 9)]
		for k in cls.get("skills", {}):
			m["skills"][k] = int(cls["skills"][k]) * uses
	if phase.has("town_bgm_scene"):
		town_bgm_scene = int(phase["town_bgm_scene"])
	if phase.has("town_index"):
		current_town = int(phase["town_index"])
		if not liberated.has(current_town):
			liberated.append(current_town)
	if phase.has("reward_item"):
		add_item(int(phase["reward_item"]["item_id"]), int(phase["reward_item"]["quantity"]))
	if phase.has("next_battle_setup"):
		next_battle_overrides = (phase["next_battle_setup"] as Dictionary).duplicate(true)


func unit_of(member: Dictionary) -> Dictionary:
	var units: Dictionary = data.get("units", {})
	return units.get(str(member.get("bingzhong", 0)), {})


func max_hp_for(bingzhong: int, level: int) -> int:
	var u: Dictionary = data.get("units", {}).get(str(bingzhong), {})
	return max(1, int(u.get("tili", 50)) + (level - 1) * int(u.get("tili_plus", 0)))


func meta() -> Dictionary:
	return data.get("meta", {})


func max_party() -> int:
	return int(meta().get("max_party", 32))


func party_size() -> int:
	return party.size() + 1


func has_member(pid: int) -> bool:
	for m in party:
		if int(m["pid"]) == pid:
			return true
	return false


func get_member(pid: int):
	if pid == PROTAGONIST_PID:
		return protagonist_member()
	for m in party:
		if int(m["pid"]) == pid:
			return m
	return null


func protagonist_member() -> Dictionary:
	# 返回持久对象，不能每次访问时重建，否则装备/经验/转职全部丢失。
	if protagonist.is_empty():
		configure_protagonist()
	protagonist["name"] = player_name.strip_edges() if player_name.strip_edges() != "" else "李勇"
	return protagonist


func configure_protagonist(face: int = 103, bingzhong: int = 1, wuli: int = 80) -> void:
	# DLZ.exe 42E98E/42E9EF/42EA3E/42EA72：六头像、四兵种、武智合160。
	var nm := player_name.strip_edges()
	if nm == "":
		nm = "李勇"
	var lv := 1
	var bz := bingzhong if bingzhong in [1, 4, 8, 11] else 1
	var cls: Dictionary = data.get("units", {}).get(str(bz), {})
	var hp := max_hp_for(bz, lv)
	var zero_skills := {}
	for k in ["buji", "jili", "yiliao", "huogong", "gunmu", "leishi",
			"weishe", "saorao", "pohuai", "lueduo", "fanjian", "yibing",
			"duzhan", "ansha", "shidu", "kongxi"]:
		zero_skills[k] = int(cls.get("skills", {}).get(k, 0))
	zero_skills["buji"] = 1
	zero_skills["jili"] = 1
	protagonist = {
		"pid": PROTAGONIST_PID,
		"name": nm,
		"face": clampi(face, 103, 108),
		"face_png": "res://assets/face/face_%03d.png" % clampi(face, 103, 108),
		"army_png": "res://assets/army/army_%03d.png" % int(cls.get("img_index", 30)),
		"bingzhong": bz,
		"unit_name": str(cls.get("name", "手枪队")),
		"level": lv,
		"wuli": clampi(wuli, 60, 100),
		"zhili": 160 - clampi(wuli, 60, 100),
		"xp": 0,
		"level_cap": 99,
		"skills": zero_skills.duplicate(),
		"skill_counts": zero_skills.duplicate(),
		"attack_count": 1,
		"faction": 0,
		"item_slots": [2, 3, [100, 82, 109, 82][[1, 4, 8, 11].find(bz)], 0, 0, 0, 0, 0],
		"mine_slots": [0, 0, 0, 0, 0, 0, 0, 0],
		"equip": -1,
		"hp": hp,
		"max_hp": hp,
		"hero": true,
	}


func deploy_member(pid: int):
	if pid == PROTAGONIST_PID:
		return protagonist_member()
	return get_member(pid)


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


func can_promote(member: Dictionary, chosen_item: int = -1) -> Dictionary:
	var cls := unit_of(member)
	var iid := chosen_item if chosen_item >= 0 else int(cls.get("zhuanzhidaoju", -1))
	if iid < 61 or iid > 80 or not item_compatible(member, iid):
		return {"ok": false, "msg": "此兵书与当前兵种不兼容"}
	var carried: bool = (member.get("item_slots", []) as Array).has(iid + 1)
	if not carried and item_count(iid) <= 0:
		return {"ok": false, "msg": "需要《%s》×1" % item(iid).get("name", "转职道具")}
	var target := int(item(iid).get("para1", -1))
	if iid == int(cls.get("zhuanzhidaoju", -1)):
		var required := 30 if iid >= 75 and iid < 79 else 15
		if int(member.get("level", 1)) < required:
			return {"ok": false, "msg": "晋升需要等级 %d" % required}
		target = int(cls.get("zhuanzhi", -1))
	if target < 0 or not data.get("units", {}).has(str(target)):
		return {"ok": false, "msg": "无可用转职路线"}
	return {"ok": true, "item_id": iid, "target": target, "carried": carried,
		"target_name": data["units"][str(target)].get("name", ""), "promotion":iid==int(cls.get("zhuanzhidaoju",-1)), "msg": ""}


func promote(member: Dictionary, chosen_item: int = -1) -> Dictionary:
	var c := can_promote(member, chosen_item)
	if not bool(c.get("ok", false)):
		return c
	var iid := int(c["item_id"])
	if c["carried"]:
		var slots: Array = member["item_slots"]
		InventorySlots.remove_id(slots,iid+1)
	else:
		add_item(iid, -1)
	change_class(member, int(c["target"]),true,not bool(c["promotion"]))
	return {"ok": true, "msg": "转职成功：%s → %s" % [member["name"], member["unit_name"]]}


func change_class(member: Dictionary, unit_id: int, learn_skills := true, clamp_hp := true) -> void:
	member["bingzhong"] = unit_id
	var cls := unit_of(member)
	member["unit_name"] = str(cls.get("name", ""))
	member["army_png"] = "res://assets/army/army_%03d.png" % int(cls.get("img_index", 0))
	var hp := max_hp_for(unit_id, int(member.get("level", 1)))
	member["max_hp"] = hp
	if clamp_hp:member["hp"] = mini(int(member.get("hp", hp)), hp)
	if learn_skills:
		var counts: Dictionary = member.get("skills", {})
		for k in cls.get("skills", {}):
			if int(cls["skills"][k]) != 0 and int(counts.get(k, 0)) == 0:
				counts[k] = 1
		member["skills"] = counts


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


func item_compatible(member: Dictionary, item_id: int) -> bool:
	var valid: Array = data.get("item_valid", [])
	var bz := int(member.get("bingzhong", 0))
	return item_id >= 0 and item_id < valid.size() and bz >= 0 and bz < valid[item_id].size() and int(valid[item_id][bz]) != 0


func equipment_bonuses(member: Dictionary) -> Dictionary:
	var out := {"attack": 0, "defense": 0, "move": 0}
	for raw in member.get("item_slots", []):
		var iid := int(raw) - 1
		if iid < 81 or not item_compatible(member, iid):
			continue
		var it := item(iid)
		out["attack"] = maxi(int(out["attack"]), int(it.get("para3", 0)))
		out["defense"] = maxi(int(out["defense"]), int(it.get("para4", 0)))
		out["move"] = maxi(int(out["move"]), int(it.get("para1", 0)))
	return out


func give_item(member: Dictionary, item_id: int) -> Dictionary:
	if item_count(item_id) <= 0:
		return {"ok": false, "msg": "仓库没有这件物品"}
	var slots: Array = member.get("item_slots", [0,0,0,0,0,0,0,0])
	var empty := slots.find(0)
	if empty < 0:
		return {"ok": false, "msg": "携带已满（每人八格）"}
	InventorySlots.add_id(slots,item_id+1)
	member["item_slots"] = slots
	add_item(item_id, -1)
	return {"ok": true, "msg": "%s 携带 %s" % [member.get("name", ""), item(item_id).get("name", "")]}


func return_item(member: Dictionary, slot: int) -> Dictionary:
	var slots: Array = member.get("item_slots", [])
	if slot < 0 or slot >= slots.size() or int(slots[slot]) == 0:
		return {"ok": false, "msg": "空格"}
	add_item(int(slots[slot]) - 1, 1)
	InventorySlots.remove_id(slots,int(slots[slot]))
	member["item_slots"] = slots
	return {"ok": true, "msg": "物品已归还仓库"}


func transfer_item(source: Dictionary, slot: int, target: Dictionary) -> Dictionary:
	var src: Array = source.get("item_slots", [])
	var dst: Array = target.get("item_slots", [])
	var empty := dst.find(0)
	if source == target or slot < 0 or slot >= src.size() or int(src[slot]) == 0 or empty < 0:
		return {"ok": false, "msg": "无法转交（目标须有空格）"}
	var stored_id:=int(src[slot])
	InventorySlots.add_id(dst,stored_id)
	InventorySlots.remove_id(src,stored_id)
	return {"ok": true, "msg": "物品已转交"}


func give_mine(member: Dictionary, packed_id: int) -> Dictionary:
	var slots: Array = member.get("mine_slots", [0,0,0,0,0,0,0,0])
	var empty := slots.find(0)
	if packed_id < 0 or packed_id >= 40 or mine_count(packed_id) <= 0 or empty < 0:
		return {"ok": false, "msg": "地雷库存不足或携带已满"}
	InventorySlots.add_id(slots,packed_id+1)
	member["mine_slots"] = slots
	add_mine(packed_id, -1)
	return {"ok": true, "msg": "地雷已分配"}


func can_equip(member: Dictionary, item_id: int) -> Dictionary:
	if member == null or item_kind(item_id) != "equip":
		return {"ok": false, "msg": "这不是可装备物品"}
	if item_count(item_id) <= 0:
		return {"ok": false, "msg": "仓库没有这件装备"}
	if not (member.get("item_slots", []) as Array).has(0):
		return {"ok": false, "msg": "携带已满（每人八格）"}
	return {"ok": true, "msg": ""}


func equip_item(member: Dictionary, item_id: int) -> Dictionary:
	var check := can_equip(member, item_id)
	if not check["ok"]:
		return check
	var result := give_item(member, item_id)
	member["equip"] = item_id  # 兼容旧UI选中项；加成以全部八格为准。
	return result


func unequip_item(member: Dictionary) -> Dictionary:
	var slots: Array = member.get("item_slots", [])
	for i in range(slots.size()):
		if int(slots[i]) - 1 >= 81:
			member["equip"] = -1
			return return_item(member, i)
	return {"ok": false, "msg": "没有携带装备"}


func auto_equip_party() -> void:
	# 原版没有免费复制/自动装备。保留入口，仅明确分配仓库现有物品。
	for m in all_members():
		for key in items.keys():
			var iid := int(key)
			if iid >= 81 and item_compatible(m, iid) and item_count(iid) > 0:
				equip_item(m, iid)
				break


func battle_context() -> Dictionary:
	"""进入战斗时的只读/消耗快照。Battle 只改 consumed_*，战后由本对象写回。"""
	return {
		"score_total":score_total,
		"mines": mines.duplicate(true),
		"items": items.duplicate(true),
		"consumed_mines": {},
		"consumed_items": {},
		"script_globals": script_globals.duplicate(true),
	}


func apply_battle_context(ctx: Dictionary) -> void:
	for k in ctx.get("consumed_mines", {}):
		add_mine(int(k), -int(ctx["consumed_mines"][k]))
	for k in ctx.get("consumed_items", {}):
		add_item(int(k), -int(ctx["consumed_items"][k]))


func grant_battle_experience(_units: Array, _victory: bool) -> void:
	# 42B35B是地雷死亡分经验，原版不存在通关白送经验。
	pass


func apply_battle_progress(units: Array) -> Array:
	var levelups: Array = []
	for u in units:
		var pid := int(u.pid)
		var m = person(0 if pid == PROTAGONIST_PID else pid)
		if m.is_empty():
			continue
		var old_level := int(m.get("level", 1))
		m["level"] = int(u.data.get("level", old_level))
		m["xp"] = int(u.data.get("xp", m.get("xp", 0)))
		m["bingzhong"] = int(u.bingzhong)
		set_person_side(0 if pid == PROTAGONIST_PID else pid,int(u.data.get("faction",0)))
		m["max_hp"] = max_hp_for(int(u.bingzhong), int(m["level"]))
		m["hp"] = clampi(int(u.hp), 0, int(m["max_hp"]))
		m["skills"] = (u.skill_counts as Dictionary).duplicate(true)
		m["attack_count"] = int(u.attack_count)
		m["wuli"] = int(u.data.get("wuli", m.get("wuli", 80)))
		m["zhili"] = int(u.data.get("zhili", m.get("zhili", 80)))
		m["item_slots"] = u.item_slots.duplicate()
		m["mine_slots"] = u.mine_slots.duplicate()
		if int(m["level"]) > old_level:
			levelups.append({"pid": pid, "name": str(m.get("name", "")),
				"from": old_level, "to": int(m["level"]), "hp": int(m["hp"]),
				"max_hp": int(m["max_hp"])})
	return levelups


func record_battle_stats(stats: Dictionary) -> void:
	"""累计原版 block8/9 的枪/雷歼敌数；只统计胜利结算里的敌方击杀。"""
	kills_by_gun += max(0, int(stats.get("kills_by_gun", 0)))
	kills_by_mine += max(0, int(stats.get("kills_by_mine", 0)))


func material_count(mid: int) -> int:
	return int(materials.get(str(mid), 0))


func mine_count(mid: int) -> int:
	return int(mines.get(str(mid), 0))


func add_item(pid: int, n: int) -> void:
	var k := str(pid)
	# 57BD50: native warehouse is WORD storage, including overflow on returns.
	items[k] = (int(items.get(k, 0)) + n) & 0xffff
	if int(items[k]) == 0:
		items.erase(k)


func add_material(mid: int, n: int) -> void:
	var k := str(mid)
	# Materials are DWORDs (473018), NOT the WORD item/mine inventory.
	materials[k] = (int(materials.get(k, 0)) + n) & 0xffffffff
	if int(materials[k]) == 0:
		materials.erase(k)


func add_mine(mid: int, n: int) -> void:
	var k := str(mid)
	mines[k] = (int(mines.get(k, 0)) + n) & 0xffff
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
	var price: int = int(it.get("price", 0)) * (7 - difficulty) / 10
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
	var price: int = int(m.get("price", 1)) * (7 - difficulty) / 10
	add_material(mid, -1)
	money += price
	return {"ok": true, "msg": "卖出 %s（+%d）" % [m.get("name", ""), price]}


func can_craft(packed: int) -> Dictionary:
	var kind := packed % 10
	var fuse := packed / 10
	if packed < 0 or packed >= 40 or int(script_globals.get("0x%x" % (0x95eaf8 + fuse * 4), 0)) == 0 or int(script_globals.get("0x%x" % (0x95eb08 + kind * 4), 0)) == 0:
		return {"ok": false, "msg": "尚未掌握这种雷或引信"}
	var m := mine(kind)
	if m.is_empty(): return {"ok": false, "msg": "未知配方"}
	var cost: int = [0,0,80,300][fuse]
	if money < cost: return {"ok": false, "msg": "引信制作资金不足"}
	var recipe: Array = m.get("recipe", [])
	var need := {}
	for i in range(recipe.size()):
		var n := int(recipe[i])
		if n > 0:
			need[i] = n
			if material_count(i) < n:
				return {"ok": false, "msg": "材料不足：%s %d/%d" % [material(i).get("name", str(i)), material_count(i), n]}
	return {"ok": true, "msg": "", "need": need, "cost": cost}


func craft_mine(packed: int) -> Dictionary:
	var c := can_craft(packed)
	if not bool(c.get("ok", false)): return c
	for i in c["need"]:
		add_material(int(i), -int(c["need"][i]))
	money -= int(c["cost"])
	add_mine(packed, 1)
	return {"ok": true, "msg": "制成%s%s" % [["普通", "引爆", "定时", "遥控"][packed / 10], mine(packed % 10).get("name", "") ]}


func return_mine(member: Dictionary, index: int) -> Dictionary:
	var slots: Array = member.get("mine_slots", [])
	if index < 0 or index >= slots.size() or int(slots[index]) == 0:
		return {"ok": false, "msg": "空格"}
	add_mine(int(slots[index]) - 1, 1)
	InventorySlots.remove_id(slots,int(slots[index]))
	return {"ok": true, "msg": "地雷已退回仓库"}


func transfer_mine(source: Dictionary, target: Dictionary, index: int) -> Dictionary:
	var src: Array = source.get("mine_slots", [])
	var dst: Array = target.get("mine_slots", [])
	if source == target or index < 0 or index >= src.size() or int(src[index]) == 0 or not dst.has(0):
		return {"ok": false, "msg": "无法转交"}
	var stored_id:=int(src[index])
	InventorySlots.add_id(dst,stored_id)
	InventorySlots.remove_id(src,stored_id)
	return {"ok": true, "msg": "地雷已转交"}


func recycle_mine(packed: int, member: Dictionary = {}, index := -1) -> Dictionary:
	if member.is_empty():
		if mine_count(packed) <= 0: return {"ok": false, "msg": "仓库不足"}
		add_mine(packed,-1)
		money += int(mine(packed % 10).get("price",0))
	else:
		var slots: Array = member.get("mine_slots",[])
		if index < 0 or index >= slots.size() or int(slots[index]) == 0: return {"ok": false, "msg": "空格"}
		# 43A2CD原版怪点：人物雷回收使用引信号作价格雷种索引，仓库用雷种。
		money += int(mine((int(slots[index])-1)/10).get("price",0))
		InventorySlots.remove_id(slots,int(slots[index]))
	return {"ok": true, "msg": "地雷已回收"}


func heal_all() -> void:
	var hero := protagonist_member()
	hero["hp"] = int(hero["max_hp"])
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
	m4_data = preload("res://scripts/battle/StateCodec.gd").integers(m4)


func m4_levels() -> Array:
	return m4_data.get("levels", [])


func m4_level(index: int) -> Dictionary:
	var arr := m4_levels()
	if index < 0 or index >= arr.size():
		return {}
	return arr[index]


func campaign_level() -> Dictionary:
	if campaign_index == 36 and not hidden_unlocked: return {}
	if campaign_index >= 36 and (hidden_done.has(campaign_index) or campaign_index > 46): return {}
	return m4_level(campaign_index)


func campaign_finished() -> bool:
	return campaign_index >= 36


func level_town(index: int) -> int:
	var lv := m4_level(index)
	return int(lv.get("town", 0))


func town_unlocked(town_index: int) -> bool:
	return liberated.has(town_index)


func _legacy_town_unlocked(town_index: int) -> bool:
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
	level_scores[str(index)] = maxi(level_score(index),score)
	score_total += score


func record_level_score(index: int, score: int) -> void:
	# 42B49A adds the score while displaying MENU10, before index/loot/phase.
	if not m4_level(index).is_empty():
		_add_score(index, maxi(0, score))


func complete_level(index: int, score: int, victory: bool, score_recorded := false) -> Dictionary:
	var lv := m4_level(index)
	if lv.is_empty():
		return {"ok": false}
	var reward := 0
	if victory:
		reward = 0 # 原版无通关保底奖金，剧情money动作已实时发放。
		if not score_recorded:record_level_score(index, score)
		if not campaign_completed.has(index):
			campaign_completed.append(index)
		if index < 36 and index == campaign_index:
			while campaign_index < 36 and campaign_completed.has(campaign_index):
				campaign_index += 1
		elif index >= 36:
			if index < 44:
				campaign_index = index + 1
			if not hidden_done.has(index):
				hidden_done.append(index)
		var town := level_town(index)
		if town >= 0 and not liberated.has(town):
			liberated.append(town)
		if index == 35:
			main_score_snapshot = score_total
			script_globals["0x7d0830"] = main_score_snapshot
		if campaign_index >= 36:
			hidden_unlocked = main_score_snapshot >= 2800
			ending_id = ending_for_score(main_score_snapshot)
		if index in [44, 45, 46]:
			campaign_index = int(script_globals.get("0x7d0834", campaign_index))
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
	if score >= 101:
		return 4
	if score >= 90:
		return 3
	if score >= 80:
		return 2
	if score >= 60:
		return 1
	return 0


func hidden_next(mode: String) -> int:
	var lo := 36 if mode == "simulation" else 40
	var hi := 40 if mode == "simulation" else 44
	var allowed := 1 if main_score_snapshot < 3000 else (2 if main_score_snapshot < 3300 else (3 if main_score_snapshot < 3600 else 4))
	if main_score_snapshot < 2800:
		return -1
	for i in range(lo, mini(hi, lo + allowed)):
		if not hidden_done.has(i):
			return i
	return -1


func hidden_mode_done(mode: String) -> bool:
	return hidden_next(mode) < 0


func available_easter() -> Array:
	# 彩蛋仅桃花岭民房30%随机入口，不按分数开放菜单。
	return []


func apply_battle_health(units: Array) -> void:
	for u in units:
		var pid := int(u.get("pid", -1))
		var m = deploy_member(pid)
		if m != null and m is Dictionary:
			(m as Dictionary)["hp"] = max(0, int(u.get("hp", 0)))


func to_dict() -> Dictionary:
	var raw_hex := {}
	for key in original_blocks:
		raw_hex[key] = (original_blocks[key] as PackedByteArray).hex_encode()
	return {
		"battle_resume": battle_resume.duplicate(true),
		"original_blocks_hex": raw_hex,
		"version": SAVE_VERSION,
		"money": money,
		"day": day,
		"party": party.duplicate(true),
		"reserve_members": reserve_members.duplicate(true),
		"script_globals": script_globals.duplicate(true),
		"main_score_snapshot": main_score_snapshot,
		"next_battle_overrides": next_battle_overrides.duplicate(true),
		"battle_turn": battle_turn,
		"play_seconds": play_seconds,
		"town_bgm_scene": town_bgm_scene,
		"items": items.duplicate(true),
		"materials": materials.duplicate(true),
		"mines": mines.duplicate(true),
		"liberated": liberated.duplicate(),
		"current_town": current_town,
		"campaign_index": campaign_index,
		"campaign_completed": campaign_completed.duplicate(),
		"level_scores": level_scores.duplicate(true),
		"score_total": score_total,
		"kills_by_gun": kills_by_gun,
		"kills_by_mine": kills_by_mine,
		"hidden_unlocked": hidden_unlocked,
		"hidden_done": hidden_done.duplicate(),
		"ending_id": ending_id,
		"endings_seen": endings_seen.duplicate(),
		"player_name": player_name,
		"protagonist": protagonist_member().duplicate(true),
		"difficulty": difficulty,
		"saved_at": Time.get_datetime_string_from_system(),
	}


func from_dict(d: Dictionary) -> bool:
	d = preload("res://scripts/battle/StateCodec.gd").integers(d)
	if int(d.get("version", 0)) not in [1, 2, 3, 4, 5, 6, SAVE_VERSION]:
		return false
	checkpoint_data.clear()
	battle_resume = (d.get("battle_resume",{}) as Dictionary).duplicate(true)
	if not battle_resume.is_empty(): checkpoint_data = battle_resume.get("checkpoint",{}).duplicate(true)
	original_blocks.clear()
	for key in d.get("original_blocks_hex", {}):
		original_blocks[key] = str(d["original_blocks_hex"][key]).hex_decode()
	money = int(d.get("money", 0))
	day = int(d.get("day", 1))
	party = (d.get("party", []) as Array).duplicate(true)
	reserve_members = (d.get("reserve_members", {}) as Dictionary).duplicate(true)
	script_globals = (d.get("script_globals", {}) as Dictionary).duplicate(true)
	main_score_snapshot = int(d.get("main_score_snapshot", d.get("score_total", 0)))
	next_battle_overrides = (d.get("next_battle_overrides", {}) as Dictionary).duplicate(true)
	battle_turn = int(d.get("battle_turn", 1))
	play_seconds = int(d.get("play_seconds", 0))
	town_bgm_scene = int(d.get("town_bgm_scene",34))
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
	kills_by_gun = int(d.get("kills_by_gun", 0))
	kills_by_mine = int(d.get("kills_by_mine", 0))
	hidden_unlocked = bool(d.get("hidden_unlocked", false))
	hidden_done = (d.get("hidden_done", []) as Array).duplicate()
	ending_id = int(d.get("ending_id", 0))
	endings_seen = []
	for v in d.get("endings_seen", []):
		endings_seen.append(int(v))
	player_name = str(d.get("player_name", "李勇"))
	protagonist = (d.get("protagonist", {}) as Dictionary).duplicate(true)
	if protagonist.is_empty():
		configure_protagonist()
	difficulty = int(d.get("difficulty", 1))
	saved_at = str(d.get("saved_at", ""))
	return true


func save_original(path: String = "user://dlz_original.dat") -> bool:
	var level := m4_level(campaign_index)
	var bytes: PackedByteArray = OriginalSave.encode(self, level)
	if bytes.size() != OriginalSave.SIZE:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


func load_original(path: String = "user://dlz_original.dat") -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	if f.get_length() != OriginalSave.SIZE:
		f.close()
		return false
	var bytes := f.get_buffer(OriginalSave.SIZE)
	f.close()
	var d: Dictionary = OriginalSave.decode(bytes)
	return OriginalSave.apply(self, d, path)


func original_info(path: String = "user://dlz_original.dat") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_length() != OriginalSave.SIZE:
		f.close()
		return {}
	var bytes := f.get_buffer(OriginalSave.SIZE)
	f.close()
	return OriginalSave.decode(bytes)


func difficulty_scale() -> float:
	match difficulty:
		0: return 0.75
		2: return 1.15
		_: return 1.0


func apply_difficulty(level: Dictionary) -> void:
	# 42A199：按已部署的0..31已入队成员平均等级，只上调主线非我军等级。
	var total := 0
	var count := 0
	for u in level.get("units", []):
		if str(u.get("side", "")) == "player" and int(u.get("slot", 128)) < 32:
			total += int(u.get("level", 1))
			count += 1
	var idx := int(level.get("index", 0))
	var gap := total / maxi(1, count) - (idx * 2 + 1)
	var offset := 0
	if idx < 36 and gap >= 2 and difficulty != 0:
		offset = gap / 2 if difficulty == 1 else gap * 4 / 5
	var active_slots := {}
	for u in level.get("units",[]): active_slots[int(u.get("slot",-1))] = true
	for u in level.get("units", []) + level.get("slot_pool", []) + level.get("spawn_pool", []):
		if str(u.get("side", "")) != "player" and active_slots.has(int(u.get("slot",-1))):
			u["level"] = mini(99, int(u.get("level", 1)) + offset)
		var cls: Dictionary = data.get("units", {}).get(str(u.get("bingzhong", 0)), {})
		u["hp"] = max_hp_for(int(u.get("bingzhong", 0)), int(u.get("level", 1)))
		u["max_hp"] = u["hp"]
		u["morale"] = 100
		u["integrity"] = 100
		u["defense_integrity"] = 100
	level["difficulty_setting"] = difficulty


func save_checkpoint(persist := true) -> bool:
	battle_resume.clear()
	checkpoint_data = to_dict().duplicate(true)
	return save_slot(8) if persist else true


func load_checkpoint() -> bool:
	var recent := {}
	for slot in range(40): recent[slot] = person(slot).duplicate(true)
	var diff := difficulty
	var restored := false
	var baseline: Dictionary = checkpoint_data if not checkpoint_data.is_empty() else slot_info(8)
	if not baseline.is_empty():
		# 42ACB9 restores People, not the strategic money/warehouse/global state.
		protagonist = baseline.get("protagonist",{}).duplicate(true)
		party = baseline.get("party",[]).duplicate(true)
		reserve_members = baseline.get("reserve_members",{}).duplicate(true)
		restored = true
	if not restored: return false
	# 42ACB9: easy retains friendly level/XP and all attack practice; normal restores those.
	if diff < 2:
		for slot in range(40):
			var m := person(slot)
			var now: Dictionary = recent[slot]
			if diff == 0:
				if int(m.get("faction",1)) == 0:
					m["level"] = now.get("level",m["level"])
					m["xp"] = now.get("xp",m["xp"])
				m["attack_count"] = now.get("attack_count",m["attack_count"])
			for key in m.get("skills",{}):
				if int(m["skills"][key]) != 0:
					m["skills"][key] = int(now.get("skills",{}).get(key,m["skills"][key]))
			m["max_hp"] = max_hp_for(int(m["bingzhong"]),int(m["level"]))
			m["hp"] = m["max_hp"]
	return true


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
