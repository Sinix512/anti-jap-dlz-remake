extends Control

## M2 战役：19 城镇世界图、城镇服务、队伍/招募/商店/锻造/转职/存档、M1 战斗演练。

signal exit_requested

const M2_PATH := "res://data/m2.json"
const M1_PATH := "res://data/m1.json"

var m2: Dictionary = {}
var m1: Dictionary = {}
var state  # GameState.gd
var font: Font
var ui_theme: Theme

var ui_root: Control
var panel_root: Control
var battle: Node2D
var result_canvas: CanvasLayer

var mode := "world"
var selected_town := 0
var party_selected := -1
var k03_selected := 0
var shop_kind := "junxie"
var shop_selling := false
var toast: Label


func setup(font_ref: Font) -> void:
	font = font_ref
	ui_theme = Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 16
	self.theme = ui_theme
	m2 = _load_json(M2_PATH)
	m1 = _load_json(M1_PATH)
	if m2.is_empty() or m1.is_empty():
		_fatal("缺少 res://data/m2.json 或 m1.json\n请先运行 tools/prepare_m1.py 与 prepare_m2.py")
		return
	state = load("res://scripts/m2/GameState.gd").new()
	state.new_game(m2)
	selected_town = state.current_town
	_show_world()


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _fatal(msg: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color("#12151a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var l := _label(msg, Vector2(40, 120), Vector2(560, 200), 16, Color("#ff8a8a"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bg.add_child(l)


# ---------------- 公共 UI ----------------

func _label(text: String, pos: Vector2, size: Vector2,
		fs: int = 16, color: Color = Color("#e8edf4")) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, pos: Vector2, size: Vector2,
		cb: Callable, fs: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.custom_minimum_size = size
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fs)
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _clear_ui() -> void:
	if is_instance_valid(panel_root):
		panel_root.queue_free()
		panel_root = null
	if is_instance_valid(ui_root):
		ui_root.queue_free()
		ui_root = null
	if is_instance_valid(toast):
		toast.queue_free()
		toast = null


func _new_ui() -> Control:
	_clear_ui()
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.theme = ui_theme
	add_child(ui_root)
	return ui_root


func _bg_texture(path: String, alpha: float = 1.0) -> void:
	var tr := TextureRect.new()
	tr.position = Vector2.ZERO
	tr.size = Vector2(640, 480)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.modulate = Color(1, 1, 1, alpha)
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	ui_root.add_child(tr)


func _dim(alpha: float = 0.45) -> void:
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, alpha)
	d.position = Vector2.ZERO
	d.size = Vector2(640, 480)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(d)


