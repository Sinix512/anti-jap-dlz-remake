extends "res://scripts/m2/Campaign.gd"

## M4/M5 战役层：19 城镇、47 关、原味 UI、剧情/结局。
## 经济/商店/锻造/队伍/存档复用 M2 Campaign 的实现，只替换表现与关卡流程。

const M4_PATH := "res://data/m4.json"
const M5_PATH := "res://data/m5.json"
const M3_PATH := "res://data/m3.json"
const LevelBuilder = preload("res://scripts/m4/LevelBuilder.gd")

var m4: Dictionary = {}
var m5: Dictionary = {}
var m3: Dictionary = {}
var campaign_mode := "main"
var current_battle_index := -1
var current_battle_standalone := false
var battle_start_stats: Dictionary = {}
var story_player: Control
var cutscene: Control
var ending_layer: CanvasLayer
var _last_report: Dictionary = {}
var battle_story_queue: Array = []
var battle_story_seen: Dictionary = {}
var story_layer: CanvasLayer
var deploy_selected: Array = []
var current_deploy_pids: Array = []
var levelup_layer: CanvasLayer
var pending_report: Dictionary = {}
var credits_layer: CanvasLayer


func setup(font_ref: Font) -> void:
	font = font_ref
	ui_theme = OriginalUI.make_theme(font)
	self.theme = ui_theme
	m2 = _load_json(M2_PATH)
	m1 = _load_json(M1_PATH)
	m4 = _load_json(M4_PATH)
	m5 = _load_json(M5_PATH)
	m3 = _load_json(M3_PATH)
	if m2.is_empty() or m4.is_empty():
		_fatal("缺少 m2.json / m4.json\n请先运行 tools/prepare_m2.py 与 prepare_m4.py")
		return
	state = load("res://scripts/m2/GameState.gd").new()
	state.setup_m4(m4)
	state.new_game(m2)
	state.player_name = _load_player_name()
	var vcfg := ConfigFile.new()
	if vcfg.load("user://dlz_config.cfg") == OK:
		state.story_variant = bool(vcfg.get_value("video", "story_variant", false))
		state.difficulty = int(vcfg.get_value("gameplay", "difficulty", 1))
	selected_town = state.level_town(state.campaign_index)
	state.current_town = selected_town
	_show_world()


func _load_player_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("user://dlz_config.cfg") == OK:
		return str(cfg.get_value("player", "name", "李勇"))
	return "李勇"


func _process(_delta: float) -> void:
	if not is_instance_valid(battle) or battle.finished_flag \
			or battle_story_queue.is_empty() or is_instance_valid(story_player) \
			or is_instance_valid(cutscene):
		return
	if battle.busy or battle.phase != "player":
		return
	var ids: Array = battle_story_queue.pop_front()
	if ids.is_empty():
		return
	battle.busy = true
	var b = battle
	_play_story(ids, func():
		if is_instance_valid(b):
			b.busy = false
	)


func load_campaign_slot(slot: int) -> bool:
	if not state.load_slot(slot):
		return false
	state.setup_m4(m4)
	selected_town = state.current_town
	_show_world()
	return true


# ---------------- M3 主题覆盖 ----------------

func _label(text: String, pos: Vector2, size: Vector2,
		fs: int = 16, color: Color = OriginalUI.INK) -> Label:
	var l := OriginalUI.label(text, font, fs, color)
	l.position = pos
	l.size = size
	return l


func _button(text: String, pos: Vector2, size: Vector2,
		cb: Callable, fs: int = 16) -> Button:
	var b := OriginalUI.button(text, font, size, cb, fs)
	b.position = pos
	b.size = size
	return b


func _bg_texture(path: String, alpha: float = 1.0) -> void:
	var tr := TextureRect.new()
	tr.position = Vector2.ZERO
	tr.size = Vector2(640, 480)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = Color(1, 1, 1, alpha)
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	ui_root.add_child(tr)


