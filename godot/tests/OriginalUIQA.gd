extends SceneTree
var main
var camp
var output := ""
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	for i in range(5):await process_frame
	var pixels := capture()
	pixels.save_png(output+"/"+name+".png")
	if name in ["10l_defeat_notice","10m_retry_prompt","10n_retry_no_hover"]:
		verify_defeat_capture(pixels,name)
	if name.begins_with("09d_"):verify_inventory_capture(pixels,name)
	if name=="09d_item_grid8":verify_item_picker_icons(pixels)
	if name.begins_with("09e_") or name.begins_with("09f_") or name in ["09_actions","10b_full_menu"]:verify_menu_capture(pixels,name)
	if name.begins_with("10c_"):verify_readout_capture(pixels,name)
	print("UI_SHOT ",name)

func capture() -> Image:
	# macOS may retain an inactive/occluded window's last framebuffer. Waiting
	# process_frames alone does not prove a PNG contains the current canvas.
	RenderingServer.force_sync()
	RenderingServer.force_draw()
	return root.get_texture().get_image()

func verify_defeat_capture(pixels: Image, name: String) -> void:
	var retry := name != "10l_defeat_notice"
	var texture: Texture2D = load("res://assets/ui/retry_original.png" if retry else "res://assets/ui/frame00_original.png")
	var expected := texture.get_image()
	var origin := Vector2i(300,200) if retry else Vector2i(118,296)
	var wrong := 0
	var checked := 0
	# All opaque perimeter pixels, outside the text/selected-row regions.
	for y in range(expected.get_height()):
		for x in range(expected.get_width()):
			if x >= 4 and x < expected.get_width()-4 and y >= 4 and y < expected.get_height()-4: continue
			var color := expected.get_pixel(x,y)
			if color.a < 1: continue
			checked += 1
			if not pixels.get_pixelv(origin+Vector2i(x,y)).is_equal_approx(color): wrong += 1
	print("UI_DEFEAT_BORDER ",name," checked=",checked," wrong=",wrong)
	if checked == 0 or wrong != 0: push_error("UI_QA missing/stale defeat canvas "+name)
func dismiss_stories() -> void:
	for i in range(100):
		if is_instance_valid(camp.story_player):camp.story_player._finish()
		if is_instance_valid(camp.cutscene):camp.cutscene._finish()
		await process_frame
		if camp.battle_story_queue.is_empty() and not is_instance_valid(camp.story_player):break
