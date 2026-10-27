extends SceneTree
var main
func _initialize() -> void:call_deferred("run")
func shot(name:String) -> void:
	for i in range(3):await process_frame
	RenderingServer.force_sync();RenderingServer.force_draw()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../out/ui_creation/"+name+".png"))
	print("CREATION_SHOT ",name)
func mouse(point:Vector2,down:=false) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../out/ui_creation"))
	main=load("res://Main.tscn").instantiate();main.qa_mode=true;root.add_child(main);await process_frame
	main._show_character_create();await process_frame
	var c=main.menu_root;c.set_process(false)
	await shot("default")
	mouse(Vector2(530,100));mouse(Vector2(430,210));mouse(Vector2(269,290));mouse(Vector2(250,380),true);mouse(Vector2(250,380))
	await shot("selected")
	mouse(Vector2(369,290));mouse(Vector2(590,380),true);mouse(Vector2(590,380))
	await shot("maximum")
	mouse(Vector2(290,435),true);await shot("pressed");mouse(Vector2(0,0))
	mouse(Vector2(150,435),true);mouse(Vector2(150,435));await shot("name_empty")
	mouse(Vector2(594,55));await shot("name_z")
	mouse(Vector2(0,72));c._advance(0.11);await shot("name_one")
	main.queue_free();await process_frame;root.get_node("Music").release_playback();await create_timer(0.5).timeout
	print("ORIGINAL_CREATION_QA_COMPLETE")
	quit()
