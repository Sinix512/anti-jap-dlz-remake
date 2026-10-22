extends RefCounted

## 原版 85072 B 存档布局的编解码器（实验）。
## 布局来自 dlz_save.bt / 28 个 block 尺寸；名字用 GBK 字节写入。
## 注意：尚未用原始 DLZ.exe 回读验证；未识别的原版字段写 0。
## 游戏内正式存档仍是 GameState 的 JSON；这里是兼容桥/校验工具。

const SIZE := 85072
const SKILL_KEYS := ["buji", "jili", "yiliao", "huogong", "gunmu", "leishi",
		"weishe", "saorao", "pohuai", "lueduo", "fanjian", "yibing",
		"duzhan", "ansha", "shidu", "kongxi"]


static func _pad(b: StreamPeerBuffer, n: int) -> void:
	var z := PackedByteArray()
	z.resize(n)
	b.put_data(z)


static func _skip(b: StreamPeerBuffer, n: int) -> void:
	b.seek(b.get_position() + n)


static func _put_name(b: StreamPeerBuffer, raw: PackedByteArray, n: int) -> void:
	var out := PackedByteArray()
	out.resize(n)
	for i in range(min(n, raw.size())):
		out[i] = raw[i]
	b.put_data(out)


static func _gbk(hex: String) -> PackedByteArray:
	if hex == "":
		return PackedByteArray()
	return hex.hex_decode()


static func _write_at(arr: PackedByteArray, off: int, raw: PackedByteArray,
		n: int) -> void:
	for i in range(min(n, raw.size())):
		arr[off + i] = raw[i]


static func _people_bytes(state) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	var base: Array = state.data.get("people", [])
	var by_pid := {}
	for m in state.party:
		by_pid[int(m["pid"])] = m
	for i in range(128):
		if i >= base.size():
			_pad(b, 132)
			continue
		var p: Dictionary = base[i]
		var m = by_pid.get(i)
		_put_name(b, _gbk(str(p.get("name_gbk_hex", ""))), 16)
		b.put_u32(int(p.get("face", 0)))
		b.put_u32(0)
		b.put_u32(int(p.get("unknown_18", 0)))
		b.put_u32(int(p.get("wuli", 0)))
		b.put_u32(int(p.get("zhili", 0)))
		b.put_u32(int(m.get("level", p.get("level", 1))) if m != null else int(p.get("level", 1)))
		b.put_u32(int(m.get("xp", p.get("jingyan", 0))) if m != null else 0)
		b.put_u32(int(m.get("bingzhong", p.get("bingzhong", 0))) if m != null else int(p.get("bingzhong", 0)))
		var counts: Dictionary = (m.get("skills", p.get("skills", {})) if m != null else p.get("skills", {}))
		b.put_u32(int(m.get("attack_count", p.get("gongji", 0))) if m != null else 0)
		for k in SKILL_KEYS:
			b.put_u32(int(counts.get(k, 0)))
		var slots: Array = (m.get("item_slots", p.get("wupin", [])) if m != null else p.get("wupin", []))
		for j in range(8):
			b.put_u8(int(slots[j]) if j < slots.size() else 0)
		var mines: Array = (m.get("mine_slots", p.get("dilei", [])) if m != null else p.get("dilei", []))
		for j in range(8):
			b.put_u8(int(mines[j]) if j < mines.size() else 0)
	return b.get_data_array()