func run() -> void:
	output=ProjectSettings.globalize_path("res://../out/ui_original")
	DirAccess.make_dir_recursive_absolute(output)
	main=load("res://Main.tscn").instantiate();main.qa_mode=true;root.add_child(main)
	await shot("01_title")
	main._show_character_create();await shot("02_creation")
	main._start_campaign();camp=main.campaign
	camp.state.data=camp.state.data.duplicate(true)
	camp.state.data.meta.save_prefix="dlz_qa_ui_"
	camp._show_town(0);await shot("03_town")
	camp._open_party();await shot("04_party")
	camp._open_loadout(-100,"items");await shot("05_carry")
	camp._close_panel();camp._open_forge();await shot("06_forge")
	camp.state.add_mine(0,3);camp.state.add_mine(10,2);camp.state.add_mine(20,1)
	camp._show_k04_status();await shot("06b_mine_distribution")
	camp.selected_town=1;camp._open_shop("junxie");await shot("06c_weapon_shop")
	camp._open_shop("zahuo");await shot("06d_grocery_shop")
	camp._open_original_info("item",1);await shot("06d1_item_info");camp.info_panel.close()
	camp._open_original_info("person",-100);await shot("06d2_person_info");camp.info_panel.close()
	var bag:Array=camp.state.protagonist.item_slots.duplicate()
	var mines:Array=camp.state.protagonist.mine_slots.duplicate()
	camp.state.protagonist.item_slots=[100,82,109,152,39,2,32,81]
	camp.state.protagonist.mine_slots=[1,11,21,31,10,20,30,40]
	camp._open_original_info("person",-100);await shot("06d2b_person_full_bags");camp.info_panel.close()
	camp.state.protagonist.item_slots=bag;camp.state.protagonist.mine_slots=mines
	camp._open_original_info("mine",20);await shot("06d3_mine_info");camp.info_panel.close()
	camp._open_original_info("item",75);await shot("06d4_promotion_info");camp.info_panel.close()
	camp._open_original_info("item",36);await shot("06d5_long_item_name");camp.info_panel.close()
	camp._open_shop("material");await shot("06e_material_shop")
	camp._show_deployment(0);await shot("06f_deployment")
	var saved:Dictionary=camp.state.to_dict().duplicate(true)
	for slot in range(32):camp.state.set_person_side(slot,0)
	camp._show_deployment(34)
	for slot in range(1,26):camp._toggle_deploy(slot,34)
	camp.deployment_screen.pages=[0,0];camp.deployment_screen.queue_redraw()
	await shot("06f1_deployment_full_page1")
	camp._deploy_page(0,34);camp._deploy_page(1,34);await shot("06f2_deployment_page2")
	camp.state.from_dict(saved);camp.deploy_selected=[-100]
	camp.state.story_variant=false
	camp._play_media(0,func():pass)
	await create_timer(0.25).timeout
	if root.get_node("Music").playing:push_error("UI_QA entry movie overlaps old BGM")
	root.get_node("Music")._try_loop()
	if root.get_node("Music").playing:push_error("UI_QA focus resumes old BGM inside entry movie")
	await shot("06g_entry_movie")
	await verify_movie_input()
	camp._launch_level(0,false,[-100]);await shot("07_story")
	await dismiss_stories();await shot("08_battle")
	var b=camp.battle
	if b.selected==null:b._focus_player()
	await shot("08b_native_move_mask")
	await native_cells(b,"move")
	b._open_context_menu();await shot("09_actions")
	b._on_attack();await shot("09c_native_attack_mask")
	b._cancel();b._close_context_menu();b._open_unit_info();await shot("09b_battle_info")
	for child in b.get_children():
		if child.get_script()==preload("res://scripts/ui/OriginalInfo.gd"):child.close()
	await native_battle_inventory(b)
	await native_chest_notice(b)
	await native_menu_popups(b)
	b._toggle_map_mode();await shot("10_full_map")
	b._open_system_menu(Vector2(500,300));await shot("10b_full_menu");b._close_context_menu();b._toggle_map_mode()
	await native_toolbar_pages(b)
	camp._battle_toolbar("save");await shot("10d_battle_save");camp._close_panel()
	await clipped_anm(b,"10e_anm_clip_normal")
	await clipped_numbers(b,"10e1_numbers_clip_normal")
	b._toggle_map_mode();await clipped_anm(b,"10f_anm_clip_full");b._toggle_map_mode()
	b._toggle_map_mode();await clipped_numbers(b,"10f1_numbers_clip_full");b._toggle_map_mode()
	await clipped_death(b)
	await native_map_markers(b)
	await native_mine_ranges(b)
	camp._show_report(false,"fixture",0,0,{},false)
	var defeat = camp.result_canvas.get_child(0)
	defeat.set_process(false);defeat.notice.set_process(false);defeat.notice.height=99;defeat.notice._scroll_step()
	await shot("10l_defeat_notice")
	defeat.notice.stage="tail";defeat._advance(0.21)
	await shot("10m_retry_prompt")
	defeat._select(1)
	await shot("10n_retry_no_hover")
	camp.result_canvas.queue_free(); camp.result_canvas = null
	camp._show_ending();await shot("11_ending")
	if is_instance_valid(camp.ending_layer):camp.ending_layer.queue_free()
	var photo_layer:=CanvasLayer.new();photo_layer.layer=99;root.add_child(photo_layer)
	var hs=load("res://scripts/m5/HistorySlideshow.gd").new();photo_layer.add_child(hs);hs.setup(main.font,main.m5.history)
	await shot("12_history_npic25")
	hs._show(16);await shot("13_history_npic03")
	hs._close();photo_layer.queue_free();await process_frame
	get_root().get_node("Music").release_playback()
	main.queue_free();await process_frame
	await create_timer(0.5).timeout
	print("ORIGINAL_UI_QA_COMPLETE ",output)
	quit()

