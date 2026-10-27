extends "res://scripts/m2/Campaign.gd"

## M4/M5 战役层：19 城镇、47 关、原味 UI、剧情/结局。
## 经济/商店/锻造/队伍/存档复用 M2 Campaign 的实现，只替换表现与关卡流程。

const M4_PATH := "res://data/m4.json"
const M5_PATH := "res://data/m5.json"
const M3_PATH := "res://data/m3.json"
const TownRules = preload("res://scripts/m4/TownRules.gd")
# Original JZ completion posts WM_CLOSE, unlike ordinary world/defeat exit.
signal game_close_requested
var pending_town_command: Dictionary = {}
# Only the actual L35 victory continuation records; ending previews never do.
var highscore_path := "user://hiscore.dat"

const LevelBuilder = preload("res://scripts/m4/LevelBuilder.gd")

var qa_mode := DisplayServer.get_name() == "headless"
var _story_generation := 0
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
var deploy_pages := [0,0]
var deploy_page_level := -1
var current_deploy_pids: Array = []
var deployment_screen: Control
var strategic_screen: Control
var strategic_palette_key := "BIGMAP"
# 96A790 target palette changes only on full IMG loads, not PLACE fades.
var native_scene_palette_key := "BIGMAP"
var credits_layer: CanvasLayer
var pending_battle_result: Dictionary = {}
var _play_accum := 0.0
var ending_steps: Array = []
var ending_step := 0
var ending_preview := false
var ending_flow_events:Array=[]
var battle_baseline: Dictionary = {}
var pending_save_snapshot: Dictionary = {}
var modal_layer: CanvasLayer
var modal_previous_busy := false
var battle_visual_active := false
var battle_visual_sequences := 0


func setup(font_ref: Font,creation:Dictionary={}) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		state.configure_protagonist(int(vcfg.get_value("player", "face", 103)),
				int(vcfg.get_value("player", "unit", 1)),
				int(vcfg.get_value("player", "wuli", 80)))
		state.story_variant = bool(vcfg.get_value("video", "story_variant", false))
		state.difficulty = int(vcfg.get_value("gameplay", "difficulty", 1))
	if not creation.is_empty():
		state.player_name=str(creation.get("name","主　角"))
		state.configure_protagonist(int(creation.get("face",103)),int(creation.get("unit",1)),int(creation.get("wuli",80)))
		state.difficulty=clampi(int(creation.get("difficulty",1)),0,2)
	selected_town = state.level_town(state.campaign_index)
	state.current_town = selected_town
	_music(state.town_bgm_scene)
	_show_world()


func _music(scene: int, restart := true) -> void:
	var player = get_node_or_null("/root/Music")
	if player != null: player.play_scene(scene,restart)


func _load_player_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("user://dlz_config.cfg") == OK:
		return str(cfg.get_value("player", "name", "李勇"))
	return "李勇"


func _process(_delta: float) -> void:
	if state != null:
		_play_accum += _delta
		if _play_accum >= 1:
			state.play_seconds += int(_play_accum)
			_play_accum -= int(_play_accum)
	if not is_instance_valid(battle) or is_instance_valid(story_player) or is_instance_valid(cutscene) or battle_visual_active:
		return
	if battle.progress_fx_active or battle.action_resolution_depth>0:
		return
	if battle_story_queue.is_empty():
		if not pending_battle_result.is_empty():
			var r := pending_battle_result
			pending_battle_result = {}
			_settle_battle(str(r["result"]), str(r["message"]))
		return
	if not battle.finished_flag and not battle.scenario.start_phase_pending and battle_visual_sequences==0 and (battle.busy or battle.phase != "player"):
		return
	var entry = battle_story_queue.pop_front()
	if entry is Dictionary:
		if entry.has("phase_end"):
			battle_visual_active = true
			await battle.scenario.complete_start_phase()
			battle_visual_active = false
			battle.update_hud()
		elif entry.has("phase_movie"):
			_play_cutscene("res://assets/m5/flc/%s.ogv" % entry["phase_movie"], Callable())
		elif entry.has("phase_flm"):
			_play_script_flm(entry["phase_flm"])
		elif entry.has("phase_mine"):
			_play_script_mine(entry["phase_mine"])
		elif entry.has("visual_end"):
			battle_visual_sequences=maxi(0,battle_visual_sequences-1)
			battle.busy=battle.finished_flag or battle.scenario.start_phase_pending or battle_visual_sequences>0
			battle.update_hud()
		elif entry.has("message_record"):
			_play_battle_text([int(entry["message_record"])])
		elif entry.has("message"):
			_play_battle_text([int(battle.scenario.trigger_texts.get(str(entry["message"]),-1))])
		else:
			await battle.scenario._apply([entry])
	else:
		_play_battle_text(entry)


func _play_script_mine(effect:Dictionary) -> void:
	battle_visual_active=true
	var generation:=_story_generation
	var current=battle
	await current.scripted_mine(Vector2i(int(effect.tile[0]),int(effect.tile[1])),int(effect.type),int(effect.slot))
	if generation!=_story_generation:return
	battle_visual_active=false
	if is_instance_valid(current):current.busy=current.finished_flag or current.scenario.start_phase_pending or battle_visual_sequences>0


func _play_script_flm(effect:Dictionary) -> void:
	# Guard before awaiting: _process must not consume the next line each frame.
	battle_visual_active=true
	battle.busy=true
	var generation:=_story_generation
	var current=battle
	var tile: Array=effect.get("tile",[0,0])
	var world:=Vector2((int(tile[0])+0.5)*current.TILE,(int(tile[1])+0.5)*current.TILE)
	if bool(effect.get("camera",false)):
		current.camera.position=current._focus_position(world)
		current._clamp_camera()
	var duration:float=current._play_single_cell_flm(int(effect.get("index",0)),world)
	if not qa_mode and not current.fast_sim:
		await current._wait_presentation_time(duration+float(effect.get("wait_ms",0))/1000.0)
	if generation!=_story_generation:return
	battle_visual_active=false
	if is_instance_valid(current):
		current.busy=current.finished_flag or current.scenario.start_phase_pending or battle_visual_sequences>0


func _play_battle_text(ids: Array) -> void:
	if ids.is_empty():
		return
	battle.busy = true
	var generation := _story_generation
	_play_story(ids, func():
		if generation == _story_generation and is_instance_valid(battle):
			battle.busy = battle.finished_flag or battle.scenario.start_phase_pending or battle_visual_sequences>0)


