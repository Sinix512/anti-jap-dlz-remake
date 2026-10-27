extends SceneTree
# Synthetic result/UI fixtures, not legal campaign completion evidence.
const Dialog = preload("res://scripts/ui/DefeatDialog.gd")
var checks := 0
var failures := 0
var camp
var exits := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("DEFEAT_FAIL " + label)
func click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point
		event.button_index = button; event.pressed = pressed
		root.push_input(event,true)
	await process_frame
func dialog(): return camp.result_canvas.get_child(0)
func has_blue(node: Node) -> bool:
	if node.get_script()==preload("res://scripts/ui/OriginalVictoryReport.gd"):return true
	if node is TextureRect and node.texture != null and node.texture.resource_path.ends_with("report_blue.png"): return true
	for child in node.get_children():
		if has_blue(child): return true
	return false
func run() -> void:
	camp = preload("res://tests/helpers/LegalProbeCampaign.gd").new()
	root.add_child(camp); camp.setup(load("res://assets/font/hzk16.fnt")); camp.qa_mode = true
	camp.state.data = camp.state.data.duplicate(true)
	camp.state.data.meta.save_prefix = "dlz_qa_defeat_"
	camp.state.difficulty = 1
	camp.exit_requested.connect(func(): exits += 1)
	camp._launch_level(5,false,[-100]); await camp.drain_story()
	var b = camp.battle
	b.set_process(false); b.sfx_enabled = false
	var baseline: Dictionary = preload("res://scripts/battle/StateCodec.gd").unpack(camp.battle_baseline)
	var before: int = camp.acknowledged_texts
	b.remove_slot(0); await b.scenario.on_tick()
	check(b.last_result == "defeat" and b.last_result_trigger.id == "hero_lost","real L05 hero-lost predicate stays defeat")
	check(b.last_message == "战斗失败！" and b.last_result_condition == b.level.failure,"condition kept separately from generic notice")
	check(camp.battle_story_queue == [[4]],"TXT4 queued once before negative settlement")
	check(not is_instance_valid(camp.result_canvas),"story not bypassed by result UI")
	await camp.drain_story()
	check(camp.acknowledged_texts == before+1 and camp.battle_story_queue.is_empty(),"TXT4 acknowledged exactly once")
	var d = dialog(); d.set_process(false); d.notice.set_process(false)
	check(d.get_script() == Dialog and not has_blue(camp.result_canvas),"negative result uses notice, never blue report")
	check(root.get_node("Music").current_scene != 43,"no victory report music on defeat")
	check(d.stage == "notice" and d.notice.visible and not d.prompt.visible,"notice precedes retry prompt")
	check(d.notice.raster.glyphs[4].text == "战" and d.notice.raster.glyphs[4].x==32 and d.notice.clip.position==Vector2(142,312),"native narration prefix and text origin")
	check(d.notice.get_child(0).position == Vector2(118,296) and d.notice.get_child(0).size == Vector2(404,127),"native notification geometry")
	d._advance(0.03)
	check(d.notice.shown_height>0 and d.notice.shown_height<99,"vertical partial reveal, not character typing")
	await click(Vector2(200,330))
	check(d.stage=="notice" and d.notice.height==99 and d.notice.stage=="scroll","left release requests99, does not draw or acknowledge")
	d._advance(0.006);await process_frame;await process_frame
	d._advance(10);check(d.notice.stage=="wait" and not d.prompt.visible,"completed roll waits for a new release, never auto-closes")
	await click(Vector2(200,330),MOUSE_BUTTON_RIGHT)
	d._advance(0.199);check(d.stage=="notice","acknowledgement retains200ms tail")
	d._advance(0.002);check(d.stage=="retry" and not d.notice.visible and d.prompt.visible,"tail after acknowledgement opens retry")
	check(d.choice == 0 and d.selected_row.position == Vector2(304,232),"default original yes highlight")
	check(d.prompt.get_child(0).position == Vector2(300,200) and d.prompt.get_child(0).size == Vector2(128,88),"MENU03 native geometry")
	check(d.options[0].position == Vector2(356,236) and d.options[1].position == Vector2(356,260),"original yes/no coordinates")
	check(d.options[0].get_theme_color("font_color") == Color("#fc8c00") and d.options[1].get_theme_color("font_color") == Color("#a4fcfc"),"KUANG04 selected/normal text colors")
	var release:=InputEventMouseButton.new();release.position=Vector2(20,240);release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;root.push_input(release,true)
	check(d.stage == "retry" and exits == 0 and camp.battle == b,"left-UP never confirms42738A")
	var motion := InputEventMouseMotion.new(); motion.position = Vector2(20,266); motion.global_position = motion.position
	root.push_input(motion,true); await process_frame
	check(d.choice == 1 and d.selected_row.position == Vector2(304,256),"full-screen-x hover selects no and its original row")
	await click(Vector2(360,240)); await camp.drain_story()
	b = camp.battle; b.set_process(false); b.sfx_enabled = false
	check(not is_instance_valid(camp.result_canvas) and b.turn == 1 and camp.current_battle_index == 5,"real yes click retries same level, not world")
	var base_hero: Dictionary = {}
	for record in baseline.level.units:
		if int(record.slot) == 0: base_hero = record
	check(b.unit_by_slot(0).alive and b.unit_by_slot(0).hp == int(base_hero.hp) and b.unit_by_slot(0).data.level == base_hero.level,"retry restores original normal baseline HP/growth")
	before = camp.acknowledged_texts
	await b.scenario.on_turn_start(31)
	check(b.last_result == "defeat" and b.last_result_trigger.id == "t750_timeout","real L05 T31 timeout remains unchanged")
	check(b.last_message == "战斗失败！" and camp.battle_story_queue.is_empty(),"timeout same generic text, no obituary")
	await camp.drain_story(); d = dialog()
	check(camp.acknowledged_texts == before and not has_blue(camp.result_canvas),"timeout adds no TXT4 or blue report")
	# Real-time roll must stop at WAIT; a fresh release starts the tail.
	await create_timer(0.85).timeout
	check(d.stage=="notice" and d.notice.stage=="wait","notice waits despite time passing")
	await click(Vector2(200,330),MOUSE_BUTTON_RIGHT);await create_timer(0.22).timeout
	await click(Vector2(360,264))
	check(exits == 1 and d.stage == "done" and root.get_node("Music").stream == null,"real no click stops old BGM and requests title")
	await click(Vector2(360,264)); check(exits == 1,"completed dialog cannot dispatch twice")
	camp._show_report(false,"unused condition",5,0,{},false)
	d = dialog();d.notice.set_process(false);d.notice.height=99;d.notice._scroll_step();await process_frame;await process_frame
	await click(Vector2(20,20),MOUSE_BUTTON_RIGHT);d._advance(0.201)
	await click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	check(exits == 2 and d.stage == "done","right-DOWN cancels to title from anywhere")
	camp._show_report(true,"win",5,100,{},false)
	check(not has_blue(camp.result_canvas) and camp.result_canvas.get_child(0).get_script()==preload("res://scripts/ui/OriginalStoryPage.gd"),"victory fixed notice precedes blue report")
	root.get_node("Music").release_playback()
	camp.queue_free(); camp = null; await process_frame; await process_frame
	var main = load("res://Main.tscn").instantiate()
	main.qa_mode = true; root.add_child(main); main._start_campaign()
	main.campaign._show_report(false,"fixture",5,0,{},false)
	var title_dialog = main.campaign.result_canvas.get_child(0)
	title_dialog.notice.set_process(false);title_dialog.notice.height=99;title_dialog.notice._scroll_step();await process_frame;await process_frame
	await click(Vector2(20,20),MOUSE_BUTTON_RIGHT);title_dialog._advance(0.201)
	await click(Vector2(360,264)); await process_frame
	check(main.campaign == null and is_instance_valid(main.title_screen) and main.title_screen.is_visible_in_tree(),"real Main negative exit opens title, not world/quit")
	check(root.get_node("Music").current_scene == 53,"title re-enters its original BGM scene")
	root.get_node("Music").release_playback()
	main.queue_free(); await process_frame; await process_frame
	print("ORIGINAL_DEFEAT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