func verify_movie_input() -> void:
	# Actual decoded entry movie, distinct from the synthetic finished-signal
	# fixture in OriginalCutsceneTest. No fabricated video completion here.
	var player=camp.cutscene
	if not is_instance_valid(player) or player._finished:
		push_error("UI_QA entry movie not live for native input check");return
	if not player.find_children("*","Label",true,false).is_empty():push_error("UI_QA modern movie hint remains")
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		for down in [true,false]:
			var click:=InputEventMouseButton.new();click.button_index=button;click.pressed=down;click.position=Vector2(550,460);click.global_position=click.position;root.push_input(click,true)
	for spec in [[KEY_SPACE,true],[KEY_ENTER,true],[KEY_ESCAPE,false]]:
		var event:=InputEventKey.new();event.keycode=spec[0];event.pressed=spec[1];root.push_input(event,true)
	if player._finished:push_error("UI_QA movie skipped by mouse/non-Esc/KEYUP")
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true)
	if not player._finished:push_error("UI_QA movie ignores native Esc-DOWN")
	await process_frame;await process_frame
	print("UI_MOVIE_INPUT native mouse/non-Esc/UP ignored; Esc-DOWN finishes")

func native_map_markers(b) -> void:
	# Isolated rendering fixture, not campaign progress or a play certificate.
	b._clear_selection();b.set_process(false);b.camera_follow=false
	var saved_chests:Array=b.chests.duplicate(true)
	var world:Vector2=b.get_global_transform_with_canvas().affine_inverse()*(b.map_rect().position+Vector2(60,150))
	var tile:=Vector2i(floori(world.x/48),floori(world.y/48))
	b.chests=[]
	var fixtures:Array=[]
	for i in range(6):
		var cell:=tile+Vector2i(i,0)
		b.chests.append({"x":cell.x,"y":cell.y,"appearance":i/2,"wupin":1,"opened":i%2==1})
		var mine:Dictionary={"tile":cell+Vector2i(0,1),"mine":b.data.mines[0]}
		b._draw_mine(mine);fixtures.append(mine.tile)
	b._spawn_level_markers()
	await shot("10h_native_map_markers")
	for cell in fixtures:
		b.mine_nodes[cell].queue_free();b.mine_nodes.erase(cell)
	b.chests=saved_chests;b._spawn_level_markers()

func native_chest_notice(b) -> void:
	# Exercise the real pickup coroutine, not a detached mock of its panel.
	var h=b._camera_focus_unit()
	b._clear_selection()
	var old_chests:Array=b.chests
	var old_items:Array=h.item_slots.duplicate()
	var old_stats:Dictionary=b.stats.duplicate(true)
	var old_fast:bool=b.fast_sim
	b.chests=[{"x":h.x,"y":h.y,"wupin":7,"appearance":0,"opened":false}]
	h.item_slots=[0,0,0,0,0,0,0,0];b.fast_sim=false
	b._open_chest(h,0)
	await shot("09d_chest_notice")
	if not b.busy or b.chests[0].wupin!=7 or h.item_slots[0]!=8:push_error("UI_QA chest modal transaction was not held")
	var ack:=InputEventKey.new();ack.keycode=KEY_SPACE;ack.pressed=false;root.push_input(ack,true)
	await process_frame
	if b.action_panel!=null or b.chests[0].wupin!=-1 or b.busy:push_error("UI_QA chest key-UP did not complete transaction")
	b.chests=old_chests;h.item_slots=old_items;b.stats=old_stats;b.fast_sim=old_fast
	b._refresh_equipment(h);b._spawn_level_markers()

