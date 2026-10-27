extends SceneTree
var title
func _initialize() -> void:call_deferred("run")
func move(point:Vector2) -> void:
	var e:=InputEventMouseMotion.new();e.position=point;e.global_position=point;root.push_input(e,true)
func shot(name:String) -> void:
	for i in range(3):await process_frame
	RenderingServer.force_sync();RenderingServer.force_draw()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../out/ui_title/"+name+".png"))
	print("TITLE_SHOT ",name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../out/ui_title"))
	title=load("res://scripts/ui/TitleScreen.gd").new();root.add_child(title);title.setup(load("res://assets/font/hzk16.fnt"));title.set_process(false)
	await shot("default")
	for row in range(1,5):move(Vector2(316,title.ROW_Y[row]+1));await shot("row%d"%row)
	for i in range(29):title.tick()
	await shot("phase29")
	move(Vector2(1,1));await shot("retained")
	title.tick();await shot("wrapped")
	title.free()
	for mode in ["scores","supporters","exit","load"]:
		var p=load("res://scripts/ui/OriginalTitlePages.gd").new();root.add_child(p);p.setup(load("res://assets/font/hzk16.fnt"),mode,load("res://scripts/ui/OriginalHighScores.gd").defaults());p.set_process(false)
		if mode=="scores":await shot("scores")
		elif mode=="supporters":
			await shot("support0");p.tick();await shot("support1")
			for i in range(3540):p.tick()
			await shot("support_last")
		else:
			for i in range(10):p.tick()
			await shot(mode+"10")
			if mode=="exit":p.tick();await shot("exit11")
		p.free()
	await process_frame;root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(0.3).timeout
	print("ORIGINAL_TITLE_QA_COMPLETE");quit()