static func encode(state, level: Dictionary) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u32(2)  # block0（用途未完全确认）
	b.put_u32(0x28)  # block1 game state：战略界面
	b.put_u32(1)  # block2 difficulty
	b.put_u32(100)  # terrain modifier
	# Intro 700 B: 关卡名/成功/失败按 GBK 写入。
	var intro := PackedByteArray(); intro.resize(700)
	_write_at(intro, 0x00, _gbk(str(level.get("name_gbk_hex", ""))), 32)
	_write_at(intro, 0x28, _gbk(str(level.get("success_gbk_hex", ""))), 64)
	_write_at(intro, 0x68, _gbk(str(level.get("failure_gbk_hex", ""))), 64)
	intro.encode_u32(0x20, 1)
	intro.encode_u32(0x2B4, 99)
	b.put_data(intro)
	b.put_u32(int(state.current_town))  # block5 town
	b.put_u32(mini(0xFFFFFFFF, int(state.money)))  # block6 money
	_pad(b, 12)
	_pad(b, 64)
	for i in range(19):
		b.put_u32(1 if state.is_liberated(i) else 0)
	for i in range(14):
		var v := 0
		match i:
			0: v = int(state.campaign_index)
			1: v = int(state.score_total)
			2: v = 1 if state.hidden_unlocked else 0
			3: v = int(state.ending_id)
			4: v = state.campaign_completed.size()
		b.put_u32(v)
	# block13 用途未确认；尾部写私有 PARY 扩展保存队伍，供本工具回读。
	var b13 := PackedByteArray(); b13.resize(380)
	# block13 开头是原版 0/1/2 状态机，保持 0；PARY 放到尾部 40 B。
	b13.encode_u32(340, 0x50415259)  # PARY
	for i in range(10):
		b13.encode_u32(344 + i * 4, int(state.party[i]["pid"]) if i < state.party.size() else 0)
	b.put_data(b13)
	_pad(b, 8192)
	_pad(b, 8192)
	var people := _people_bytes(state)
	b.put_data(people)
	b.put_data(people)
	for i in range(160):
		b.put_u16(mini(65535, state.item_count(i)))
	_pad(b, 320)
	# block20/21 是 4×10 物品格缓存：当前页写前 10 个库存物品。
	var top_ids: Array = []
	for i in range(160):
		if state.item_count(i) > 0:
			top_ids.append(i)
			if top_ids.size() >= 10:
				break
	for i in range(40):
		b.put_u16(state.item_count(int(top_ids[i])) if i < top_ids.size() else 0)
	for i in range(10):
		b.put_u32(int(top_ids[i]) if i < top_ids.size() else 0)
	_pad(b, 32768)
	_pad(b, 8)
	_pad(b, 28)
	_pad(b, 12)
	b.put_u32(int(Time.get_unix_time_from_system()))
	b.put_u32(0)
	var data := b.get_data_array()
	if data.size() != SIZE:
		push_error("OriginalSave size %d != %d" % [data.size(), SIZE])
	return data


static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() != SIZE:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = data
	b.big_endian = false
	b.get_u32()  # block0
	var out := {"game_state": int(b.get_u32()), "difficulty": int(b.get_u32())}
	b.get_u32()  # block3 terrain
	var intro_got = b.get_data(700)
	var intro: PackedByteArray = intro_got[1]
	out["intro_name_gbk_hex"] = intro.slice(0, 32).hex_encode()
	out["intro_success_gbk_hex"] = intro.slice(0x28, 0x28 + 64).hex_encode()
	out["intro_failure_gbk_hex"] = intro.slice(0x68, 0x68 + 64).hex_encode()
	out["town"] = int(b.get_u32())
	out["money"] = int(b.get_u32())
	out["map_width"] = 128
	_skip(b, 12)
	_skip(b, 64)
	var liberated: Array = []
	for i in range(19):
		if int(b.get_u32()) != 0:
			liberated.append(i)
	out["liberated"] = liberated
	var progress: Array = []
	for i in range(14):
		progress.append(int(b.get_u32()))
	var b13_got = b.get_data(380)
	var b13: PackedByteArray = b13_got[1]
	_skip(b, 8192)
	_skip(b, 8192)
	var people_got = b.get_data(16896)
	var people_raw: PackedByteArray = people_got[1]
	_skip(b, 16896)
	var people := _decode_people(people_raw)
	out["people"] = people
	var cangku: Array = []
	for i in range(160):
		cangku.append(int(b.get_u16()))
	var items := {}
	for i in range(160):
		if cangku[i] > 0:
			items[str(i)] = cangku[i]
	out["items"] = items
	_skip(b, 320)
	var grid_counts: Array = []
	for i in range(40):
		grid_counts.append(int(b.get_u16()))
	var grid_ids: Array = []
	for i in range(10):
		grid_ids.append(int(b.get_u32()))
	out["item_grid"] = {"ids": grid_ids, "counts": grid_counts.slice(0, 10)}
	var members: Array = []
	if b13.size() >= 380 and b13.decode_u32(340) == 0x50415259:
		for i in range(10):
			var pid := int(b13.decode_u32(344 + i * 4))
			if pid > 0 and pid < 40:
				members.append(pid)
	out["members"] = members
	out["fight_index"] = progress[0] if progress.size() > 0 else 0
	out["score_total"] = progress[1] if progress.size() > 1 else 0
	out["hidden_unlocked"] = (progress[2] if progress.size() > 2 else 0) != 0
	out["ending_id"] = progress[3] if progress.size() > 3 else 0
	out["campaign_completed"] = progress[4] if progress.size() > 4 else 0
	return out