func clipped_anm(b,name:String) -> void:
	b.set_process(false);b.camera_follow=false;b.animations_enabled=true
	b.camera.force_update_scroll()
	for i in range(5):await process_frame
	var before:Image=capture()
	var rect:Rect2=b.map_rect()
	var world:Vector2=b.get_global_transform_with_canvas().affine_inverse()*rect.position
	b._play_anm_sheet("res://assets/m5/anm/ffpact00_sheet.png",world)
	await create_timer(0.35).timeout
	await shot(name)
	var after:Image=capture()
	var outside:=0;var inside:=0
	for y in range(after.get_height()):
		for x in range(after.get_width()):
			if before.get_pixel(x,y)==after.get_pixel(x,y):continue
			if rect.has_point(Vector2(x,y)):inside+=1
			else:outside+=1
	print("UI_ANM_CLIP ",name," inside=",inside," outside=",outside)
	if outside!=0 or inside==0:push_error("UI_QA ANM clip outside=%d inside=%d"%[outside,inside])
	await create_timer(2.0).timeout

func clipped_numbers(b,name:String) -> void:
	b.set_process(false);b.camera_follow=false;b.animations_enabled=true
	b.camera.force_update_scroll()
	for i in range(5):await process_frame
	var before:Image=capture()
	var rect:Rect2=b.map_rect()
	var world:Vector2=b.get_global_transform_with_canvas().affine_inverse()*(rect.position+Vector2(2,25))
	b._queue_damage_number(120,world,"hp")
	b._wait_damage_numbers("attack")
	await create_timer(0.59).timeout
	await shot(name)
	var after:Image=capture()
	var outside:=0;var inside:=0
	for y in range(after.get_height()):
		for x in range(after.get_width()):
			if before.get_pixel(x,y)==after.get_pixel(x,y):continue
			if rect.has_point(Vector2(x,y)):inside+=1
			else:outside+=1
	print("UI_NUMBER_CLIP ",name," inside=",inside," outside=",outside)
	if outside!=0 or inside==0:push_error("UI_QA number clip outside=%d inside=%d"%[outside,inside])
	await create_timer(0.8).timeout


func clipped_death(b) -> void:
	b.set_process(false);b.camera_follow=false;b.animations_enabled=true
	b.camera.force_update_scroll()
	for i in range(5):await process_frame
	var before:Image=capture()
	var rect:Rect2=b.map_rect()
	var world:Vector2=b.get_global_transform_with_canvas().affine_inverse()*(rect.position+Vector2(2,160))
	var tile:=Vector2i(floori(world.x/48),floori(world.y/48))
	var source=b.unit_by_slot(0)
	var d:Dictionary=source.state_record()
	d.merge({"slot":127,"pid":-1,"x":tile.x,"y":tile.y,"alive":true,"placed":true},true)
	var fixture=b._spawn_unit(d)
	var captured:Array=[]
	var capture:Callable=func(kind:String,payload:Dictionary):
		var weight:int=payload.get("weight",-1)
		if kind=="death_mix_end" or (kind=="death_mix_frame" and weight in [0,128,256]):
			var name:="10g_death_mix_"+("final" if kind=="death_mix_end" else "%03d"%weight)
			var after:Image=capture()
			captured.append(name)
			after.save_png(output+"/"+name+".png");print("UI_SHOT ",name)
			var outside:=0;var inside:=0
			for y in range(after.get_height()):
				for x in range(after.get_width()):
					if before.get_pixel(x,y)==after.get_pixel(x,y):continue
					if rect.has_point(Vector2(x,y)):inside+=1
					else:outside+=1
			print("UI_DEATH_CLIP ",name," inside=",inside," outside=",outside)
			if outside!=0:push_error("UI_QA death mix outside=%d"%outside)
			if kind=="death_mix_frame" and weight<=128 and inside==0:push_error("UI_QA synchronous death blit was not rendered")
	b.presentation_step.connect(capture)
	b._play_death_mix(fixture)
	b.presentation_step.disconnect(capture)
	if captured.size()!=4:push_error("UI_QA missing death blit captures")
	b.units.erase(fixture);b.player_units.erase(fixture);b.enemy_units.erase(fixture);fixture.free()

