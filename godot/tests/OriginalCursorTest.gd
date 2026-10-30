extends SceneTree
# Static cursor contract decoded from the original executable.
# OS-native arrows differ by platform; these are semantic/input-shape checks,
# not a claim that macOS pixels equal the historical Windows system cursor.
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("CURSOR_FAIL "+label)
func arrow_controls(node:Node) -> bool:
	for child in node.find_children("*","Control",true,false):
		if child.mouse_default_cursor_shape!=Control.CURSOR_ARROW:return false
	return true
func run() -> void:
	var m3:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m3.json"))
	check(m3.meta.get("cursor_mode","")=="system_arrow" and not m3.meta.has("cursor"),"manifest does not attribute MENU30 to the cursor")
	check(not FileAccess.file_exists("res://assets/ui/cursor.png") and not m3.assets.values().has("res://assets/ui/cursor.png"),"obsolete generated cursor alias removed")
	var handle:Texture2D=load("res://assets/ui/menu30_slider.png")
	check(handle!=null and handle.get_size()==Vector2(17,25),"MENU30 retained as 17x25 slider artwork")
	var font:Font=load("res://assets/font/hzk16.fnt")
	var button:=OriginalUI.button("cursor",font)
	check(button.mouse_default_cursor_shape==Control.CURSOR_ARROW,"original button does not invent a pointing-hand hover")
	button.free()
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND);OriginalUI.apply_cursor()
	check(Input.get_current_cursor_shape()==Input.CURSOR_ARROW,"startup restores native arrow rather than MENU30/hotspot")
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	var before_mode:int=Input.mouse_mode
	OriginalUI.apply_cursor()
	check(Input.mouse_mode==before_mode,"shape reset preserves platform mouse visibility")
	print("CURSOR_VISIBILITY supported_hidden=",before_mode==Input.MOUSE_MODE_HIDDEN)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var main=load("res://Main.tscn").instantiate();main.qa_mode=true;root.add_child(main)
	await process_frame
	check(main.title_screen!=null and arrow_controls(main.title_screen),"title controls inherit the arrow")
	main._start_campaign();await process_frame
	check(main.campaign!=null and arrow_controls(main.campaign),"world controls inherit the arrow")
	main.campaign._show_town(0);await process_frame
	check(arrow_controls(main.campaign),"town controls inherit the arrow")
	main.campaign._launch_level(0,true,[-100]);await process_frame
	var battle=main.campaign.battle
	check(battle!=null and arrow_controls(battle.hud_root),"battle toolbar controls inherit the arrow")
	var choice=load("res://scripts/ui/OriginalChoice.gd").new();root.add_child(choice)
	choice.setup(font,["A","B","C"],Vector2(100,100))
	check(choice.mouse_default_cursor_shape==Control.CURSOR_ARROW and arrow_controls(choice),"native MOVE/DOWN choice keeps arrow shape")
	choice.free();OriginalUI.apply_cursor();OriginalUI.apply_cursor()
	check(Input.get_current_cursor_shape()==Input.CURSOR_ARROW,"repeated restoration remains arrow")
	main.queue_free();await process_frame;await create_timer(0.2).timeout
	# Music is an autoload, not a child of Main. Retire its desktop mixer
	# playback explicitly, as the other desktop QA entry points do.
	root.get_node("Music").release_playback()
	print("ORIGINAL_CURSOR checks=",checks," failures=",failures)
	quit(1 if failures else 0)