func load_campaign_slot(slot: int) -> bool:
	if not preload("res://scripts/ui/OriginalSaveSlots.gd").load_slot(state,slot):
		return false
	state.setup_m4(m4)
	selected_town = state.current_town
	_close_panel()
	if is_instance_valid(battle): battle.queue_free(); battle = null
	if not state.battle_resume.is_empty():
		var record: Dictionary = state.battle_resume
		current_deploy_pids = record.get("deploy",[]).duplicate()
		current_battle_standalone = bool(record.get("standalone",false))
		battle_baseline = record.get("baseline",{}).duplicate(true)
		_resume_battle(record.get("snapshot",{}))
	else:
		_music(state.town_bgm_scene)
		_show_town(selected_town)
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
	for key in ["K00","K01","K02","K03","K04"]:
		if path.ends_with("/"+key.to_lower()+".png"):
			native_scene_palette_key=key;strategic_palette_key=key
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
	if is_instance_valid(battle):
		modal_previous_busy = battle.busy
		battle.busy = true
		modal_layer = CanvasLayer.new()
		modal_layer.layer = 110
		add_child(modal_layer)
		modal_layer.add_child(panel_root)
	else: ui_root.add_child(panel_root)
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


func _close_panel() -> void:
	super._close_panel()
	if is_instance_valid(modal_layer):
		modal_layer.queue_free()
		if is_instance_valid(battle): battle.busy = modal_previous_busy
	modal_layer = null


func _top_status(title: String) -> void:
	ui_root.add_child(OriginalUI.header(title, font, Rect2(0, 0, 640, 30)))


func _new_ui() -> Control:
	if is_instance_valid(ui_root):
		ui_root.visible = false
	if is_instance_valid(panel_root):
		panel_root.visible = false
	return super._new_ui()


# ---------------- 世界地图 ----------------

func _service_palette(key:String) -> void:
	strategic_palette_key=key;native_scene_palette_key=key

func _service_input_blocked() -> bool:
	return _strategic_input_blocked()

func _strategic_input_blocked() -> bool:
	# Native _input must not swallow GUI-based report/info/developer overlays.
	return is_instance_valid(panel_root) or is_instance_valid(result_canvas) or is_instance_valid(story_player) or is_instance_valid(cutscene) or is_instance_valid(info_panel)


func _show_world() -> void:
	mode="world"
	_new_ui()
	strategic_palette_key="BIGMAP";native_scene_palette_key="BIGMAP"
	strategic_screen=preload("res://scripts/ui/OriginalStrategicScreen.gd").new();ui_root.add_child(strategic_screen)
	strategic_screen.input_blocked=_strategic_input_blocked
	strategic_screen.setup(font,"world",state)
	strategic_screen.town_enter.connect(_select_town)
	strategic_screen.system_requested.connect(_world_system)


func _world_system(point:Vector2) -> void:
	_close_panel()
	modal_layer=CanvasLayer.new();modal_layer.layer=125;add_child(modal_layer)
	panel_root=preload("res://scripts/ui/OriginalChoice.gd").new();modal_layer.add_child(panel_root)
	panel_root.setup(font,["退  出","音  乐","音  效","读  档","存  档"],Vector2(minf(point.x,551),minf(point.y,343)))
	panel_root.cancelled.connect(_close_panel)
	panel_root.chosen.connect(_world_system_chosen)


func _world_system_chosen(choice:int) -> void:
	_close_panel()
	match choice:
		0:_strategy_confirm("退出吗？",func():exit_requested.emit(),Vector2(300,200))
		1:
			var music=get_node_or_null("/root/Music")
			if music!=null:music.toggle()
		2:OriginalUI.sfx_enabled=not OriginalUI.sfx_enabled
		3,4:_world_save_picker(choice==3)


func _strategy_confirm(prompt:String,accepted:Callable,origin:=Vector2(320,200)) -> void:
	_close_panel()
	modal_layer=CanvasLayer.new();modal_layer.layer=125;add_child(modal_layer)
	panel_root=preload("res://scripts/ui/OriginalConfirm.gd").new();modal_layer.add_child(panel_root)
	var palette:Array=preload("res://scripts/ui/OriginalPalette.gd").colors(strategic_palette_key)
	panel_root.setup(font,prompt,origin,preload("res://scripts/ui/OriginalPalette.gd").color_at(palette,OriginalUI.native_text_index),palette)
	panel_root.answered.connect(func(yes:bool):
		_close_panel()
		if yes:accepted.call())


func _world_save_picker(load_first:bool) -> void:
	_close_panel()
	modal_layer=CanvasLayer.new();modal_layer.layer=125;add_child(modal_layer)
	panel_root=preload("res://scripts/ui/OriginalSavePicker.gd").new();modal_layer.add_child(panel_root)
	panel_root.setup(font,preload("res://scripts/ui/OriginalPalette.gd").colors("BIGMAP"),preload("res://scripts/ui/OriginalSaveSlots.gd").previews(state),load_first)
	panel_root.chosen.connect(func(slot:int):
		_close_panel()
		if slot<0:return
		_strategy_confirm("取档吗？" if load_first else "存档吗？",func():
			if load_first:
				if load_campaign_slot(slot) and not is_instance_valid(battle):_show_world()
			else:_save_slot(slot),Vector2(300,200)))


func _select_town(i: int) -> void:
	if not state.town_unlocked(i):return
	selected_town=i;state.current_town=i
	_show_town(i)


func _enter_town() -> void:
	_show_town(selected_town)


func _show_town(index: int) -> void:
	if state.town(index).is_empty():return
	mode="town";selected_town=index;state.current_town=index
	_new_ui()
	strategic_palette_key="PLACE%02d"%index
	strategic_screen=preload("res://scripts/ui/OriginalStrategicScreen.gd").new();ui_root.add_child(strategic_screen)
	strategic_screen.input_blocked=_strategic_input_blocked
	strategic_screen.setup(font,"town",state,index)
	strategic_screen.building_enter.connect(_town_building)


func _town_building(slot:int) -> void:
	if slot!=4:OriginalUI.play_native_sfx(9)
	match slot:
		0:_service_heal()
		1:_open_command()
		2:_service_junxie()
		3:_service_zahuo()
		4:_show_world()
		5:_open_forge()


