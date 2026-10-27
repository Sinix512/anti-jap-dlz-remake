extends RefCounted

## 实验性原版28块布局：战略导出mode57；导入转战略状态，不声称战斗中途续存。
## 静态证据见extract/research_save_20261025.md及审计；尚无原EXE回读实测。
const SIZE := 85072
const BLOCK_SIZES := [4,4,4,4,700,4,4,4,4,4,64,76,56,380,8192,8192,16896,16896,320,320,80,40,32768,8,28,12,4,4]
const SKILL_KEYS := ["buji","jili","yiliao","huogong","gunmu","leishi","weishe","saorao","pohuai","lueduo","fanjian","yibing","duzhan","ansha","shidu","kongxi"]
const GBK = preload("res://scripts/m2/GBK.gd")

static func offsets() -> Array:
	var result: Array = []
	var offset := 0
	for size in BLOCK_SIZES:
		result.append(offset)
		offset += int(size)
	assert(offset == SIZE)
	return result

static func _block(state, index: int) -> PackedByteArray:
	var raw: PackedByteArray = state.original_blocks.get("block%d" % index,PackedByteArray()).duplicate()
	if raw.size() != int(BLOCK_SIZES[index]): raw.resize(int(BLOCK_SIZES[index]))
	return raw

static func _people_bytes(state, level: Dictionary) -> PackedByteArray:
	var raw := _block(state,16)
	if not state.original_blocks.has("block16"):
		var fight: PackedByteArray = str(level.get("people_hex","")).hex_decode()
		for i in range(mini(fight.size(),88*132)): raw[40*132+i] = fight[i]
	for slot in range(40):
		var member: Dictionary = state.person(slot)
		if member.is_empty(): continue
		var offset := slot*132
		var name: PackedByteArray = GBK.encode(str(member.get("name","")),16)
		for i in range(16): raw[offset+i] = name[i]
		raw.encode_u32(offset+16,int(member.get("face",0)))
		# pad2是原版未知/零字段，不再私写PART。
		for pair in [[24,"faction"],[28,"wuli"],[32,"zhili"],[36,"level"],[40,"xp"],[44,"bingzhong"],[48,"attack_count"]]:
			raw.encode_u32(offset+int(pair[0]),int(member.get(pair[1],0)))
		for index in range(16): raw.encode_u32(offset+52+index*4,int(member.get("skills",{}).get(SKILL_KEYS[index],0)))
		for pair in [[116,"item_slots",156],[124,"mine_slots",40]]:
			var slots: Array = member.get(pair[1],[])
			for index in range(8):
				var value := int(slots[index]) if index < slots.size() else 0
				if value < 0 or value > int(pair[2]):
					push_error("非法原版携带字节 slot%d/%s/%d" % [slot,pair[1],value])
					return PackedByteArray()
				raw[offset+int(pair[0])+index] = value
	return raw

