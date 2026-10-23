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
	var built: Dictionary = builder.build(m4, m2, idx, gs.party, false)
	var b = load("res://scripts/Battle.gd").new()
	root.add_child(b)
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
	var ps: Array = b.player_units.filter(func(u): return u.alive)
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
	_check(int(b.stats.get("score_bonus", 0)) == 1000, "L19 组 1 +1000 分")
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

	if failures.is_empty():
		print("TRIGGER_TEST_OK")
		quit(0)
	else:
		print("TRIGGER_TEST_FAIL %d" % failures.size())
		quit(1)