func _show_room(kind:String) -> void:
	mode=kind
	_new_ui()
	if kind=="command":native_scene_palette_key="BACK19"
	strategic_palette_key=native_scene_palette_key
	strategic_screen=preload("res://scripts/ui/OriginalStrategicScreen.gd").new();ui_root.add_child(strategic_screen)
	strategic_screen.input_blocked=_strategic_input_blocked
	strategic_screen.setup(font,kind,state,selected_town,native_scene_palette_key)
	strategic_screen.room_exit.connect(func():_show_town(selected_town))


func _open_command() -> void:
	_open_mission()


func _service_heal() -> void:
	_show_room("resident")
	var visit: Dictionary = TownRules.visit_resident(state, selected_town)
	_play_story(visit.get("messages", []), func():
		if visit.has("easter"):
			_launch_level(int(visit["easter"]), false)
		elif bool(visit.get("first_deploy", false)):
			_show_first_departure()
		)


func _show_first_departure() -> void:
	_strategy_confirm("出战吗？",func():
		TownRules.set_flag(state,0,2);pending_town_command={}
		_launch_campaign_level())


func _open_mission() -> void:
	_show_room("command")
	# Original town0 commander is an empty function, not a resident shortcut.
	if selected_town==0:return
	pending_town_command=TownRules.prepare_command(state,selected_town)
	var messages:Array=pending_town_command.get("messages",[])
	if bool(pending_town_command.get("no_choice",false)):
		_play_story(messages,func():pass)
	else:_play_story(messages,_show_mission_brief)


func _show_mission_brief() -> void:
	if state.campaign_level().is_empty():return
	if pending_town_command.has("choice_options"):
		_show_solo_choice()
	else:_strategy_confirm("出战吗？",_launch_campaign_level)


func _show_solo_choice() -> void:
	_close_panel()
	modal_layer=CanvasLayer.new();modal_layer.layer=125;add_child(modal_layer)
	panel_root=preload("res://scripts/ui/OriginalChoice.gd").new();modal_layer.add_child(panel_root)
	panel_root.setup(font,["肖  飞","李霜泗"],Vector2(320,200),true,preload("res://scripts/ui/OriginalPalette.gd").colors(strategic_palette_key))
	panel_root.cancelled.connect(_close_panel)
	panel_root.chosen.connect(func(choice:int):_close_panel();_accept_solo(choice))


func _launch_campaign_level() -> void:
	current_battle_standalone = false
	if state.campaign_level().is_empty():
		_toast("当前路线已完成")
		return
	_close_panel()
	if not pending_town_command.is_empty():
		if pending_town_command.has("choice_options"):
			_show_solo_choice()
			return
		TownRules.accept_command(state, selected_town, pending_town_command)
		pending_town_command.clear()
	if not qa_mode:
		state.save_checkpoint()
	_show_deployment(state.campaign_index)


func _accept_solo(choice: int) -> void:
	var result: Dictionary = TownRules.accept_command(state, selected_town, pending_town_command, choice)
	pending_town_command.clear()
	var slot := int(result.get("solo", 8))
	current_deploy_pids = [slot]
	var level: Dictionary = state.m4_level(state.campaign_index)
	# 本关仅部署所选角色，敌40..47指定目标改为该slot。
	state.next_battle_overrides = {"solo": slot}
	_play_media(state.campaign_index, func(): _launch_level(state.campaign_index, false, [slot]))


func _show_deployment(idx: int) -> void:
	var dep:Dictionary=state.m4_level(idx).get("deployment",{})
	var limit:=int(dep.get("max_units",0))
	if not bool(state.m4_level(idx).get("party_deploy",limit not in [0,999])) or limit==999 or limit==0:
		current_deploy_pids=[]
		_play_media(idx,func():_launch_level(idx,false,[]))
		return
	mode="deployment";strategic_palette_key="K00";native_scene_palette_key="K00"
	_new_ui()
	deployment_screen=preload("res://scripts/ui/OriginalDeployment.gd").new();ui_root.add_child(deployment_screen)
	deployment_screen.setup(font,state,idx)
	deploy_page_level=idx
	deployment_screen.selection_changed.connect(_sync_deployment)
	deployment_screen.confirmed.connect(func(slots:Array):
		current_deploy_pids=slots.duplicate()
		_play_media(idx,func():_launch_level(idx,false,current_deploy_pids)))
	_sync_deployment()


func _sync_deployment() -> void:
	if not is_instance_valid(deployment_screen):return
	deploy_pages=deployment_screen.pages.duplicate()
	deploy_selected=deployment_screen.selected_slots().filter(func(pid):return int(pid)!=-999)


func _deploy_page(side: int, _idx: int) -> void:
	if is_instance_valid(deployment_screen):deployment_screen.set_page(side)


func _deploy_go(_idx: int) -> void:
	if is_instance_valid(deployment_screen):deployment_screen.submit()


# Diagnostic helper only; the normal UI uses native drag/drop or doubleclick.
func _toggle_deploy(pid: int, _idx: int) -> void:
	if not is_instance_valid(deployment_screen):return
	for side in [1,0]:
		for slot in range(32):
			var m:Dictionary=deployment_screen.member(side,slot)
			if not m.is_empty() and int(m.pid)==pid:
				deployment_screen.transfer(side,slot);return


func _silence_media_until(cb:Callable) -> Callable:
	var music=get_node_or_null("/root/Music")
	if music==null:return cb
	var token:int=music.suspend_playback()
	# Bound methods compare as the same signal target even when their bound
	# tokens differ. Entry MPEG owns both an entry and a chapter suspension;
	# each must have its own closure so leaving the tree releases both.
	var release:Callable=func():music.resume_playback(token)
	tree_exiting.connect(release,CONNECT_ONE_SHOT)
	return func():
		if tree_exiting.is_connected(release):tree_exiting.disconnect(release)
		release.call()
		if cb.is_valid():cb.call()


func _play_media(idx: int, cb: Callable) -> void:
	# 41B8E9 stops the old track before both MPEG and alternative TXT entry.
	_play_chapter(idx,"entry",_silence_media_until(cb))