static func encode(state, level: Dictionary) -> PackedByteArray:
	var blocks: Array = []
	for index in range(28): blocks.append(_block(state,index))
	blocks[0].encode_u32(0,57) # 原版load包装仅mode57进入世界图，其余转战斗150。
	blocks[1].encode_u32(0,int(state.campaign_index))
	blocks[2].encode_u32(0,int(state.difficulty))
	blocks[3].encode_u32(0,int(state.battle_turn))
	var intro: PackedByteArray = str(level.get("intro_hex","")).hex_decode()
	if intro.size() == 700: blocks[4] = intro
	for pair in [[5,state.current_town],[6,state.money],[7,state.score_total],[8,state.kills_by_gun],[9,state.kills_by_mine]]:
		blocks[int(pair[0])].encode_u32(0,int(pair[1]))
	for index in range(19): blocks[11].encode_u32(index*4,1 if state.is_liberated(index) else 0)
	for index in range(14): blocks[12].encode_u32(index*4,int(state.script_globals.get("0x%x" % (0x95eaf8+index*4),0)))
	for index in range(95):
		var key := "0x%x" % (0x7d06c8+index*4)
		if state.script_globals.has(key): blocks[13].encode_u32(index*4,int(state.script_globals[key]))
	blocks[13].encode_u32(90*4,int(state.main_score_snapshot))
	if not state.original_blocks.has("block14"):
		var fighters: PackedByteArray = str(level.get("fighter_hex","")).hex_decode()
		if fighters.size() == 8192:
			blocks[14] = fighters
			blocks[15] = fighters.duplicate()
	blocks[16] = _people_bytes(state,level)
	if blocks[16].size() != 16896: return PackedByteArray()
	if not state.original_blocks.has("block17"): blocks[17] = blocks[16].duplicate()
	for index in range(160): blocks[18].encode_u16(index*2,clampi(state.item_count(index),0,65535))
	# 战略导出已结算，不携带上次战斗暂存战利品/统计造成重复领取。
	blocks[19].fill(0)
	blocks[25].fill(0)
	for index in range(40): blocks[20].encode_u16(index*2,clampi(state.mine_count(index),0,65535))
	for index in range(10): blocks[21].encode_u32(index*4,maxi(0,state.material_count(index)))
	blocks[26].encode_u32(0,maxi(0,int(state.play_seconds)))
	blocks[27].encode_u32(0,int(state.town_bgm_scene))
	var result := PackedByteArray()
	for index in range(28):
		if blocks[index].size() != int(BLOCK_SIZES[index]): return PackedByteArray()
		result.append_array(blocks[index])
	return result if result.size() == SIZE else PackedByteArray()

static func decode(raw: PackedByteArray) -> Dictionary:
	if raw.size() != SIZE: return {}
	var locations := offsets()
	var blocks := {}
	for index in range(28): blocks["block%d" % index] = raw.slice(int(locations[index]),int(locations[index])+int(BLOCK_SIZES[index]))
	var index := int(blocks["block1"].decode_u32(0))
	var town := int(blocks["block5"].decode_u32(0))
	var difficulty := int(blocks["block2"].decode_u32(0))
	if index > 46 or town > 18 or difficulty > 2: return {}
	var out := {"game_state":int(blocks["block0"].decode_u32(0)),"fight_index":index,"town":town,"difficulty":difficulty,
		"battle_turn":int(blocks["block3"].decode_u32(0)),"money":int(blocks["block6"].decode_u32(0)),"score_total":int(blocks["block7"].decode_u32(0)),
		"kills_by_gun":int(blocks["block8"].decode_u32(0)),"kills_by_mine":int(blocks["block9"].decode_u32(0)),"play_seconds":int(blocks["block26"].decode_u32(0)),"town_bgm_scene":int(blocks["block27"].decode_u32(0)),"_raw":blocks}
	out["level_index"] = index # 仅旧UI兼容别名，绝不读block3为关卡。
	out["intro_name_gbk_hex"] = blocks["block4"].slice(0,32).hex_encode()
	var liberated: Array = []
	for i in range(19):
		if blocks["block11"].decode_u32(i*4) != 0: liberated.append(i)
	out["liberated"] = liberated
	var globals := {}
	for i in range(14): globals["0x%x" % (0x95eaf8+i*4)] = int(blocks["block12"].decode_u32(i*4))
	for i in range(95): globals["0x%x" % (0x7d06c8+i*4)] = int(blocks["block13"].decode_u32(i*4))
	out["script_globals"] = globals
	out["main_score_snapshot"] = int(blocks["block13"].decode_u32(360))
	for pair in [["items",18,160,2],["temp_loot",19,160,2],["mines",20,40,2],["materials",21,10,4]]:
		var stock := {}
		for i in range(int(pair[2])):
			var quantity := int(blocks["block%d" % pair[1]].decode_u16(i*2) if int(pair[3]) == 2 else blocks["block%d" % pair[1]].decode_u32(i*4))
			if quantity > 0: stock[str(i)] = quantity
		out[pair[0]] = stock
	var people: Array = []
	var source: PackedByteArray = blocks["block16"]
	var members: Array = []
	for i in range(128):
		var base := i*132
		var person := {"slot":i,"name_gbk":source.slice(base,base+16),"name":GBK.decode(source.slice(base,base+16)),"face":int(source.decode_u32(base+16)),"pad2":int(source.decode_u32(base+20))}
		for pair in [[24,"enemy"],[28,"wuli"],[32,"zhili"],[36,"level"],[40,"xp"],[44,"bingzhong"],[48,"attack_count"]]: person[pair[1]] = int(source.decode_u32(base+int(pair[0])))
		var skills := {}
		for j in range(16): skills[SKILL_KEYS[j]] = int(source.decode_u32(base+52+j*4))
		person["skills"] = skills
		person["items"] = Array(source.slice(base+116,base+124))
		person["mines"] = Array(source.slice(base+124,base+132))
		people.append(person)
		if i > 0 and i < 32 and int(person["enemy"]) == 0: members.append(i)
	out["people"] = people
	out["members"] = members
	return out