func native_mine_ranges(b) -> void:
	var hero=b.unit_by_slot(0)
	if hero==null:return
	b._select_unit(hero);b._mine_command("recover")
	await shot("10i_native_recover_mask")
	b._cancel();b._close_context_menu();b._mine_command("remote")
	await shot("10j_native_remote_mask")
	b._cancel();b._cancel()
	var old_behavior:int=hero.behavior
	hero.behavior=11;hero.refresh()
	await shot("10k_native_luan_overlay")
	await native_cells(b,"luan")
	hero.behavior=old_behavior;hero.refresh()

func native_cells(b,label:String) -> void:
	# Original indexed4170AA composition is an independent pixel oracle for
	# actual normal rendering, including dark map and undimmed army/glyph.
	b.set_process(false);b.camera_follow=false;b.camera.force_update_scroll()
	for i in range(5):await process_frame
	var actual:Image=capture()
	var mix=preload("res://scripts/battle/OriginalDeathMix.gd")
	var sources:Dictionary=mix.sources(str(b.level.map.png).replace(".png","_index.png"))
	var checked:=0;var wrong:=0
	for u in b.units:
		if not u.alive or not u.placed:continue
		var tile:=Vector2i(u.x,u.y)
		var screen:Vector2=b.get_global_transform_with_canvas()*Vector2(tile*48)
		if not b.map_rect().intersects(Rect2(screen,Vector2(48,48))):continue
		var layers:Dictionary={"box":sources.box,"mine":sources.mine,"chests":b.chests,
			"mine_present":b.mines.any(func(m):return m.tile==tile),"behavior":u.behavior,
			"dark":b.native_dark_mask[tile.y*b.map_w+tile.x]!=0,"dark_lut":PackedByteArray(b.data.meta.map_dark_lut),"luan_glyph":PackedByteArray(b.data.meta.luan_glyph)}
		var buffers:Dictionary=mix.tile_buffers(sources.map,b.map_w,tile,sources.army,int(b.unit_class(u).img_index),u.native_frame(),layers)
		var expected:Image=mix.rgba(buffers.old,b.data.meta.battle_palette)
		for y in range(48):
			for x in range(48):
				var point:=Vector2(roundi(screen.x)+x,roundi(screen.y)+y)
				if not b.map_rect().has_point(point):continue
				checked+=1
				if not actual.get_pixelv(point).is_equal_approx(expected.get_pixel(x,y)):wrong+=1
	print("UI_NATIVE_CELL ",label," checked=",checked," wrong=",wrong)
	if checked==0 or wrong!=0:push_error("UI_QA native cell mismatch "+label+" pixels="+str(wrong))