func _bar(y: float, h: float, color: Color = Color(0.04, 0.055, 0.08, 0.94)) -> void:
	var r := ColorRect.new()
	r.color = color
	r.position = Vector2(0, y)
	r.size = Vector2(640, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(r)


func _top_status(title: String) -> void:
	_bar(0, 44)
	var t := _label(title, Vector2(8, 5), Vector2(300, 30), 16, Color("#f2c14e"))
	ui_root.add_child(t)
	var info := _label("资金 %d   第 %d 天   队伍 %d/%d" % [
		state.money, state.day, state.party_size(), state.max_party()],
		Vector2(300, 12), Vector2(330, 24), 16, Color("#dfe6f0"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_root.add_child(info)


func _toast(msg: String) -> void:
	if is_instance_valid(toast):
		toast.queue_free()
	toast = _label(msg, Vector2(8, 48), Vector2(624, 24), 16, Color("#ffe08a"))
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	toast.add_theme_constant_override("outline_size", 4)
	var parent: Control = panel_root if is_instance_valid(panel_root) else ui_root
	parent.add_child(toast)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)
	tw.tween_callback(toast.queue_free)


# ---------------- 世界地图 ----------------

func _show_world() -> void:
	mode = "world"
	_new_ui()
	_bg_texture(str(m2["meta"].get("bigmap", "")), 1.0)
	_dim(0.42)
	_top_status("M2 战役 / 19 城镇")
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.position = Vector2(17, 56)
	ui_root.add_child(grid)
	var towns: Array = m2.get("towns", [])
	for i in range(towns.size()):
		var t: Dictionary = towns[i]
		var status := "已解放" if state.is_liberated(i) else "未解放"
		var b := _button("%s\n%s" % [t["name"], status],
				Vector2.ZERO, Vector2(118, 54),
				_select_town.bind(i), 16)
		if i == selected_town:
			b.modulate = Color(1.0, 0.88, 0.55)
		grid.add_child(b)
	_bar(392, 88)
	var sel: Dictionary = state.town(selected_town)
	var info := _label("当前：%s    %s" % [
		sel.get("name", ""),
		"已解放" if state.is_liberated(selected_town) else "未解放"],
		Vector2(8, 398), Vector2(300, 24), 16, Color("#f2c14e"))
	ui_root.add_child(info)
	var hint := _label("选城镇 → 进入", Vector2(8, 420),
			Vector2(300, 24), 16, Color("#9aa8ba"))
	ui_root.add_child(hint)
	var enter := _button("进入城镇", Vector2(310, 410), Vector2(100, 40),
			_enter_town, 16)
	ui_root.add_child(enter)
	var party := _button("队伍", Vector2(414, 410), Vector2(64, 40),
			_open_party, 16)
	ui_root.add_child(party)
	var save := _button("存档", Vector2(482, 410), Vector2(64, 40),
			_open_save, 16)
	ui_root.add_child(save)
	var loadb := _button("读档", Vector2(550, 410), Vector2(64, 40),
			_open_save_load, 16)
	ui_root.add_child(loadb)
	var back := _button("主菜单", Vector2(8, 446), Vector2(80, 28),
			func(): exit_requested.emit(), 14)
	ui_root.add_child(back)


func _select_town(i: int) -> void:
	selected_town = i
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
	_bar(0, 44)
	_bar(384, 96)
	var title := _label("L%02d  %s" % [index, t["name"]],
			Vector2(8, 5), Vector2(300, 30), 16, Color("#f2c14e"))
	ui_root.add_child(title)
	var info := _label("资金 %d   第 %d 天   队伍 %d/%d" % [
		state.money, state.day, state.party_size(), state.max_party()],
		Vector2(300, 12), Vector2(330, 24), 16, Color("#dfe6f0"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_root.add_child(info)

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
	var hint := _label("选择建筑服务；军械/杂货/作坊是 M2 经济入口",
			Vector2(8, 392), Vector2(620, 24), 16, Color("#d7dfea"))
	ui_root.add_child(hint)


func _service_heal() -> void:
	_show_house()


func _show_house() -> void:
	_new_ui()
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/bg02.png") \
			if ResourceLoader.exists("res://assets/ui/bg02.png") else null
	bg.position = Vector2.ZERO
	bg.size = Vector2(640, 480)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui_root.add_child(bg)
	ui_root.add_child(OriginalUI.header("民 房 / 队 伍 休 整", font,
			Rect2(0, 0, 640, 30)))
	var info := _label("在老乡家里休整。选择休息可恢复全队体力。", Vector2(40, 70),
			Vector2(560, 24), 16, Color("#f0e4c8"))
	ui_root.add_child(info)
	var y := 106
	for m in state.party:
		var l := _label("%s  %s  HP %d/%d" % [m.get("name", ""),
				m.get("unit_name", ""), int(m.get("hp", 0)),
				int(m.get("max_hp", 0))], Vector2(60, y), Vector2(520, 22), 14,
				Color("#f0e4c8"))
		ui_root.add_child(l)
		y += 22
		if y > 320:
			break
	var rest := _button("休 息（恢复全队）", Vector2(80, 350), Vector2(180, 34),
			_do_house_rest, 16)
	ui_root.add_child(rest)
	var back := _button("返 回 城 镇", Vector2(290, 350), Vector2(150, 34),
			func(): _close_panel(); _show_town(selected_town), 16)
	ui_root.add_child(back)


func _do_house_rest() -> void:
	state.heal_all()
	_toast("队伍体力已恢复")
	_show_house()


func _service_junxie() -> void:
	_open_shop("junxie", false)


func _service_zahuo() -> void:
	_open_shop("zahuo", false)


# ---------------- 面板骨架 ----------------

func _close_panel() -> void:
	if is_instance_valid(panel_root):
		panel_root.queue_free()
		panel_root = null


func _panel_shell(title: String, w: int = 560, h: int = 390) -> VBoxContainer:
	_close_panel()
	panel_root = Control.new()
	panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(panel_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.position = Vector2.ZERO
	dim.size = Vector2(640, 480)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_root.add_child(dim)
	var card := ColorRect.new()
	card.color = Color(0.06, 0.075, 0.10, 0.98)
	card.position = Vector2((640 - w) / 2, (480 - h) / 2)
	card.size = Vector2(w, h)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_root.add_child(card)
	var tl := _label(title, Vector2(16, 10), Vector2(w - 90, 28), 16,
			Color("#f2c14e"))
	card.add_child(tl)
	var close := _button("关闭", Vector2(w - 74, 8), Vector2(58, 28),
			_close_panel, 14)
	card.add_child(close)
	var content := VBoxContainer.new()
	content.position = Vector2(16, 46)
	content.size = Vector2(w - 32, h - 60)
	content.add_theme_constant_override("separation", 4)
	card.add_child(content)
	return content


# ---------------- 商店 ----------------

func _shop_title(kind: String) -> String:
	match kind:
		"junxie": return "军械部 / 买卖武器"
		"zahuo": return "杂货铺 / 买卖杂货"
		"material": return "材料 / 买卖地雷材料"
	return "商店"


func _open_shop(kind: String, selling: bool = false) -> void:
	shop_kind = kind
	shop_selling = selling
	var content := _panel_shell(_shop_title(kind), 560, 390)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)
	var money := _label("资金 %d" % state.money, Vector2.ZERO, Vector2(180, 24),
			16, Color("#f2c14e"))
	money.custom_minimum_size = Vector2(180, 24)
	top.add_child(money)
	var b1 := _button("购买", Vector2.ZERO, Vector2(70, 28),
			_open_shop_buy.bind(kind), 14)
	b1.custom_minimum_size = Vector2(70, 28)
	top.add_child(b1)
	var b2 := _button("出售", Vector2.ZERO, Vector2(70, 28),
			_open_shop_sell.bind(kind), 14)
	b2.custom_minimum_size = Vector2(70, 28)
	top.add_child(b2)
	var b3 := _button("买材料", Vector2.ZERO, Vector2(80, 28),
			func(): _open_shop("material", false), 14)
	b3.custom_minimum_size = Vector2(80, 28)
	top.add_child(b3)
	var b4 := _button("锻造", Vector2.ZERO, Vector2(70, 28),
			_open_forge, 14)
	b4.custom_minimum_size = Vector2(70, 28)
	top.add_child(b4)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 265)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	var rows: Array = []
	if selling:
		var inv: Dictionary = state.materials if kind == "material" else state.items
		for k in inv:
			var rec: Dictionary = state.material(int(k)) if kind == "material" else state.item(int(k))
			if not rec.is_empty():
				rows.append({"rec": rec, "count": int(inv[k]), "id": int(k)})
	else:
		var shop: Dictionary = state.town(selected_town).get("shops", {})
		var arr: Array = shop.get(kind, [])
		for rec in arr:
			rows.append({"rec": rec, "count": 0, "id": int(rec["index"])})
	for r in rows:
		list.add_child(_shop_row(r, kind, selling))
	if rows.is_empty():
		list.add_child(_label("（空）", Vector2.ZERO, Vector2(500, 24), 16,
				Color("#8b98aa")))


func _shop_row(r: Dictionary, kind: String, selling: bool) -> HBoxContainer:
	var rec: Dictionary = r["rec"]
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(str(rec.get("icon", ""))):
		icon.texture = load(rec["icon"])
	row.add_child(icon)
	var nm := _label(str(rec.get("name", "")), Vector2.ZERO, Vector2(200, 24), 16)
	nm.custom_minimum_size = Vector2(190, 24)
	row.add_child(nm)
	var price := int(rec.get("price", 0))
	var price_text := ("卖 %d" % max(1, int(price / 2.0))) if selling else ("%d" % price)
	var pl := _label(price_text, Vector2.ZERO, Vector2(80, 24), 16,
			Color("#f2c14e"))
	pl.custom_minimum_size = Vector2(80, 24)
	row.add_child(pl)
	if selling:
		var cl := _label("×%d" % int(r["count"]), Vector2.ZERO, Vector2(60, 24), 16,
				Color("#c8d3e2"))
		cl.custom_minimum_size = Vector2(60, 24)
		row.add_child(cl)
	var btn_text := "卖" if selling else "买"
	var btn := _button(btn_text, Vector2.ZERO, Vector2(56, 28), Callable(), 14)
	btn.custom_minimum_size = Vector2(56, 28)
	btn.pressed.connect(_shop_action.bind(kind, int(r["id"]), selling))
	if not selling and state.money < price:
		btn.disabled = true
	row.add_child(btn)
	return row


func _open_shop_buy(kind: String) -> void:
	_open_shop(kind, false)


func _open_shop_sell(kind: String) -> void:
	_open_shop(kind, true)


func _shop_action(kind: String, id: int, selling: bool) -> void:
	var r: Dictionary
	if selling:
		r = state.sell_material(id) if kind == "material" else state.sell_item(id)
	else:
		r = state.buy_material(id) if kind == "material" else state.buy_item(id)
	_toast(str(r.get("msg", "")))
	_open_shop(kind, selling)


# ---------------- 锻造 ----------------

func _open_forge() -> void:
	var content := _panel_shell("作坊 / 锻造地雷", 560, 390)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)
	var buy := _button("材料商店", Vector2.ZERO, Vector2(100, 28),
			func(): _open_shop("material", false), 14)
	buy.custom_minimum_size = Vector2(100, 28)
	top.add_child(buy)
	var back := _button("返回", Vector2.ZERO, Vector2(60, 28),
			func(): _close_panel(); _show_town(selected_town), 14)
	back.custom_minimum_size = Vector2(60, 28)
	top.add_child(back)
	var summary := _label("材料库存：\n%s" % _material_summary(), Vector2.ZERO,
			Vector2(520, 40), 16, Color("#c8d3e2"))
	summary.custom_minimum_size = Vector2(520, 40)
	content.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for mid in range(10):
		var mine: Dictionary = state.mine(mid)
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 34)
		row.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_path := str(mine.get("icon", ""))
		if ResourceLoader.exists(icon_path):
			var at := AtlasTexture.new()
			at.atlas = load(icon_path)
			at.region = Rect2(0, 0, 48, 48)
			icon.texture = at
		row.add_child(icon)
		var nm := _label(str(mine.get("name", "")), Vector2.ZERO,
				Vector2(70, 24), 16)
		nm.custom_minimum_size = Vector2(60, 24)
		row.add_child(nm)
		var rec := _recipe_text(mine.get("recipe", []))
		var rl := _label(rec, Vector2.ZERO, Vector2(290, 24), 16,
				Color("#b8c4d4"))
		rl.custom_minimum_size = Vector2(290, 24)
		row.add_child(rl)
		var can: Dictionary = state.can_craft(mid)
		var btn := _button("锻造", Vector2.ZERO, Vector2(70, 28), Callable(), 14)
		btn.custom_minimum_size = Vector2(70, 28)
		btn.disabled = not bool(can.get("ok", false))
		btn.pressed.connect(_forge.bind(mid))
		row.add_child(btn)
		list.add_child(row)


func _material_summary() -> String:
	var parts: Array = []
	for mid in range(10):
		var c: int = state.material_count(mid)
		if c > 0:
			parts.append("%s%d" % [state.material(mid).get("name", str(mid)), c])
	if parts.is_empty():
		return "无"
	var lines: Array = []
	for i in range(0, parts.size(), 5):
		lines.append(" ".join(parts.slice(i, min(i + 5, parts.size()))))
	return "\n".join(lines)


func _recipe_text(recipe: Array) -> String:
	var parts: Array = []
	for i in range(recipe.size()):
		if int(recipe[i]) > 0:
			parts.append("%s%d" % [state.material(i).get("name", str(i)), int(recipe[i])])
	return " ".join(parts)


func _forge(mid: int) -> void:
	var r: Dictionary = state.craft_mine(mid)
	_toast(str(r.get("msg", "")))
	_open_forge()


# ---------------- 队伍 / 转职 ----------------

func _open_party() -> void:
	var content := _panel_shell("队伍 / 转职", 560, 390)
	var k3 := _button("K03 队伍状态", Vector2.ZERO, Vector2(140, 28),
			_show_k03_roster, 14)
	content.add_child(k3)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_constant_override("separation", 2)
	body.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(228, 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	if not state.party.is_empty() and state.get_member(party_selected) == null:
		party_selected = int(state.party[0]["pid"])
	for m in state.party:
		var b := _button("%s  Lv%d\n%s" % [m["name"], m["level"], m["unit_name"]],
				Vector2.ZERO, Vector2(220, 44), _party_select.bind(int(m["pid"])), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if int(m["pid"]) == party_selected:
			b.modulate = Color(1, 0.88, 0.55)
		list.add_child(b)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	body.add_child(right)
	var m = state.get_member(party_selected)
	if m == null:
		right.add_child(_label("队伍为空", Vector2.ZERO, Vector2(260, 30), 16))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	right.add_child(row)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(64, 80)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(str(m.get("face_png", ""))):
		portrait.texture = load(m["face_png"])
	row.add_child(portrait)
	var info := _label("%s\n%s  Lv%d\nHP %d/%d\n武力 %d  智力 %d" % [
		m["name"], m["unit_name"], m["level"], m["hp"], m["max_hp"],
		m["wuli"], m["zhili"]],
		Vector2.ZERO, Vector2(250, 90), 16)
	info.custom_minimum_size = Vector2(250, 90)
	row.add_child(info)
	var u: Dictionary = state.unit_of(m)
	var atk := int(round(float(u.get("gongji", 0)) + float(m["wuli"]) * 0.6))
	var df := int(round(float(u.get("fangyu", 0)) + float(m["zhili"]) * 0.3))
	right.add_child(_label("攻击 %d   防御 %d   移动 %d" % [
		atk, df, int(u.get("yidong", 0))],
		Vector2.ZERO, Vector2(300, 24), 16))
	var eq_id := int(m.get("equip", -1))
	var eq_text := "未装备"
	if eq_id >= 0:
		var eq_b: Dictionary = state.equip_bonus(eq_id)
		eq_text = "%s  攻+%d 防+%d" % [state.item(eq_id).get("name", "?"),
				int(eq_b["attack"]), int(eq_b["defense"])]
	right.add_child(_label("装备：" + eq_text, Vector2.ZERO, Vector2(300, 22), 14,
			Color("#e8ba4c") if eq_id >= 0 else Color("#b8c4d4")))
	var eq_row := HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 6)
	right.add_child(eq_row)
	var eb := _button("换装备", Vector2.ZERO, Vector2(100, 28),
			_open_equip_panel.bind(int(m["pid"])), 14)
	eb.custom_minimum_size = Vector2(100, 28)
	eq_row.add_child(eb)
	if eq_id >= 0:
		var ub := _button("卸下", Vector2.ZERO, Vector2(80, 28),
				_unequip.bind(int(m["pid"])), 14)
		ub.custom_minimum_size = Vector2(80, 28)
		eq_row.add_child(ub)
	var c: Dictionary = state.can_promote(m)
	if bool(c.get("ok", false)):
		right.add_child(_label("可转职：%s → %s" % [m["unit_name"], c["target_name"]],
				Vector2.ZERO, Vector2(300, 24), 16, Color("#8fd18f")))
		var item_id := int(c.get("item_id", -1))
		if item_id >= 0:
			right.add_child(_label("需要：%s ×1（库存 %d）" % [
				state.item(item_id).get("name", "道具"), state.item_count(item_id)],
				Vector2.ZERO, Vector2(300, 24), 16, Color("#c8d3e2")))
		var pb := _button("转职", Vector2.ZERO, Vector2(100, 30),
				_promote.bind(int(m["pid"])), 16)
		pb.custom_minimum_size = Vector2(100, 30)
		right.add_child(pb)
	else:
		right.add_child(_label(str(c.get("msg", "无转职路线")), Vector2.ZERO,
				Vector2(300, 24), 12, Color("#b8c4d4")))


func _open_equip_panel(pid: int) -> void:
	var m = state.get_member(pid)
	if m == null:
		return
	var content := _panel_shell("装备 / %s" % m.get("name", ""), 520, 340)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)
	var auto := _button("一键装备", Vector2.ZERO, Vector2(100, 28),
			_auto_equip_all, 14)
	auto.custom_minimum_size = Vector2(100, 28)
	top.add_child(auto)
	var back := _button("返回队伍", Vector2.ZERO, Vector2(100, 28),
			_open_party, 14)
	back.custom_minimum_size = Vector2(100, 28)
	top.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(490, 235)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var shown := 0
	for k in state.items:
		var iid := int(k)
		if state.item_kind(iid) != "equip" or state.item_count(iid) <= 0:
			continue
		shown += 1
		var it: Dictionary = state.item(iid)
		var b: Dictionary = state.equip_bonus(iid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_l := _label("%s  攻+%d 防+%d  库存%d" % [
			it.get("name", "?"), int(b["attack"]), int(b["defense"]),
			state.item_count(iid)], Vector2.ZERO, Vector2(350, 24), 14)
		name_l.custom_minimum_size = Vector2(350, 24)
		row.add_child(name_l)
		var btn := _button("已装备" if int(m.get("equip", -1)) == iid else "装备",
				Vector2.ZERO, Vector2(80, 26), _equip_selected.bind(pid, iid), 14)
		btn.custom_minimum_size = Vector2(80, 26)
		btn.disabled = int(m.get("equip", -1)) == iid
		row.add_child(btn)
		list.add_child(row)
	if shown == 0:
		list.add_child(_label("库存没有可装备物品；可在军械部购买。",
				Vector2.ZERO, Vector2(470, 30), 14, Color("#b8c4d4")))


func _equip_selected(pid: int, item_id: int) -> void:
	var m = state.get_member(pid)
	if m == null:
		return
	var r: Dictionary = state.equip_item(m, item_id)
	_toast(str(r.get("msg", "")))
	_open_party()


func _unequip(pid: int) -> void:
	var m = state.get_member(pid)
	if m == null:
		return
	var r: Dictionary = state.unequip_item(m)
	_toast(str(r.get("msg", "")))
	_open_party()


func _auto_equip_all() -> void:
	state.auto_equip_party()
	_toast("已按库存自动装备")
	_open_party()


func _show_k03_roster() -> void:
	_new_ui()
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/k03.png") \
			if ResourceLoader.exists("res://assets/ui/k03.png") else null
	bg.position = Vector2.ZERO
	bg.size = Vector2(640, 480)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui_root.add_child(bg)
	ui_root.add_child(OriginalUI.header("队 伍 状 态 / K03", font,
			Rect2(0, 0, 640, 30)))
	var shown := mini(4, state.party.size())
	if k03_selected >= shown:
		k03_selected = 0
	for i in range(shown):
		var m: Dictionary = state.party[i]
		var slot := Vector2(28 + (i % 2) * 80, 126 + int(i / 2) * 80)
		var portrait := TextureRect.new()
		portrait.position = slot
		portrait.size = Vector2(64, 52)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if ResourceLoader.exists(str(m.get("face_png", ""))):
			portrait.texture = load(m["face_png"])
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui_root.add_child(portrait)
		var b := _button("", slot, Vector2(64, 76), _k03_select.bind(i), 14)
		b.flat = true
		ui_root.add_child(b)
		var name_l := OriginalUI.label("%s Lv%d" % [m.get("name", ""),
				int(m.get("level", 1))], font, 12,
				OriginalUI.GOLD_LIGHT if i == k03_selected else Color("#e8dcc2"))
		name_l.position = slot + Vector2(0, 54)
		name_l.size = Vector2(74, 18)
		ui_root.add_child(name_l)
	var m = state.party[k03_selected] if k03_selected < state.party.size() else null
	if m != null:
		var info_bg := ColorRect.new()
		info_bg.color = Color(0, 0, 0, 0.58)
		info_bg.position = Vector2(276, 78)
		info_bg.size = Vector2(316, 252)
		info_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui_root.add_child(info_bg)
		var info := "姓名：%s
兵种：%s  Lv%d
HP：%d/%d
武力：%d  智力：%d
武器：%s
技能：%s" % [
			m.get("name", ""), m.get("unit_name", ""), int(m.get("level", 1)),
			int(m.get("hp", 0)), int(m.get("max_hp", 0)),
			int(m.get("wuli", 0)), int(m.get("zhili", 0)),
			m.get("equip_name", "无"), m.get("skill_text", "—")]
		var info_l := OriginalUI.label(info, font, 14, Color("#f0e4c8"))
		info_l.position = Vector2(286, 92)
		info_l.size = Vector2(320, 250)
		ui_root.add_child(info_l)
	var back := _button("返 回 队 伍", Vector2(450, 400), Vector2(140, 30),
			_open_party, 14)
	ui_root.add_child(back)
	var note := OriginalUI.label("K03 原版队伍状态 / 显示前 4 人", font, 12,
			Color("#c8b88f"))
	note.position = Vector2(40, 440)
	ui_root.add_child(note)


func _k03_select(i: int) -> void:
	k03_selected = i
	_show_k03_roster()


func _party_select(pid: int) -> void:
	party_selected = pid
	_open_party()


func _promote(pid: int) -> void:
	var m = state.get_member(pid)
	if m == null:
		return
	var r: Dictionary = state.promote(m)
	_toast(str(r.get("msg", "")))
	_open_party()


# ---------------- 招募 ----------------

func _open_command() -> void:
	var content := _panel_shell("指挥部", 430, 300)
	content.add_child(_label("招募新兵 / 转职 / 出击演练", Vector2.ZERO,
			Vector2(390, 24), 16, Color("#c8d3e2")))
	var b1 := _button("招募新兵", Vector2.ZERO, Vector2(200, 34),
			_open_recruit, 16)
	b1.custom_minimum_size = Vector2(200, 34)
	content.add_child(b1)
	var b2 := _button("队伍 / 转职", Vector2.ZERO, Vector2(200, 34),
			_open_party, 16)
	b2.custom_minimum_size = Vector2(200, 34)
	content.add_child(b2)
	var b3 := _button("出击演练（M1 战斗）", Vector2.ZERO, Vector2(260, 34),
			_open_battle_select, 16)
	b3.custom_minimum_size = Vector2(260, 34)
	content.add_child(b3)
	var b4 := _button("返回城镇", Vector2.ZERO, Vector2(160, 30),
			func(): _close_panel(); _show_town(selected_town), 14)
	b4.custom_minimum_size = Vector2(160, 30)
	content.add_child(b4)


func _open_recruit() -> void:
	var content := _panel_shell("指挥部 / 招募新兵", 560, 390)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)
	var money := _label("资金 %d   队伍 %d/%d" % [
		state.money, state.party_size(), state.max_party()],
		Vector2.ZERO, Vector2(360, 24), 16, Color("#f2c14e"))
	money.custom_minimum_size = Vector2(360, 24)
	top.add_child(money)
	var back := _button("返回", Vector2.ZERO, Vector2(70, 28),
			_open_command, 14)
	back.custom_minimum_size = Vector2(70, 28)
	top.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for p in state.candidates():
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 32)
		row.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists(str(p.get("face_png", ""))):
			icon.texture = load(p["face_png"])
		row.add_child(icon)
		var nm := _label("%s  Lv%d  %s" % [p["name"], p["level"], p["unit_name"]],
				Vector2.ZERO, Vector2(250, 24), 16)
		nm.custom_minimum_size = Vector2(250, 24)
		row.add_child(nm)
		var cost := int(p.get("recruit_cost", 0))
		var cl := _label("%d" % cost, Vector2.ZERO, Vector2(70, 24), 16,
				Color("#f2c14e"))
		cl.custom_minimum_size = Vector2(70, 24)
		row.add_child(cl)
		var btn := _button("招募", Vector2.ZERO, Vector2(60, 28),
				_recruit.bind(int(p["pid"])), 14)
		btn.custom_minimum_size = Vector2(60, 28)
		if state.money < cost or state.party_size() >= state.max_party():
			btn.disabled = true
		row.add_child(btn)
		list.add_child(row)