static func apply(state, d: Dictionary, path: String) -> bool:
	if d.is_empty() or (d.get("people",[]) as Array).size() != 128: return false
	# Native battle mode requires a dedicated 128-slot/flags/mines adapter. Never
	# silently heal/redeploy it as strategy and settle its temporary loot.
	if int(d.get("game_state",-1))!=57:return false
	# 先完整decode校验，之后一次性替换。保留m2/m4表，不继承上一局人物/剧情。
	state.new_game(state.data)
	state.original_blocks = (d["_raw"] as Dictionary).duplicate(true)
	for key in ["money","current_town","campaign_index","difficulty","battle_turn","play_seconds","town_bgm_scene","score_total","kills_by_gun","kills_by_mine"]:
		var source_key: String = "town" if key == "current_town" else ("fight_index" if key == "campaign_index" else key)
		state.set(key,int(d.get(source_key,0)))
	state.liberated = (d["liberated"] as Array).duplicate()
	state.script_globals = (d["script_globals"] as Dictionary).duplicate(true)
	state.main_score_snapshot = int(d["main_score_snapshot"])
	state.hidden_unlocked = state.main_score_snapshot >= 2800
	state.ending_id = state.ending_for_score(state.main_score_snapshot)
	state.party.clear()
	state.reserve_members.clear()
	for slot in range(40):
		var source: Dictionary = d["people"][slot]
		var m: Dictionary = state.person(slot)
		for key in ["name","face","wuli","zhili","level","xp","bingzhong","attack_count"]: m[key] = source[key]
		m["faction"] = int(source["enemy"])
		m["skills"] = (source["skills"] as Dictionary).duplicate(true)
		m["item_slots"] = (source["items"] as Array).duplicate()
		m["mine_slots"] = (source["mines"] as Array).duplicate()
		m["name_gbk_hex"] = (source["name_gbk"] as PackedByteArray).hex_encode()
		m["face_png"] = "res://assets/face/face_%03d.png" % int(m["face"])
		var cls: Dictionary = state.unit_of(m)
		m["army_png"] = "res://assets/army/army_%03d.png" % int(cls.get("img_index",0))
		m["unit_name"] = cls.get("name","")
		m["max_hp"] = state.max_hp_for(int(m["bingzhong"]),int(m["level"]))
		m["hp"] = m["max_hp"] # 明确战略导入；下一战依原版满血初始化。
		if slot == 0: state.player_name = str(m["name"])
		elif slot < 32 and int(m["faction"]) == 0: state.party.append(m)
	state.items = (d["items"] as Dictionary).duplicate(true)
	state.mines = (d["mines"] as Dictionary).duplicate(true)
	state.materials = (d["materials"] as Dictionary).duplicate(true)
	# 战略转换把未结战利品入库一次，并清保留块，防止再次领取。
	for key in d["temp_loot"]: state.add_item(int(key),int(d["temp_loot"][key]))
	state.original_blocks["block19"].fill(0)
	for i in range(mini(state.campaign_index,36)): state.campaign_completed.append(i)
	state.saved_at = "original strategy import:" + path
	return true