func _panel_shell(title: String, w: int = 560, h: int = 390) -> VBoxContainer:
	_close_panel()
	panel_root = Control.new()
	panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(panel_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.position = Vector2.ZERO
	dim.size = Vector2(640, 480)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_root.add_child(dim)
	var x := (640 - w) / 2.0
	var y := (480 - h) / 2.0
	var card := PanelContainer.new()
	card.position = Vector2(x, y)
	card.size = Vector2(w, h)
	card.add_theme_stylebox_override("panel", OriginalUI._style("panel_red.png"))
	panel_root.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	v.add_child(head)
	var tl := OriginalUI.label(title, font, 16, OriginalUI.GOLD_LIGHT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var close := _button("关闭", Vector2(0, 0), Vector2(58, 26), _close_panel, 14)
	close.custom_minimum_size = Vector2(58, 26)
	head.add_child(close)
	var line := ColorRect.new()
	line.color = OriginalUI.GOLD_DARK
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	v.add_child(content)
	return content


func _top_status(title: String) -> void:
	ui_root.add_child(OriginalUI.header(title, font, Rect2(0, 0, 640, 30)))


func _new_ui() -> Control:
	if is_instance_valid(ui_root):
		ui_root.visible = false
	if is_instance_valid(panel_root):
		panel_root.visible = false
	return super._new_ui()


# ---------------- 世界地图 ----------------

func _show_world() -> void:
	mode = "world"
	_new_ui()
	_bg_texture(str(m2["meta"].get("bigmap", "")), 1.0)
	_dim(0.22)
	_top_status("战 役 / 平 阳")
	var lv: Dictionary = state.campaign_level()
	var title := "第 %d / 36 关" % (state.campaign_index + 1)
	if state.campaign_finished():
		title = "主线完成"
	if state.hidden_unlocked:
		title += "    隐藏关已解锁"
	var chapter := _label(title, Vector2(10, 36), Vector2(420, 24), 16,
			OriginalUI.GOLD_LIGHT)
	ui_root.add_child(chapter)
	var info := _label("累计得分 %d    资金 %d    队伍 %d/%d" % [
		state.score_total, state.money, state.party_size(), state.max_party()],
		Vector2(330, 36), Vector2(300, 24), 16, OriginalUI.INK)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_root.add_child(info)

	# 当前任务牌
	var card := OriginalUI.nine_patch(OriginalUI.PANEL_RED,
			Rect2(10, 66, 214, 306), 10)
	ui_root.add_child(card)
	var head := OriginalUI.header("当前任务", font, Rect2(16, 72, 202, 26))
	ui_root.add_child(head)
	var mission := "全部关卡已完成"
	var mission2 := "可进入隐藏关 / 战斗演练"
	if not lv.is_empty():
		mission = "L%02d %s" % [int(lv["index"]), str(lv["name"])]
		mission2 = "目标：%s" % str(lv.get("objective", {}).get("label", lv["success"]))
	var ml := _label(mission, Vector2(20, 104), Vector2(194, 48), 16,
			OriginalUI.GOLD_LIGHT)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_root.add_child(ml)
	var m2l := _label(mission2, Vector2(20, 154), Vector2(194, 70), 14,
			OriginalUI.INK)
	m2l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_root.add_child(m2l)
	var st := _label("出击城镇：%s" % state.town_name(selected_town),
			Vector2(20, 228), Vector2(194, 24), 16, Color("#d8c39a"))
	ui_root.add_child(st)
	var enter := _button("进入城镇", Vector2(20, 254), Vector2(194, 32),
			_enter_town, 16)
	ui_root.add_child(enter)
	var archive := _button("剧情回顾", Vector2(20, 290), Vector2(94, 28),
			_open_story_archive, 14)
	ui_root.add_child(archive)
	var party := _button("队伍", Vector2(120, 290), Vector2(94, 28),
			_open_party, 14)
	ui_root.add_child(party)
	var save := _button("存档", Vector2(20, 322), Vector2(94, 28),
			_open_save, 14)
	ui_root.add_child(save)
	var loadb := _button("读档", Vector2(120, 322), Vector2(94, 28),
			_open_save_load, 14)
	ui_root.add_child(loadb)
	var back := _button("返回标题", Vector2(20, 354), Vector2(194, 28),
			func(): exit_requested.emit(), 14)
	ui_root.add_child(back)

	# 19 城镇，右侧石牌
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.position = Vector2(238, 70)
	ui_root.add_child(grid)
	var towns: Array = m2.get("towns", [])
	for i in range(towns.size()):
		var t: Dictionary = towns[i]
		var unlocked: bool = state.town_unlocked(i)
		var status := "已解放" if state.is_liberated(i) else ("可进入" if unlocked else "未开放")
		var b := _button("%s\n%s" % [t["name"], status], Vector2.ZERO,
				Vector2(94, 46), _select_town.bind(i), 14)
		if not unlocked:
			b.disabled = true
			b.modulate = Color(0.55, 0.55, 0.55, 0.8)
		elif i == selected_town:
			b.modulate = Color(1.15, 1.0, 0.62)
		grid.add_child(b)

	# 隐藏关 / 彩蛋入口
	if state.hidden_unlocked:
		var sim := _button("隐藏关 模拟", Vector2(238, 322), Vector2(120, 30),
				_start_hidden.bind("simulation"), 14)
		ui_root.add_child(sim)
		var fic := _button("隐藏关 虚构", Vector2(364, 322), Vector2(120, 30),
				_start_hidden.bind("fiction"), 14)
		ui_root.add_child(fic)
		var egg := _button("彩蛋关", Vector2(490, 322), Vector2(110, 30),
				_open_easter, 14)
		ui_root.add_child(egg)
	var drill := _button("战斗演练 / 47 关", Vector2(238, 356), Vector2(180, 30),
			_open_battle_select, 14)
	ui_root.add_child(drill)
	var hint := _label("选择城镇 → 进入；指挥部出击当前关卡。", Vector2(238, 392),
			Vector2(390, 20), 14, Color("#d8c39a"))
	ui_root.add_child(hint)


func _select_town(i: int) -> void:
	if not state.town_unlocked(i):
		_toast("该城镇尚未开放")
		return
	selected_town = i
	state.current_town = i
	_show_world()


func _enter_town() -> void:
	_show_town(selected_town)


func _show_town(index: int) -> void:
	var t: Dictionary = state.town(index)
	if t.is_empty():
		return
	mode = "town"
	selected_town = index
	state.current_town = index
	_new_ui()
	_bg_texture(str(t.get("bg", "")), 1.0)
	_dim(0.10)
	_top_status("L%02d %s / %s" % [index, t["name"], "已解放" if state.is_liberated(index) else "未解放"])
	var lv: Dictionary = state.campaign_level()
	var same: bool = not lv.is_empty() and state.level_town(state.campaign_index) == index
	var banner := OriginalUI.nine_patch(OriginalUI.PANEL_RED,
			Rect2(10, 38, 620, 58), 8)
	ui_root.add_child(banner)
	var mission := "本镇暂无当前战事，可整训队伍。"
	if same:
		mission = "当前任务：L%02d %s    目标：%s" % [
			int(lv["index"]), str(lv["name"]),
			str(lv.get("objective", {}).get("label", lv["success"]))]
	var ml := _label(mission, Vector2(20, 44), Vector2(480, 44), 16,
			OriginalUI.GOLD_LIGHT)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_root.add_child(ml)
	if same:
		var go := _button("出击", Vector2(520, 50), Vector2(96, 34),
				_open_mission, 16)
		ui_root.add_child(go)

	var services := [
		["民房", _service_heal],
		["指挥部", _open_command],
		["军械部", _service_junxie],
		["杂货铺", _service_zahuo],
		["作坊", _open_forge],
		["队伍", _open_party],
		["出口", _show_world],
	]
	for i in range(services.size()):
		var b := _button(services[i][0], Vector2(8 + i * 86, 424),
				Vector2(82, 44), services[i][1], 16)
		if i == 2 and t["shops"]["junxie"].is_empty():
			b.disabled = true
		if i == 3 and t["shops"]["zahuo"].is_empty():
			b.disabled = true
		ui_root.add_child(b)
	var foot := _label("民房回血 / 指挥部作战 / 军械/杂货/作坊补给 / 队伍转职 / 出口回地图",
			Vector2(8, 396), Vector2(620, 20), 14, Color("#d8c39a"))
	ui_root.add_child(foot)


func _open_command() -> void:
	var lv: Dictionary = state.campaign_level()
	if not lv.is_empty() and state.level_town(state.campaign_index) == selected_town:
		_open_mission()
		return
	# 非前线：保留 M2 的招募/队伍入口
	var content := _panel_shell("指挥部 / 整训", 430, 300)
	content.add_child(_label("招募新兵 / 转职 / 战斗演练", Vector2.ZERO,
			Vector2(390, 24), 16, Color("#d8c39a")))
	var b1 := _button("招募新兵", Vector2.ZERO, Vector2(220, 34),
			_open_recruit, 16)
	content.add_child(b1)
	var b2 := _button("队伍 / 转职", Vector2.ZERO, Vector2(220, 34),
			_open_party, 16)
	content.add_child(b2)
	var b3 := _button("战斗演练（47 关）", Vector2.ZERO, Vector2(260, 34),
			_open_battle_select, 16)
	content.add_child(b3)
	var b4 := _button("返回城镇", Vector2.ZERO, Vector2(160, 30),
			func(): _close_panel(); _show_town(selected_town), 14)
	content.add_child(b4)


func _open_mission() -> void:
	var lv: Dictionary = state.campaign_level()
	if lv.is_empty():
		_toast("没有可出击的关卡")
		return
	var content := _panel_shell("作战会议 / L%02d %s" % [
		int(lv["index"]), str(lv["name"])], 560, 300)
	content.add_child(_label("胜利：%s\n失败：%s\n回合上限：%s\n目标：%s" % [
		str(lv.get("success", "")), str(lv.get("failure", "")),
		str(lv.get("turn_limit", 0)) if int(lv.get("turn_limit", 0)) > 0 else "无",
		str(lv.get("objective", {}).get("label", ""))],
		Vector2.ZERO, Vector2(520, 96), 16, OriginalUI.INK))
	content.add_child(_label("可出击队伍：%d 人    部署点：%d" % [
		state.party_size(), (lv.get("deploy", []) as Array).size()],
		Vector2.ZERO, Vector2(520, 24), 16, Color("#d8c39a")))
	var hint := _label("战斗为原版 47 关数据；目标/增援/敌军行为已接入通用运行时。",
			Vector2.ZERO, Vector2(520, 40), 14, Color("#b9a98b"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var go := _button("出 击", Vector2.ZERO, Vector2(160, 40),
			_launch_campaign_level, 16)
	row.add_child(go)
	var story := _button("剧情", Vector2.ZERO, Vector2(100, 40),
			_play_current_story, 16)
	row.add_child(story)
	var back := _button("返回", Vector2.ZERO, Vector2(100, 40),
			func(): _close_panel(); _show_town(selected_town), 16)
	row.add_child(back)
	content.add_child(row)


func _launch_campaign_level() -> void:
	current_battle_standalone = false
	if state.campaign_finished():
		_toast("主线已完成；请从世界图进入隐藏关或战斗演练")
		return
	_close_panel()
	var idx: int = state.campaign_index
	if not current_battle_standalone:
		state.save_checkpoint()
	_play_media(idx, func():
		_play_story_then(idx, func(): _show_deployment(idx)))


func _show_deployment(idx: int) -> void:
	_new_ui()
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/k00.png") \
			if ResourceLoader.exists("res://assets/ui/k00.png") else null
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.size = Vector2(640, 480)
	ui_root.add_child(bg)
	var lv: Dictionary = state.m4_level(idx)
	var max_dep := mini(int(lv.get("max_deploy", 10)), state.party_size())
	max_dep = maxi(1, max_dep)
	# 过滤已不在队伍/已阵亡的旧选择
	var valid: Array = []
	for pid in deploy_selected:
		for m in state.party:
			if int(m["pid"]) == int(pid) and int(m.get("hp", 0)) > 0:
				valid.append(int(pid))
	deploy_selected = valid
	if deploy_selected.is_empty():
		for m in state.party:
			if deploy_selected.size() >= max_dep:
				break
			if int(m.get("hp", 0)) > 0:
				deploy_selected.append(int(m["pid"]))
	ui_root.add_child(OriginalUI.header("出 战 / L%02d %s" % [idx, lv.get("name", "")],
			font, Rect2(0, 0, 640, 30)))
	var left := VBoxContainer.new()
	left.position = Vector2(44, 84)
	left.size = Vector2(268, 292)
	left.add_theme_constant_override("separation", 3)
	ui_root.add_child(left)
	for m in state.party:
		var pid := int(m["pid"])
		var mark := "✓" if deploy_selected.has(pid) else "·"
		var b := OriginalUI.button("%s %s  Lv%d %s" % [mark, m.get("name", ""),
				int(m.get("level", 1)), m.get("unit_name", "")], font,
				Vector2(262, 24), _toggle_deploy.bind(pid, idx), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = int(m.get("hp", 0)) <= 0
		left.add_child(b)
	var right := VBoxContainer.new()
	right.position = Vector2(372, 84)
	right.size = Vector2(224, 292)
	right.add_theme_constant_override("separation", 3)
	ui_root.add_child(right)
	right.add_child(OriginalUI.label("出战 %d/%d" % [deploy_selected.size(), max_dep],
			font, 14, OriginalUI.GOLD_LIGHT))
	for pid in deploy_selected:
		var m = state.get_member(int(pid))
		if m != null:
			right.add_child(OriginalUI.label("%s  Lv%d" % [m.get("name", ""),
					int(m.get("level", 1))], font, 14, Color("#f0e4c8")))
	right.add_child(OriginalUI.label("目标：%s" % lv.get("objective", {}).get("label", ""),
			font, 12, Color("#e5d4ad")))
	right.add_child(OriginalUI.label("敌军：%d" % int(lv.get("enemies", 0)),
			font, 12, Color("#e5d4ad")))
	var go := _button("出 击", Vector2(120, 398), Vector2(140, 34),
			_deploy_go.bind(idx), 16)
	ui_root.add_child(go)
	var back := _button("返 回", Vector2(300, 398), Vector2(120, 34),
			_show_world, 16)
	ui_root.add_child(back)
	var hint := OriginalUI.label("K00 出战 / 选择出战队员 / 自动检查点已保存",
			font, 12, Color("#c8b88f"))
	hint.position = Vector2(120, 440)
	ui_root.add_child(hint)


func _deploy_go(idx: int) -> void:
	current_deploy_pids = deploy_selected.duplicate()
	_launch_level(idx, false, current_deploy_pids)


func _toggle_deploy(pid: int, idx: int) -> void:
	var lv: Dictionary = state.m4_level(idx)
	var max_dep := maxi(1, mini(int(lv.get("max_deploy", 10)), state.party_size()))
	if deploy_selected.has(pid):
		deploy_selected.erase(pid)
	elif deploy_selected.size() >= max_dep:
		_toast("最多出战 %d 人" % max_dep)
		return
	else:
		deploy_selected.append(pid)
	_show_deployment(idx)


func _play_media(idx: int, cb: Callable) -> void:
	var path := _media_for(idx)
	if path == "":
		cb.call()
		return
	_play_cutscene(path, cb)


func _play_story_then(idx: int, cb: Callable) -> void:
	var ids := _story_ids(idx, "intro")
	if ids.is_empty():
		cb.call()
		return
	_play_story(ids, cb)


func _media_for(idx: int) -> String:
	var media: Dictionary = m5.get("media", {})
	if (media.get("clips", []) as Array).is_empty():
		var f := FileAccess.open("res://data/m5_media.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				media = parsed
	var base := ""
	var variant := ""
	for c in media.get("clips", []):
		if str(c.get("kind", "mpeg")) != "mpeg":
			continue
		var lvl := int(c.get("level_index", c.get("level", -1)))
		var cid := str(c.get("id", ""))
		if lvl != idx and cid != ("d%02d" % (idx + 1)):
			continue
		var p := str(c.get("ogv_path", c.get("ogv", "")))
		if p == "" or not ResourceLoader.exists(p):
			continue
		if bool(c.get("variant", false)):
			variant = p
		else:
			base = p
	if state.story_variant and variant != "":
		return variant
	return base


func _play_current_story() -> void:
	var ids := _story_ids(state.campaign_index, "intro")
	if ids.is_empty():
		_toast("本关暂无剧情文本")
		return
	_close_panel()
	_play_story(ids, func(): _show_world())


func _open_battle_select() -> void:
	var content := _panel_shell("战斗演练 / 47 关", 600, 420)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var tip := _label("任意关卡可直接演练；主线关卡会补入当前队伍。", Vector2.ZERO,
			Vector2(430, 24), 14, Color("#d8c39a"))
	tip.custom_minimum_size = Vector2(430, 24)
	top.add_child(tip)
	var back := _button("返回", Vector2.ZERO, Vector2(70, 26),
			func(): _close_panel(), 14)
	back.custom_minimum_size = Vector2(70, 26)
	top.add_child(back)
	content.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for lv in m4.get("levels", []):
		var idx := int(lv["index"])
		var tag := "主线"
		if str(lv.get("kind", "")) == "hidden":
			tag = "隐藏/" + str(lv.get("hidden_mode", ""))
		elif str(lv.get("kind", "")) == "easter":
			tag = "彩蛋"
		var b := _button("L%02d  %s    %s    敌%d" % [
			idx, str(lv["name"]), tag, int(lv.get("enemies", 0))],
			Vector2.ZERO, Vector2(548, 28),
			_launch_level.bind(idx, true), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)


func _launch_level(idx: int, standalone: bool, deploy_pids: Array = []) -> void:
	var selected: Array = deploy_pids
	if selected.is_empty() and not standalone:
		selected = current_deploy_pids
	var level: Dictionary = LevelBuilder.build(m4, m2, idx, state.party, false, -1, selected)
	if level.is_empty():
		_toast("关卡数据缺失")
		return
	state.apply_difficulty(level)
	_close_panel()
	current_battle_index = idx
	current_battle_standalone = standalone
	if is_instance_valid(ui_root):
		ui_root.visible = false
	if is_instance_valid(battle):
		battle.queue_free()
	battle = preload("res://scripts/Battle.gd").new()
	add_child(battle)
	battle.finished.connect(_on_battle_finished)
	battle.looted.connect(_on_loot)
	battle.story_event.connect(_on_battle_story_event)
	battle_story_queue.clear()
	battle_story_seen.clear()
	var ctx: Dictionary = state.battle_context()
	battle.setup(m4, level, font, ctx)
	battle_start_stats = {"enemies": battle.enemy_units.size(),
			"players": battle.player_units.size()}


func _on_battle_story_event(kind: String, data: Dictionary) -> void:
	if current_battle_standalone or current_battle_index < 0:
		return
	var scenes: Dictionary = m5.get("scenes", {})
	var sc: Dictionary = scenes.get(str(current_battle_index), {})
	var events: Array = sc.get("events", [])
	for i in range(events.size()):
		var ev: Dictionary = events[i]
		if str(ev.get("trigger", "")) != kind:
			continue
		if kind == "turn" and int(ev.get("turn", -1)) != int(data.get("turn", -2)):
			continue
		if kind == "unit_died":
			if _norm(str(ev.get("key", ""))) != _norm(str(data.get("key", ""))):
				continue
		var key := "%d:%d" % [current_battle_index, i]
		if battle_story_seen.has(key):
			continue
		battle_story_seen[key] = true
		battle_story_queue.append((ev.get("ids", []) as Array).duplicate())


func _norm(text: String) -> String:
	return str(text).replace("\u3000", "").replace(" ", "")


func _on_loot(item_id: int) -> void:
	if item_id >= 0 and not state.item(item_id).is_empty():
		state.add_item(item_id, 1)


func _on_battle_finished(result: String, message: String) -> void:
	battle_story_queue.clear()
	var victory := result == "victory"
	var stats: Dictionary = {}
	var levelups: Array = []
	if is_instance_valid(battle):
		stats = (battle.stats as Dictionary).duplicate(true)
		stats["turn"] = battle.turn
		stats["enemies_total"] = max(int(battle_start_stats.get("enemies", 0)),
				int(stats.get("enemies_total", 0)))
		var units: Array = []
		for u in battle.player_units:
			if int(u.data.get("pid", -1)) >= 0:
				units.append({"pid": int(u.data.get("pid", -1)), "hp": int(u.hp)})
		state.apply_battle_health(units)
		state.apply_battle_context(battle.battle_context)
		state.grant_battle_experience(battle.player_units, victory)
		levelups = state.apply_battle_progress(battle.player_units)
	var idx := current_battle_index
	var score := _score_for(stats, victory, idx)
	var info: Dictionary = {}
	var joined_names: Array = []
	if victory and not current_battle_standalone:
		for pid in state.m4_level(idx).get("joins", []):
			var jr: Dictionary = state.join_member(int(pid))
			if bool(jr.get("ok", false)):
				joined_names.append(str(jr.get("msg", "")).replace("加入队伍", ""))
	stats["joined"] = joined_names
	if not current_battle_standalone:
		info = state.complete_level(idx, score, victory)
		state.current_town = state.level_town(state.campaign_index) \
				if not state.campaign_finished() else state.current_town
		if victory:
			selected_town = state.current_town
	if victory and not current_battle_standalone and not levelups.is_empty():
		pending_report = {"victory": victory, "message": message, "idx": idx,
				"score": score, "info": info, "standalone": current_battle_standalone}
		_show_levelups(levelups)
		return
	_show_report(victory, message, idx, score, info, current_battle_standalone)


func _score_for(stats: Dictionary, victory: bool, idx: int) -> int:
	if not victory:
		return 0
	var total: int = max(1, int(stats.get("enemies_total", 1)))
	var killed: int = total - int(stats.get("enemies_left", 0))
	var kr := clampf(float(killed) / float(total), 0.0, 1.0)
	var chest_ratio := 0.0
	var lv: Dictionary = state.m4_level(idx)
	var chests := (lv.get("chests", []) as Array).size()
	if chests > 0:
		chest_ratio = clampf(float(stats.get("chests", 0)) / float(chests), 0.0, 1.0)
	var limit := int(lv.get("turn_limit", 0))
	var speed := 1.0
	if limit > 0:
		speed = clampf(1.0 - float(max(0, int(stats.get("turn", 1)) - 1)) / float(limit),
				0.0, 1.0)
	var no_loss := 1.0 if int(stats.get("losses", 0)) == 0 else 0.0
	var score := 55.0 + 20.0 * kr + 10.0 * chest_ratio + 10.0 * speed + 5.0 * no_loss
	if idx >= 36:
		score += 4.0
	return clampi(int(round(score)), 0, 100)


func _show_levelups(levelups: Array) -> void:
	if is_instance_valid(levelup_layer):
		levelup_layer.queue_free()
	levelup_layer = CanvasLayer.new()
	levelup_layer.layer = 101
	add_child(levelup_layer)
	var layer := Control.new()
	layer.theme = ui_theme
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	levelup_layer.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.03, 0.02, 0.96)
	bg.position = Vector2.ZERO
	bg.size = Vector2(640, 480)
	layer.add_child(bg)
	layer.add_child(OriginalUI.nine_patch(OriginalUI.PANEL_BLUE,
			Rect2(28, 46, 584, 360), 12))
	layer.add_child(OriginalUI.header("升 级 / 战 斗 结 算", font,
			Rect2(0, 0, 640, 30)))
	var list_bg := ColorRect.new()
	list_bg.color = Color(0, 0, 0, 0.58)
	list_bg.position = Vector2(40, 62)
	list_bg.size = Vector2(376, 132)
	list_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(list_bg)
	var y := 76
	for lu in levelups:
		var l := OriginalUI.label("%s  Lv%d → Lv%d   HP %d/%d" % [
			lu.get("name", ""), int(lu.get("from", 1)), int(lu.get("to", 1)),
			int(lu.get("hp", 0)), int(lu.get("max_hp", 0))], font, 15,
			Color("#f0e4c8"))
		l.position = Vector2(56, y)
		l.size = Vector2(360, 24)
		layer.add_child(l)
		y += 30
		if y > 330:
			break
	var go := _button("继 续", Vector2(250, 390), Vector2(140, 34),
			_close_levelups, 16)
	layer.add_child(go)
	var note := OriginalUI.label("战斗经验结算", font, 12, Color("#9a8a6a"))
	note.position = Vector2(56, 440)
	layer.add_child(note)


func _close_levelups() -> void:
	if is_instance_valid(levelup_layer):
		levelup_layer.queue_free()
		levelup_layer = null
	if pending_report.is_empty():
		return
	var r := pending_report
	pending_report = {}
	_show_report(bool(r.get("victory", false)), str(r.get("message", "")),
			int(r.get("idx", 0)), int(r.get("score", 0)),
			r.get("info", {}), bool(r.get("standalone", false)))


func _show_report(victory: bool, message: String, idx: int, score: int,
		info: Dictionary, standalone: bool) -> void:
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
	result_canvas = CanvasLayer.new()
	result_canvas.layer = 100
	add_child(result_canvas)
	var layer := Control.new()
	layer.theme = ui_theme
	result_canvas.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/report_red.png") \
			if ResourceLoader.exists("res://assets/ui/report_red.png") else null
	bg.position = Vector2.ZERO
	bg.size = Vector2(640, 480)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(bg)
	var title := OriginalUI.title("胜  利" if victory else "失  败", font, 18,
			OriginalUI.GOLD if victory else Color("#ff6b6b"))
	title.position = Vector2(0, 410)
	title.size = Vector2(640, 28)
	layer.add_child(title)
	# 原版战报的 8 个黑框
	var bs: Dictionary = battle.stats if is_instance_valid(battle) else {}
	var lv: Dictionary = state.m4_level(idx)
	var values := [
		[str(bs.get("kills", 0)), 146],
		[str(bs.get("kills", 0)), 176],
		[str(bs.get("enemies_total", battle_start_stats.get("enemies", 0))), 206],
		[str(bs.get("losses", 0)), 236],
		[str(bs.get("chests", 0)), 266],
		[str(score), 296],
		["", 326],
		[str(info.get("total", state.score_total) if not standalone else score), 386],
	]
	for pair in values:
		var l := OriginalUI.label(pair[0], font, 16, Color("#ffffff"))
		l.position = Vector2(450, int(pair[1]))
		l.size = Vector2(120, 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		layer.add_child(l)
	var grade := OriginalUI.grade(state.grade_for_score(score))
	grade.position = Vector2(466, 312)
	grade.size = Vector2(120, 28)
	layer.add_child(grade)
	if not (bs.get("joined", []) as Array).is_empty():
		var jl := OriginalUI.label("新加入：%s" % "、".join(bs["joined"]),
				font, 14, OriginalUI.GOLD_LIGHT)
		jl.position = Vector2(160, 420)
		jl.size = Vector2(320, 22)
		layer.add_child(jl)
	var row := HBoxContainer.new()
	row.position = Vector2(160, 450)
	row.add_theme_constant_override("separation", 12)
	var cont := _button("继 续", Vector2.ZERO, Vector2(120, 26),
			_report_continue, 14)
	row.add_child(cont)
	var retry := _button("重 试", Vector2.ZERO, Vector2(120, 26),
			_retry_battle, 14)
	row.add_child(retry)
	var back := _button("返回标题", Vector2.ZERO, Vector2(120, 26),
			func(): exit_requested.emit(), 14)
	row.add_child(back)
	layer.add_child(row)
	_last_report = {"victory": victory, "idx": idx, "score": score,
			"info": info, "standalone": standalone}


func _retry_battle() -> void:
	var r := _last_report
	if not bool(r.get("victory", false)) and not bool(r.get("standalone", true)):
		state.load_checkpoint()
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
		result_canvas = null
	if is_instance_valid(battle):
		battle.queue_free()
		battle = null
	_launch_level(int(r.get("idx", current_battle_index)),
			bool(r.get("standalone", false)), current_deploy_pids)


func _report_continue() -> void:
	var r := _last_report
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
		result_canvas = null
	if is_instance_valid(battle):
		battle.queue_free()
		battle = null
	if bool(r.get("standalone", true)):
		_show_world()
		return
	if not bool(r.get("victory", false)):
		if state.load_checkpoint():
			_launch_level(int(r.get("idx", current_battle_index)), false)
		else:
			_show_world()
		return
	var idx := int(r.get("idx", 0))
	# 胜利后先放收尾剧情，再回世界
	var ids := _story_ids(idx, "outro")
	if not ids.is_empty():
		_play_story(ids, func(): _after_victory(idx))
	else:
		_after_victory(idx)


func _after_victory(idx: int) -> void:
	if idx == 35:
		_show_ending(state.ending_id)
	elif idx >= 36:
		var mode := "simulation" if idx < 40 else "fiction"
		if state.hidden_mode_done(mode):
			_show_ending(5)
		else:
			_show_world()
	else:
		_show_world()


# ---------------- 剧情 / 过场 / 结局 ----------------

func _story_ids(idx: int, kind: String) -> Array:
	var scenes: Dictionary = m5.get("scenes", {})
	var s: Dictionary = scenes.get(str(idx), {})
	return (s.get(kind, []) as Array).duplicate()


func _play_story(ids: Array, cb: Callable) -> void:
	if m5.is_empty() or ids.is_empty():
		cb.call()
		return
	if is_instance_valid(story_player):
		story_player.queue_free()
	story_player = load("res://scripts/m5/StoryPlayer.gd").new()
	var parent: Node = self
	if is_instance_valid(battle):
		story_layer = CanvasLayer.new()
		story_layer.layer = 120
		add_child(story_layer)
		parent = story_layer
	parent.add_child(story_player)
	story_player.setup(font, m5, ids, state.player_name, func():
		story_player = null
		if is_instance_valid(story_layer):
			story_layer.queue_free()
		story_layer = null
		cb.call())


func _play_cutscene(path: String, cb: Callable) -> void:
	if path == "" or not ResourceLoader.exists(path):
		cb.call()
		return
	if is_instance_valid(cutscene):
		cutscene.queue_free()
	cutscene = load("res://scripts/m5/CutscenePlayer.gd").new()
	add_child(cutscene)
	cutscene.setup(path, font, func():
		cutscene = null
		cb.call())


func _show_ending(forced := -1) -> void:
	if is_instance_valid(ui_root):
		ui_root.visible = false
	if is_instance_valid(ending_layer):
		ending_layer.queue_free()
		ending_layer = null
	if is_instance_valid(panel_root):
		panel_root.queue_free()
		panel_root = null
	var id: int = forced if forced >= 0 else state.ending_id
	var endings: Array = m5.get("endings", [])
	var e: Dictionary = {}
	for ed in endings:
		if int(ed.get("id", -1)) == id:
			e = ed
	if e.is_empty() and not endings.is_empty():
		e = endings[0]
	var layer := CanvasLayer.new()
	layer.layer = 90
	ending_layer = layer
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = ui_theme
	layer.add_child(root)
	var img := TextureRect.new()
	img.texture = load(str(e.get("image", ""))) \
			if ResourceLoader.exists(str(e.get("image", ""))) else null
	img.position = Vector2.ZERO
	img.size = Vector2(640, 480)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_SCALE
	img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(img)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.36)
	dim.position = Vector2(0, 330)
	dim.size = Vector2(640, 150)
	root.add_child(dim)
	var t := OriginalUI.title(str(e.get("title", "结局")), font, 28,
			OriginalUI.GOLD_LIGHT)
	t.position = Vector2(0, 338)
	t.size = Vector2(640, 30)
	root.add_child(t)
	var body := OriginalUI.label(str(e.get("text", "")), font, 16,
			Color("#f2ead6"))
	body.position = Vector2(60, 374)
	body.size = Vector2(520, 54)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(body)
	var row := HBoxContainer.new()
	row.position = Vector2(120, 438)
	row.add_theme_constant_override("separation", 14)
	var back := _button("返回标题", Vector2.ZERO, Vector2(120, 28),
			func(): exit_requested.emit(), 14)
	row.add_child(back)
	if ResourceLoader.exists("res://assets/ui/credits.png"):
		var cr := _button("片 尾", Vector2.ZERO, Vector2(80, 28),
				_show_credits, 14)
		row.add_child(cr)
	if state.hidden_unlocked:
		var sim := _button("模拟", Vector2.ZERO, Vector2(90, 28),
				_start_hidden.bind("simulation"), 14)
		row.add_child(sim)
		var fic := _button("虚构", Vector2.ZERO, Vector2(90, 28),
				_start_hidden.bind("fiction"), 14)
		row.add_child(fic)
	root.add_child(row)
	var gallery := _button("结局一览", Vector2(520, 40), Vector2(90, 26),
			_show_ending_gallery, 14)
	root.add_child(gallery)
	var state_l := OriginalUI.label("累计得分 %d / 3600" % state.score_total,
			font, 14, Color("#d8c39a"))
	state_l.position = Vector2(0, 462)
	state_l.size = Vector2(640, 18)
	state_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(state_l)


func _show_credits() -> void:
	if is_instance_valid(credits_layer):
		credits_layer.queue_free()
	credits_layer = CanvasLayer.new()
	credits_layer.layer = 95
	add_child(credits_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = ui_theme
	credits_layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var tex := TextureRect.new()
	tex.texture = load("res://assets/ui/credits.png")
	tex.position = Vector2(0, 480)
	tex.size = Vector2(640, 7562)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(tex)
	var skip := _button("跳过片尾", Vector2(520, 446), Vector2(100, 26),
			_close_credits, 14)
	root.add_child(skip)
	var tw := create_tween()
	tw.tween_property(tex, "position:y", -7562.0, 45.0)
	tw.tween_callback(_close_credits)


func _close_credits() -> void:
	if is_instance_valid(credits_layer):
		credits_layer.queue_free()
	credits_layer = null
	exit_requested.emit()


func _show_ending_gallery() -> void:
	if is_instance_valid(ending_layer):
		ending_layer.queue_free()
	ending_layer = CanvasLayer.new()
	ending_layer.layer = 95
	add_child(ending_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = ui_theme
	ending_layer.add_child(root)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/bg03.png") \
			if ResourceLoader.exists("res://assets/ui/bg03.png") else null
	bg.position = Vector2.ZERO
	bg.size = Vector2(640, 480)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(bg)
	var head := OriginalUI.header("结 局 一 览", font, Rect2(0, 0, 640, 30))
	root.add_child(head)
	var endings: Array = m5.get("endings", [])
	for i in range(endings.size()):
		var e: Dictionary = endings[i]
		var b := _button("%s  %d" % [e.get("title", "结局"), int(e.get("score", 0))],
				Vector2(310, 74 + i * 56), Vector2(260, 40),
				_show_ending.bind(int(e.get("id", i))), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		root.add_child(b)
	var back := _button("返 回", Vector2(520, 438), Vector2(90, 26),
			func(): _show_ending(state.ending_id), 14)
	root.add_child(back)


func _open_story_archive() -> void:
	if m5.is_empty():
		_toast("剧情数据未生成")
		return
	if is_instance_valid(story_player):
		return
	story_player = load("res://scripts/m5/StoryPlayer.gd").new()
	add_child(story_player)
	story_player.setup(font, m5, [], state.player_name, func():
		story_player = null)


func _start_hidden(mode: String) -> void:
	if is_instance_valid(ending_layer):
		ending_layer.queue_free()
		ending_layer = null
	if not state.hidden_unlocked:
		_toast("累计得分达到 2800 后才可进入隐藏关")
		return
	var idx: int = state.hidden_next(mode)
	if idx < 0:
		_toast("该隐藏模式已完成")
		return
	_close_panel()
	current_battle_standalone = false
	_launch_level(idx, false)


func _open_easter() -> void:
	if not state.hidden_unlocked and state.hidden_done.is_empty():
		_toast("完成主线后才会出现彩蛋关")
		return
	var content := _panel_shell("彩蛋关 / 中国象棋 / 龟兔赛跑 / 鬼子进村", 420, 250)
	for idx in [44, 45, 46]:
		var lv: Dictionary = state.m4_level(idx)
		if lv.is_empty():
			continue
		var b := _button("L%02d  %s" % [idx, str(lv["name"])], Vector2.ZERO,
				Vector2(300, 34), _launch_level.bind(idx, false), 16)
		content.add_child(b)
	var back := _button("返回", Vector2.ZERO, Vector2(120, 30),
			func(): _close_panel(), 14)
	content.add_child(back)