func verify_inventory_capture(pixels:Image,name:String) -> void:
	var file:="item_picker_original.png";var rect:=Rect2i(168,126,304,227)
	match name:
		"09d_item_actions":file="choice_4_original.png";rect=Rect2i(360,280,88,112)
		"09d_mine_duplicates":file="choice_3_original.png";rect=Rect2i(276,200,88,88)
		"09d_mine_single":file="choice_1_original.png";rect=Rect2i(276,224,88,32)
		"09d_manual_confirm":file="retry_original.png";rect=Rect2i(320,200,128,88)
		"09d_manual_notice":file="frame00_original.png";rect=Rect2i(118,296,404,127)
		"09d_chest_notice":file="frame00_original.png";rect=Rect2i(118,296,404,127)
	var expected:Image=load("res://assets/ui/"+file).get_image()
	var checked:=0;var wrong:=0
	var clipped:=name in ["09d_item_actions","09d_mine_duplicates"]
	for y in range(rect.size.y-(2 if clipped else 0)):
		for x in range(rect.size.x):
			if x>=3 and y>=3 and x<rect.size.x-3 and y<rect.size.y-3:continue
			var color:=expected.get_pixel(x,y)
			if color.a<1:continue
			checked+=1
			if not pixels.get_pixelv(rect.position+Vector2i(x,y)).is_equal_approx(color):wrong+=1
	print("UI_INVENTORY_BORDER ",name," checked=",checked," wrong=",wrong)
	if checked==0 or wrong!=0:push_error("UI_QA missing/stale inventory canvas "+name)
	if clipped:verify_choice_background(pixels,name,rect)

func native_battle_inventory(b) -> void:
	var hero=b.unit_by_slot(0)
	var old_items:Array=hero.item_slots.duplicate();var old_mines:Array=hero.mine_slots.duplicate();var acted:bool=hero.acted
	b._close_context_menu();b._close_action_panel();b.selected=hero;hero.acted=false
	hero.item_slots=[2,0,82,2,32,94,0,6]
	b._open_item_menu();await shot("09d_item_grid8")
	b._item_options(81);await shot("09d_item_actions")
	hero.mine_slots=[12,0,2,12,0,0,0,0]
	b._open_mine_menu();await shot("09d_mine_duplicates")
	hero.mine_slots=[2,0,0,0,0,0,0,0]
	b._open_mine_menu();await shot("09d_mine_single")
	b._close_action_panel();b.busy=true
	var confirm=preload("res://scripts/ui/OriginalConfirm.gd").new();b.hud_root.add_child(confirm)
	confirm.setup(b.font,"转职吗？");await shot("09d_manual_confirm");confirm.queue_free();await process_frame
	var notice=preload("res://scripts/ui/OriginalNotice.gd").new();b.hud_root.add_child(notice)
	notice.setup(b.font,"李勇转职为手枪队");await shot("09d_manual_notice");notice.queue_free();await process_frame
	hero.item_slots=old_items;hero.mine_slots=old_mines;hero.acted=acted;b.busy=false
	b._clear_selection()

func verify_item_picker_icons(pixels:Image) -> void:
	var bag:Array=camp.battle.selected.item_slots
	var checked:=0;var wrong:=0
	for slot in range(bag.size()):
		var id:=int(bag[slot])-1
		if id<0:continue
		var goods:int=int(camp.battle.data.items[str(id)].goods)
		var texture:Texture2D=load("res://assets/goods/goods_%03d.png"%goods)
		var expected:=texture.get_image()
		var origin:=Vector2i(194+67*(slot%4),144+100*(slot/4))
		for y in range(48):
			for x in range(48):
				var color:=expected.get_pixel(x,y)
				if color.a<1:continue
				checked+=1
				if not pixels.get_pixelv(origin+Vector2i(x,y)).is_equal_approx(color):wrong+=1
	print("UI_INVENTORY_ICONS checked=",checked," wrong=",wrong)
	if checked==0 or wrong!=0:push_error("UI_QA missing/stale item picker icons")

