extends SceneTree
var c
var manifest:Dictionary={}
func _initialize() -> void:call_deferred("run")
func shot(name:String) -> void:
	# Static pixel fixtures are not live hover tests. Suspend desktop events
	# during this capture, then restore each node's exact input setting.
	var suspended:Array=[]
	for node in [c.strategic_screen,c.deployment_screen,c.panel_root]:
		if is_instance_valid(node):
			suspended.append({"node":node,"enabled":node.is_processing_input()});node.set_process_input(false)
	for i in range(3):await process_frame
	RenderingServer.force_sync();RenderingServer.force_draw()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../out/ui_strategy/"+name+".png"))
	var entry:Dictionary={"mode":c.mode,"palette":c.strategic_palette_key,"town":c.selected_town}
	if c.mode=="world":
		entry["unlocked"]=[]
		for i in range(19):entry.unlocked.append(c.state.town_unlocked(i))
		entry["clock"]=c.strategic_screen.clock;entry["hover"]=c.strategic_screen.mine_hover
	if c.mode=="deployment":
		var d=c.deployment_screen
		entry["pages"]=d.pages.duplicate();entry["right"]=d.right.duplicate(true);entry["left"]=d.left.duplicate(true);entry["limit"]=d.limit;entry["drag"]=d.drag.duplicate();entry["drag_point"]=[d.drag_point.x,d.drag_point.y];entry["pressed"]=d.button_pressed
		entry["members"]={}
		for i in range(32):
			var m:Dictionary=c.state.person(i).duplicate(true)
			m["army_index"]=int(c.state.data.units[str(m.get("bingzhong",0))].img_index)
			m["class_name"]=str(c.state.data.units[str(m.get("bingzhong",0))].name)
			entry.members[str(m.pid)]=m
	manifest[name]=entry
	for saved in suspended:
		if is_instance_valid(saved.node):saved.node.set_process_input(saved.enabled)
	print("STRATEGY_SHOT ",name)
func mouse(point:Vector2,down:bool) -> void:
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../out/ui_strategy"))
	c=load("res://scripts/m4/Campaign.gd").new();root.add_child(c);c.qa_mode=true;c.setup(load("res://assets/font/hzk16.fnt"));c.set_process(false);c.state.play_seconds=3661;c.strategic_screen._refresh_clock();c.strategic_screen.set_process(false)
	await shot("world")
	c.strategic_screen.mine_hover=true;c.strategic_screen.queue_redraw();await shot("world_hover")
	c._world_system(Vector2(618,100));await shot("world_system");c._close_panel()
	for i in [0,4,5,6]:
		c._show_town(i);await shot("town%02d"%i)
		c._show_room("resident");await shot("resident%02d"%i)
	c._show_room("command");await shot("command")
	c._show_town(4);c._show_room("resident");await shot("resident_after_command")
	c._show_first_departure();await shot("departure");c._close_panel()
	c._show_room("command");c._show_solo_choice();c.panel_root.set_process_input(false);c.panel_root._select(0);await shot("solo");c._close_panel()
	# Actual town StoryPlayer now uses current palette for FRAME and FACE indices.
	c._show_town(5);c._show_room("resident");c._play_story([21],func():pass)
	c.story_player._advance();c.story_player.set_process(false);await shot("resident_story")
	c.story_player.free();c.story_player=null
	c._show_deployment(0);await shot("deployment0")
	for i in range(32):c.state.set_person_side(i,0)
	c._show_deployment(34);await shot("deployment34")
	mouse(Vector2(33,75),true);await shot("deployment_drag");mouse(Vector2(600,340),false)
	c._toggle_deploy(2,34);c._toggle_deploy(1,34);await shot("deployment_hole")
	for i in range(1,26):
		if not c.deploy_selected.has(i):c._toggle_deploy(i,34)
	c.deployment_screen.pages=[0,0];c.deployment_screen.queue_redraw();await shot("deployment_full1")
	c._deploy_page(0,34);c._deploy_page(1,34);await shot("deployment_full2")
	mouse(Vector2(525,391),true);await shot("deployment_pressed")
	var f:=FileAccess.open("res://../out/ui_strategy/manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(manifest));f.close()
	c.queue_free();await process_frame;root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(0.3).timeout
	print("ORIGINAL_STRATEGIC_QA_COMPLETE");quit()