func _recruit(pid: int) -> void:
	var r: Dictionary = state.recruit(pid)
	_toast(str(r.get("msg", "")))
	_open_recruit()


# ---------------- 存档 ----------------

func _open_save() -> void:
	_open_save_impl(false)


func _open_save_load() -> void:
	_open_save_impl(true)


func _open_save_impl(load_first: bool) -> void:
	var content := _panel_shell("存档 / 读档", 560, 360)
	content.add_child(_label("资金 %d   第 %d 天   队伍 %d 人" % [
		state.money, state.day, state.party_size()],
		Vector2.ZERO, Vector2(500, 24), 16, Color("#f2c14e")))
	for slot in range(int(m2["meta"].get("save_slots", 3))):
		var info: Dictionary = state.slot_info(slot)
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 44)
		row.add_theme_constant_override("separation", 8)
		var txt := "槽 %d：空" % slot
		if not info.is_empty():
			txt = "槽 %d：第 %d 天 / 资金 %d / %d 人 / %s" % [
				slot, int(info.get("day", 0)), int(info.get("money", 0)),
				(info.get("party", []) as Array).size(),
				str(info.get("saved_at", ""))]
		var l := _label(txt, Vector2.ZERO, Vector2(380, 24), 16,
				Color("#e8edf4"))
		l.custom_minimum_size = Vector2(380, 24)
		row.add_child(l)
		var save := _button("存档", Vector2.ZERO, Vector2(66, 30),
				_save_slot.bind(slot), 14)
		save.custom_minimum_size = Vector2(66, 30)
		row.add_child(save)
		var loadb := _button("读档", Vector2.ZERO, Vector2(66, 30),
				_load_slot.bind(slot), 14)
		loadb.custom_minimum_size = Vector2(66, 30)
		if info.is_empty():
			loadb.disabled = true
		row.add_child(loadb)
		content.add_child(row)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 8)
	var exp := _button("导出原版布局", Vector2.ZERO, Vector2(130, 28),
			_export_original, 14)
	exp.custom_minimum_size = Vector2(130, 28)
	orow.add_child(exp)
	var imp := _button("导入原版布局", Vector2.ZERO, Vector2(130, 28),
			_import_original, 14)
	imp.custom_minimum_size = Vector2(130, 28)
	orow.add_child(imp)
	var olabel := _label("实验：85072 B / 未用原始 EXE 回读", Vector2.ZERO,
			Vector2(240, 24), 12, Color("#9aa8ba"))
	olabel.custom_minimum_size = Vector2(240, 24)
	orow.add_child(olabel)
	content.add_child(orow)
	var hint := _label("自用存档：user://%s*.json" % [
		m2["meta"].get("save_prefix", "dlz_m2_save_")],
		Vector2.ZERO, Vector2(520, 24), 12, Color("#9aa8ba"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)


func _export_original() -> void:
	if state == null:
		return
	_toast("已导出原版布局" if state.save_original() else "导出失败")
	_open_save_impl(false)


func _import_original() -> void:
	if state == null:
		return
	if state.load_original():
		selected_town = state.current_town
		_close_panel()
		_toast("已导入原版布局")
		_show_world()
	else:
		_toast("导入失败：缺 user://dlz_original.dat")


func _save_slot(slot: int) -> void:
	if state.save_slot(slot):
		_toast("存档成功：槽 %d" % slot)
	else:
		_toast("存档失败")
	_open_save_impl(false)


func _load_slot(slot: int) -> void:
	if state.load_slot(slot):
		selected_town = state.current_town
		_close_panel()
		_toast("读档成功：槽 %d" % slot)
		_show_town(selected_town)
	else:
		_toast("读档失败")


# ---------------- 出击演练 ----------------

func _open_battle_select() -> void:
	var content := _panel_shell("出击演练 / M1 战斗", 500, 300)
	var alive := 0
	for m in state.party:
		if int(m["hp"]) > 0:
			alive += 1
	content.add_child(_label("可出击：%d 人（战斗最多按地图出生位）" % alive,
			Vector2.ZERO, Vector2(460, 24), 16, Color("#c8d3e2")))
	for idx in m2["meta"].get("battle_levels", [14, 8]):
		var lv: Dictionary = _m1_level(int(idx))
		if lv.is_empty():
			continue
		var b := _button("L%02d %s" % [int(lv["index"]), lv["name"]],
				Vector2.ZERO, Vector2(300, 34),
				_start_battle.bind(int(lv["index"])), 16)
		b.custom_minimum_size = Vector2(300, 34)
		content.add_child(b)
	var back := _button("返回城镇", Vector2.ZERO, Vector2(160, 30),
			func(): _close_panel(); _show_town(selected_town), 14)
	back.custom_minimum_size = Vector2(160, 30)
	content.add_child(back)


func _m1_level(idx: int) -> Dictionary:
	for lv in m1.get("levels", []):
		if int(lv.get("index", -1)) == idx:
			return lv
	return {}


func _build_battle_level(idx: int) -> Dictionary:
	var base: Dictionary = _m1_level(idx)
	if base.is_empty():
		return {}
	var lv = base.duplicate(true)
	var spawns: Array = []
	var enemies: Array = []
	for u in lv["units"]:
		if str(u.get("side", "")) == "player":
			spawns.append(u)
		else:
			enemies.append(u)
	var alive: Array = []
	for m in state.party:
		if int(m["hp"]) > 0:
			alive.append(m)
	var deploy: int = min(spawns.size(), alive.size())
	if deploy <= 0:
		return {}
	var players: Array = []
	for i in range(deploy):
		players.append(_member_unit(alive[i], spawns[i]))
	lv["units"] = players + enemies
	lv["players"] = players.size()
	lv["enemies"] = enemies.size()
	lv["name"] = "演练 / " + str(lv["name"])
	# 只保留仍在队伍里的失败单位
	var fail_units: Array = []
	for name in lv.get("fail_units", []):
		for m in alive:
			if str(m["name"]) == str(name):
				fail_units.append(name)
	lv["fail_units"] = fail_units
	return lv


func _member_unit(m: Dictionary, spawn: Dictionary) -> Dictionary:
	var p: Dictionary = m2["people"][int(m["pid"])]
	var u: Dictionary = p.get("unit", {})
	var d: Dictionary = spawn.duplicate(true)
	d["pid"] = int(m["pid"])
	d["side"] = "player"
	d["name"] = m["name"]
	d["unit_name"] = m["unit_name"]
	d["bingzhong"] = int(m["bingzhong"])
	d["level"] = int(m["level"])
	d["wuli"] = int(m["wuli"])
	d["zhili"] = int(m["zhili"])
	d["hp"] = max(1, int(m["hp"]))
	d["raw_hp"] = int(m["hp"])
	d["hp_source"] = "m2"
	d["max_hp"] = int(m["max_hp"])
	d["x"] = int(spawn["x"])
	d["y"] = int(spawn["y"])
	d["direction"] = int(spawn.get("direction", 1))
	d["face"] = int(p.get("face", 0))
	d["face_png"] = p.get("face_png", "")
	d["army_png"] = p.get("army_png", "")
	d["select"] = int(u.get("select", 1))
	d["apply"] = int(u.get("apply", 0))
	d["move"] = int(u.get("yidong", 4))
	d["gongji"] = int(u.get("gongji", 0))
	d["fangyu"] = int(u.get("fangyu", 0))
	d["tili"] = int(u.get("tili", 50))
	d["tili_plus"] = int(u.get("tili_plus", 0))
	d["is_boss"] = false
	return d


func _start_battle(idx: int) -> void:
	var level: Dictionary = _build_battle_level(idx)
	if level.is_empty():
		_toast("没有可出击的单位")
		return
	_close_panel()
	ui_root.visible = false
	battle = preload("res://scripts/Battle.gd").new()
	add_child(battle)
	battle.finished.connect(_on_battle_finished)
	var bd: Dictionary = m2["battle"].duplicate(true)
	bd["meta"]["font"] = m2["meta"].get("font", "res://assets/font/hzk16.fnt")
	bd["meta"]["font_size"] = 16
	bd["mine_png"] = m2["meta"].get("mine_png", "")
	battle.setup(bd, level, font)


func _on_battle_finished(result: String, message: String) -> void:
	var units: Array = []
	if is_instance_valid(battle):
		for u in battle.player_units:
			units.append({"side": "player", "pid": int(u.data.get("pid", -1)),
						  "hp": int(u.hp)})
	var info: Dictionary = state.apply_battle(result == "victory", units, selected_town)
	_show_battle_result(result, message, info)


func _show_battle_result(result: String, message: String, info: Dictionary) -> void:
	result_canvas = CanvasLayer.new()
	result_canvas.layer = 100
	add_child(result_canvas)
	var layer := Control.new()
	layer.theme = ui_theme
	result_canvas.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.position = Vector2.ZERO
	dim.size = Vector2(640, 480)
	layer.add_child(dim)
	var center := CenterContainer.new()
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var ok := result == "victory"
	var head := _label("胜  利" if ok else "失  败", Vector2.ZERO, Vector2(440, 40),
			32, Color("#f2c14e") if ok else Color("#ff6b6b"))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var msg := _label(message, Vector2.ZERO, Vector2(440, 30), 16,
			Color("#e8edf4"))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)
	var reward := int(info.get("reward", 0))
	box.add_child(_label("奖励 %d    当前资金 %d" % [reward, state.money],
			Vector2.ZERO, Vector2(440, 24), 16, Color("#f2c14e")))
	var btn := _button("返回城镇", Vector2.ZERO, Vector2(160, 34),
			_close_battle_result, 16)
	btn.custom_minimum_size = Vector2(160, 34)
	box.add_child(btn)


func _close_battle_result() -> void:
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
		result_canvas = null
	if is_instance_valid(battle):
		battle.queue_free()
		battle = null
	if is_instance_valid(ui_root):
		ui_root.visible = true
	_show_town(selected_town)