func native_menu_popups(b) -> void:
	# Real menu entry points on a presentation fixture, not campaign progress.
	var hero=b._camera_focus_unit()
	var practice:Dictionary=hero.skill_counts.duplicate()
	var previous:bool=hero.acted
	b._clear_selection();b._close_context_menu();b._close_action_panel()
	b.selected=hero;hero.acted=false
	for sid in range(16):hero.skill_counts[b.SKILL_KEYS[sid]]=0
	hero.skill_counts.buji=1
	b._open_skill_menu();await shot("09e_skill1");b._close_action_panel()
	for sid in range(16):hero.skill_counts[b.SKILL_KEYS[sid]]=300 if sid%2 else 1
	b._open_skill_menu();await shot("09e_skill16");b._close_action_panel()
	b._on_mine();await shot("09e_mine_operations");b._close_action_panel()
	b._choose_timer(Vector2i(hero.x,hero.y),true);await shot("09e_timer10");b._close_action_panel()
	b.show_trigger_choice(null,"not an extra original title",["枪  毙","放  逐","收  编"])
	await shot("09e_trigger_default")
	var move:=InputEventMouseMotion.new();move.position=Vector2(20,260);move.global_position=move.position;root.push_input(move,true)
	await shot("09e_trigger_recruit")
	b._on_trigger_choice(null,2)
	hero.skill_counts=practice;hero.acted=previous;b.selected=null

func verify_menu_capture(pixels:Image,name:String) -> void:
	var specs:Dictionary={
		"09_actions":[6,Vector2i(320,240)],"10b_full_menu":[13,Vector2i(500,151)],
		"09e_skill1":[1,Vector2i(276,224)],"09e_skill16":[16,Vector2i(276,44)],
		"09e_mine_operations":[5,Vector2i(300,280)],"09e_timer10":[10,Vector2i(276,112)],
		"09e_trigger_default":[3,Vector2i(276,196)],"09e_trigger_recruit":[3,Vector2i(276,196)],
		"09f_speed_normal":[5,Vector2i(282,32)],"09f_speed_system":[5,Vector2i(320,200)],
		"09f_end_normal":[3,Vector2i(500,32)],"09f_end_system":[3,Vector2i(320,200)]}
	var spec:Array=specs[name]
	var rolled:=int(spec[0])>1 and name not in ["09e_trigger_default","09e_trigger_recruit"]
	var expected:Image=load("res://assets/ui/choice_%d_original.png"%int(spec[0])).get_image()
	var wrong:=0;var checked:=0
	for y in range(expected.get_height()-(2 if rolled else 0)):
		for x in range(expected.get_width()):
			if x>=4 and x<expected.get_width()-4 and y>=4 and y<expected.get_height()-4:continue
			checked+=1
			if not pixels.get_pixelv(Vector2i(spec[1])+Vector2i(x,y)).is_equal_approx(expected.get_pixel(x,y)):wrong+=1
	print("UI_MENU_BORDER ",name," checked=",checked," wrong=",wrong)
	if checked==0 or wrong!=0:push_error("UI_QA missing/stale native menu "+name)
	if rolled:verify_choice_background(pixels,name,Rect2i(Vector2i(spec[1]),expected.get_size()))

func verify_choice_background(pixels:Image,name:String,rect:Rect2i) -> void:
	# 426C6A's last copy is H-2, not H. Verify the missing two rows
	# against the actual pre-entry saved rect; do not merely exclude them.
	var menu=null
	for node in root.find_children("*","Control",true,false):
		if node.get_script()==preload("res://scripts/ui/OriginalChoice.gd") and node.is_visible_in_tree() and not node.is_queued_for_deletion() and not node.done and Rect2i(node.frame)==rect:
			menu=node;break
	if menu==null or menu.saved_background==null:
		push_error("UI_QA missing native saved menu background "+name);return
	var before:Image=menu.saved_background.get_image()
	var checked:=0;var wrong:=0
	var differences:Array=[]
	for y in range(rect.size.y-2,rect.size.y):
		for x in range(rect.size.x):
			checked+=1
			if not pixels.get_pixelv(rect.position+Vector2i(x,y)).is_equal_approx(before.get_pixel(x,y)):
				wrong+=1
				if differences.size()<32:differences.append({"at":[rect.position.x+x,rect.position.y+y],"before":before.get_pixel(x,y).to_html(),"actual":pixels.get_pixelv(rect.position+Vector2i(x,y)).to_html()})
	print("UI_MENU_UNTOUCHED ",name," checked=",checked," wrong=",wrong)
	if wrong:print("UI_MENU_BACKGROUND_DIFF ",name," ",JSON.stringify(differences))
	if wrong!=0 or not menu.raster_root.clip_contents or menu.raster_root.size.y!=rect.end.y-2:push_error("UI_QA bottom two rows overwritten "+name)