static func _decode_people(raw: PackedByteArray) -> Array:
	var out: Array = []
	var b := StreamPeerBuffer.new()
	b.data_array = raw
	b.big_endian = false
	for i in range(128):
		var name_got = b.get_data(16)
		var name_bytes: PackedByteArray = name_got[1]
		var face := int(b.get_u32())
		b.get_u32()
		var enemy := int(b.get_u32())
		var wuli := int(b.get_u32())
		var zhili := int(b.get_u32())
		var level := int(b.get_u32())
		var xp := int(b.get_u32())
		var bz := int(b.get_u32())
		var atk := int(b.get_u32())
		var skills := {}
		for k in SKILL_KEYS:
			skills[k] = int(b.get_u32())
		var items: Array = []
		for j in range(8):
			items.append(int(b.get_u8()))
		var mines: Array = []
		for j in range(8):
			mines.append(int(b.get_u8()))
		out.append({"slot": i, "name_gbk": name_bytes, "face": face,
				"enemy": enemy, "wuli": wuli, "zhili": zhili, "level": level,
				"xp": xp, "bingzhong": bz, "attack_count": atk,
				"skills": skills, "items": items, "mines": mines})
	return out


static func apply(state, d: Dictionary, path: String) -> bool:
	if d.is_empty():
		return false
	state.party.clear()
	state.items.clear()
	state.materials.clear()
	state.mines.clear()
	state.liberated = (d.get("liberated", []) as Array).duplicate()
	state.money = int(d.get("money", 0))
	state.current_town = int(d.get("town", 0))
	state.campaign_index = int(d.get("fight_index", 0))
	state.score_total = int(d.get("score_total", 0))
	state.hidden_unlocked = bool(d.get("hidden_unlocked", false))
	state.ending_id = int(d.get("ending_id", 0))
	state.campaign_completed.clear()
	for i in range(min(state.campaign_index, 36)):
		state.campaign_completed.append(i)
	var people: Array = d.get("people", [])
	for pid in d.get("members", []):
		var p: Dictionary = people[pid] if pid < people.size() else {}
		state._add_member(int(pid))
		var m = state.get_member(int(pid))
		if m == null:
			continue
		m["level"] = int(p.get("level", 1))
		m["xp"] = int(p.get("xp", 0))
		m["bingzhong"] = int(p.get("bingzhong", m.get("bingzhong", 0)))
		m["wuli"] = int(p.get("wuli", m.get("wuli", 0)))
		m["zhili"] = int(p.get("zhili", m.get("zhili", 0)))
		m["skills"] = (p.get("skills", {}) as Dictionary).duplicate(true)
		m["attack_count"] = int(p.get("attack_count", 0))
		m["item_slots"] = (p.get("items", []) as Array).duplicate()
		m["mine_slots"] = (p.get("mines", []) as Array).duplicate()
		m["max_hp"] = state.max_hp_for(int(m["bingzhong"]), int(m["level"]))
		m["hp"] = int(m["max_hp"])
	if state.party.is_empty():
		# 真原版存档没有 PARY；回退到默认起始队伍，避免导入后队伍为空。
		for pid in state.data.get("starting", {}).get("party", []):
			state._add_member(int(pid))
	for k in d.get("items", {}):
		state.items[str(k)] = int(d["items"][k])
	state.saved_at = "original:" + path
	return true
