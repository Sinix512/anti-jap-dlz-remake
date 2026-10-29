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
var forge_fuse := 0
var forge_kind := 0
var forge_quantity := 0
var party_selected := -1
var k04_page := 0
var k04_person := -999
var k04_source := -1
var k04_held := -1
var _shop_detail: Label
var shop_kind := "junxie"
var shop_selling := false
var shop_mode := 0
var shop_item_page := 0
var shop_people_page := 0
var shop_person := -100
var shop_pending: Dictionary = {}
# Modern shop input is opt-out so native input/palette fixtures can retain their
# exact original contract without making normal players use drag-only input.
var shop_convenience_enabled := true
var info_panel: CanvasLayer
var toast: Label
var toast_bg: NinePatchRect
var _ambient: AudioStreamPlayer
var _drag_state: Dictionary = {}
var service_screen: Control
var native_service_timer_count:=0



func _notification(what:int) -> void:
	if what!=NOTIFICATION_DRAG_END or _drag_state.is_empty():return
	var previous:=_drag_state
	_drag_state={}
	if get_viewport().gui_is_drag_successful():return
	if previous.kind=="shop" and shop_convenience_enabled:
		_shop_clear_interaction()
		if is_instance_valid(previous.ui) and ui_root==previous.ui:call_deferred("_render_shop")
		return
	# A cancelled/invalid drop is not a click selection or a transaction.
	shop_pending=previous.pending
	k04_source=int(previous.source);k04_held=int(previous.held)
	if is_instance_valid(previous.ui) and ui_root==previous.ui:
		if previous.kind=="shop":call_deferred("_render_shop")
		else:call_deferred("_show_k04_status",false)


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
	return preload("res://scripts/battle/StateCodec.gd").integers(parsed) if parsed is Dictionary else {}


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
	l.add_theme_font_size_override("font_size", maxi(fs, OriginalUI.MIN_TEXT_SIZE))
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
	b.add_theme_font_size_override("font_size", maxi(fs, OriginalUI.MIN_TEXT_SIZE))
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _clear_ui() -> void:
	if shop_convenience_enabled:_shop_clear_interaction()
	if is_instance_valid(panel_root):
		panel_root.set_process_input(false);panel_root.hide();panel_root.queue_free()
		panel_root = null
	if is_instance_valid(ui_root):
		ui_root.set_process_input(false);ui_root.hide()
		if is_instance_valid(service_screen):service_screen.enabled=false
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
	if is_instance_valid(toast_bg):
		toast_bg.queue_free()
	var parent: Control = panel_root if is_instance_valid(panel_root) else ui_root
	toast_bg = OriginalUI.nine_patch("res://assets/ui/panel_stone_small.png",
			Rect2(150, 64, 340, 58), 10)
	parent.add_child(toast_bg)
	toast = _label(msg, Vector2(162, 80), Vector2(316, 26), 16, Color("#ffe08a"))
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	toast.add_theme_constant_override("outline_size", 4)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(toast)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.parallel().tween_property(toast, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(toast_bg, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		if is_instance_valid(toast):
			toast.queue_free()
		if is_instance_valid(toast_bg):
			toast_bg.queue_free())


# ---------------- 世界地图 ----------------

func _show_world() -> void:
	mode = "world"
	_stop_ambient()
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
	var hint := _label("选择建筑服务；军械/杂货/作坊是 M2 经济入口；点击镇内热点听环境音",
			Vector2(8, 392), Vector2(620, 24), 16, Color("#d7dfea"))
	ui_root.add_child(hint)
	_setup_town_audio(t)


func _setup_town_audio(t: Dictionary) -> void:
	var hotspots: Array = t.get("sound_hotspots", [])
	for h in hotspots:
		var wave := int(h.get("wave", -1))
		if wave < 800:
			continue
		var path := "res://assets/audio/wave_%04d.wav" % wave
		if not ResourceLoader.exists(path):
			continue
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "环境音"
		b.position = Vector2(int(h.get("x", 0)) * 2,
				int(h.get("y", 0)) * 2 + 44)
		b.size = Vector2(28, 28)
		b.pressed.connect(_play_ambient.bind(wave))
		ui_root.add_child(b)
	# 进入城镇先播放第一个热点，作为环境底音；点击热点可重放。
	for h in hotspots:
		var wave := int(h.get("wave", -1))
		if wave >= 800:
			_play_ambient(wave)
			break


func _play_ambient(wave: int) -> void:
	var path := "res://assets/audio/wave_%04d.wav" % wave
	if not ResourceLoader.exists(path):
		return
	if _ambient == null or not is_instance_valid(_ambient):
		_ambient = AudioStreamPlayer.new()
		_ambient.volume_db = -16.0
		add_child(_ambient)
	_ambient.stream = load(path)
	_ambient.play()


func _stop_ambient() -> void:
	if _ambient != null and is_instance_valid(_ambient):
		_ambient.stop()


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
		panel_root.set_process_input(false);panel_root.hide();panel_root.queue_free()
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
	if shop_convenience_enabled:_shop_clear_interaction()
	# Original K01 initialization only, not every redraw or arbitrary person.
	if kind!="material":
		for person in _shop_roster():state.InventorySlots.compact(person.get("item_slots",[]))
	shop_kind = "zahuo" if kind == "material" else kind
	shop_mode = 3 if kind == "material" else (2 if selling else 0)
	shop_item_page=0; shop_people_page=0; shop_pending.clear()
	var roster:=_shop_roster();shop_person=int(roster[0].pid) if not roster.is_empty() else -999
	_show_service("shop")


func _shop_mode(mode_: int) -> void:
	if shop_convenience_enabled:_shop_clear_interaction()
	if mode_==shop_mode:return
	shop_mode=mode_;shop_item_page=0;shop_people_page=0;shop_pending.clear()
	var roster:=_shop_roster();shop_person=int(roster[0].pid) if not roster.is_empty() else -999
	_render_shop()


func _shop_roster() -> Array:
	var people: Array=[]
	for slot in range(32):
		var person: Dictionary=state.person(slot)
		if int(person.get("faction",1))==0:people.append(person)
	return people


func _shop_stock() -> Array:
	var result: Array=[]
	if shop_mode in [0,3]:
		for record in state.town(selected_town).get("shops",{}).get("material" if shop_mode==3 else shop_kind,[]):
			result.append({"id":int(record["index"]),"record":record,"slot":-1})
	elif shop_mode==1:
		var person=state.deploy_member(shop_person)
		if person!=null:
			var slots: Array=person.get("item_slots",[])
			for index in range(slots.size()):
				var iid:=int(slots[index])-1
				result.append({"id":iid,"record":state.item(iid),"slot":index})
	else:
		for iid in range(80 if shop_kind=="junxie" else 0,156 if shop_kind=="junxie" else 80):
			if state.item_count(iid)>0:result.append({"id":iid,"record":state.item(iid),"slot":-1})
	return result


# Native Godot drag/drop keeps click-source -> click-target as an accessible
# alternative. No stock or money changes until the actual drop is committed.
func _drag_payload(_position:Vector2,kind:String,record:Dictionary) -> Variant:
	if kind=="shop" and shop_mode==3:return null
	_drag_state={"kind":kind,"pending":shop_pending.duplicate(true),"source":k04_source,"held":k04_held,"ui":ui_root}
	var preview:=TextureRect.new()
	preview.texture=OriginalUI.first_frame(str(record.get("icon","")))
	preview.custom_minimum_size=Vector2(48,48)
	if kind=="shop":
		shop_pending=record.item.duplicate(true)
	else:
		k04_source=int(record.slot);k04_held=int(record.code)
	var owner:Control=get_viewport().gui_get_hovered_control()
	if owner!=null:owner.set_drag_preview(preview)
	else:preview.queue_free()
	return {"dlz_drag":kind}


func _accept_drop(_position:Vector2,payload:Variant,kind:String) -> bool:
	return payload is Dictionary and payload.get("dlz_drag","")==kind


func _shop_drop(_position:Vector2,_payload:Variant,destination:String,pid:int) -> void:
	_shop_commit(destination,pid,false)


func _mine_drop(_position:Vector2,_payload:Variant,pid:int) -> void:
	if pid==-999:_k04_store()
	elif pid==-998:_k04_sell()
	else:_k04_target(pid)


func _service_input_blocked() -> bool:
	return is_instance_valid(panel_root) or is_instance_valid(result_canvas) or is_instance_valid(info_panel)

func _service_palette(_key:String) -> void:pass

func _show_service(screen:String) -> void:
	if is_instance_valid(ui_root):preload("res://scripts/ui/OriginalPaletteFade.gd").play(ui_root,false)
	_new_ui()
	mode=screen
	_service_palette({"shop":"K01","forge":"K03","mines":"K04"}[screen])
	ui_root.set_meta("original_screen",screen)
	service_screen=preload("res://scripts/ui/OriginalServiceScreen.gd").new()
	ui_root.add_child(service_screen);service_screen.setup(self,screen)
	preload("res://scripts/ui/OriginalPaletteFade.gd").play(ui_root,true)
	preload("res://scripts/ui/OriginalPaletteFade.gd").discard_buffered_input(get_tree())

func _service_return_town() -> void:
	if shop_convenience_enabled:_shop_clear_interaction()
	preload("res://scripts/ui/OriginalPaletteFade.gd").play(ui_root,false)
	_show_town(selected_town)
	preload("res://scripts/ui/OriginalPaletteFade.gd").play(ui_root,true)
	preload("res://scripts/ui/OriginalPaletteFade.gd").discard_buffered_input(get_tree())

func _refresh_service(screen:String) -> void:
	if is_instance_valid(service_screen) and service_screen.is_visible_in_tree() and service_screen.kind==screen:service_screen.refresh()
	else:_show_service(screen)

func _render_shop() -> void:
	var stock:=_shop_stock()
	shop_item_page=clampi(shop_item_page,0,maxi(0,(stock.size()-1)/12))
	shop_people_page=clampi(shop_people_page,0,maxi(0,(_shop_roster().size()-1)/8))
	_refresh_service("shop")


func _info_right_input(event: InputEvent, kind: String, id: int) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed:
		get_viewport().set_input_as_handled()
		_open_original_info(kind,id)


func _open_original_info(kind: String, id: int) -> void:
	if is_instance_valid(info_panel):return
	if shop_convenience_enabled:_shop_clear_interaction()
	info_panel=preload("res://scripts/ui/OriginalInfo.gd").new()
	add_child(info_panel)
	var origin_ui=ui_root
	info_panel.closed.connect(func():
		info_panel=null
		if kind=="person" and is_instance_valid(origin_ui) and ui_root==origin_ui and origin_ui.get_meta("original_screen","")=="shop":_render_shop()
	)
	var person:Dictionary={}
	if kind=="person":
		var member=state.deploy_member(id)
		if member!=null:person=member
	info_panel.setup(font,m2,kind,id,person)


func _service_confirm(prompt:String,callback:Callable) -> void:
	if shop_convenience_enabled:_shop_clear_interaction()
	_close_panel()
	panel_root=preload("res://scripts/ui/OriginalConfirm.gd").new();ui_root.add_child(panel_root)
	var dialog=panel_root
	dialog.setup(font,prompt,Vector2(320,200),Color("#a4fcfc"),preload("res://scripts/ui/OriginalPalette.gd").colors("K01"))
	dialog.answered.connect(func(yes:bool):_close_panel();callback.call(yes))

func _service_notice(value:String) -> void:
	if shop_convenience_enabled:_shop_clear_interaction()
	_close_panel()
	panel_root=preload("res://scripts/ui/ShopNotice.gd").new() if shop_convenience_enabled and mode=="shop" else preload("res://scripts/ui/OriginalNotice.gd").new()
	ui_root.add_child(panel_root)
	panel_root.setup(font,value,preload("res://scripts/ui/OriginalPalette.gd").colors("K01"))
	panel_root.closed.connect(_close_panel)

func _shop_bulk_input(event: InputEvent) -> void:
	if shop_mode==2 and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and event.double_click:
		get_viewport().set_input_as_handled()
		_service_confirm("全卖掉吗",func(yes:bool):
			if yes:_shop_bulk_sell()
		)


func _shop_bulk_sell() -> void:
	if shop_mode!=2:return
	if shop_convenience_enabled:_shop_clear_interaction()
	# Preserve the original odd boundary: individual military pages include80,
	# but bulk military starts81; bulk grocery includes80. Round each kind once.
	for iid in range(81 if shop_kind=="junxie" else 0,156 if shop_kind=="junxie" else 81):
		var count:int=state.item_count(iid)
		if count<=0:continue
		state.money+=int(state.item(iid).get("price",0))*count*(7-state.difficulty)/10
		state.add_item(iid,-count)
	shop_pending.clear();_render_shop()


func _shop_page(delta: int, people: bool) -> void:
	if shop_convenience_enabled:_shop_clear_interaction()
	if people:shop_people_page+=delta
	else:shop_item_page+=delta
	shop_pending.clear();_render_shop()


func _shop_pick(item: Dictionary) -> void:
	if shop_mode==3:
		_shop_material(int(item.id))
		return
	shop_pending=item.duplicate(true)
	_render_shop()


func _shop_target(pid: int) -> void:
	if shop_pending.is_empty():
		if shop_mode==1:shop_person=pid;_render_shop()
	else:_shop_commit("person",pid,false)


func _shop_clear_interaction() -> void:
	shop_pending.clear()
	if _drag_state.get("kind","")=="shop":_drag_state.clear()
	if is_instance_valid(service_screen) and service_screen.kind=="shop":service_screen.clear_shop_interaction()


func _shop_cancel_selection() -> void:
	_shop_clear_interaction()
	_render_shop()


func _shop_failure(message:String) -> void:
	_shop_cancel_selection()
	_service_notice(message)


func _shop_continue_sale(iid:int) -> void:
	# Keep only the selected kind, never the old slot: removing an item compacts
	# personal bags and may move a different kind into that slot immediately.
	_shop_clear_interaction()
	for entry in _shop_stock():
		if int(entry.id)==iid:
			shop_pending=entry.duplicate(true)
			break
	_render_shop()


func _shop_commit_convenient(destination:String,pid:int,confirmed:bool) -> void:
	if shop_pending.is_empty():return
	# Validate the destination and source again at commit, never on mouse DOWN.
	if not (destination=="person" or destination=="store" and shop_mode in [0,1] or destination=="sell" and shop_mode in [1,2]):
		_shop_cancel_selection();return
	var iid:=int(shop_pending.get("id",-1))
	if iid<0 or not shop_mode in [0,1,2]:_shop_cancel_selection();return
	var record:Dictionary=state.item(iid)
	var target=state.deploy_member(pid)
	var source=state.deploy_member(shop_person)
	if shop_mode==0:
		var available:=false
		for entry in _shop_stock():
			if int(entry.id)==iid:available=true;break
		if not available:_shop_failure("商品已变化，请重新选择。");return
	elif shop_mode==1:
		if source==null:_shop_failure("物品来源已变化，请重新选择。");return
		var slots:Array=source.get("item_slots",[])
		var index:=int(shop_pending.get("slot",-1))
		if index<0 or index>=slots.size() or int(slots[index])!=iid+1:
			_shop_failure("物品来源已变化，请重新选择。");return
	elif state.item_count(iid)<=0:_shop_failure("库房中已没有这件物品。");return
	if destination=="person":
		if target==null:_shop_failure("请选择有效的人物。");return
		if shop_mode==1 and source==target:_shop_failure("请选择其他人物或库房。");return
		if not (target.get("item_slots",[]) as Array).has(0):_shop_failure("该人物携带物品已满！");return
		if not confirmed and not state.item_compatible(target,iid):
			var pending:=shop_pending.duplicate(true)
			var source_person:=shop_person
			var source_mode:=shop_mode
			_service_confirm("不能用，保留吗",func(yes:bool):
				if yes and mode=="shop" and shop_mode==source_mode and shop_person==source_person:
					shop_pending=pending;_shop_commit(destination,pid,true)
				else:_shop_cancel_selection()
			)
			return
	if shop_mode==0:
		if state.money<int(record.get("price",0)):_shop_failure("资金不够！");return
		state.money-=int(record.get("price",0))
	elif shop_mode==2:state.add_item(iid,-1)
	else:state.InventorySlots.remove_id(source.get("item_slots",[]),iid+1)
	if destination=="person":state.InventorySlots.add_id(target.get("item_slots",[]),iid+1)
	elif destination=="sell":state.money+=int(record.get("price",0))*(7-state.difficulty)/10
	elif destination=="store":state.add_item(iid,1)
	if destination=="sell":_shop_continue_sale(iid)
	else:_shop_cancel_selection()


func _shop_commit(destination: String, pid: int, confirmed: bool) -> void:
	if shop_convenience_enabled:
		_shop_commit_convenient(destination,pid,confirmed)
		return
	if shop_pending.is_empty():return
	var iid:=int(shop_pending.id)
	var record:Dictionary=state.item(iid)
	var target=state.deploy_member(pid)
	var source=state.deploy_member(shop_person)
	if destination=="person":
		if target==null or not (target.get("item_slots",[]) as Array).has(0):shop_pending.clear();_render_shop();return
		if shop_mode==1 and source==target:shop_pending.clear();_render_shop();return
		if not confirmed and not state.item_compatible(target,iid):
			var pending:=shop_pending.duplicate(true)
			_service_confirm("不能用，保留吗",func(yes:bool):
				shop_pending.clear()
				if yes:shop_pending=pending;_shop_commit(destination,pid,true)
				else:_render_shop()
			)
			return
	if shop_mode==0:
		if state.money<int(record.get("price",0)):shop_pending.clear();_render_shop();_service_notice("资金不够！");return
		state.money-=int(record.get("price",0))
	elif shop_mode==2:
		if state.item_count(iid)<=0:return
		state.add_item(iid,-1)
	elif shop_mode==1:
		var slots:Array=source.get("item_slots",[])
		var index:=int(shop_pending.slot)
		if int(slots[index])!=iid+1:return
		state.InventorySlots.remove_id(slots,iid+1)
	if destination=="person":
		var slots:Array=target.get("item_slots",[]);state.InventorySlots.add_id(slots,iid+1)
	elif destination=="sell":state.money+=int(record.get("price",0))*(7-state.difficulty)/10
	elif destination=="store":state.add_item(iid,1)
	shop_pending.clear();_render_shop()


func _shop_material(id: int) -> void:
	var material:Dictionary=state.material(id)
	var price:=int(material.get("price",0))
	if price<=0:return
	var maximum:int=mini(1000/price,state.money/price)
	if shop_convenience_enabled:
		_shop_clear_interaction()
		_close_panel()
		panel_root=preload("res://scripts/ui/ShopQuantity.gd").new();ui_root.add_child(panel_root)
		panel_root.setup(font,str(material.name),str(material.unit),price,maximum,state.money)
		panel_root.chosen.connect(func(count:int):
			_close_panel()
			var current_maximum:int=mini(1000/price,state.money/price)
			if count>0 and count<=current_maximum:
				state.money-=count*price;state.add_material(id,count)
			elif count>0:_service_notice("资金或可购数量已变化，请重新选择。")
			_render_shop()
		)
		panel_root.cancelled.connect(func():_close_panel();_render_shop())
		return
	var stock:=_shop_stock()
	for slot in range(stock.size()):
		if int(stock[slot].id)==id:
			# 436AFC uses grid-slot price here, mapped-ID price below.
			if state.money<int(state.material(slot).get("price",0)):return
			break
	_close_panel()
	panel_root=preload("res://scripts/ui/OriginalQuantity.gd").new();ui_root.add_child(panel_root)
	panel_root.setup(font,preload("res://scripts/ui/OriginalPalette.gd").colors("K01"),service_screen.quantity_backdrop(),maximum,str(material.name),str(material.unit))
	panel_root.chosen.connect(func(count:int):
		if count*price<=state.money:state.money-=count*price;state.add_material(id,count)
		_close_panel();_render_shop()
	)


func _shop_show_detail(rec: Dictionary, selling: bool) -> void:
	if _shop_detail == null:
		return
	var price := int(rec.get("price", 0))
	var desc := str(rec.get("desc", rec.get("description", "")))
	_shop_detail.text = "商品：%s\n\n价格：%d\n售价：%d\n\n%s" % [
		rec.get("name", ""), price, max(1, int(price / 2.0)),
		desc if desc != "" else "点击右侧按钮买入/卖出。"]


func _shop_row(r: Dictionary, kind: String, selling: bool) -> HBoxContainer:
	var rec: Dictionary = r["rec"]
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(func(): _shop_show_detail(rec, selling))
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

func _forge_max() -> int:
	var kind: Dictionary = state.mine(forge_kind)
	var maximum: int = 9999
	var recipe: Array = kind.get("recipe",[])
	for material in range(recipe.size()):
		if int(recipe[material]) > 0: maximum = mini(maximum,state.material_count(material)/int(recipe[material]))
	var price: int = [0,0,80,300][forge_fuse]
	if price > 0: maximum = mini(maximum,state.money/price)
	if not bool(state.can_craft(forge_fuse*10+forge_kind).get("ok",false)): return 0
	return maxi(0,maximum)


func _open_forge() -> void:
	forge_kind=0;forge_fuse=0;forge_quantity=0
	_show_service("forge")

func _set_forge_kind(kind_: int) -> void:
	if kind_==forge_kind or kind_<0 or kind_>=10 or int(state.script_globals.get("0x%x"%(0x95eb08+kind_*4),0))==0:return
	forge_kind=kind_;forge_quantity=0;_refresh_service("forge")
func _set_forge_fuse(fuse: int) -> void:
	if fuse==forge_fuse or fuse<0 or fuse>=4 or int(state.script_globals.get("0x%x"%(0x95eaf8+fuse*4),0))==0:return
	forge_fuse=fuse;forge_quantity=0;_refresh_service("forge")
func _forge_adjust(delta: int) -> void:
	forge_quantity=clampi(forge_quantity+delta,0,_forge_max());_refresh_service("forge")
func _forge_reset() -> void:
	forge_quantity=0;_refresh_service("forge")
func _forge_set_max() -> void:
	forge_quantity=_forge_max();_refresh_service("forge")
func _forge_batch() -> void:
	var made:=0
	for i in range(forge_quantity):
		if not bool(state.craft_mine(forge_fuse*10+forge_kind).get("ok",false)):break
		made+=1
	if made>0:OriginalUI.play_native_sfx(13)
	forge_quantity=0;_refresh_service("forge")


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
	var content := _panel_shell("队伍 / 携带 / 转职", 584, 408)
	var top := HBoxContainer.new()
	content.add_child(top)
	top.add_child(_button("仓库", Vector2.ZERO, Vector2(90,28), _open_inventory,16))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",10)
	content.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(190,260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var roster: Array = state.all_members()
	if state.deploy_member(party_selected) == null: party_selected = state.PROTAGONIST_PID
	for person in roster:
		var button := _button("%s  Lv%d\n%s" % [person["name"],person["level"],person["unit_name"]],Vector2.ZERO,Vector2(180,46),_party_select.bind(int(person["pid"])),16)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if int(person["pid"]) == party_selected: button.modulate = Color(1,0.88,0.55)
		list.add_child(button)
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(320,260)
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation",8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	var m = state.deploy_member(party_selected)
	if m == null: return
	var bonuses: Dictionary = state.equipment_bonuses(m)
	var cls: Dictionary = state.unit_of(m)
	var rules = preload("res://scripts/battle/CombatRules.gd")
	var atk: int = rules.attack_power(m,cls,100,100,int(m.get("attack_count",1)),int(bonuses.get("attack",0)))
	var defense: int = rules.defense_power(m,cls,100,0,int(bonuses.get("defense",0)))
	var info := _label("%s  %s\n等级%d  经验%d/100\n体力%d/%d  武力%d 智力%d\n攻击%d 防御%d 移动%d" % [m["name"],m["unit_name"],m["level"],m.get("xp",0),m["hp"],m["max_hp"],m["wuli"],m["zhili"],atk,defense,int(cls.get("yidong",0))+int(bonuses.get("move",0))],Vector2.ZERO,Vector2(310,96),16)
	info.custom_minimum_size = Vector2(310,96)
	right.add_child(info)
	var carried: Array = m.get("item_slots",[])
	var mine_slots: Array = m.get("mine_slots",[])
	right.add_child(_button("物品 %d/8（管理携带）" % (carried.size()-carried.count(0)),Vector2.ZERO,Vector2(280,30),_open_loadout.bind(int(m["pid"]),"items"),16))
	right.add_child(_button("地雷 %d/8（管理携带）" % (mine_slots.size()-mine_slots.count(0)),Vector2.ZERO,Vector2(280,30),_open_loadout.bind(int(m["pid"]),"mines"),16))
	var check: Dictionary = state.can_promote(m)
	if bool(check.get("ok",false)):
		right.add_child(_button("转职为%s" % check.get("target_name",""),Vector2.ZERO,Vector2(280,30),_promote.bind(int(m["pid"])),16))
	else:
		right.add_child(_label(str(check.get("msg","")),Vector2.ZERO,Vector2(310,26),16))


func _loadout_name(kind: String, id: int) -> String:
	if kind == "items": return str(state.item(id).get("name","?"))
	return "%s%s" % [["普通","引爆","定时","遥控"][id/10],state.mine(id%10).get("name","地雷")]


func _open_loadout(pid: int, kind: String) -> void:
	var m = state.deploy_member(pid)
	if m == null: return
	var content := _panel_shell("%s / %s" % [m["name"],"物品携带" if kind == "items" else "地雷携带"],584,408)
	content.add_child(_button("返回队伍",Vector2.ZERO,Vector2(120,28),_open_party,16))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540,288)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var slots: Array = m.get("item_slots" if kind == "items" else "mine_slots",[])
	list.add_child(OriginalUI.label("已携带（每类八格）",font,16))
	for index in range(slots.size()):
		if int(slots[index]) == 0: continue
		var row := HBoxContainer.new()
		list.add_child(row)
		var label := OriginalUI.label(_loadout_name(kind,int(slots[index])-1),font,16)
		label.custom_minimum_size = Vector2(260,28)
		row.add_child(label)
		row.add_child(_button("退仓",Vector2.ZERO,Vector2(70,28),_return_loadout.bind(pid,kind,index),16))
		row.add_child(_button("交给",Vector2.ZERO,Vector2(70,28),_open_transfer.bind(pid,kind,index),16))
	list.add_child(OriginalUI.label("仓库（战场不能直接使用，请在此分配）",font,16))
	var stock: Dictionary = state.items if kind == "items" else state.mines
	var keys := stock.keys()
	keys.sort_custom(func(a,b): return int(a)<int(b))
	for key in keys:
		if int(stock[key]) <= 0: continue
		var row := HBoxContainer.new()
		list.add_child(row)
		var label := OriginalUI.label("%s ×%d" % [_loadout_name(kind,int(key)),stock[key]],font,16)
		label.custom_minimum_size = Vector2(330,28)
		row.add_child(label)
		var button := _button("携带",Vector2.ZERO,Vector2(90,28),_give_loadout.bind(pid,kind,int(key)),16)
		button.disabled = not slots.has(0)
		row.add_child(button)


func _give_loadout(pid: int, kind: String, id: int) -> void:
	var m = state.deploy_member(pid)
	var result: Dictionary = state.give_item(m,id) if kind == "items" else state.give_mine(m,id)
	_toast(str(result.get("msg","")))
	_open_loadout(pid,kind)


func _return_loadout(pid: int, kind: String, index: int) -> void:
	var m = state.deploy_member(pid)
	var result: Dictionary = state.return_item(m,index) if kind == "items" else state.return_mine(m,index)
	_toast(str(result.get("msg","")))
	_open_loadout(pid,kind)


func _open_transfer(pid: int, kind: String, index: int) -> void:
	var content := _panel_shell("交给谁？",540,380)
	content.add_child(_button("返回",Vector2.ZERO,Vector2(90,28),_open_loadout.bind(pid,kind),16))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480,260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	for m in state.all_members():
		if int(m["pid"]) == pid: continue
		var slots: Array = m.get("item_slots" if kind == "items" else "mine_slots",[])
		var button := _button(str(m["name"]),Vector2.ZERO,Vector2(460,30),_do_transfer.bind(pid,int(m["pid"]),kind,index),16)
		button.disabled = not slots.has(0)
		list.add_child(button)


func _do_transfer(from_pid: int, to_pid: int, kind: String, index: int) -> void:
	var a = state.deploy_member(from_pid)
	var b = state.deploy_member(to_pid)
	var result: Dictionary = state.transfer_item(a,index,b) if kind == "items" else state.transfer_mine(a,b,index)
	_toast(str(result.get("msg","")))
	_open_loadout(from_pid,kind)


func _open_inventory() -> void:
	_close_panel()
	var inv := preload("res://scripts/ui/InventoryPanel.gd").new()
	ui_root.add_child(inv)
	panel_root = inv
	inv.setup(font, m2, state.items, state.mines, state.materials)
	inv.closed.connect(_close_panel)


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


func _native_icon(path: String, position_: Vector2, size_: Vector2 = Vector2(48,48)) -> TextureRect:
	var image := TextureRect.new()
	image.texture = OriginalUI.first_frame(path)
	image.position = position_
	image.size = size_
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(image)
	return image


func _show_k04_status(enter:=true) -> void:
	if enter:
		for person in _shop_roster():state.InventorySlots.compact(person.get("mine_slots",[]))
		k04_person=-999;k04_page=0;k04_source=-1;k04_held=-1
		_show_service("mines")
	else:_refresh_service("mines")

func _k04_pick(index: int, packed: int) -> void:
	k04_source=index;k04_held=packed;_show_k04_status(false)

func _k04_target(pid: int) -> void:
	if k04_held<0:
		if k04_person!=-999:k04_person=pid;k04_source=-1;_show_k04_status(false)
		return
	var target=state.deploy_member(pid)
	var source=state.deploy_member(k04_person)
	if target!=null and target!=source:
		if source==null:state.give_mine(target,k04_held)
		else:state.transfer_mine(source,target,k04_source)
	k04_held=-1;k04_source=-1;_show_k04_status(false)

func _k04_switch() -> void:
	var roster:=_shop_roster()
	k04_person=int(roster[0].pid) if k04_person==-999 and not roster.is_empty() else -999
	k04_page=0;k04_source=-1;k04_held=-1;_show_k04_status(false)

func _k04_fuse(delta: int) -> void:
	if k04_person!=-999:return
	k04_page=clampi(k04_page+delta,0,3);k04_source=-1;k04_held=-1;_show_k04_status(false)

func _k04_store() -> void:
	if k04_source<0:return
	var person=state.deploy_member(k04_person)
	if person!=null:state.return_mine(person,k04_source)
	k04_source=-1;k04_held=-1;_show_k04_status(false)

func _k04_sell() -> void:
	if k04_held<0:return
	var person=state.deploy_member(k04_person)
	state.recycle_mine(k04_held,person if person!=null else {},k04_source)
	k04_source=-1;k04_held=-1;_show_k04_status(false)

func _k04_page(delta: int) -> void:_k04_fuse(delta)
func _show_k03_workshop() -> void:_open_forge()


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
	var content := _panel_shell("存档 / 读档", 560, 410)
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
			var ci := int(info.get("campaign_index", -1))
			var lv_name := ""
			if ci >= 0 and ci < 47:
				lv_name = str(state.m4_level(ci).get("name", ""))
			txt = "槽 %d：L%02d %s / 第 %d 天 / 资金 %d / %d 人" % [
				slot, ci, lv_name, int(info.get("day", 0)),
				int(info.get("money", 0)), (info.get("party", []) as Array).size()]
		var l := _label(txt, Vector2.ZERO, Vector2(390, 24), 14,
				Color("#e8edf4"))
		l.custom_minimum_size = Vector2(390, 24)
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
	var auto: Dictionary = state.slot_info(7)
	if not auto.is_empty():
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 8)
		var atxt := "自动存档（胜利后）：第 %d 天 / 资金 %d / %d 人" % [
			int(auto.get("day", 0)), int(auto.get("money", 0)),
			(auto.get("party", []) as Array).size()]
		var al := _label(atxt, Vector2.ZERO, Vector2(390, 24), 14,
				Color("#8fe0a8"))
		al.custom_minimum_size = Vector2(390, 24)
		arow.add_child(al)
		var aload := _button("读取自动存档", Vector2.ZERO, Vector2(110, 28),
				_load_auto_save, 14)
		aload.custom_minimum_size = Vector2(110, 28)
		arow.add_child(aload)
		content.add_child(arow)
	var cp: Dictionary = state.slot_info(8)
	if not cp.is_empty():
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 8)
		var ctxt := "自动检查点：第 %d 天 / 资金 %d / %d 人" % [
			int(cp.get("day", 0)), int(cp.get("money", 0)),
			(cp.get("party", []) as Array).size()]
		var cl := _label(ctxt, Vector2.ZERO, Vector2(390, 24), 14,
				Color("#f2c14e"))
		cl.custom_minimum_size = Vector2(390, 24)
		crow.add_child(cl)
		var cload := _button("读取检查点", Vector2.ZERO, Vector2(100, 28),
				_load_checkpoint, 14)
		cload.custom_minimum_size = Vector2(100, 28)
		crow.add_child(cload)
		content.add_child(crow)
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
	var olabel := _label("实验：仅战略档57；战斗档150尚不支持", Vector2.ZERO,
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
		_toast("导入失败：缺少文件、格式无效，或是不支持的原版战斗档")


func _save_slot(slot: int) -> void:
	if state.save_slot(slot):
		_toast("存档成功：槽 %d" % slot)
	else:
		_toast("存档失败")
	_open_save_impl(false)


func _load_auto_save() -> void:
	if state.load_slot(7):
		selected_town = state.current_town
		_close_panel()
		_toast("已读取自动存档")
		_show_town(selected_town)
	else:
		_toast("没有自动存档")


func _load_checkpoint() -> void:
	if state.load_checkpoint():
		selected_town = state.current_town
		_close_panel()
		_toast("已读取自动检查点")
		_show_town(selected_town)
	else:
		_toast("没有自动检查点")


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