func native_toolbar_pages(b) -> void:
	b._clear_selection();b.set_process(false)
	b._show_speed();await shot("09f_speed_normal");b._close_action_panel()
	b._show_speed(true);await shot("09f_speed_system");b._close_action_panel()
	b._ask_end_turn();await shot("09f_end_normal");b._close_action_panel()
	b._ask_end_turn(true);await shot("09f_end_system");b._close_action_panel()
	b._show_task();b.action_panel.set_process_input(false)
	await shot("10c_task");b._close_action_panel()
	b._show_roster("player");b.action_panel.set_process_input(false)
	await shot("10c_roster_player");b._close_action_panel()
	# Isolated page/HP/behavior rendering fixture, never campaign evidence.
	var extras:Array=[]
	for slot in range(70,95):
		var u:Dictionary=b.level.units[0].duplicate(true)
		u.merge({"slot":slot,"pid":slot,"name":"情报单位%d"%slot,"faction":2,"side":"enemy","x":slot%12,"y":slot/12,"hp":100,"max_hp":150,"level":12,"morale":75,"bingzhong":1,"behavior":11 if slot==70 else 0},true)
		b._spawn_unit(u);extras.append(b.unit_by_slot(slot))
	extras[0].hp=40;extras[1].hp=90;extras[2].hp=120
	# Screenshot fixtures are not input tests. A real desktop key/right release
	# legitimately advances this original ANY-UP waiter, even while shot() yields.
	# Isolate just these static captures; OriginalToolbarTest independently tests
	# viewport UPs, first-left swallowing, per-page gating and final close.
	b._show_roster("enemy");b.action_panel.set_process_input(false)
	await shot("10c_roster_enemy_page1")
	var readout=b.action_panel
	print("UI_READOUT_STATE before_page2 valid=",is_instance_valid(readout)," page=",readout.page if is_instance_valid(readout) else -1," count=",readout.pages.size() if is_instance_valid(readout) else -1)
	if not is_instance_valid(readout) or readout.pages.size()<3 or readout.page!=0:
		push_error("UI_QA roster fixture not at live page0 before page2 input")
	else:
		readout._advance()
		print("UI_READOUT_STATE after_page2 page=",readout.page," done=",readout.done," count=",readout.pages.size()," owns_modal=",b.action_panel==readout)
	await shot("10c_roster_enemy_page2")
	if b.action_panel!=readout or not is_instance_valid(readout) or readout.done or readout.page!=1:
		push_error("UI_QA roster page2 fixture changed while capturing")
	b._close_action_panel()
	for u in extras:b.units.erase(u);b.enemy_units.erase(u);u.free()

func verify_readout_capture(pixels:Image,name:String) -> void:
	var readout=camp.battle.action_panel
	if readout==null or readout.backdrop.texture==null:push_error("UI_QA missing native screen backup "+name);return
	var expected:Image=readout.backdrop.texture.get_image()
	var wrong:=0;var checked:=0
	for y in range(360):
		for x in range(480):
			var at:=Vector2(80+x,60+y);var covered:=false
			for label in readout.labels:
				if Rect2(label.position,Vector2(label.get_minimum_size().x,16)).has_point(at):covered=true;break
			if covered:continue
			checked+=1
			if not pixels.get_pixel(80+x,60+y).is_equal_approx(expected.get_pixel(x,y)):wrong+=1
	print("UI_READOUT_LUT ",name," checked=",checked," wrong=",wrong)
	if checked<100000 or wrong!=0:push_error("UI_QA native partial-screen LUT mismatch "+name)
