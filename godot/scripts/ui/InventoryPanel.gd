extends Control

## 共用行囊：库存和宝箱奖励可见，不把成长书籍冒充战斗消耗品。
signal closed

var font: Font
var tables: Dictionary
var stock: Dictionary
var mine_stock: Dictionary
var material_stock: Dictionary
var category := "items"
var list: VBoxContainer
var detail: Label
var icon: TextureRect


func setup(f: Font, d: Dictionary, items: Dictionary, mines: Dictionary = {},
		materials: Dictionary = {}) -> void:
	font = f
	tables = d
	stock = items
	mine_stock = mines
	material_stock = materials
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var card := OriginalUI.nine_patch(OriginalUI.PANEL_RED, Rect2(28, 36, 584, 408), 10)
	add_child(card)
	add_child(_label("行 囊", Rect2(44, 46, 380, 24), OriginalUI.GOLD_LIGHT))
	var close := OriginalUI.button("关闭", font, Vector2(64, 28), func(): closed.emit())
	close.position = Vector2(530, 44)
	add_child(close)
	var tabs := [["物品", "items"], ["地雷", "mines"], ["材料", "materials"]]
	for i in range(tabs.size()):
		var tab := OriginalUI.button(tabs[i][0], font, Vector2(78, 28),
				_show_category.bind(str(tabs[i][1])))
		tab.position = Vector2(44 + i * 84, 82)
		add_child(tab)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(44, 120)
	scroll.size = Vector2(268, 274)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	icon = TextureRect.new()
	icon.position = Vector2(330, 120)
	icon.size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	detail = _label("", Rect2(330, 178, 262, 218))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(detail)
	add_child(_label("宝箱收入与战斗消耗会随战役存档保存。", Rect2(44, 410, 540, 24)))
	_show_category("items")


func _label(text: String, rect: Rect2, color := OriginalUI.INK) -> Label:
	var l := OriginalUI.label(text, font, 16, color)
	l.position = rect.position
	l.size = rect.size
	return l


func _show_category(kind: String) -> void:
	category = kind
	for node in list.get_children():
		list.remove_child(node)
		node.queue_free()
	detail.text = "（暂无库存）"
	icon.texture = null
	var inv: Dictionary = stock if kind == "items" else (
			mine_stock if kind == "mines" else material_stock)
	var keys := inv.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	var first := true
	for key in keys:
		if int(inv[key]) <= 0:
			continue
		var rec := _record(kind, int(key))
		var b := OriginalUI.button("%s ×%d" % [_name(rec), int(inv[key])], font,
				Vector2(248, 30), _show_detail.bind(kind, int(key), int(inv[key])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
		if first:
			_show_detail(kind, int(key), int(inv[key]))
			first = false
	if first:
		list.add_child(OriginalUI.label("（暂无库存）", font))


func _record(kind: String, id: int) -> Dictionary:
	var records = tables.get(kind, {})
	if records is Array:
		return records[id % 10] if id >= 0 and not records.is_empty() else {}
	var result: Dictionary = records.get(str(id % 10 if kind == "mines" else id), {}).duplicate(true)
	if kind == "mines": result["name"] = ["普通", "引爆", "定时", "遥控"][id / 10] + str(result.get("name", "地雷"))
	return result


func _name(rec: Dictionary) -> String:
	return str(rec.get("name", "未知物品")).replace("\u3000", "").replace(" ", "")


func _show_detail(kind: String, id: int, count: int) -> void:
	var rec := _record(kind, id)
	var path := str(rec.get("icon", ""))
	icon.texture = OriginalUI.first_frame(path)
	var usage := "可在作坊锻造地雷。"
	if kind == "mines":
		usage = "战斗中选择单位，再用埋雷菜单选择雷种。"
	elif kind == "items":
		if id >= 81:
			usage = "在队伍页面分配给人物携带；兼容装备自动取最大加成。"
		elif id >= 61 and id <= 80:
			usage = "兵书与转职道具。在队伍页面查看可用的转职路线。"
		elif id >= 31 and id <= 40:
			usage = "31/32为携带时每轮被动恢复；33至40可在战斗中研读成长。"
		else:
			usage = "战斗中选择单位，再打开物品菜单使用。"
	detail.text = "%s\n数量：%d\n\n%s\n\n%s" % [_name(rec), count,
			str(rec.get("desc", rec.get("description", ""))), usage]