func _play_chapter(idx: int, branch: String, cb: Callable) -> void:
	var entry: Dictionary = m5.get("chapter_transitions",{}).get(str(idx),{}).get(branch,{})
	if not bool(entry.get("enabled",false)):
		cb.call()
		return
	if state.story_variant:
		var record := int(entry.get("text_id",-1))
		if record < 0 or bool(entry.get("text_empty",true)): cb.call()
		else: _play_story([record],cb)
	else:
		var path:=str(entry.get("mpeg_path",""))
		# 4294BE closes the CD device only for a file that actually plays.
		# This is deliberately NOT a generic FLC/VideoStreamPlayer rule.
		_play_cutscene(path,_silence_media_until(cb) if path!="" and ResourceLoader.exists(path) else cb)


func _play_story_then(idx: int, cb: Callable) -> void:
	var ids := _story_ids(idx, "intro")
	if ids.is_empty():
		cb.call()
		return
	_play_story(ids, cb)


func _media_for(idx: int, entry := true) -> String:
	# 4294BE(param0)进入战斗播dNN a；param1胜后播dNN。不是设置变体。
	var media: Dictionary = m5.get("media", {})
	if (media.get("clips", []) as Array).is_empty():
		var f := FileAccess.open("res://data/m5_media.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				media = parsed
	var wanted := "d%02d%s" % [idx + 1, "a" if entry else ""]
	for clip in media.get("clips", []):
		if str(clip.get("id", "")) == wanted:
			var path := str(clip.get("ogv_path", clip.get("ogv", "")))
			if ResourceLoader.exists(path):
				return path
	return ""


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


# One factory for launch and resume; tests may wrap permissions without
# duplicating the real campaign loading, checkpoint or settlement path.
func _create_battle() -> Node2D:
	return preload("res://scripts/Battle.gd").new()


func _launch_level(idx: int, standalone: bool, deploy_pids: Array = []) -> void:
	_story_generation += 1
	battle_visual_active=false
	battle_visual_sequences=0
	if is_instance_valid(story_player):
		story_player.queue_free()
	story_player = null
	if is_instance_valid(story_layer):
		story_layer.queue_free()
	story_layer = null
	if is_instance_valid(result_canvas):
		result_canvas.queue_free()
	result_canvas = null
	var selected: Array = deploy_pids
	if not bool(state.m4_level(idx).get("party_deploy",true)):
		selected=[]
	elif selected.is_empty() and not standalone:
		selected = current_deploy_pids
	current_deploy_pids = selected.duplicate()
	if not standalone: state.save_checkpoint(not qa_mode)
	state.apply_phase_state(state.m4_level(idx).get("start_phase", {}))
	var roster: Array = []
	for slot in range(40):
		roster.append(state.person(slot))
	var level: Dictionary = LevelBuilder.build(m4, m2, idx, roster, false, -1, selected)
	if level.is_empty():
		_toast("关卡数据缺失")
		return
	state.apply_difficulty(level)
	if state.next_battle_overrides.has("solo"):
		var solo := int(state.next_battle_overrides["solo"])
		var existing: Array = []
		for rec in level.get("units", []):
			if str(rec.get("side", "")) != "player" or int(rec.get("slot", -1)) == solo:
				if int(rec.get("slot", -1)) >= 40 and int(rec.get("slot", -1)) < 48:
					rec["target_slot"] = solo
				existing.append(rec)
		if not existing.any(func(rec): return int(rec.get("slot", -1)) == solo):
			var point: Array = level.get("deploy", [[0,0]])[0]
			existing.append(LevelBuilder.member_unit(m2,state.person(solo),{"x":point[0],"y":point[1]}))
		level["units"] = existing
	for slot in state.next_battle_overrides.get("hp", {}):
		for rec in level.get("units", []):
			if int(rec.get("slot", -1)) == int(slot):
				rec["hp"] = int(state.next_battle_overrides["hp"][slot])
	for slot in state.next_battle_overrides.get("behavior", {}):
		for rec in level.get("units", []):
			if int(rec.get("slot", -1)) == int(slot):
				rec["behavior"] = int(state.next_battle_overrides["behavior"][slot])
	state.next_battle_overrides.clear()
	_close_panel()
	current_battle_index = idx
	current_battle_standalone = standalone
	if is_instance_valid(ui_root):
		ui_root.visible = false
	if is_instance_valid(battle):
		battle.queue_free()
	battle = _create_battle()
	add_child(battle)
	battle.finished.connect(_on_battle_finished)
	battle.toolbar_requested.connect(_battle_toolbar)
	battle.looted.connect(_on_loot)
	battle.story_event.connect(_on_battle_story_event)
	battle_story_queue.clear()
	battle_story_seen.clear()
	pending_battle_result.clear()
	var ctx: Dictionary = state.battle_context()
	ctx["campaign_story"] = not standalone
	battle.setup(m4, level, font, ctx)
	battle.sfx_enabled=OriginalUI.sfx_enabled
	native_scene_palette_key="KUANG04"
	battle_baseline = battle.initial_state.duplicate(true)
	_music(int(level.get("bgm_scene",34)))
	battle_start_stats = {"enemies": battle.enemy_units.size(),
			"players": battle.player_units.size()}
	if battle.scenario.start_phase_pending:
		battle.busy = true


func _battle_toolbar(action: String) -> void:
	if battle == null or battle.busy: return
	match action:
		"movie_toggle":
			state.story_variant = not state.story_variant
			var cfg := ConfigFile.new();cfg.load("user://dlz_config.cfg")
			cfg.set_value("video","story_variant",state.story_variant);cfg.save("user://dlz_config.cfg")
			_toast("过场使用文字" if state.story_variant else "过场使用影片")
		"save":
			if not battle.can_save(): battle._log("请先取消当前指令，再保存。索敌/选择目标时不能保存。 "); return
			pending_save_snapshot = battle.snapshot()
			_open_save_impl(false)
		"load": _open_save_impl(true)
		"restart", "exit":
			_close_panel()
			modal_layer=CanvasLayer.new();modal_layer.layer=125;add_child(modal_layer)
			modal_previous_busy=battle.busy;battle.busy=true
			panel_root=preload("res://scripts/ui/OriginalConfirm.gd").new();modal_layer.add_child(panel_root)
			panel_root.setup(font,"重来吗？" if action=="restart" else "退出吗？",Vector2(300,200))
			panel_root.answered.connect(func(yes:bool):
				_close_panel()
				if not yes:return
				if action=="restart":_restart_current_battle()
				else:exit_requested.emit())


func _open_save_impl(load_first:bool) -> void:
	_close_panel()
	modal_layer=CanvasLayer.new();modal_layer.layer=125;add_child(modal_layer)
	if is_instance_valid(battle):modal_previous_busy=battle.busy;battle.busy=true
	panel_root=preload("res://scripts/ui/OriginalSavePicker.gd").new();modal_layer.add_child(panel_root)
	var key:=strategic_palette_key
	if is_instance_valid(battle):key="KUANG04"
	panel_root.setup(font,preload("res://scripts/ui/OriginalPalette.gd").colors(key),preload("res://scripts/ui/OriginalSaveSlots.gd").previews(state),load_first)
	panel_root.chosen.connect(func(slot:int):
		_close_panel()
		if slot<0:return
		if load_first:_load_slot(slot)
		else:_save_slot(slot))


func _save_slot(slot: int) -> void:
	if is_instance_valid(battle):
		if pending_save_snapshot.is_empty(): return
		state.battle_resume = {"snapshot":pending_save_snapshot,"baseline":battle_baseline,
			"checkpoint":state.checkpoint_data,"deploy":current_deploy_pids,
			"standalone":current_battle_standalone}
	else: state.battle_resume.clear()
	var ok: bool = state.save_slot(slot)
	if ok and not is_instance_valid(battle) and slot>=0 and slot<5:
		preload("res://scripts/ui/OriginalSaveSlots.gd").save_strategy_native(state,slot)
	# Native picker is a one-shot operation and restores the caller, not a
	# self-reopening save manager. Direct diagnostic calls retain visibility.
	_close_panel()
	if slot>=5:_open_save_impl(false)
	if not ok:_toast("存档失败")


func _load_slot(slot: int) -> void:
	if not load_campaign_slot(slot): _toast("读档失败：存档为空或版本不兼容")


func _load_auto_save() -> void:
	_load_slot(7)


func _resume_battle(encoded: Dictionary, restart := false) -> void:
	var snap: Dictionary = preload("res://scripts/battle/StateCodec.gd").unpack(encoded)
	var lv: Dictionary = snap.get("level",{})
	if lv.is_empty(): return
	_story_generation += 1
	battle_visual_active=false
	battle_visual_sequences=0
	battle_story_queue.clear(); battle_story_seen.clear(); pending_battle_result.clear()
	if is_instance_valid(story_player): story_player.queue_free(); story_player = null
	if is_instance_valid(story_layer): story_layer.queue_free(); story_layer = null
	if is_instance_valid(cutscene): cutscene.queue_free(); cutscene = null
	if is_instance_valid(result_canvas): result_canvas.queue_free(); result_canvas = null
	if is_instance_valid(battle): battle.queue_free()
	current_battle_index = int(lv.get("index",0))
	if is_instance_valid(ui_root): ui_root.visible = false
	battle = _create_battle()
	add_child(battle)
	battle.finished.connect(_on_battle_finished)
	battle.toolbar_requested.connect(_battle_toolbar)
	battle.looted.connect(_on_loot)
	battle.story_event.connect(_on_battle_story_event)
	battle.setup(m4,lv,font,snap.get("context",{}),encoded)
	battle_start_stats = {"enemies":battle.stats.get("enemies_total",0),"players":battle.stats.get("deployed",0)}
	_music(int(lv.get("bgm_scene",34)))
	if restart:
		battle.scenario.on_start()
		battle._begin_player_phase("第 1 回合，我方行动")
		if battle.scenario.start_phase_pending: battle.busy = true
		else: battle._focus_player()


func _restart_current_battle() -> void:
	if battle_baseline.is_empty(): return
	var now := {}
	for record in battle.level.get("slot_pool",[]) + battle.units.map(func(unit): return unit.state_record()):
		now[int(record.get("slot",-1))] = record
	state.apply_battle_progress(battle.units)
	if not current_battle_standalone: state.load_checkpoint()
	var snap: Dictionary = preload("res://scripts/battle/StateCodec.gd").unpack(battle_baseline)
	for pool in ["units","slot_pool","spawn_pool"]:
		for record in snap.level.get(pool,[]):
			var slot := int(record.get("slot",-1))
			var recent: Dictionary = now.get(slot,{})
			if state.difficulty == 0:
				if int(record.get("faction",1)) == 0:
					for key in ["level","xp"]: record[key] = recent.get(key,record.get(key,0))
				record["attack_count"] = recent.get("attack_count",record.get("attack_count",0))
			if state.difficulty < 2:
				for key in record.get("skill_counts",{}):
					if int(record.skill_counts[key]) > 0:
						record.skill_counts[key] = recent.get("skill_counts",{}).get(key,record.skill_counts[key])
				record["skills"] = record.get("skill_counts",{}).duplicate()
	for chest in snap.level.get("chests",[]):
		var roll := randi_range(0,99)
		chest["wupin"] = chest.get("wupin0" if roll < 50 else ("wupin1" if roll < 80 else "wupin2"),chest.get("wupin",0))
		chest["opened"] = false
	snap["context"] = state.battle_context()
	snap.context["campaign_story"] = not current_battle_standalone
	snap.scenario["trigger_flags"] = state.script_globals.duplicate(true)
	for addr in range(0x583f18,0x583f58,4): snap.scenario.trigger_flags["0x%x"%addr] = 0
	_resume_battle(preload("res://scripts/battle/StateCodec.gd").pack(snap),true)


func _on_battle_story_event(kind: String, data: Dictionary) -> void:
	if current_battle_standalone or current_battle_index < 0:
		return
	if kind == "person_side":
		if int(data["slot"]) < 40:
			state.set_person_side(int(data["slot"]), int(data["faction"]))
	elif kind == "person_field":
		if int(data["slot"]) < 40:
			state.person(int(data["slot"]))[str(data["field"])] = int(data["value"])
	elif kind == "money":
		state.money += int(data["amount"])
	elif kind == "global":
		state.script_globals[str(data["addr"])] = int(data["value"])
	elif kind == "phase_steps":
		battle_story_queue.append_array(data.get("steps", []))
		battle_story_queue.append({"phase_end": true})
	elif kind == "visual_steps":
		battle_visual_sequences+=1
		battle.busy=true
		battle_story_queue.append_array(data.get("steps",[]))
		battle_story_queue.append({"visual_end":true})
	elif kind == "trigger_message":
		var rec := int(data.get("record", -1))
		if rec >= 0:
			battle_story_queue.append([rec])
	# 不再播放按剧情猜测的turn/unit_died/chest事件，四阶段原脚本为唯一来源。


func _norm(text: String) -> String:
	return str(text).replace("\u3000", "").replace(" ", "")


func _on_loot(item_id: int) -> void:
	if item_id >= 0 and not state.item(item_id).is_empty():
		state.add_item(item_id, 1)
		# The battle's permanent store is native u16, including overflow on
		# a full-bag chest. Mirror it instead of retaining an impossible 65536.
		var key:=str(item_id)
		state.items[key]=int(state.items.get(key,0))&0xffff
		if int(state.items[key])==0:state.items.erase(key)


func _on_battle_finished(result: String, message: String) -> void:
	# T510 胜败分支会先发 TXT，再发 finished。不能清空队列或拒绝
	# finished_flag，否则主角讣告/L00胜利对白等必定丢失。
	pending_battle_result = {"result": result, "message": message}


func _settle_battle(result: String, message: String) -> void:
	var victory := result == "victory"
	var stats: Dictionary = {}
	if is_instance_valid(battle):
		stats = (battle.stats as Dictionary).duplicate(true)
		stats["turn"] = battle.turn
		state.battle_turn = battle.turn
		stats["enemies_total"] = max(int(battle_start_stats.get("enemies", 0)),
				int(stats.get("enemies_total", 0)))
		var units: Array = []
		for u in battle.player_units:
			if state.deploy_member(int(u.data.get("pid", -1))) != null:
				units.append({"pid": int(u.data.get("pid", -1)), "hp": int(u.hp)})
		state.apply_battle_health(units)
		state.apply_battle_context(battle.battle_context)
		state.apply_battle_progress(battle.units)
	var idx := current_battle_index
	var score := _score_for(stats, victory, idx)
	# HP/XP/source-slot changes above already occurred in the battle's People
	# model. Bridging them is not permission to advance the campaign early.
	# 41DEAA waits for the victory notice, then42B49A adds score; index,
	# accumulated kills, warehouse loot and the phase hook all wait for MENU10.
	var info: Dictionary = {"total":state.score_total}
	_show_report(victory, message, idx, score, info, current_battle_standalone)
	_last_report["settlement_pending"]=true
	_last_report["stats"]=stats.duplicate(true)


func _score_for(stats: Dictionary, victory: bool, idx: int) -> int:
	if not victory:
		return 0
	var gun := int(stats.get("kills_by_gun", 0))
	var mine := int(stats.get("kills_by_mine", 0))
	var raw := maxi(0, gun * 10 + mine * 10 + 50 - int(stats.get("losses", 0)) * 40 - int(stats.get("turn", 1)))
	var denominator := maxi(1, int(state.m4_level(idx).get("difficulty", 1)))
	return raw * 100 / denominator + state.difficulty * 2


func _show_report(victory: bool, message: String, idx: int, score: int,
		info: Dictionary, standalone: bool) -> void:
	_last_report = {"victory": victory, "idx": idx, "score": score,
			"info": info, "standalone": standalone}
	if is_instance_valid(result_canvas):
		result_canvas.process_mode=Node.PROCESS_MODE_DISABLED
		for child in result_canvas.get_children():
			if child is CanvasItem:child.hide()
		result_canvas.queue_free()
	result_canvas = CanvasLayer.new()
	result_canvas.layer = 100
	add_child(result_canvas)
	if not victory:
		# The story queue (including TXT4) has already drained before settlement.
		# Keep battle music; scene43 and the blue report are victory-only.
		var dialog := preload("res://scripts/ui/DefeatDialog.gd").new()
		result_canvas.add_child(dialog)
		dialog.setup(font)
		dialog.retry_requested.connect(_retry_battle)
		dialog.title_requested.connect(_defeat_to_title)
		if is_instance_valid(battle) and not qa_mode: battle._play_sfx(14)
		return
	# 41DEAA: fixed43D454 notice keeps battle music, then42B49A.
	var notice:=preload("res://scripts/ui/OriginalStoryPage.gd").new()
	result_canvas.add_child(notice)
	var pages:=preload("res://scripts/ui/OriginalStoryLayout.gd").pages("战斗胜利！","",46)
	notice.setup(font,pages[0],-1,"KUANG04",46)
	notice.confirmed.connect(func():
		notice.hide();notice.set_process_input(false);notice.queue_free()
		_show_victory_page(score,info,standalone))

func _show_victory_page(score:int,info:Dictionary,standalone:bool) -> void:
	_commit_victory_score()
	if bool(_last_report.get("settlement_pending",false)):info=_last_report.info
	_music(43)
	var bs:Dictionary=battle.stats.duplicate(true) if is_instance_valid(battle) else {}
	var captured:=0
	if is_instance_valid(battle):
		for quantity in battle.battle_context.get("temporary_loot",{}).values():captured+=int(quantity)&0xffff
	bs["captured_items"]=captured
	var page:=preload("res://scripts/ui/OriginalVictoryReport.gd").new()
	result_canvas.add_child(page)
	page.setup(font,bs,score,int(info.get("total",state.score_total)) if not standalone else score)
	page.closed.connect(func():
		var player=get_node_or_null("/root/Music")
		if player!=null:player.release_playback()
		_report_continue())


func _defeat_to_title() -> void:
	var player = get_node_or_null("/root/Music")
	if player != null: player.release_playback()
	exit_requested.emit()


func _retry_battle() -> void:
	if not battle_baseline.is_empty() and is_instance_valid(battle):
		_restart_current_battle()
		return
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


func _commit_victory_score() -> void:
	if not bool(_last_report.get("settlement_pending",false)) or not bool(_last_report.get("victory",false)) or bool(_last_report.get("score_committed",false)):return
	_last_report["score_committed"]=true
	if not bool(_last_report.get("standalone",true)):
		state.record_level_score(int(_last_report.idx),int(_last_report.score))
	_last_report.info={"total":state.score_total}


func _commit_victory_loot() -> void:
	# 41DF69 ->42B2C8, after the report wait:156 WORD additions, then clear.
	# Losing/retrying never commits temporary loot. Keep it intact for MENU10.
	if not bool(_last_report.get("victory",false)) or bool(_last_report.get("loot_committed",false)) or not is_instance_valid(battle):return
	var loot:Dictionary=battle.battle_context.get("temporary_loot",{})
	for iid in range(156):
		var amount:=int(loot.get(str(iid),0))&0xffff
		if amount!=0:state.add_item(iid,amount)
		loot.erase(str(iid))
	battle.battle_context["temporary_loot"]=loot
	_last_report["loot_committed"]=true


func _commit_victory_result() -> void:
	if not bool(_last_report.get("victory",false)) or bool(_last_report.get("result_committed",false)):return
	_last_report["result_committed"]=true
	var standalone:=bool(_last_report.get("standalone",true))
	var idx:=int(_last_report.get("idx",current_battle_index))
	if bool(_last_report.get("settlement_pending",false)) and not standalone:
		# No input/yield is allowed inside this completed-result transaction.
		_commit_victory_score()
		_last_report.info=state.complete_level(idx,int(_last_report.score),true,true)
		state.record_battle_stats(_last_report.get("stats",{}))
	_commit_victory_loot()
	if bool(_last_report.get("settlement_pending",false)) and not standalone:
		state.apply_phase_state(state.m4_level(idx).get("victory_phase",{}))
		selected_town=state.current_town
		# Remake autosave includes progression AND loot, never a report preview.
		if not qa_mode:state.save_slot(7)


func _report_continue() -> void:
	if bool(_last_report.get("continued",false)):return
	_last_report["continued"]=true
	var r := _last_report
	_commit_victory_result()
	if not bool(r.get("victory",false)) and not bool(r.get("standalone",true)) and not battle_baseline.is_empty() and is_instance_valid(battle):
		_restart_current_battle()
		return
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
	# 40EB9D: L35 freezes/writes the score and plays the whole END group
	# before4294BE(1). Other victories retain their ordinary chapter order.
	if idx==35:_after_victory(idx)
	else:_play_chapter(idx,"victory",func(): _after_victory(idx))


func _after_victory(idx: int) -> void:
	_music(state.town_bgm_scene)
	var phase: Dictionary = state.m4_level(idx).get("victory_phase", {})
	if idx == 35:
		preload("res://scripts/ui/OriginalHighScores.gd").record_result(state.player_name,state.main_score_snapshot,highscore_path)
		_show_ending()
	elif idx >= 44:
		_show_town(state.current_town)
	elif idx >= 36:
		var threshold := int(phase.get("hidden_threshold", {}).get("main_score_snapshot_gte", 99999))
		if state.main_score_snapshot < threshold or idx in [39, 43]:
			_show_finale()
		elif bool(phase.get("direct_next_battle", false)):
			_launch_level(idx + 1, false)
		else:
			_show_town(state.current_town)
	elif bool(phase.get("direct_next_battle", false)) or idx in [32,33]:
		_show_deployment(idx + 1)
	else:
		_show_town(state.current_town)


func _story_ids(idx: int, kind: String) -> Array:
	var scenes: Dictionary = m5.get("scenes", {})
	var s: Dictionary = scenes.get(str(idx), {})
	return (s.get(kind, []) as Array).duplicate()


func _story_context() -> Dictionary:
	var people := {}
	for slot in range(40): people[str(slot)] = state.person(slot)
	var idx: int = current_battle_index if is_instance_valid(battle) else state.campaign_index
	var level: Dictionary = state.m4_level(idx)
	for person in level.get("slot_pool",[]): people[str(person.get("slot",-1))] = person
	# 全局持久人物优先于模板，活跃战场人物再优先。
	for slot in range(40): people[str(slot)] = state.person(slot)
	if is_instance_valid(battle):
		for unit in battle.units: people[str(unit.slot)] = unit.data
	people["0"] = state.protagonist_member()
	var context:Dictionary={"people_by_slot":people,"level_name":level.get("name",""),"effective_level_index":idx}
	context["battle_profile"]=is_instance_valid(battle)
	if not is_instance_valid(battle):context["native_palette_key"]=strategic_palette_key
	return context


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
	var caller_screen:WeakRef=weakref(strategic_screen) if is_instance_valid(strategic_screen) else null
	if caller_screen!=null:caller_screen.get_ref().enabled=false
	var generation := _story_generation
	story_player.context = _story_context()
	story_player.setup(font, m5, ids, state.player_name, func():
		if generation != _story_generation:
			return
		story_player = null
		if caller_screen!=null and caller_screen.get_ref()!=null:caller_screen.get_ref().enabled=true
		if is_instance_valid(story_layer):
			story_layer.queue_free()
		story_layer = null
		cb.call(), _story_context())


func _play_cutscene(path: String, cb: Callable, parent:Node=null) -> void:
	if path == "" or not ResourceLoader.exists(path):
		if cb.is_valid():
			cb.call()
		return
	if is_instance_valid(cutscene):
		cutscene.queue_free()
	cutscene = load("res://scripts/m5/CutscenePlayer.gd").new()
	(parent if parent!=null else self).add_child(cutscene)
	cutscene.setup(path, font, func():
		cutscene = null
		if cb.is_valid():
			cb.call())


func _show_ending(forced := -1) -> void:
	_ending_fade_out(4)
	mode="ending"
	ending_preview=forced>=0
	ending_flow_events.append("END")
	_music(49)
	if is_instance_valid(ui_root): ui_root.visible = false
	_close_panel()
	_clear_ending_layer()
	ending_layer = CanvasLayer.new()
	ending_layer.layer = 90
	add_child(ending_layer)
	ending_steps = [{"image":0,"records":[401]}]
	if int(state.person(31).get("faction",1)) == 0:
		ending_steps.append({"image":2,"records":[402]})
	else: ending_steps.append({"image":1,"records":[403]})
	if TownRules.get_flag(state,2) == 0:
		ending_steps.append({"image":3,"records":[404]})
		ending_steps.append({"image":5,"records":[407]})
	else: ending_steps.append({"image":4,"records":[405,406]})
	# Explicit gallery previews are not score endings and never unlock progression.
	if forced >= 0:
		ending_steps = [{"image":forced,"records":m5.get("endings",[])[clampi(forced,0,5)].get("records",[])}]
	ending_step = 0
	_play_ending_step()


func _play_ending_step() -> void:
	if ending_step >= ending_steps.size():
		if ending_preview:_show_finale()
		else:_play_ending_chapter()
		return
	var step: Dictionary = ending_steps[ending_step]
	var id := int(step["image"])
	if not state.endings_seen.has(id): state.endings_seen.append(id)
	# Retain the picture after StoryPlayer removes its text, for the separate
	# outer W/D. Do not let an old page or release leak into the next one.
	for child in ending_layer.get_children():
		child.process_mode=Node.PROCESS_MODE_DISABLED
		if child is CanvasItem:child.hide()
		child.queue_free()
	var page=preload("res://scripts/ui/OriginalEndingPage.gd").new()
	ending_layer.add_child(page)
	var context := _story_context()
	# END pixel-only loads retain the live battle KUANG04 palette, not K00.
	context["native_palette_key"]="KUANG04"
	page.confirmed.connect(func():
		ending_step += 1
		_play_ending_step())
	page.setup(font,m5,id,step["records"],state.player_name,context)


func _clear_ending_layer() -> void:
	if not is_instance_valid(ending_layer):return
	ending_layer.process_mode=Node.PROCESS_MODE_DISABLED
	for child in ending_layer.get_children():
		if child is CanvasItem:child.hide()
	ending_layer.queue_free();ending_layer=null


func _ending_fade_out(increment:int) -> void:
	# A transient topmost surface can fade the old report, END or JZ even
	# when it lives on another CanvasLayer. No input is dispatched mid-fade.
	var layer:=CanvasLayer.new();layer.layer=130;add_child(layer)
	var surface:=Control.new();layer.add_child(surface)
	preload("res://scripts/ui/OriginalPaletteFade.gd").play(surface,false,increment)
	layer.free()


func _play_ending_chapter() -> void:
	ending_flow_events.append("chapter35")
	_ending_fade_out(4)
	_clear_ending_layer()
	# L35's4294BE text path clears both surfaces toFF, still usingKUANG04.
	# Keep this surface on the ending layer so it cannot be occluded by END.
	ending_layer=CanvasLayer.new();ending_layer.layer=90;add_child(ending_layer)
	var background:=ColorRect.new();background.color=Color.BLACK;background.size=Vector2(640,480)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE;ending_layer.add_child(background)
	var after_chapter:Callable=func():
		if state.hidden_unlocked:_show_hidden_choice()
		else:_show_finale()
	var entry:Dictionary=m5.get("chapter_transitions",{}).get("35",{}).get("victory",{})
	if not bool(entry.get("enabled",false)):after_chapter.call();return
	if not state.story_variant:
		# MPEG owns its normal CD suspension. Its device Restore residue is
		# normalised to the proved text-path black surface after it finishes.
		var path:=str(entry.get("mpeg_path",""))
		_play_cutscene(path,_silence_media_until(after_chapter) if path!="" and ResourceLoader.exists(path) else after_chapter,ending_layer)
		return
	var record:=int(entry.get("text_id",-1))
	if record<0 or bool(entry.get("text_empty",true)):after_chapter.call();return
	preload("res://scripts/ui/OriginalPaletteFade.gd").play(background,true,4)
	var player=preload("res://scripts/m5/StoryPlayer.gd").new();ending_layer.add_child(player)
	var context:=_story_context();context["native_palette_key"]="KUANG04";context["battle_profile"]=false
	player.setup(font,m5,[record],state.player_name,func():
		_ending_fade_out(4);after_chapter.call(),context)


func _show_hidden_choice() -> void:
	mode="hidden_notice"
	ending_flow_events.append("hidden_notice")
	_clear_ending_layer()
	ending_layer = CanvasLayer.new()
	ending_layer.layer = 90
	add_child(ending_layer)
	# 40EC1F ->43D454(446AB0), then native426A05 two-row choice.
	# 429517..552 cleared both original surfaces toFF before this phase.
	# Normalise video-device Restore residue to the proved text-path black.
	var background:=ColorRect.new();background.color=Color.BLACK;background.size=Vector2(640,480)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE;ending_layer.add_child(background)
	preload("res://scripts/ui/OriginalPaletteFade.gd").play(background,true,4)
	var notice=load("res://scripts/m5/StoryPlayer.gd").new();ending_layer.add_child(notice)
	var context:=_story_context();context["native_palette_key"]="KUANG04";context["battle_profile"]=false
	notice.setup(font,{"records":[{"n":-1,"lines":[{"code":-1,"text":"由于GG的优良表现，可以进入隐藏关，请选择隐藏关的模式。"}]}]},[-1],state.player_name,_show_hidden_menu,context)


func _show_hidden_menu() -> void:
	mode="hidden_choice"
	_clear_ending_layer()
	ending_layer=CanvasLayer.new();ending_layer.layer=90;add_child(ending_layer)
	var background:=ColorRect.new();background.color=Color.BLACK;background.size=Vector2(640,480)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE;ending_layer.add_child(background)
	var menu:=preload("res://scripts/ui/OriginalChoice.gd").new();ending_layer.add_child(menu)
	menu.setup(font,["模  拟","虚  构"],Vector2(320,200),true,preload("res://scripts/ui/OriginalPalette.gd").colors("KUANG04"))
	menu.chosen.connect(func(choice:int):_start_hidden("simulation" if choice==0 else "fiction"))
	menu.cancelled.connect(_show_finale)


func _show_finale() -> void:
	_ending_fade_out(4)
	mode="finale"
	ending_flow_events.append("finale")
	_clear_ending_layer()
	ending_layer = CanvasLayer.new()
	ending_layer.layer = 90
	add_child(ending_layer)
	_show_final_image(0)


func _show_final_image(index: int) -> void:
	if index >= 2:
		game_close_requested.emit()
		return
	for child in ending_layer.get_children():
		child.process_mode=Node.PROCESS_MODE_DISABLED
		if child is CanvasItem:child.hide()
		child.queue_free()
	var image:=preload("res://scripts/ui/OriginalFinalImage.gd").new()
	ending_layer.add_child(image)
	image.setup(load("res://assets/ui/jz%d.png"%(index+1)),index==1)
	image.confirmed.connect(func():_show_final_image(index+1))


func _show_credits() -> void:
	_music(38)
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
		var eid := int(e.get("id", i))
		var unlocked: bool = state.endings_seen.has(eid)
		var b := _button("%s  %d" % [e.get("title", "结局") if unlocked else "未解锁",
				int(e.get("score", 0))], Vector2(310, 74 + i * 56), Vector2(260, 40),
				_show_ending.bind(eid), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked
		root.add_child(b)
	var back := _button("返 回", Vector2(520, 438), Vector2(90, 26),
			func(): _show_ending(), 14)
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
	state.campaign_index = idx
	if mode == "fiction" and idx == 40:
		TownRules.set_flag(state,85,2)
		if not state.liberated.has(17): state.liberated.append(17)
		_show_town(17)
	else: _launch_level(idx, false)


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
