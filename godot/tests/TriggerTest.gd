extends SceneTree

## 0x446510 触发器的行为级回归：不只看 schema，还强制战场状态验证
## “到达 / 占格 / 生成 / 移除 / 胜负 / 分数”确实由数据驱动。

var failures: Array[String] = []
var font: Font
var m4: Dictionary
var m2: Dictionary
var gs


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok   ", msg)
	else:
		failures.append(msg)
		print("FAIL ", msg)


func _load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return null if f == null else JSON.parse_string(f.get_as_text())


func _new_battle(idx: int):
	var builder = load("res://scripts/m4/LevelBuilder.gd")
	# Full original-person fixtures, not a campaign-clear claim. gs.party
	# excludes the protagonist and cannot stand in for a deployed roster.
	var people:Array=[]
	for slot in range(40):people.append(gs.person(slot))
	var built: Dictionary = builder.build(m4, m2, idx, people, false)
	var b = load("res://scripts/Battle.gd").new()
	root.add_child(b)
	b.fast_sim=true
	b.setup(m4, built, font)
	b.set_process(false)
	return b


func _leader(b):
	for u in b.player_units:
		if u.alive:
			return u
	return null


func _run() -> void:
	m4 = _load_json("res://data/m4.json")
	m2 = _load_json("res://data/m2.json")
	font = load("res://assets/font/hzk16.fnt")
	gs = load("res://scripts/m2/GameState.gd").new()
	gs.setup_m4(m4)
	gs.new_game(m2)
	if m4 == null or m2 == null or font == null:
		print("TRIGGER_TEST_FAIL data")
		quit(1)
		return

	# 1) 47 关都有触发数据，且入口地址与 dump 表一致
	var entries := {
		0: "0x408D28", 3: "0x409107", 12: "0x40995B", 18: "0x40A0BA",
		36: "0x40B2CF", 39: "0x40BC2F", 42: "0x410B99", 46: "0x411873",
	}
	var all_have := true
	for lv in m4["levels"]:
		var t: Dictionary = lv.get("triggers", {})
		if t.is_empty() or (t.get("rules", []) as Array).is_empty():
			all_have = false
			print("  no triggers L", lv["index"])
	_check(all_have, "47 关都有触发器规则")
	var entries_ok := true
	for idx in entries:
		if str(m4["levels"][idx]["triggers"].get("entry", "")) != entries[idx]:
			entries_ok = false
			print("  entry mismatch L", idx, m4["levels"][idx]["triggers"].get("entry", ""))
	_check(entries_ok, "关键关入口地址与 0x446510 dump 一致")

	# 1b) 47 关在开场 tick 不应被触发器直接判胜负
	var start_ok := true
	for idx in range(47):
		var sb = _new_battle(idx)
		if bool(sb.finished_flag):
			start_ok = false
			print("  early finish L", idx, " ", sb.last_result)
		sb.queue_free()
	_check(start_ok, "47 关开场不误触发胜负")

	# 2) L00 到达 (17,0) -> 胜利
	var b = _new_battle(0)
	var p = _leader(b)
	p.set_tile(17, 0)
	b.scenario.on_tick()
	_check(bool(b.finished_flag) and b.last_result == "victory", "L00 到达 (17,0) 胜利")
	b.queue_free()

	# 3) L00 进入 (12,8) -> 42–44 生成
	b = _new_battle(0)
	p = _leader(b)
	_check(b.unit_by_slot(42) == null, "L00 42 初始不在场")
	p.set_tile(12, 8)
	b.scenario.on_tick()
	_check(b.unit_by_slot(42) != null and b.unit_by_slot(43) != null \
			and b.unit_by_slot(44) != null, "L00 进入 (12,8) 生成 42–44")
	b.queue_free()

	# 4) L04 移除 40 -> 胜利
	b = _new_battle(4)
	b.remove_slot(40)
	b.scenario.on_tick()
	_check(bool(b.finished_flag) and b.last_result == "victory", "L04 40 号离场胜利")
	b.queue_free()

	# 5) L12 两个仓库格各站 1 人 -> 胜利
	b = _new_battle(12)
	for u in b.units:
		if u.alive and u.side == "enemy" and (u.x == 8 or u.x == 10) and u.y == 3:
			b.remove_slot(int(u.slot))
	var ps: Array = b.player_units.filter(func(u): return u.alive)
	if ps.size()<2:
		ps.append(b._spawn_unit(load("res://scripts/m4/LevelBuilder.gd").member_unit(m2,gs.person(1),{"x":0,"y":0})))
		b.set_slot_faction(1,0)
	if ps.size() >= 2:
		ps[0].set_tile(8, 3)
		ps[1].set_tile(10, 3)
		b.scenario.on_tick()
		_check(bool(b.finished_flag) and b.last_result == "victory", "L12 占住 (8,3)/(10,3) 胜利")
	else:
		_check(false, "L12 需要至少 2 名我方")
	b.queue_free()

	# 6) L10 站到 65 号隐藏目标格 -> 65 出场
	b = _new_battle(10)
	p = _leader(b)
	var t65: Vector2i = b.scenario._slot_pos(65)
	p.set_tile(t65.x, t65.y)
	b.scenario.on_tick()
	_check(b.unit_by_slot(65) != null, "L10 目标格被占后 65 出场")
	b.queue_free()

	# 7) L16 与 19 号相邻 -> 清场并生成 33/35
	b = _new_battle(16)
	var u19 = b.unit_by_slot(19)
	p = null
	for u in b.player_units:
		if u != u19 and u.alive:
			p = u
			break
	var tx: int = u19.x + 1
	var ty: int = u19.y
	p.set_tile(tx, ty)
	b.scenario.on_tick()
	_check(b.unit_by_slot(33) != null and b.unit_by_slot(35) != null,
			"L16 邻接事件后 33/35 登场")
	_check(b.unit_by_slot(40) == null, "L16 邻接事件清掉 40")
	b.queue_free()

	# 8) L19 40–42 全部离场 -> +1000 胜利
	b = _new_battle(19)
	b.remove_slot(40)
	b.remove_slot(41)
	b.remove_slot(42)
	b.scenario.on_tick()
	_check(bool(b.finished_flag) and b.last_result == "victory", "L19 40–42 离场胜利")
	_check(int(b.stats.get("money_bonus", 0)) == 1000, "L19 组 1 +1000 元")
	b.queue_free()

	# 9) L26 到达 (2,39) -> 胜利
	b = _new_battle(26)
	p = _leader(b)
	p.set_tile(2, 39)
	b.scenario.on_tick()
	_check(bool(b.finished_flag) and b.last_result == "victory", "L26 到达 (2,39) 胜利")
	b.queue_free()

	# 10) L45 40 号到达 (0,0) -> 胜利
	b = _new_battle(45)
	var u40 = b.unit_by_slot(40)
	u40.set_tile(0, 0)
	b.scenario.on_tick()
	_check(bool(b.finished_flag) and b.last_result == "victory", "L45 柳忻到达 (0,0) 胜利")
	b.queue_free()

	# 10b) L37 存活单位<2 -> 95–104 增援
	b = _new_battle(37)
	for u in b.units:
		if int(u.slot) != 40:
			b.remove_slot(int(u.slot))
	b.scenario.on_tick()
	_check(b.unit_by_slot(95) != null and b.unit_by_slot(104) != null,
			"L37 残存<2 时 95–104 增援")
	b.queue_free()

	# 10c) L38 44/59/60 都不在场 -> 68/69/71 + 98–125 增援
	b = _new_battle(38)
	b.remove_slot(44)
	b.remove_slot(59)
	b.remove_slot(60)
	b.scenario.on_tick()
	_check(b.unit_by_slot(68) != null and b.unit_by_slot(98) != null,
			"L38 44/59/60 离场后 68/98 增援")
	b.queue_free()

	# 11) L46 村民少于 11 -> 失败
	b = _new_battle(46)
	b.remove_slot(70)
	b.remove_slot(71)
	b.remove_slot(72)
	b.scenario.on_tick()
	_check(bool(b.finished_flag) and b.last_result == "defeat", "L46 村民少于 11 失败")
	b.queue_free()

	# 12) 旧 objective 不再抢在触发器前判胜
	b = _new_battle(0)
	p = _leader(b)
	p.set_tile(17, 1)
	b.scenario.on_tick()
	_check(not b.finished_flag, "L00 旧目标 (17,1) 不抢判")
	b.queue_free()

	b = _new_battle(12)
	var e12 = b.enemy_units[0]
	e12.set_tile(8, 3)
	b.scenario.on_tick()
	_check(not b.finished_flag, "L12 只有敌军占仓库格不判胜")
	b.queue_free()

	b = _new_battle(26)
	var e26 = b.enemy_units[0]
	e26.set_tile(2, 39)
	b.scenario.on_tick()
	_check(not b.finished_flag, "L26 只有敌军在 (2,39) 不判胜")
	b.queue_free()

	b = _new_battle(10)
	p = _leader(b)
	p.set_tile(4, 35)
	b.scenario.on_tick()
	_check(not b.finished_flag, "L10 旧目标点不抢判")
	b.queue_free()

	b = _new_battle(18)
	var u21 = b.unit_by_slot(21)
	p = _leader(b)
	if u21 != null:
		p.set_tile(u21.x + 1, u21.y)
		b.scenario.on_tick()
	_check(not b.finished_flag, "L18 接近郑之光不抢判")
	b.queue_free()

	b = _new_battle(23)
	p = _leader(b)
	p.set_tile(24, 4)
	b.scenario.on_tick()
	_check(not b.finished_flag, "L23 旧目标点不抢判")
	b.queue_free()

	# 13) 主角阵亡消息：0x472598 是 TXT 槽 4，不是 WAV
	b = _new_battle(0)
	p = _leader(b)
	b.remove_slot(int(p.slot))
	b.scenario.on_tick()
	_check(b.trigger_messages.any(func(m): return int(m.get("record", -1)) == 4),
			"L00 主角阵亡显示 TXT 4")
	_check(bool(b.finished_flag) and b.last_result == "defeat",
			"L00 主角阵亡失败")
	b.queue_free()

	# 14) L00 T750 第 6 回合重排 40/41，西北院重新生成
	b = _new_battle(0)
	b.scenario.on_turn_start(6)
	b.scenario.on_tick()
	_check(b.scenario._global_value("0x583F18") == 2,
			"L00 第 6 回合 flag=2")
	_check(b.unit_by_slot(40) == null and b.unit_by_slot(41) == null,
			"L00 第 6 回合撤下 40/41")
	_check(b.scenario._slot_pos(40) == Vector2i(1, 3),
			"L00 40 号重排到 (1,3)")
	p = _leader(b)
	p.set_tile(1, 6)
	b.scenario.on_tick()
	_check(b.unit_by_slot(40) != null and b.unit_by_slot(41) != null,
			"L00 西北院重新生成 40/41")
	b.queue_free()

	b = _new_battle(0)
	b.scenario.on_turn_start(41)
	b.scenario.on_tick()
	_check(bool(b.finished_flag) and b.last_result == "defeat",
			"L00 第 41 回合失败")
	b.queue_free()

	# 15) L22 三选一：放走 +5000
	b = _new_battle(22)
	b.fast_sim=false
	b.remove_slot(24)
	b.scenario.on_tick()
	_check(not b.scenario.pending_choice.is_empty(), "L22 触发三选一")
	_check(b.trigger_messages.any(func(m): return int(m.get("record", -1)) == 159),
			"L22 显示投降 TXT 159")
	b.scenario.resolve_choice(1)
	_check(int(b.stats.get("money_bonus", 0)) == 5000, "L22 放走 +5000")
	_check(bool(b.finished_flag) and b.last_result == "victory", "L22 放走胜利")
	b.queue_free()

	# 收编仅改People.side，24保持离场，不能复活补HP/移动/改控制。
	b = _new_battle(22)
	b.fast_sim=false
	b.remove_slot(24)
	b.scenario.on_tick()
	b.scenario.resolve_choice(2)
	var r24 = b.units.filter(func(u):return int(u.slot)==24)[0]
	var r25 = b.unit_by_slot(25)
	_check(r24 != null and r24.side == "player" and int(r24.data.faction)==0 and not r24.alive, "L22 收编 24 号不复活")
	_check(r25 != null and r25.side == "player" and int(r25.data.faction)==0, "L22 收编 25 号精确侧别")
	_check(not r24.control and not r25.control and b.stats.get("recruited",[]).is_empty(), "L22 不改控制或额外结算招募")
	b.queue_free()

	# 枪毙：People0..23等级 +2
	b = _new_battle(22)
	b.fast_sim=false
	if not b.player_units.is_empty():
		b.player_units[0].morale = 80
	var before: Array = []
	for u in b.player_units:
		before.append(int(u.data.level))
	b.remove_slot(24)
	b.scenario.on_tick()
	b.scenario.resolve_choice(0)
	var gained := false
	for i in range(b.player_units.size()):
		if int(b.player_units[i].data.level) > int(before[i]):
			gained = true
	_check(gained, "L22 枪毙People0..23等级 +2")
	b.queue_free()

	# 16) L23 34 号随机出生，占住出生格后出场胜利
	b = _new_battle(23)
	_check(b.scenario._global_value("0x583F54") == 1,
			"L23 第 1 回合初始化 34 号")
	var pos34: Vector2i = b.scenario._slot_pos(34)
	_check(pos34 in [Vector2i(0, 31), Vector2i(7, 31), Vector2i(21, 21)],
			"L23 34 号出生点在三个预设点")
	for u in b.enemy_units.duplicate():
		b.remove_slot(int(u.slot))
	p = _leader(b)
	p.set_tile(pos34.x, pos34.y)
	b.scenario.on_tick()
	_check(b.unit_by_slot(34) != null, "L23 34 号在出生格生成")
	_check(bool(b.finished_flag) and b.last_result == "victory", "L23 占出生格胜利")
	b.queue_free()

	# 17) L38 出口占格按阵营判定
	b = _new_battle(38)
	var e38 = b.enemy_units[0]
	e38.set_tile(18, 40)
	b.scenario.on_tick()
	_check(bool(b.finished_flag) and b.last_result == "defeat",
			"L38 敌军进入出口判负")
	b.queue_free()

	b = _new_battle(38)
	p = _leader(b)
	p.set_tile(18, 40)
	b.scenario.on_tick()
	_check(not b.finished_flag, "L38 我军进入出口不判负")
	b.queue_free()

	# 18) L18未招募21的side原值1来自People批量加载。
	b = _new_battle(18)
	b.remove_slot(21)
	b.scenario.on_tick()
	_check(b.finished_flag and b.last_result=="victory", "L18未招募21离场清敌胜利")
	b.queue_free()

	if failures.is_empty():
		print("TRIGGER_TEST_OK")
		quit(0)
	else:
		print("TRIGGER_TEST_FAIL %d" % failures.size())
		quit(1)
